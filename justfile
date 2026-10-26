set dotenv-load := true
set shell := ["bash", "-eu", "-c"]
# Recipes also get their arguments as "$@", so quoted arguments stay intact.
set positional-arguments := true

# podman if present, else docker -- every recipe goes through this
tool := `command -v podman >/dev/null && echo podman || echo docker`
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

# Like `just rm`, but also delete named volumes -- wipes db data etc.
nuke *args:
    #!/usr/bin/env bash
    set -euo pipefail
    read -rp "⚠️  Delete containers, images AND volumes for this project? type 'yes': " c
    [[ "$c" == "yes" ]] || { echo "aborted"; exit 1; }
    just _pre-nuke
    {{compose}} down --volumes --remove-orphans {{args}}
    just rm
    # catches volumes left by services no longer in the compose file
    {{tool}} volume prune --force --filter "label=com.docker.compose.project={{project}}"
    echo "done"

# (internal) hook run by `nuke` before anything is deleted, e.g. `just database-dump`
_pre-nuke:
    @true

# Show container status
ps:
    {{compose}} ps

# Follow logs, optionally for one service: `just logs web`
logs *args:
    {{compose}} logs -f {{args}}

# Run a command in a running service container: `just exec web ls`
exec service *cmd:
    #!/usr/bin/env bash
    set -euo pipefail
    cid="$(just _cid {{service}})"
    [ -n "$cid" ] || { echo "no running container for service '{{service}}'"; exit 1; }
    ti=-i; [ -t 0 ] && ti=-ti
    exec {{tool}} exec $ti "$cid" {{cmd}}

# Open an interactive shell in a service container: `just sh web`
sh service:
    #!/usr/bin/env bash
    set -euo pipefail
    cid="$(just _cid {{service}})"
    [ -n "$cid" ] || { echo "no running container for service '{{service}}'"; exit 1; }
    ti=-i; [ -t 0 ] && ti=-ti
    exec {{tool}} exec $ti "$cid" sh -c 'exec "$(command -v bash || command -v sh)"'

# Detach with Ctrl-C (non-tty services) or ctrl-p ctrl-q; the container keeps running.
# Attach this terminal to a running service's live stdio: `just attach web`
attach service:
    #!/usr/bin/env bash
    set -euo pipefail
    cid="$(just _cid {{service}})"
    [ -n "$cid" ] || { echo "no running container for service '{{service}}'"; exit 1; }
    exec {{tool}} attach --sig-proxy=false "$cid"

# (internal) print the container id for a compose service in this project
_cid service:
    @{{tool}} ps -q --filter "label=com.docker.compose.project.working_dir={{justfile_directory()}}" --filter "label=com.docker.compose.service={{service}}" | head -n1

#### Lint

# Lint every workflow: syntax + shellcheck, security audit, schema
lint-workflows:
    actionlint
    zizmor .github/
    check-jsonschema --builtin-schema vendor.github-workflows .github/workflows/*.yml

#### Database (example)
# Postgres backup/restore, for a compose service named `db` with POSTGRES_USER
# and POSTGRES_DB in .env. Uncomment once you add one, and make `_pre-nuke`
# run `just database-dump` so `nuke` never deletes data without a backup.

# # Dump the whole database to db_backup_<timestamp>.sql
# database-dump:
#     #!/usr/bin/env bash
#     set -euo pipefail
#     source <(just _ensure-db)
#     out="db_backup_$(date +%Y%m%d_%H%M%S).sql"
#     {{tool}} exec "$cid" pg_dumpall -U "${POSTGRES_USER}" > "$out"
#     echo "Dumped database into $out"
#
# # Pipe a .sql file into the database: `just database-pipe db_backup_x.sql`
# database-pipe file:
#     #!/usr/bin/env bash
#     set -euo pipefail
#     [[ -f "{{file}}" ]] || { echo "{{file}} not found" >&2; exit 1; }
#     source <(just _ensure-db)
#     {{tool}} exec -i "$cid" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" < "{{file}}"
#     echo "Piped {{file}} into the database"
#
# # (internal) start `db` if it is down, wait for it, and print `cid=<id>`.
# # A db started here is stopped again when the calling recipe exits.
# _ensure-db:
#     #!/usr/bin/env bash
#     set -euo pipefail
#     cid="$(just _cid db)"
#     if [[ -z "$cid" ]]; then
#         echo "db is down -- starting it" >&2
#         {{compose}} up -d db >&2
#         for _ in $(seq 1 30); do
#             cid="$(just _cid db)"
#             [[ -n "$cid" ]] && {{tool}} exec "$cid" pg_isready -U "${POSTGRES_USER}" >/dev/null 2>&1 && break
#             sleep 1
#         done
#         echo "trap '{{tool}} stop $cid >/dev/null || true' EXIT"
#     fi
#     [[ -n "$cid" ]] || { echo "could not find the db container" >&2; exit 1; }
#     echo "cid=$cid"
