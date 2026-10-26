# check-jsonschema (validates workflows against GitHub's schema): a Python
# package with no binary release, so this rebuilds nixpkgs' package from the
# pinned tag. Bump: version, then `hash` (a build with a wrong hash prints it).
{ pkgs }:
let
  # It needs a newer click than nixpkgs ships; overridden for this tool only.
  python = pkgs.python3.override {
    packageOverrides = self: super: {
      click = super.click.overridePythonAttrs (old: rec {
        version = "8.5.0";
        src = pkgs.fetchFromGitHub {
          owner = "pallets";
          repo = "click";
          tag = version;
          hash = "sha256-VYdaEN9l2MRVz42I8t8IDOpG5XeDM8bf34dLZy3yf10=";
        };
        # its pager tests need a real terminal, which the build sandbox lacks
        disabledTestPaths = (old.disabledTestPaths or [ ]) ++ [ "tests/test_utils/test_echo_via_pager.py" ];
      });
    };
  };
in
(pkgs.check-jsonschema.override { python3Packages = python.pkgs; }).overridePythonAttrs (old: rec {
  version = "0.38.2";
  src = pkgs.fetchFromGitHub {
    owner = "python-jsonschema";
    repo = "check-jsonschema";
    tag = version;
    hash = "sha256-78HaLqcsL9VK+e7+9lB2WbGKG/d+vNg0bJOAxRfUlPE=";
  };
  # The dev shell's PYTHONPATH carries nixpkgs' older click (via podman-compose);
  # keep this tool on its own dependencies.
  makeWrapperArgs = (old.makeWrapperArgs or [ ]) ++ [ "--unset" "PYTHONPATH" ];
})
