{ pkgs, inputs, ... }:
let
  pkgs-unstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.system; };
in
{
  packages = with pkgs-unstable; [
    lua51Packages.busted
    lua51Packages.luacheck
  ];

  languages.lua = {
    enable = true;
    package = pkgs.lua5_1;
  };
}