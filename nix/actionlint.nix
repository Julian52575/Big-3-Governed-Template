# actionlint, official static release binary. Bump: version, then the four
# hashes (`nix store prefetch-file <url>`). It runs shellcheck on `run:` scripts.
{ pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  target = {
    x86_64-linux = "linux_amd64";
    aarch64-linux = "linux_arm64";
    x86_64-darwin = "darwin_amd64";
    aarch64-darwin = "darwin_arm64";
  }.${system};
  hash = {
    x86_64-linux = "sha256-isqNuW8blHcPGw1ytt3cseu4EjyzcSUwsIzDh7NJo9g=";
    aarch64-linux = "sha256-Ml6XG2upv6UEZy4pvpPCSYHuscB1dtcw6ffIgFr/8MY=";
    x86_64-darwin = "sha256-W0TDvCJVEVybaeMO/A/s30mP22PF1Y4XCE/V8WMkxkQ=";
    aarch64-darwin = "sha256-q6nO0t7o0n/syj3H/rGn+aUsrvoetG8ycepmtuDmlT8=";
  }.${system};
in
pkgs.stdenvNoCC.mkDerivation rec {
  pname = "actionlint";
  version = "1.7.12";
  src = pkgs.fetchurl {
    url = "https://github.com/rhysd/actionlint/releases/download/v${version}/actionlint_${version}_${target}.tar.gz";
    inherit hash;
  };
  sourceRoot = ".";
  installPhase = "install -Dm755 actionlint $out/bin/actionlint";
}
