# MacBookPro16,1 (Apple T2) host configuration
{ config, lib, pkgs, ... }:

{
  imports = [
    ./configuration.nix
  ];

  networking.hostName = "macbookpro";
}
