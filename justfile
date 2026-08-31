set dotenv-load := true
set shell := ["bash", "-eu", "-c"]

# List available recipes
default:
    @just --list
    @echo "\nusing: {{tool}}"

#### Container

# podman if present, else docker -- every recipe goes through this
tool := `command -v podman >/dev/null && echo podman || echo docker`
compose := tool + " compose"

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
    project="$(basename "$PWD" | tr '[:upper:] ' '[:lower:]-')"
    {{tool}} images -q \
        --filter "reference=${project}*" --filter "reference=localhost/${project}*" \
      | sort -u | xargs -r {{tool}} rmi -f || true

# Like `just rm`, but also delete named volumes -- wipes db data etc.
nuke *args:
    #!/usr/bin/env bash
    set -euo pipefail
    read -rp "Delete containers, images AND volumes for this project? type 'yes': " c
    [[ "$c" == "yes" ]] || { echo "aborted"; exit 1; }
    {{compose}} down --volumes --remove-orphans {{args}}
    just rm
    echo "done"

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
