# Dev-shell CLIs, one file per tool, each pinned to its latest release as a
# prebuilt binary: nothing here compiles on `nix develop`. The Podman stack
# stays on nixpkgs (see flake.nix). Each file says how to bump it.
{ pkgs, unstable }:
# Only each tool's binaries: a `dev` output (curl's) would also put nixpkgs'
# own openssl on PATH.
map (file: pkgs.lib.getBin (import file { inherit pkgs unstable; })) [
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
