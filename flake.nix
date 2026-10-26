{
  description = "Dev environment template: Nix + Just + rootless Podman + Traefik";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          # Everything a bare `nix develop` needs so `just up` works with no
          # host container packages installed. Add project tooling here.
          packages = with pkgs; [
            lolcat
            just
            jq
            openssl # the shellHook fills `change-me-*` secrets in .env
            podman-compose
            curl # the shellHook pings the podman API socket with it
            nodejs_24 # npm for frontend/ and backend/
            # workflow linting (`just lint-workflows`)
            actionlint
            shellcheck # actionlint uses it to lint `run:` scripts
            check-jsonschema # validates workflows: --builtin-schema vendor.github-workflows
          ] ++ lib.optionals stdenv.isLinux [
            # rootless podman stack. On macOS, Podman comes from the host
            # (Podman Desktop, Homebrew or MacPorts) and runs in `podman machine`.
            podman
            fuse-overlayfs # rootless overlay storage driver
            crun # OCI runtime (containers.conf pins runtime = "crun")
            slirp4netns # rootless networking / port publishing
            passt # pasta, podman's newer rootless net backend
            catatonit # lightweight PID 1 for `--init` / compose
            util-linux # setsid -- detaches the fallback API service from the tty
          ] ++ (import ./nix/tools.nix { inherit pkgs; }).all;

          shellHook = ''
            # --- .env ----------------------------------------------------
            if [ ! -e .env ] && [ -f .env.example ]; then
              cp .env.example .env && echo "env: created .env from .env.example"
            fi
            # Carry over variables added to .env.example since .env was made;
            # podman-compose passes an unset variable through literally.
            if [ -f .env ] && [ -f .env.example ]; then
              for key in $(sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p' .env.example); do
                if ! grep -qE "^$key=" .env; then
                  grep -E "^$key=" .env.example >> .env
                  echo "env: added $key from .env.example"
                fi
              done
            fi
            # Any value starting with `change-me-` is a placeholder secret:
            # replace it once, so re-entering the shell never rotates it.
            if [ -f .env ] && command -v openssl >/dev/null 2>&1; then
              for key in $(sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*)="?change-me-.*/\1/p' .env); do
                # -i.bak: works with both GNU and BSD (macOS) sed
                sed -i.bak "s|^$key=.*|$key=$(openssl rand -hex 32)|" .env && rm -f .env.bak
                echo "env: generated $key (openssl rand -hex 32)"
              done
            fi
            if [ -f .env ]; then
              set -a
              . ./.env
              set +a
            fi

            # --- container tooling ---------------------------------------
            # Inside this shell everything goes through rootless Podman:
            # `podman compose` must delegate to the pinned podman-compose,
            # never to a host docker-compose it might find first.
            export PODMAN_COMPOSE_PROVIDER="$(command -v podman-compose)"
            export PODMAN_COMPOSE_WARNING_LOGS=false

            if [ "$(uname -s)" = "Darwin" ]; then
              # --- macOS: host Podman inside `podman machine` ---------------
              # Nothing to configure locally; only expose the machine's API
              # socket for Docker-compatible tools (and Traefik's bind mount).
              if ! command -v podman >/dev/null 2>&1; then
                echo "podman: not found -- install Podman Desktop, or 'brew install podman'" >&2
              elif ! podman info >/dev/null 2>&1; then
                echo "podman: the machine is not running -- 'podman machine init' once, then 'podman machine start'" >&2
              elif [ -z "''${PODMAN_NO_SOCKET:-}" ]; then
                podman_sock="$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null | head -n1)"
                if [ -S "$podman_sock" ]; then
                  export DOCKER_HOST="unix://$podman_sock"
                  export DOCKER_SOCK="$podman_sock"
                  echo "podman: Docker-compatible API at $DOCKER_HOST" | lolcat
                else
                  echo "podman: machine API socket not found ('$podman_sock')" >&2
                fi
              fi
            else
              proj="$(basename "$PWD")"

              # --- in-repo rootless podman config --------------------------
              # Point podman at the checked-in config through its per-file env
              # vars so nothing under ~ or /etc is mutated. Only policy.json
              # has no env var, so it gets a user-owned symlink -- and only
              # when nothing is there already.
              export PODMAN_CONFIG_DIR="$PWD/.config/podman"
              export CONTAINERS_CONF="$PODMAN_CONFIG_DIR/containers.conf"
              export CONTAINERS_STORAGE_CONF="$PODMAN_CONFIG_DIR/storage.conf"
              export CONTAINERS_REGISTRIES_CONF="$PODMAN_CONFIG_DIR/registries.conf"
              if [ ! -e ~/.config/containers/policy.json ] && [ ! -L ~/.config/containers/policy.json ]; then
                mkdir -p ~/.config/containers
                ln -s "$PODMAN_CONFIG_DIR/policy.json" ~/.config/containers/policy.json
                echo "podman: linked in-repo policy.json -> ~/.config/containers/policy.json"
              fi

              # --- container storage root ---------------------------------
              # Podman's overlay storage needs real POSIX filesystem semantics.
              # Network / virtualised filesystems (9p/drvfs under WSL2, NFS,
              # CIFS/SMB, sshfs) can misreport file types and cause obscure
              # "Not a directory" mount errors. Detect that generically and
              # fall back to a local path under $HOME.
              is_network_fs() {
                case "$(stat -f -c %T "$1" 2>/dev/null)" in
                  v9fs|cifs|smb2|smbfs|nfs|nfs4|nfsd|afs|coda|ncpfs|fuseblk) return 0 ;;
                  *) return 1 ;;
                esac
              }

              STORAGE_ROOT="''${PODMAN_STORAGE_DIR:-$PWD/.containers}"
              if [ -z "''${PODMAN_STORAGE_DIR:-}" ] && is_network_fs "$PWD"; then
                if is_network_fs "$HOME"; then
                  echo "podman: \$PWD and \$HOME are both on a network fs -- set PODMAN_STORAGE_DIR to a local disk." >&2
                else
                  STORAGE_ROOT="$HOME/.cache/podman-storage/$proj"
                  echo "podman: project is on $(stat -f -c %T "$PWD"); using $STORAGE_ROOT for container storage"
                fi
              fi
              mkdir -p "$STORAGE_ROOT"

              use_pct=$(df -P "$STORAGE_ROOT" 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')
              if [ -n "$use_pct" ] && [ "$use_pct" -ge 90 ] 2>/dev/null; then
                echo "podman: warning -- disk backing $STORAGE_ROOT is ''${use_pct}% full" >&2
              fi

              printf '%s\n' \
                '[storage]' \
                'driver = "overlay"' \
                "runroot = \"$STORAGE_ROOT/run\"" \
                "graphroot = \"$STORAGE_ROOT/storage\"" \
                '[storage.options]' \
                "mount_program = \"$(command -v fuse-overlayfs)\"" \
                > "$CONTAINERS_STORAGE_CONF"

              # --- Docker-compatible API socket --------------------------
              # Exposes a Docker API socket via DOCKER_HOST for tools that
              # expect one (`docker compose`, testcontainers, lazydocker...).
              # podman-compose itself does NOT need it. First match wins:
              #   1. a socket already answers      -> reuse it
              #   2. systemd --user podman.socket  -> real socket activation
              #   3. detached `podman system service` -> dies with this shell
              # Set PODMAN_NO_SOCKET=1 to skip this block entirely (CI/headless).
              if [ -z "''${PODMAN_NO_SOCKET:-}" ]; then
                podman_sock="$(podman info --format '{{.Host.RemoteSocket.Path}}' 2>/dev/null || true)"
                : "''${podman_sock:=''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock}"
                export DOCKER_HOST="unix://$podman_sock"
                export DOCKER_SOCK="$podman_sock" # bare path, for bind-mounting into containers (see docker-compose.yml)
                mkdir -p "$(dirname "$podman_sock")"

                _ping() { curl -fsS --max-time 2 --unix-socket "$podman_sock" http://d/_ping >/dev/null 2>&1; }
                _wait() { for _ in $(seq 40); do _ping && return 0; sleep 0.25; done; return 1; }

                if _ping; then
                  echo "podman: reusing running API socket ($podman_sock)" | lolcat
                elif [ "$(systemctl --user show -p LoadState --value podman.socket 2>/dev/null)" = "loaded" ] \
                     && systemctl --user start podman.socket >/dev/null 2>&1 && _wait; then
                  echo "podman: using systemd --user podman.socket (on-demand, self-reaping)" | lolcat
                else
                  pidfile="$(dirname "$podman_sock")/$proj-nix-shell.pid"
                  owned=""
                  if [ -f "$pidfile" ] \
                     && kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null \
                     && tr '\0' ' ' < "/proc/$(cat "$pidfile")/cmdline" 2>/dev/null | grep -q podman; then
                    owned="$(cat "$pidfile")"
                    echo "podman: adopted API service from an earlier shell (pid $owned)" | lolcat
                  else
                    rm -f "$pidfile"
                    [ -e "$podman_sock" ] && ! _ping && rm -f "$podman_sock"
                    # Own session (setsid) so Ctrl-C / SIGHUP on the interactive
                    # shell can't reach it; only the EXIT trap below stops it.
                    if command -v setsid >/dev/null 2>&1; then
                      setsid sh -c 'echo $$ > "$1"; exec podman system service --time=0 "unix://$2"' \
                        sh "$pidfile" "$podman_sock" >/dev/null 2>&1 &
                    else
                      ( trap "" INT QUIT HUP; echo $$ > "$pidfile"
                        exec podman system service --time=0 "unix://$podman_sock" >/dev/null 2>&1 ) &
                    fi
                    disown 2>/dev/null || true
                    for _ in $(seq 30); do [ -s "$pidfile" ] && break; sleep 0.1; done
                    owned="$(cat "$pidfile" 2>/dev/null || true)"
                    [ -n "$owned" ] || owned=$!
                    _wait || echo "podman: warning -- API socket $podman_sock did not come up" >&2
                    echo "podman: started detached API service (pid $owned, stops when this shell exits)" | lolcat
                  fi
                  # Only the shell that owns the process tears it down.
                  trap '
                    _p="'"$owned"'"
                    if [ -n "$_p" ]; then
                      kill "$_p" 2>/dev/null || true
                      [ "$(cat "'"$pidfile"'" 2>/dev/null)" = "$_p" ] && rm -f "'"$pidfile"'"
                    fi
                  ' EXIT
                fi
              fi
            fi

            # --- Conventional Commits hook ------------------------------
            # Point git at the in-repo hooks so `.githooks/commit-msg` runs
            # (git's default .git/hooks/ is not version-controlled); it execs
            # `.githooks/check-conventional-commit-msg`. Local feedback only --
            # the enforced gate is the PR-title check in
            # .github/workflows/check-conventional-commit-pr-title.yml.
            if git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
               && [ "$(git config --local core.hooksPath 2>/dev/null || true)" != ".githooks" ]; then
              git config --local core.hooksPath .githooks
              echo "git: commit-msg hook enabled (.githooks -- Conventional Commits)"
            fi

            echo "dev shell ready -- run 'just' to see available commands. Using $(podman --version 2>/dev/null || echo 'no podman')" | lolcat
          '';
        };
      });
    };
}
