# just, official static release binary. Bump: version, then the four hashes
# (`nix store prefetch-file <url>`).
{ pkgs }:
let
  system = pkgs.stdenv.hostPlatform.system;
  target = {
    x86_64-linux = "x86_64-unknown-linux-musl";
    aarch64-linux = "aarch64-unknown-linux-musl";
    x86_64-darwin = "x86_64-apple-darwin";
    aarch64-darwin = "aarch64-apple-darwin";
  }.${system};
  hash = {
    x86_64-linux = "sha256-QJBEYXtvBlF8EDXlXKOMjIVv+LZQ5BvCqh74LVkDoj4=";
    aarch64-linux = "sha256-I4cbFwK/1VD7X5AXeP1CkOzy7gNKRaiJ++ltibGICG0=";
    x86_64-darwin = "sha256-A26tnfm8MduumTSuO0I27RJNC6/P/TNDlGCuCE1cnLc=";
    aarch64-darwin = "sha256-ZXTOp3TtTK4S4ktqoRhX3jPoDatGZ89ij9WEDflqKp0=";
  }.${system};
in
pkgs.stdenvNoCC.mkDerivation rec {
  pname = "just";
  version = "1.59.0";
  src = pkgs.fetchurl {
    url = "https://github.com/casey/just/releases/download/${version}/just-${version}-${target}.tar.gz";
    inherit hash;
  };
  sourceRoot = ".";
  installPhase = "install -Dm755 just $out/bin/just";
}
