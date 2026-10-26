# openssl: upstream publishes source only, no binary. The newest prebuilt
# build is nixpkgs-unstable's, downloaded from cache.nixos.org, never compiled
# here. The version is asserted so a `nix flake update` that moves it fails
# loudly. Bump: `nix flake update nixpkgs-unstable`, then the version below.
{ pkgs, unstable, ... }:
let version = "3.5.9"; in
# Intel Macs (no nixpkgs-unstable): the stable channel's older prebuilt build.
if unstable == null then pkgs.openssl
else assert unstable.openssl.version == version; unstable.openssl
