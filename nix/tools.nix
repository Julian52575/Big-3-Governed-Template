# CLIs pinned to exact upstream releases, independent of the nixpkgs channel.
# Bump: change the version, then refresh hashes with
# `nix store prefetch-file <url>` (per system).
{ pkgs }:
let
  inherit (pkgs) lib stdenvNoCC fetchurl;
  system = pkgs.stdenv.hostPlatform.system;

  zizmorTarget = {
    x86_64-linux = "x86_64-unknown-linux-gnu";
    aarch64-linux = "aarch64-unknown-linux-gnu";
    x86_64-darwin = "x86_64-apple-darwin";
    aarch64-darwin = "aarch64-apple-darwin";
  }.${system};

  zizmorHash = {
    x86_64-linux = "sha256-0YX3Jr2vkt94JzIX390k681rDvSM8853b/V2K24TjJk=";
    aarch64-linux = "sha256-N+671XYqRPJi2Uh1QxsUptJAKZHpCmhRE+qXuLQb6DM=";
    x86_64-darwin = "sha256-cq5ju4W2cinAYkLwQZXLQ5J+n6tfQ4A8ZDTccBpRfWE=";
    aarch64-darwin = "sha256-rVqmM81WIVsR5sUdUfkMfmsikEp1BH0SFau9Qi9h1pg=";
  }.${system};
in
rec {
  # nixpkgs 25.05 ships 1.8.0; keep this in sync with the `zizmor` job in ci.yml
  zizmor = stdenvNoCC.mkDerivation rec {
    pname = "zizmor";
    version = "1.31.1";
    src = fetchurl {
      url = "https://github.com/zizmorcore/zizmor/releases/download/v${version}/zizmor-${zizmorTarget}.tar.gz";
      hash = zizmorHash;
    };
    nativeBuildInputs = lib.optional pkgs.stdenv.isLinux pkgs.autoPatchelfHook;
    buildInputs = lib.optional pkgs.stdenv.isLinux pkgs.stdenv.cc.cc.lib;
    sourceRoot = ".";
    installPhase = "install -Dm755 zizmor $out/bin/zizmor";
  };

  # Pins `uses:` refs in workflows to commit SHAs
  pin-github-action = pkgs.buildNpmPackage rec {
    pname = "pin-github-action";
    version = "3.5.2";
    src = pkgs.fetchFromGitHub {
      owner = "mheap";
      repo = "pin-github-action";
      rev = "v${version}";
      hash = "sha256-k29f/8mBNgOjsPejLEn0UiczvawepeQtQjwesPqJPZc=";
    };
    npmDepsHash = "sha256-RlmtwE6AUV6RnAIwGly1pnuLbcLJ7nbUxH6NHX0IGg0=";
    dontNpmBuild = true;
  };

  all = [ zizmor pin-github-action ];
}
