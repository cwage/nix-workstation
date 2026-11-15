# System76 Darter Pro (darp11-b) host configuration
{ config, lib, pkgs, ... }:

{
  imports = [
    ./configuration.nix
  ];

  networking.hostName = "darterpro";

  # Same arrangement as macbookpro: this is the Smallstep machine, so the
  # tooling goes on the main account rather than a separate one, and awesome
  # splits personal/work into two tag contexts (see .config/awesome/rc.lua in
  # the dotfiles). The "work" profile leaves ~/.ssh/config and
  # ~/.gitconfig.local unmanaged so onboarding tooling (`step ssh config`,
  # etc.) can write to them; both are hand-maintained here.
  home-manager.users.cwage = {
    imports = [ ../common/smallstep-tools.nix ];
    dotfiles.profile = "work";
  };
}
