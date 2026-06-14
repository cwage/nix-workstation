# Installing NixOS on the MacBookPro16,1 (Apple T2), dual-booting Ubuntu

This is a standalone runbook. If you're a fresh Claude session helping with
this install: this file plus the `nix-workstation` repo are the source of
truth — you don't need any prior conversation. Read the whole file first, then
work top to bottom. **Stop and ask before any destructive step** (partitioning,
formatting).

## Goal & strategy

- **Machine:** MacBookPro16,1 (16", late 2019) — Intel i9-9980HK, 64 GB RAM,
  Intel UHD 630 + AMD Radeon Pro 5500M, Apple **T2** security chip.
- **Plan:** Install NixOS onto the **internal NVMe**, **dual-booting** the
  existing Ubuntu install (reclaim Ubuntu's space later once NixOS is trusted).
- **Config:** the `macbookpro` host in this flake. It pulls in the
  `nixos-hardware` `apple-t2` module for the patched (apple-bce) kernel,
  Wi-Fi/BT firmware, audio, touchbar, and suspend params.

## Why this machine is special (the T2 tax)

The T2 puts the SSD, keyboard, trackpad, audio, and Wi-Fi behind a coprocessor.
A **stock** NixOS installer ISO will boot with **no keyboard, no trackpad, and
no access to the internal NVMe** — useless for installing. You therefore need a
**T2-patched installer ISO** (see Prerequisites). The `apple-t2` module provides
the matching patched kernel for the installed system.

## Prerequisites / bring with you

1. **T2-patched NixOS installer ISO**, flashed to a USB stick.
   - Get it from the t2linux project: <https://wiki.t2linux.org/distributions/nixos/installation/>
   - Flash with `dd if=<iso> of=/dev/sdX bs=4M status=progress conv=fsync`
     (replace `/dev/sdX` with the stick — **double-check the device**) or
     Etcher/`cp`. This wipes the stick.
   - Flakes are enabled in the t2 ISO since v6.4.9-3.
2. **USB ethernet adapter** for network during install. The known-good one is a
   Realtek `r8152` adapter — that driver is in the mainline kernel, so it works
   in the live environment with **zero firmware** (sidesteps the Wi-Fi
   chicken/egg: the installer has no Broadcom firmware). Plug into a port
   directly, avoid hubs.
3. **Broadcom firmware backup** (fallback only). A known-good copy of this
   board's Wi-Fi/BT firmware was tarred from the working Ubuntu install:
   `~/t2-firmware-backup-x86_64/brcm-firmware.tar.gz` (35 MB, 283 files).
   Carry it on separate writable media. Only needed if the module's declarative
   firmware fetch misbehaves (see Troubleshooting).
4. **This repo**, reachable on the target: `git clone https://github.com/cwage/nix-workstation`
   (or carry it on a stick). The branch with the macbookpro host is
   `macbookpro-t2` (fold to `main` once merged).

## Current internal disk layout (before install)

From the Ubuntu install (verify with `lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT`):

```
nvme0n1
├─nvme0n1p1   512M  vfat   (EFI System Partition — SHARED, do NOT reformat)
└─nvme0n1p2   931G  ext4   (Ubuntu root)
```

There is no macOS partition (it was removed when Ubuntu was installed), so the
layout is simple: one shared ESP + Ubuntu root. NixOS will get a **new third
partition** carved from Ubuntu's space, and will **share the existing ESP**.

---

## Step 0 — Firmware/Secure Boot settings (already done, just confirm)

Booting Linux off USB on a T2 Mac requires, in macOS Recovery's *Startup
Security Utility*: **Secure Boot = "No Security"** and **"Allow booting from
external media" = enabled**. These persist in the T2 and were already set when
Ubuntu was installed (you couldn't boot Ubuntu otherwise). Nothing to change.

## Step 1 — Boot the installer

1. Insert the T2-patched installer USB.
2. Power on holding **⌥ Option (Alt)** to reach Apple's boot picker.
3. Select the **"EFI Boot"** entry for the USB.
4. At the NixOS installer, confirm keyboard + trackpad work (they should, on the
   patched ISO). You'll likely land at a shell or a graphical installer; this
   runbook uses the **shell / manual** path.

## Step 2 — Network in the live environment

Plug in the `r8152` USB ethernet, then:

```bash
ip -br addr            # expect an enx... iface with an IP
ping -c1 1.1.1.1       # or: curl -sI https://cache.nixos.org | head -1
```

If no IP: `sudo dhcpcd <iface>` or use `nmtui`. (Wi-Fi won't work here without
firmware — use ethernet.)

## Step 3 — Partition: shrink Ubuntu, create the NixOS partition

> ⚠️ **Destructive. Back up anything irreplaceable from Ubuntu first.** Shrinking
> a filesystem carries risk. If the ISO has a GUI, **GParted is the safest** way
> to do this visually. The manual CLI path is below.

Decide the split (example: leave Ubuntu ~400 GB, give NixOS the rest ~530 GB).

Manual CLI shrink of `nvme0n1p2` (Ubuntu ext4), then create `nvme0n1p3`:

```bash
# 1. Filesystem must be unmounted and checked first
sudo umount /dev/nvme0n1p2 2>/dev/null || true
sudo e2fsck -f /dev/nvme0n1p2

# 2. Shrink the FILESYSTEM first (to e.g. 400G). Always shrink fs <= partition.
sudo resize2fs /dev/nvme0n1p2 400G

# 3. Shrink the PARTITION to match, then create a new one in the freed space.
#    Do this interactively in parted (safer for the resize/mkpart math).
#    Keep p2's START sector unchanged; only move its END inward.
sudo parted /dev/nvme0n1
# (parted) unit GiB
# (parted) print                              # note p2's start, confirm numbers
# (parted) resizepart 2 410GiB                # end a hair past the 400G fs, for safety
# (parted) mkpart primary ext4 410GiB 100%    # new NixOS partition -> nvme0n1p3
# (parted) print
# (parted) quit

# 4. (optional) grow the ext4 fs to exactly fill its (now smaller) partition
sudo e2fsck -f /dev/nvme0n1p2
sudo resize2fs /dev/nvme0n1p2     # no size = fill partition
```

Result should be:

```
nvme0n1p1   512M  vfat   (shared ESP)
nvme0n1p2   ~410G ext4   (Ubuntu root)
nvme0n1p3   ~520G        (new — NixOS)
```

## Step 4 — Format and mount

```bash
# Format the NEW partition only. NEVER mkfs the ESP (p1) or Ubuntu root (p2).
sudo mkfs.ext4 -L nixos /dev/nvme0n1p3

# Mount NixOS root, then mount the SHARED ESP at /mnt/boot/efi (do NOT format it)
sudo mount /dev/nvme0n1p3 /mnt
sudo mkdir -p /mnt/boot/efi
sudo mount /dev/nvme0n1p1 /mnt/boot/efi
```

No swap is configured (64 GB RAM). Add a swapfile later if wanted; skip
hibernation on T2 (unreliable).

## Step 5 — Generate the hardware scan

```bash
sudo nixos-generate-config --root /mnt
```

This writes `/mnt/etc/nixos/hardware-configuration.nix` (real UUIDs for the new
root + the ESP) and a throwaway `configuration.nix` (ignore it; we use the flake).

## Step 6 — Get the flake and slot in the real hardware scan

Get the repo onto the target. **Preferred: copy it from the preserved Ubuntu
partition** — this is a dual-boot, so `nvme0n1p2` (Ubuntu root) survives the
shrink and still holds `~/git/cwage/nix-workstation`, *including any uncommitted
branch work*. No network or push needed:

```bash
sudo mkdir -p /mnt/ubuntu-old && sudo mount /dev/nvme0n1p2 /mnt/ubuntu-old
sudo mkdir -p /mnt/home/cwage/git/cwage
sudo cp -r /mnt/ubuntu-old/home/cwage/git/cwage/nix-workstation \
  /mnt/home/cwage/git/cwage/nix-workstation
cd /mnt/home/cwage/git/cwage/nix-workstation
```

Alternative (only if the `macbookpro-t2` branch has been **committed + pushed**
to GitHub — a fresh clone won't have local-only work):

```bash
sudo git clone https://github.com/cwage/nix-workstation \
  /mnt/home/cwage/git/cwage/nix-workstation
cd /mnt/home/cwage/git/cwage/nix-workstation
git checkout macbookpro-t2     # until merged to main
```

Then replace the placeholder hardware scan with the generated one:

```bash
sudo cp /mnt/etc/nixos/hardware-configuration.nix \
  hosts/macbookpro/hardware-configuration.nix
```

Now **edit `hosts/macbookpro/hardware-configuration.nix`** and confirm:
- `fileSystems."/"` points at the new `nixos`-labelled partition (by UUID).
- `fileSystems."/boot/efi"` exists, is the `vfat` ESP, fsType `vfat`. (If
  `nixos-generate-config` recorded it at `/boot` instead of `/boot/efi`, fix the
  mount point to `/boot/efi` to match `hosts/macbookpro/configuration.nix`.)
- (optional) add a read-only mount of the Ubuntu root for file access, like the
  thinkpad does:
  ```nix
  fileSystems."/mnt/ubuntu" = {
    device = "/dev/disk/by-uuid/<UBUNTU-ROOT-UUID>";
    fsType = "ext4";
    options = [ "nofail" ];
  };
  ```

> 🔑 **Flake gotcha (important):** flakes only see **git-tracked** files —
> untracked files are silently excluded from the build. If the repo was copied
> with local-only work, `hosts/common/` and `hosts/macbookpro/` (and the newly
> copied hardware scan) may be **untracked**, so the flake would evaluate
> *without them* and fail. Stage everything before building:
> ```bash
> git add -A
> git status        # confirm hosts/common, hosts/macbookpro, flake.nix all staged
> ```
> (No need to commit — staged is enough for a local flake build. Commit later.)

Also pin the new input (we added `nixos-hardware` to the flake; `flake.lock`
needs it). Requires network:

```bash
nix --extra-experimental-features 'nix-command flakes' flake lock
git add flake.lock
```

## Step 7 — Install

```bash
sudo nixos-install --flake /mnt/home/cwage/git/cwage/nix-workstation#macbookpro
```

- **This compiles the patched T2 kernel from source** — the `apple-t2` module
  ships no binary cache, so expect **~30–45 min** on the i9 the first time
  (cached afterward). This is normal, not a hang. (Optional speedup: add the
  t2linux Cachix as a substituter before installing.)
- It will prompt for the **root password** at the end.
- Set the user password too:
  ```bash
  sudo nixos-enter --root /mnt -c 'passwd cwage'
  ```

## Step 8 — Reboot into NixOS

```bash
sudo reboot
```

Remove the USB. Hold **⌥ Option** and pick the internal **"EFI Boot"** — it
should land in **GRUB**, which (via `useOSProber`) should list both **NixOS**
and **Ubuntu**.

---

## Step 9 — Post-install verification

```bash
uname -r                                  # a *-t2 kernel
lsmod | grep -E 'apple_bce|brcmfmac'      # T2 storage/input bridge + Wi-Fi
nmcli device                              # wlp* Wi-Fi present & connectable
wpctl status                              # "Apple Audio Device": Speakers/Mic
cat /sys/power/mem_sleep                  # s2idle (expected on T2)
lspci -k | grep -iA3 'VGA\|3D'            # confirm iGPU active (enableIGPU=true)
```

Check the Touch Bar lights up, brightness keys work, lid-suspend works.

---

## Troubleshooting

**Wi-Fi dead after install.** The declarative firmware (`firmware.version =
"sonoma"`) didn't match. Either try `"ventura"`/`"monterey"` in
`hosts/macbookpro/configuration.nix` and rebuild, OR drop in the known-good
backup manually:
```bash
sudo tar xzf /path/to/t2-firmware-backup-x86_64/brcm-firmware.tar.gz \
  -C /run/current-system/sw/lib/firmware    # or wire via hardware.firmware
sudo modprobe -r brcmfmac && sudo modprobe brcmfmac
```
(For a durable fix, point `hardware.firmware` at the backed-up files in the
config rather than copying at runtime.)

**GRUB doesn't list Ubuntu.** Ensure `useOSProber = true` (it is, in the config),
that `os-prober` can read the Ubuntu root, then on NixOS:
`sudo nixos-rebuild boot --flake .#macbookpro` to regenerate the menu.

**Mac boot picker won't show / boot NixOS.** The Apple firmware sometimes ignores
EFI BootOrder. Use the **⌥ Option** picker and select "EFI Boot". If multiple
loaders conflict in the ESP, inspect with `efibootmgr -v` from NixOS and set the
order, or re-bless. Ubuntu remains independently bootable from the same picker
as a fallback.

**Kernel build feels stuck.** It's compiling (no cache). Watch with `journalctl`
or just wait. Add the t2linux Cachix substituter to avoid it next time.

**Black screen / no display on boot.** Confirm `hardware.apple-t2.enableIGPU =
true` took effect (forces Intel iGPU over the AMD dGPU). If you need the dGPU,
set it false and rebuild.

## Rollback / safety

- **Ubuntu is untouched** (separate partition + its own bootloader) — bootable
  from the ⌥ Option picker the whole time. This is your fallback.
- NixOS generations: pick a previous one from the GRUB menu, or
  `sudo nixos-rebuild switch --flake .#macbookpro --rollback`.
- Reclaiming Ubuntu's space later: once NixOS is trusted, delete `nvme0n1p2`,
  then grow `nvme0n1p3` + its ext4 into the freed space (offline, from a live
  USB), and remove the `/mnt/ubuntu` mount + the Ubuntu GRUB entry.
```
