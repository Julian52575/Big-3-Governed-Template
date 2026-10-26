# shellcheck, official static release binary. Bump: version, then the four
# hashes (`nix store prefetch-file <url>`).
{ pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  target = {
    x86_64-linux = "linux.x86_64";
    aarch64-linux = "linux.aarch64";
    x86_64-darwin = "darwin.x86_64";
    aarch64-darwin = "darwin.aarch64";
  }.${system};
  hash = {
    x86_64-linux = "sha256-jDvhKwXVwXegTCnjx4zomshvFZVoHKsUm2W5fE4icZg=";
    aarch64-linux = "sha256-ErMxwdLba56xPPymQwaxsVeobraduDAj4mHqp+fBRYg=";
    x86_64-darwin = "sha256-PInbTtyrfPHCe/8XiILg9vJ/ev31ToWfoEH8oQ/r5MY=";
    aarch64-darwin = "sha256-Vq/92N5VJ4lNym3D1+Cpmoc7DwBNeqvDCuQH0/SLCnk=";
  }.${system};
in
pkgs.stdenvNoCC.mkDerivation rec {
  pname = "shellcheck";
  version = "0.11.0";
  src = pkgs.fetchurl {
    url = "https://github.com/koalaman/shellcheck/releases/download/v${version}/shellcheck-v${version}.${target}.tar.xz";
    inherit hash;
  };
  installPhase = "install -Dm755 shellcheck $out/bin/shellcheck";
}
