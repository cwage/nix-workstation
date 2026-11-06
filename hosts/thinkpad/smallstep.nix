# Separate local account for the Smallstep contract (Nov 2026 - ~Feb 2027).
# Shares the desktop dotfiles with cwage via the "work" dotfiles profile, which
# leaves ~/.ssh and ~/.gitconfig.local unmanaged so Smallstep onboarding
# (`step ssh config`, etc.) can write to them.
#
# Password is set imperatively (mutableUsers), same as cwage.
#
# At contract end: drop this import, rebuild, then remove the account and
# home directory (`userdel -r smallstep`).
{ config, lib, pkgs, dotfiles, ... }:

{
  users.users.smallstep = {
    isNormalUser = true;
    description = "Smallstep contract";
    extraGroups = [ "wheel" "audio" "video" "networkmanager" "plugdev" "kvm" "tss" ];
  };

  home-manager.users.smallstep = {
    imports = [
      dotfiles.homeManagerModules.default
      ../common/smallstep-tools.nix
    ];
    dotfiles.profile = "work";
    home.stateVersion = "26.05";
  };
}
