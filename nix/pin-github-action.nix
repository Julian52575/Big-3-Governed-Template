# pin-github-action: pins `uses:` refs in workflows to commit SHAs. No binary
# release, so it is built from the tagged source. Bump: version, then `hash`
# and `npmDepsHash` (a build with a wrong hash prints the right one).
{ pkgs }:
pkgs.buildNpmPackage rec {
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
}
