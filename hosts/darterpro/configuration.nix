# System76 Darter Pro (darp11-b) host-specific configuration.
#
# Shared workstation config comes from hosts/common. This machine is the
# Smallstep work laptop, so it takes the homelab module (tunnel + NAS) but
# skips gaming/SDR/Android.
#
# Hardware notes (everything below "just works" on the stock kernel, no
# nixos-hardware module needed — there is no darp11 profile upstream anyway):
#   - Intel Core Ultra 7 255H (Arrow Lake-H), Arc iGPU on i915, NPU on
#     intel_vpu (enabled by the generated hardware scan)
#   - Wi-Fi 7 BE200 + Intel BT on iwlwifi/ibt, redistributable firmware comes
#     in via not-detected.nix
#   - ALC245 analog audio on legacy HDA (snd_hda_intel), not SOF; the
#     headphone jack's plug sensor is dead, see the audio section below
#   - System76 Open Firmware (coreboot), system76_acpi is in-tree and provides
#     the airplane + kbd_backlight LEDs
#   - Backlight is acpi_video0 only; there is no intel_backlight node under
#     coreboot, so plain `brightnessctl` (no -d) is correct here

{ config, lib, pkgs, ... }:

{
  imports = [
    ../common
    ../common/homelab.nix
    ./hardware-configuration.nix
  ];

  # Newest kernel, for an Arrow Lake-H machine still gaining fixes upstream
  # (xe/i915, NPU, BE200 Wi-Fi). Revisit if kernel churn ever costs more than
  # the new-silicon support is worth.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Bootloader: systemd-boot on the ESP at /boot. No GRUB/os-prober here —
  # unlike the thinkpad and macbookpro this disk has no other OS to detect.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # The ESP is only 1 GiB, and each generation parks a kernel + initrd on it.
  # Five is roughly 500 MB and leaves headroom; older generations are still
  # GC'd from the store by nix.gc.
  boot.loader.systemd-boot.configurationLimit = 5;

  # System76 firmware updates (system76-firmware-cli / the DBus daemon).
  # This machine runs System76 Open Firmware, which fwupd doesn't handle.
  hardware.system76.firmware-daemon.enable = true;

  # WireGuard tunnel address (host-specific; peer config lives in
  # hosts/common/homelab.nix).
  networking.wg-quick.interfaces.wg0.address = [ "10.10.16.6/32" ];

  # Hibernation support: 32 GiB swapfile (>= the 30 GiB of RAM) so
  # suspend-then-hibernate has somewhere to write the memory image. NixOS
  # creates the file on activation.
  swapDevices = [ { device = "/swapfile"; size = 32 * 1024; } ];

  # Resume from the swapfile on the root filesystem. Root is LUKS, so
  # resumeDevice is the *mapper* device, which initrd unlocks before the
  # resume attempt.
  #
  # resume_offset is REQUIRED, not optional. Systemd stage 1 (the default
  # since 26.05) can carry the hibernation location in the HibernateLocation
  # EFI variable, but that only covers the resume side. logind validates the
  # *configured* resume target against the active swap before it will allow
  # hibernation at all: with resume= set but /sys/power/resume_offset still 0,
  # it answered CanHibernate = CanSuspendThenHibernate = "na", which also
  # disabled the configured lid action. Verify with:
  #   busctl call org.freedesktop.login1 /org/freedesktop/login1 \
  #     org.freedesktop.login1.Manager CanHibernate
  #
  # The value is the physical offset of the swapfile's FIRST extent, in pages.
  # Here the ext4 block size (4096) equals PAGE_SIZE, so filefrag's
  # physical_offset is already in the right unit:
  #   sudo filefrag -v /swapfile | awk '$1=="0:" {print $4+0}'
  # /swapfile is fragmented across many extents (extent 1 is nowhere near
  # extent 0); that's fine, because this number only has to locate the swap
  # header.
  #
  # FRAGILE: it is a physical block address, not a name. If /swapfile is ever
  # recreated — changing swapDevices.size, restoring or resizing the
  # filesystem, reinstalling — the offset moves and hibernation breaks
  # *silently*, back to "na". Re-derive with the command above. Being a kernel
  # parameter, a change needs `nixos-rebuild boot` plus a reboot; `switch`
  # alone won't alter the running kernel's cmdline.
  boot.resumeDevice = "/dev/mapper/luks-4223b115-b3a1-4d72-a7f2-76ad9c28af81";
  boot.kernelParams = [ "resume_offset=15329280" ];

  # Lid close: plain "suspend" — i.e. the hosts/common default, with the
  # suspend-then-hibernate override deliberately disabled below.
  #
  # HIBERNATION DOES NOT WORK ON THIS MACHINE. Not a config problem: the
  # firmware hands the kernel a different E820 memory map on every boot, and
  # x86 refuses to restore an image whose recorded map doesn't match the
  # current one (arch_hibernation_header_restore compares an E820 digest):
  #   Hibernate inconsistent memory map detected!
  #   PM: hibernation: Image mismatch: architecture specific data
  #   PM: hibernation: Failed to load image, recovering.
  #   PM: hibernation: resume failed (-1)
  # Everything else is correct — the image is written, the HibernateLocation
  # EFI variable survives, systemd-hibernate-resume finds the right device and
  # offset, and the kernel reports "Image signature found, resuming" before
  # rejecting it on the digest.
  #
  # Measured 2026-11-14 across four consecutive boots: 51 / 53 / 53 / 52
  # BIOS-e820 entries, no two maps identical. So this fails every time, not
  # intermittently. Known firmware-bug class (Framework 13/16, some Macs,
  # Surface, HP); upstream suspects the EFI stub allocating the TPM event log
  # as ACPI reclaim memory, which shifts the regions near the top of RAM. A
  # `hibernate=relaxed_memmap` kernel option that would only compare usable
  # RAM was proposed on linux-pm but is not merged (absent from 7.3.1).
  #
  # Precisely characterised 2026-11-14: 45 of ~53 e820 regions are identical
  # between boots. Exactly one cluster floats — 6 pages of "ACPI data" plus 1
  # page "device reserved", constant in size, based at 0x87ec29000 on one boot
  # and 0x87f14f000 on the next (~5.1 MiB apart). Everything below
  # 0x100000000 and above 0x87f83d000 is fixed. A constant-size allocation at
  # a varying address looks like an EDK2 heap watermark that depends on
  # boot-time work. Use scripts/e820-check.sh to re-test.
  #
  # Three escape routes investigated and ruled out:
  #
  #   1. Newer firmware. There isn't any. The daemon's Download method returns
  #      darp11-b's full published changelog, and it has exactly one entry:
  #      2025-04-03_04c4e20 / "Added original firmware" — i.e. the build that
  #      is already installed. (system76-firmware-cli has no read-only verb;
  #      query the daemon over D-Bus instead, see scripts/e820-check.sh notes.
  #      firmware.system76.com pins its own CA, so curl/browsers can't reach
  #      the buildchain endpoint without the cert from pop-os/system76-firmware.)
  #
  #   2. `hibernate=relaxed_memmap`. Wouldn't help even if it were merged: it
  #      relaxes the check to usable-RAM regions only, and the usable RAM
  #      regions are precisely what differ here (the floating cluster moves
  #      the System RAM boundaries around it).
  #
  #   3. Forcing a deterministic map with `memmap=exactmap` / `memmap=N$addr`.
  #      Impossible: arch/x86/power/hibernate.c hashes `e820_table_firmware`
  #      on both save and restore, and e820.c documents that table as "not
  #      modified by the kernel" (it exists precisely to fingerprint physical
  #      memory for hibernation). Command-line overrides only edit the
  #      kernel's working `e820_table`.
  #
  # So the only remaining levers are a future System76 firmware release, or
  # finding the boot-time input that moves the allocation (the TPM event log
  # is the leading suspect — try disabling measured boot in firmware setup and
  # re-running the e820 check).
  # Leaving suspend-then-hibernate on would be a session-destroying trap: the
  # lid suspends to S3, then after HibernateDelaySec it hibernates, and the
  # next power-on silently discards the session. Plain suspend is strictly
  # better until the firmware is fixed. The cost is that a lid-closed machine
  # in a bag drains at the S3 rate (~1-2%/hr) instead of parking at zero.
  #
  # Re-test after a System76 firmware update (system76-firmware-daemon is
  # enabled above) — first check whether the map is stable across boots at
  # all, since that is the actual blocker:
  #   for b in -1 0; do journalctl -b $b -k | grep -c BIOS-e820; done
  #   journalctl -b -1 -k | grep BIOS-e820 > /tmp/a; \
  #     journalctl -b 0 -k | grep BIOS-e820 > /tmp/b; diff /tmp/a /tmp/b
  # If identical, try `systemctl hibernate`, and on success restore:
  #   services.logind.settings.Login.HandleLidSwitch = lib.mkForce "suspend-then-hibernate";
  #   systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";
  # (A fixed HibernateDelaySec rather than systemd's battery-discharge
  # estimation is the thinkpad lesson: the estimation path never armed the RTC
  # wake alarm, so that machine sat in S3 until the battery hard-died.)

  # Internal keyboard: evdev-level key remaps so they apply everywhere,
  # including GLFW/SDL games that bind by physical scancode and ignore
  # XKB-layer remapping, and so they survive the keyboard being
  # re-enumerated on resume.
  #   CapsLock -> Left Control (one-way; left Ctrl stays Ctrl)
  #   Grave    -> Escape       (the key above Tab sends Esc)
  #   Escape   -> Grave        (physical Esc sends `/~)
  # Scancodes are AT set-1: 3a=CapsLock 29=Grave 01=Escape.
  # The DMI match comes from /sys/class/dmi/id/modalias, which strips spaces
  # out of the product name ("Darter Pro" -> "DarterPro"):
  #   svnSystem76:pnDarterPro:pvrdarp11-b
  # NOTE: requires that ~/.xsession not also apply the setxkbmap
  # ctrl:swapcaps + esc/grave swap, or the two layers cancel out.
  services.udev.extraHwdb = ''
    evdev:atkbd:dmi:bvn*:bvr*:bd*:svnSystem76:pnDarterPro:pvrdarp11*
     KEYBOARD_KEY_3a=leftctrl
     KEYBOARD_KEY_29=esc
     KEYBOARD_KEY_01=grave
  '';

  # Headphone jack: the plug sensor on this unit never fires. Pin 0x21 reads
  # GET_PIN_SENSE = 0x0 with known-good headphones fully seated, yet audio
  # out of the jack works. With the sensor stuck "unplugged", WirePlumber
  # marks the Headphones port unavailable and refuses to make the card the
  # default sink, so apps (Brave etc.) silently get no output at all.
  #
  # Fix: a HDA "early patch" (Documentation/sound/hd-audio/notes.rst) that
  # sets the "no presence detect" misc bit on the headphone pin's default
  # config (0x04211020 -> 0x04211120) — the same trick the kernel's own
  # System76 quirk uses for the headset mic on pin 0x19. The port then shows
  # as availability-unknown: selectable and default-able, but switching
  # between Speakers and Headphones is manual (pavucontrol Port dropdown),
  # and WirePlumber remembers the choice across reboots.
  #
  # Codec line = vendor id, subsystem id, codec address
  # (/sys/class/sound/hwC0D0/{vendor_id,subsystem_id}). Remove this whole
  # block if the jack is ever repaired/replaced and detection works again.
  hardware.firmware = [
    (pkgs.writeTextDir "lib/firmware/darterpro-hda-jack.fw" ''
      [codec]
      0x10ec0245 0x1558a743 0

      [pincfg]
      0x21 0x04211120
    '')
  ];
  boot.extraModprobeConfig = ''
    options snd-hda-intel patch=darterpro-hda-jack.fw
  '';

  # Trackpad: ignore it while typing, and switch it off entirely when an
  # external mouse is plugged in (same as macbookpro).
  services.libinput.touchpad = {
    disableWhileTyping = true;
    sendEventsMode = "disabled-on-external-mouse";
  };

  # This value determines the NixOS release from which the default settings for
  # stateful data were taken. Set to the release this host was installed from.
  system.stateVersion = "26.05"; # Did you read the comment?
}
