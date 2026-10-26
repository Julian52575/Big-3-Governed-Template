set dotenv-load := true
set shell := ["bash", "-eu", "-c"]
# Recipes also get their arguments as "$@", so quoted arguments stay intact.
set positional-arguments := true

# Every recipe goes through this. Inside the nix shell (IN_NIX_SHELL, also set
# by direnv) it is always rootless podman; outside, podman if present, else docker.
tool := if env("IN_NIX_SHELL", "") != "" { "podman" } else { `command -v podman >/dev/null && echo podman || echo docker` }
compose := tool + " compose"
# compose derives the project name from the directory name
project := lowercase(file_name(justfile_directory()))

# List available recipes
default:
    @just --list
    @echo -e "\nusing '{{tool}}' as a container tool."

#### Container

# Start the stack. Pass `-d` to detach (recommended -- see README).
up *args:
    {{compose}} up {{args}}

# Stop the stack, keeping volumes
down *args:
    {{compose}} down {{args}}

# Stop the stack and delete its built images (`just rm; just up` = clean rebuild).
rm *args:
    #!/usr/bin/env bash
    set -euo pipefail
    {{compose}} down --remove-orphans {{args}}
    {{tool}} images -q \
        --filter "reference={{project}}*" --filter "reference=localhost/{{project}}*" \
      | sort -u | xargs -r {{tool}} rmi -f || true

# Rebuild one service from scratch and recreate it, leaving the rest running: `just rebuild backend`
rebuild service:
    #!/usr/bin/env bash
    set -euo pipefail
    {{compose}} build --no-cache {{service}}
    # via the container tool: podman-compose has no `rm`
    {{tool}} ps -aq --filter "label=com.docker.compose.project.working_dir={{justfile_directory()}}" \
        --filter "label=com.docker.compose.service={{service}}" | xargs -r {{tool}} rm -f >/dev/null
    # a stale <service>-node-modules volume would hide the image's fresh dependencies
    {{tool}} volume rm -f "{{project}}_{{service}}-node-modules" >/dev/null 2>&1 || true
    {{compose}} up -d --no-deps {{service}}

# Like `just rm`, but also delete named volumes -- wipes db data etc.
nuke *args:
    #!/usr/bin/env bash
    set -euo pipefail
    # A checkout on main or a release tag is usually a deployment: refuse.
    # Override with NUKE_ANYWAY=1.
    if [[ -z "${NUKE_ANYWAY:-}" ]]; then
        branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
        tag="$(git describe --tags --exact-match 2>/dev/null || true)"
        [[ "$branch" != "main" ]] || { echo "refusing to nuke on 'main' (NUKE_ANYWAY=1 to override)"; exit 1; }
        [[ -z "$tag" ]] || { echo "refusing to nuke on release tag '$tag' (NUKE_ANYWAY=1 to override)"; exit 1; }
    fi
    read -rp "⚠️  Delete containers, images AND volumes for this project? type 'yes': " c
    [[ "$c" == "yes" ]] || { echo "aborted"; exit 1; }
    just _pre-nuke
    {{compose}} down --volumes --remove-orphans {{args}}
    just rm
    # catches volumes left by services no longer in the compose file
    {{tool}} volume prune --force --filter "label=com.docker.compose.project={{project}}"
    echo "done"

# (internal) hook run by `nuke` before anything is deleted
_pre-nuke:
    just database-dump

# Show container status
ps:
    {{compose}} ps

# Follow logs, optionally for one service: `just logs frontend`
logs *args:
    {{compose}} logs -f {{args}}

# Run a command in a running service container: `just exec frontend ls`
exec service *cmd:
    #!/usr/bin/env bash
    set -euo pipefail
    cid="$(just _cid {{service}})"
    [ -n "$cid" ] || { echo "no running container for service '{{service}}'"; exit 1; }
    ti=-i; [ -t 0 ] && ti=-ti
    shift # "$@" keeps each argument intact; {{cmd}} would re-split quoted ones
    exec {{tool}} exec $ti "$cid" "$@"

# Open an interactive shell in a service container: `just sh frontend`
sh service:
    #!/usr/bin/env bash
    set -euo pipefail
    cid="$(just _cid {{service}})"
    [ -n "$cid" ] || { echo "no running container for service '{{service}}'"; exit 1; }
    ti=-i; [ -t 0 ] && ti=-ti
    exec {{tool}} exec $ti "$cid" sh -c 'exec "$(command -v bash || command -v sh)"'

# Detach with Ctrl-C (non-tty services) or ctrl-p ctrl-q; the container keeps running.
# Attach this terminal to a running service's live stdio: `just attach frontend`
attach service:
    #!/usr/bin/env bash
    set -euo pipefail
    cid="$(just _cid {{service}})"
    [ -n "$cid" ] || { echo "no running container for service '{{service}}'"; exit 1; }
    exec {{tool}} attach --sig-proxy=false "$cid"

# (internal) print the container id for a compose service in this project
_cid service:
    @{{tool}} ps -q --filter "label=com.docker.compose.project.working_dir={{justfile_directory()}}" --filter "label=com.docker.compose.service={{service}}" | head -n1

# Diagnose the stack: prints what looks wrong; full report in .compose-diagnostic-<time>.md to share
compose-diagnostic:
    @python3 scripts/compose_diagnostic.py --tool {{tool}}

#### Lint

# Lint every workflow: syntax + shellcheck, security audit, schema
lint-workflows:
    actionlint
    zizmor .github/
    check-jsonschema --builtin-schema vendor.github-workflows .github/workflows/*.yml

#### Database
# Postgres backup/restore in pg_dump's custom format (compressed, restorable
# with pg_restore) for the `db` service, using POSTGRES_USER / POSTGRES_DB
# from .env. `nuke` dumps first through `_pre-nuke`.

# Dump the database to db_backup_<timestamp>.dump
database-dump:
    #!/usr/bin/env bash
    set -euo pipefail
    source <(just _ensure-db)
    # computed once, so the file written and the name printed always match
    out="db_backup_$(date +%Y%m%d_%H%M%S).dump"
    # via a temp file: a failed pg_dump must not leave an empty "backup"
    {{tool}} exec "$cid" pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -Fc > "$out.part" \
        || { rm -f "$out.part"; exit 1; }
    mv "$out.part" "$out"
    echo "Dumped database into $out"

# Restore a dump, replacing what it contains: `just database-pipe db_backup_x.dump`
database-pipe file:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ -f "{{file}}" ]] || { echo "{{file}} not found" >&2; exit 1; }
    source <(just _ensure-db)
    {{tool}} exec -i "$cid" pg_restore -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" --clean --if-exists < "{{file}}"
    echo "Restored {{file}} into the database"

# (internal) start `db` if it is down, wait for it, and print `cid=<id>`.
# A db started here is stopped again when the calling recipe exits.
_ensure-db:
    #!/usr/bin/env bash
    set -euo pipefail
    cid="$(just _cid db)"
    if [[ -z "$cid" ]]; then
        echo "db is down -- starting it" >&2
        {{compose}} up -d db >&2
        for _ in $(seq 1 30); do
            cid="$(just _cid db)"
            [[ -n "$cid" ]] && {{tool}} exec "$cid" pg_isready -U "${POSTGRES_USER}" >/dev/null 2>&1 && break
            sleep 1
        done
        echo "trap '{{tool}} stop $cid >/dev/null || true' EXIT"
    fi
    [[ -n "$cid" ]] || { echo "could not find the db container" >&2; exit 1; }
    echo "cid=$cid"
