# lolcat: nixpkgs already ships the latest release (a Ruby gem, no binary
# release). The assertion fails the build if nixpkgs ever moves off it, so a
# channel bump cannot change the version silently.
{ pkgs }:
let version = "100.0.1"; in
assert pkgs.lolcat.version == version;
pkgs.lolcat
