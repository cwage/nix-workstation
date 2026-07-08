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

  # WireGuard tunnel address (host-specific; peer config lives in hosts/common).
  networking.wg-quick.interfaces.wg0.address = [ "10.10.16.4/32" ];

  # Hibernation support: swapfile sized to RAM (31 GiB) so suspend-then-hibernate
  # has somewhere to write the memory image. NixOS creates the file on activation.
  swapDevices = [ { device = "/swapfile"; size = 32 * 1024; } ];

  # Resume from the swapfile on the root partition. resume_offset is the
  # swapfile's physical extent start, found after the file exists via:
  #   sudo filefrag -v /swapfile | awk '$1=="0:" {print substr($4, 1, length($4)-2)}'
  boot.resumeDevice = "/dev/disk/by-uuid/6dec2fdc-865e-4f53-b2e6-10a90509fb9d";
  boot.kernelParams = [ "resume_offset=10444800" ];

  # Lid close: suspend, then hibernate once systemd estimates the battery is
  # near depletion (systemd >= 253 battery-discharge estimation; no fixed
  # HibernateDelaySec so the adaptive logic applies). Overrides the plain
  # "suspend" default in hosts/common.
  services.logind.settings.Login.HandleLidSwitch = lib.mkForce "suspend-then-hibernate";

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken.
  system.stateVersion = "25.11"; # Did you read the comment?
}
