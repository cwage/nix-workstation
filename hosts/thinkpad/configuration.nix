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
  # Cap boot menu entries; older generations are still GC'd by nix.gc.
  boot.loader.grub.configurationLimit = 10;

  # WireGuard tunnel address (host-specific; peer config lives in hosts/common).
  networking.wg-quick.interfaces.wg0.address = [ "10.10.16.4/32" ];

  # Hibernation support: 32 GiB swapfile (>= the 31 GiB of RAM) so
  # suspend-then-hibernate has somewhere to write the memory image. NixOS
  # creates the file on activation.
  swapDevices = [ { device = "/swapfile"; size = 32 * 1024; } ];

  # Resume from the swapfile on the root partition. resume_offset is the
  # swapfile's physical extent start, found after the file exists via:
  #   sudo filefrag -v /swapfile | awk '$1=="0:" {print $4+0}'
  boot.resumeDevice = "/dev/disk/by-uuid/6dec2fdc-865e-4f53-b2e6-10a90509fb9d";
  boot.kernelParams = [ "resume_offset=10444800" ];

  # Lid close: suspend, then hibernate to the swapfile after a fixed delay in
  # S3. Overrides the plain "suspend" default in hosts/common.
  services.logind.settings.Login.HandleLidSwitch = lib.mkForce "suspend-then-hibernate";

  # Use an explicit HibernateDelaySec instead of systemd's battery-discharge
  # estimation. The estimation path was never arming the RTC wake alarm that
  # triggers the hibernate step, so the machine sat in S3 (deep suspend, which
  # still drains ~1-2%/hr) until the battery hard-died in the bag. A fixed
  # delay arms a definite RTC alarm; this hardware wakes from the RTC in S3
  # (verified with `rtcwake -m mem`), so the hibernate step now fires. 30min is
  # short enough to preserve battery in a bag but long enough that a brief
  # lid-close-and-reopen just resumes from S3 rather than doing a slow
  # hibernate round trip. Tune upward if quick lid closes hibernate too eagerly.
  systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";

  # Internal keyboard: evdev-level key remaps so they apply everywhere,
  # including GLFW/SDL games (Minecraft etc.) that bind by physical scancode
  # and ignore XKB-layer remapping. Same approach as the Unicomp hwdb on
  # portaplotz:
  #   CapsLock -> Left Control (one-way; left Ctrl stays Ctrl)
  #   Grave    -> Escape       (the key above Tab sends Esc)
  #   Escape   -> Grave        (physical Esc sends `/~)
  # Scancodes are AT set-1: 3a=CapsLock 29=Grave 01=Escape.
  # NOTE: requires removing the setxkbmap ctrl:swapcaps + esc/grave swap from
  # ~/.xsession / ~/.xkb (dotfiles repo), or the layers cancel out.
  services.udev.extraHwdb = ''
    evdev:atkbd:dmi:bvn*:bvr*:bd*:svnLENOVO:pn*:pvrThinkPadT580*
     KEYBOARD_KEY_3a=leftctrl
     KEYBOARD_KEY_29=esc
     KEYBOARD_KEY_01=grave
  '';

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken.
  system.stateVersion = "25.11"; # Did you read the comment?
}
