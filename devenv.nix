# devenv.nix
{ pkgs, inputs, ... }:
let
  # Import the unstable Nixpkgs set, using the 'system' from the default pkgs
  pkgs-unstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.system; };
in
{
  # Add packages required for your environment
  packages = [
    pkgs-unstable.lua51Packages.busted # Get Busted from nixpkgs-unstable
    # You could add other general tools here, e.g., pkgs.git
  ];

  # Enable Lua language support
  languages.lua = {
    enable = true;
    # Specify the Lua version (using the default pkgs here, but could use pkgs-unstable.lua5_1 if needed)
    package = pkgs.lua5_1;
  };
}