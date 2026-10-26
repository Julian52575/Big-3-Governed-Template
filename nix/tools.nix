# Dev-shell CLIs pinned to exact upstream releases, one file per tool,
# independent of the nixpkgs channel. The Podman stack stays on nixpkgs
# (see flake.nix). Each file says how to bump it.
{ pkgs }:
# Only each tool's binaries: a `dev` output (curl's) would also put nixpkgs'
# own openssl on PATH.
map (file: pkgs.lib.getBin (import file { inherit pkgs; })) [
  ./actionlint.nix
  ./check-jsonschema.nix
  ./curl.nix
  ./jq.nix
  ./just.nix
  ./lolcat.nix
  ./openssl.nix
  ./pin-github-action.nix
  ./shellcheck.nix
  ./zizmor.nix
]
