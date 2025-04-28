{ pkgs, inputs, ... }:
let
  pkgs-unstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.system; };
in
{
  packages = [
    pkgs-unstable.lua51Packages.busted
  ];

  languages.lua = {
    enable = true;
    package = pkgs.lua5_1;
  };
}