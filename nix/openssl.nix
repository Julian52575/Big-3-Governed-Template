# openssl: upstream publishes source only, so this rebuilds nixpkgs' openssl
# from the pinned release. Only the CLI is used (`openssl rand` in the
# shellHook); nothing else links against it. Bump: version, then `hash`.
{ pkgs }:
pkgs.openssl.overrideAttrs (old: rec {
  version = "4.1.0";
  src = pkgs.fetchurl {
    url = "https://github.com/openssl/openssl/releases/download/openssl-${version}/openssl-${version}.tar.gz";
    hash = "sha256-UMF7r1TLAI9s5C1Q3rSygFChqtcRY2yr1LJBx+kMwv0=";
  };
  # nixpkgs' patches target its own 3.x release
  patches = [ ];
})
