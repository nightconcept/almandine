{ pkgs, inputs, ... }:
let
  pkgs-unstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.system; };
in
{
  packages = with pkgs-unstable; [
    lua51Packages.busted
    lua51Packages.luacheck
    lua51Packages.luacov
    pre-commit
  ];

  languages.lua = {
    enable = true;
    package = pkgs-unstable.lua5_1;
  };

  languages.javascript = {
    enable = true;
    package = pkgs-unstable.nodejs_22;
  };

  enterShell = ''
    # Ensure pre-commit hook is installed/updated on direnv/devenv entry
    if [ -d .git ]; then
      pre-commit install --install-hooks --overwrite || true
    fi
  '';
}