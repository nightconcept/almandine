{ pkgs, inputs, ... }:
{
  packages = with pkgs; [
    lua51Packages.busted
    lua51Packages.luacheck
    lua51Packages.luacov
    pre-commit
  ];

  languages.lua = {
    enable = true;
    package = pkgs.lua5_1;
  };

  languages.javascript = {
    enable = true;
    package = pkgs.nodejs_22;
  };

  enterShell = ''
    # Ensure pre-commit hook is installed/updated on direnv/devenv entry
    if [ -d .git ]; then
      pre-commit install --install-hooks --overwrite || true
    fi
  '';
}