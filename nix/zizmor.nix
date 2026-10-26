# zizmor, official release binary. Bump: version, then the four hashes
# (`nix store prefetch-file <url>`). Keep in sync with the `zizmor` job in ci.yml.
{ pkgs, ... }:
let
  inherit (pkgs) lib stdenv;
  system = stdenv.hostPlatform.system;
  target = {
    x86_64-linux = "x86_64-unknown-linux-gnu";
    aarch64-linux = "aarch64-unknown-linux-gnu";
    x86_64-darwin = "x86_64-apple-darwin";
    aarch64-darwin = "aarch64-apple-darwin";
  }.${system};
  hash = {
    x86_64-linux = "sha256-0YX3Jr2vkt94JzIX390k681rDvSM8853b/V2K24TjJk=";
    aarch64-linux = "sha256-N+671XYqRPJi2Uh1QxsUptJAKZHpCmhRE+qXuLQb6DM=";
    x86_64-darwin = "sha256-cq5ju4W2cinAYkLwQZXLQ5J+n6tfQ4A8ZDTccBpRfWE=";
    aarch64-darwin = "sha256-rVqmM81WIVsR5sUdUfkMfmsikEp1BH0SFau9Qi9h1pg=";
  }.${system};
in
pkgs.stdenvNoCC.mkDerivation rec {
  pname = "zizmor";
  version = "1.31.1";
  src = pkgs.fetchurl {
    url = "https://github.com/zizmorcore/zizmor/releases/download/v${version}/zizmor-${target}.tar.gz";
    inherit hash;
  };
  # glibc build: patch its interpreter for the Nix store
  nativeBuildInputs = lib.optional stdenv.isLinux pkgs.autoPatchelfHook;
  buildInputs = lib.optional stdenv.isLinux stdenv.cc.cc.lib;
  sourceRoot = ".";
  installPhase = "install -Dm755 zizmor $out/bin/zizmor";
}
