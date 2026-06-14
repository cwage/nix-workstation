# ThinkPad host-specific configuration. Shared workstation config lives in
# hosts/common; only bootloader, the generated hardware scan, and stateVersion
# are host-specific here.

{ config, lib, pkgs, ... }:

{
  imports = [
    ../common
    ./hardware-configuration.nix
  ];

  # Bootloader (GRUB with EFI on NVMe). os-prober picks up the Ubuntu install
  # for dual-boot.
  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.device = "nodev";
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub.useOSProber = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken.
  system.stateVersion = "25.11"; # Did you read the comment?
}
