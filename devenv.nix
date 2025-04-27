{ pkgs, lib, config, inputs, ... }:
{
  languages.lua = {
    enable = true;
    package = pkgs.lua5_1;
  };

  # need busted
}
