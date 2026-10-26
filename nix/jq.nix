# jq, official static release binary. Bump: version, then the four hashes
# (`nix store prefetch-file <url>`).
{ pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  target = {
    x86_64-linux = "linux-amd64";
    aarch64-linux = "linux-arm64";
    x86_64-darwin = "macos-amd64";
    aarch64-darwin = "macos-arm64";
  }.${system};
  hash = {
    x86_64-linux = "sha256-scIhct0wPzvknpNapWqkiot6RuC8g4tJl9O7RRSVhw8=";
    aarch64-linux = "sha256-i4XIF4M4FN3KAKFEwzcFVGNVr8zwzzmxiPPNtIuFIwk=";
    x86_64-darwin = "sha256-6UsmbjwmaQVQAGq+YxUreCKA9OFDdKzN8Ey96ETwC8A=";
    aarch64-darwin = "sha256-LXU0C6V6S0tMhwiiHC3I6VikiqqLuhOyf3f25MDsoH4=";
  }.${system};
in
pkgs.stdenvNoCC.mkDerivation rec {
  pname = "jq";
  version = "1.8.2";
  src = pkgs.fetchurl {
    url = "https://github.com/jqlang/jq/releases/download/jq-${version}/jq-${target}";
    inherit hash;
  };
  dontUnpack = true;
  installPhase = "install -Dm755 $src $out/bin/jq";
}
