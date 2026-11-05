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
  # Cap boot menu entries; older generations are still GC'd by nix.gc.
  boot.loader.grub.configurationLimit = 10;

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

  # Trackpad: ignore it while typing (palms and thumbs graze it constantly),
  # and switch it off entirely whenever an external mouse is plugged in.
  services.libinput.touchpad = {
    disableWhileTyping = true;
    sendEventsMode = "disabled-on-external-mouse";
  };

  # Swap Option and Command on the built-in keyboard so Alt (awesome's Mod1)
  # sits next to the space bar, where it is on a PC keyboard. Done in the
  # Apple keyboard driver, so it applies everywhere (console, X, games) and
  # leaves external keyboards alone.
  boot.extraModprobeConfig = ''
    options hid_apple swap_opt_cmd=1
  '';

  # Built-in keyboard remaps at the evdev level (same approach as the
  # thinkpad's hwdb), so they survive the keyboard being re-enumerated on
  # resume from suspend — an X keymap applied at login is lost when that
  # happens. Scancodes are USB HID usages:
  #   70039 CapsLock <-> 700e0 Left Control (swapped)
  #   70029 Escape   <-> 70035 Grave        (swapped)
  # The matching XKB remaps were removed from .xsession.macbookpro (dotfiles),
  # or the two layers would cancel out.
  services.udev.extraHwdb = ''
    evdev:input:b0003v05ACp0340*
     KEYBOARD_KEY_70039=leftctrl
     KEYBOARD_KEY_700e0=capslock
     KEYBOARD_KEY_70029=grave
     KEYBOARD_KEY_70035=esc
  '';

  # Login screen scaling. The greeter runs before ~/.Xresources is loaded, so
  # it doesn't see the session's Xft.dpi/cursor settings; give it the same
  # 2x values (192 DPI, 48px cursor) directly.
  services.xserver.displayManager.lightdm.greeters.gtk = {
    cursorTheme.size = 48;
    extraConfig = ''
      xft-dpi = 192
    '';
  };

  # Suspend workarounds (see issue #54). Deep sleep works on this machine, but
  # needs two things done around it:
  #
  # 1. Take every CPU except CPU 0 offline before suspending and bring them
  #    back afterwards. On T2 Macs the firmware makes waking secondary CPUs
  #    during early resume extremely slow; the t2linux 7.x patch set does this
  #    in the kernel ("Apple T2 systems need early CPU offlining"), which the
  #    6.18 stable channel lacks. Drop this once the kernel carries that patch.
  # 2. Turn the internal panel off and on again after resume. Without it the
  #    machine wakes but the screen stays black (X on the Intel GPU).
  #
  # powerDownCommands also runs at shutdown, where offlining CPUs is harmless.
  # The display step assumes the single local X session of user cwage on :0.
  powerManagement.powerDownCommands = ''
    for f in /sys/devices/system/cpu/cpu[1-9]*/online; do
      echo 0 > "$f" || true
    done
  '';
  powerManagement.resumeCommands = ''
    for f in /sys/devices/system/cpu/cpu[1-9]*/online; do
      echo 1 > "$f" || true
    done
    xr() {
      ${pkgs.util-linux}/bin/runuser -u cwage -- ${pkgs.coreutils}/bin/env \
        DISPLAY=:0 XAUTHORITY=/home/cwage/.Xauthority \
        ${pkgs.xrandr}/bin/xrandr "$@" || true
    }
    xr --output eDP-1 --off
    sleep 2
    xr --output eDP-1 --auto
  '';

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
