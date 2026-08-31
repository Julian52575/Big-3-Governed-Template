{
  description = "Dev environment template: Nix + Just + rootless Podman + Traefik";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
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
            # rootless podman stack
            podman
            podman-compose
            fuse-overlayfs # rootless overlay storage driver
            crun # OCI runtime (containers.conf pins runtime = "crun")
            slirp4netns # rootless networking / port publishing
            passt # pasta, podman's newer rootless net backend
            catatonit # lightweight PID 1 for `--init` / compose
            curl # the shellHook pings the podman API socket with it
            util-linux # setsid -- detaches the fallback API service from the tty
          ];

          shellHook = ''
            # --- .env (optional) -------------------------------------------
            if [ -f .env ]; then
              set -a
              . ./.env
              set +a
            fi

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

            echo "dev shell ready -- run 'just' to see available commands. Using $(podman --version)" | lolcat
          '';
        };
      });
    };
}
