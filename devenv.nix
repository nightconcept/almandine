{ pkgs, inputs, ... }:
let
  pkgs-unstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.system; };
in
{
  packages = with pkgs-unstable; [
    lua51Packages.busted
    lua51Packages.luacheck
    lua51Packages.luacov
  ];

  languages.lua = {
    enable = true;
    package = pkgs.lua5_1;
  };
}