# Thinkpad host configuration
{ config, lib, pkgs, ... }:

{
  imports = [
    ./configuration.nix
    ./smallstep.nix
  ];

  networking.hostName = "thinkpad";
}
