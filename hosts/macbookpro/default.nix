# MacBookPro16,1 (Apple T2) host configuration
{ config, lib, pkgs, ... }:

{
  imports = [
    ./configuration.nix
  ];

  networking.hostName = "macbookpro";

  # This machine is dedicated to the Smallstep contract for now, so the tooling
  # goes on the main account rather than a separate one. The "work" profile
  # leaves ~/.gitconfig.local unmanaged so onboarding tooling can write to it.
  # ~/.ssh/config is never a managed file (`step ssh config` owns it);
  # ssh.personalHosts links the personal hosts into ~/.ssh/config.d/ and
  # appends an Include for them if it's missing.
  home-manager.users.cwage = {
    imports = [ ../common/smallstep-tools.nix ];
    dotfiles.profile = "work";
    dotfiles.ssh.personalHosts = true;
  };
}
