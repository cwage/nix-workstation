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
  # the dotfiles). The "work" profile leaves ~/.gitconfig.local unmanaged so
  # onboarding tooling can write to it. ~/.ssh/config is never a managed file
  # (`step ssh config` owns it); ssh.personalHosts links the personal hosts
  # into ~/.ssh/config.d/ and appends an Include for them if it's missing.
  home-manager.users.cwage = {
    imports = [ ../common/smallstep-tools.nix ];
    dotfiles.profile = "work";
    dotfiles.ssh.personalHosts = true;
  };
}
