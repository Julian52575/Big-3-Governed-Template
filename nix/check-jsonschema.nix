# check-jsonschema (validates workflows against GitHub's schema), from its
# official PyPI wheels: a wheel is unpacked, not compiled. Its other
# dependencies come prebuilt from nixpkgs. Bump: the versions, then the
# hashes (`nix store prefetch-file <wheel url>`).
{ pkgs, ... }:
let
  py = pkgs.python3Packages;
  wheel = pname: version: hash: py.buildPythonPackage {
    inherit pname version;
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/py3/${builtins.substring 0 1 pname}/${pname}/${pname}-${version}-py3-none-any.whl";
      inherit hash;
    };
  };
  # nixpkgs' click is older than the >=8.5 check-jsonschema needs
  click = wheel "click" "8.5.0" "sha256-JVvJWZz3dItLGkRszHNUIb0Ioq5SmouIWX095WZO42A=";
in
py.buildPythonApplication {
  pname = "check-jsonschema";
  version = "0.38.2";
  format = "wheel";
  src = pkgs.fetchurl {
    url = "https://files.pythonhosted.org/packages/py3/c/check_jsonschema/check_jsonschema-0.38.2-py3-none-any.whl";
    hash = "sha256-jt7+FUtxF5YvLogxjzFfxLuWFYJ/kys3y2dqjUKjooY=";
  };
  dependencies = [ click py.jsonschema py.regress py.requests py.ruamel-yaml ];
  # The dev shell's PYTHONPATH carries nixpkgs' older click (via podman-compose);
  # keep this tool on its own dependencies.
  makeWrapperArgs = [ "--unset" "PYTHONPATH" ];
}
