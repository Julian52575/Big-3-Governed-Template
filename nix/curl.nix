# curl: upstream publishes source only, so this rebuilds nixpkgs' curl from the
# pinned release. Bump: version, then `hash` (`nix store prefetch-file <url>`).
{ pkgs }:
pkgs.curlMinimal.overrideAttrs (old: rec {
  version = "8.23.0";
  src = pkgs.fetchurl {
    url = "https://curl.se/download/curl-${version}.tar.xz";
    hash = "sha256-ja3X0lNqMU+YKtBaZRtxP0Jr99Aswsds/7l5byIY5sU=";
  };
  # nixpkgs' patches target its own older release
  patches = [ ];
})
