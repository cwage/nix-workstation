# MacBookPro16,1 host-specific configuration.
#
# Shared workstation config comes from hosts/common. The Apple T2 support
# (patched apple-bce kernel, Wi-Fi/BT firmware, audio profiles, touchbar,
# suspend params) comes from the nixos-hardware `apple-t2` module, which is
# wired into this host in flake.nix.

{ config, lib, pkgs, ... }:

{
  imports = [
    ../common
    ./hardware-configuration.nix
  ];

  # --- Bootloader: dual-boot with the existing Ubuntu install ---
  # Shared EFI system partition; os-prober detects Ubuntu's boot entry so it
  # shows up in the GRUB menu. (Mirrors the thinkpad's GRUB + os-prober setup.)
  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.device = "nodev";
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub.useOSProber = true;

  # --- Apple T2 support (module wired in via flake.nix) ---
  hardware.apple-t2 = {
    # Kernel release stream. "stable" tracks the T2 LTS kernel and is the safer
    # default; switch to "latest" only if you need newer hardware support and
    # accept more churn.
    kernelChannel = "stable";

    # Force the integrated Intel UHD 630 instead of the AMD Radeon Pro 5500M
    # dGPU. On this machine the dGPU otherwise stays powered (observed at D0
    # under Ubuntu) and runs hot / drains battery. Set to false if you actually
    # want the discrete GPU.
    enableIGPU = true;

    # Declarative Broadcom Wi-Fi/Bluetooth firmware. "sonoma" matches the
    # macOS 14.x (apple-firmware 14.8.x) blobs that work on this board today.
    # A known-good copy is also backed up at ~/t2-firmware-backup-* as a manual
    # fallback if this fetch ever mismatches the hardware.
    firmware = {
      enable = true;
      version = "sonoma";
    };
  };

  # WireGuard tunnel address (host-specific; peer config lives in hosts/common).
  networking.wg-quick.interfaces.wg0.address = [ "10.10.16.5/32" ];

  # Clamp the AMD dGPU to its lowest DPM state. `enableIGPU` above only routes
  # display through the iGPU via apple-gmux — it does NOT power down the dGPU,
  # which otherwise idles at PCI D0 (hot + battery drain). Full D3cold isn't
  # reachable on MacBookPro16,1 because the ACPI methods (PWRD/PWG1) macOS
  # uses to bring the dGPU back aren't called by Linux, so a hard power-off
  # can't be reliably reversed. DPM=low is the canonical t2linux fix.
  # Source: https://wiki.t2linux.org/guides/hybrid-graphics/
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", DRIVERS=="amdgpu", ATTR{device/power_dpm_force_performance_level}="low"
  '';

  # This value determines the NixOS release from which the default settings for
  # stateful data were taken. Set to the release this host is installed from.
  system.stateVersion = "25.11";
}
