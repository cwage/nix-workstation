# MacBookPro16,1 (Apple T2) host configuration
{ config, lib, pkgs, ... }:

{
  imports = [
    ./configuration.nix
  ];

  networking.hostName = "macbookpro";

  # This machine is dedicated to the Smallstep contract for now, so the tooling
  # goes on the main account rather than a separate one. The "work" profile
  # leaves ~/.ssh/config and ~/.gitconfig.local unmanaged so onboarding tooling
  # (`step ssh config`, etc.) can write to them; both are hand-maintained here.
  home-manager.users.cwage = {
    imports = [ ../common/smallstep-tools.nix ];
    dotfiles.profile = "work";
  };
}
