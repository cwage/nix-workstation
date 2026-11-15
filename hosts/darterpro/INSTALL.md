# Bringing up the System76 Darter Pro (`darterpro`)

NixOS 26.05 was installed from the graphical ISO before this host config
existed, so the machine starts out on the stock `/etc/nixos/configuration.nix`
(GNOME/GDM, no flakes). This file is the checklist for switching it over to
the flake. Work top to bottom.

## What the installer left behind

- **Disk:** single 931 GB NVMe — 1 GiB ESP at `/boot` (vfat), rest is LUKS
  (`luks-4223b115-…`) with ext4 root. No other OS on the disk.
- **Bootloader:** systemd-boot (hence no GRUB/os-prober in this host, unlike
  thinkpad and macbookpro).
- **No swap**, so no hibernation until step 4 below.
- `hardware-configuration.nix` in this directory is a verbatim copy of the
  generated `/etc/nixos/hardware-configuration.nix`. Regenerate with
  `nixos-generate-config --show-hardware-config` if the disk layout changes.

Hardware all works on the stock kernel — no `nixos-hardware` module (there is
no `darp11` profile upstream anyway). Details are commented in
`configuration.nix`.

## 1. First activation: use `boot`, not `switch`

This config replaces GDM/GNOME with LightDM/awesome. A `switch` restarts
`display-manager.service` during activation, which **kills the running desktop
session** — including the terminal you're running the rebuild from. Use `boot`
and reboot instead:

```bash
cd ~/git/cwage/nix-workstation
sudo nixos-rebuild boot --flake .#darterpro
sudo reboot
```

No `--extra-experimental-features` is needed even though the stock installer
config never enabled flakes: the current (Python) `nixos-rebuild` passes
`--extra-experimental-features 'nix-command flakes'` to the `nix` commands it
runs whenever `--flake` is used. It also *rejects* that flag as an argument of
its own — if you ever do need to set Nix options through it, the spelling is
`--option extra-experimental-features 'nix-command flakes'`.

Subsequent rebuilds are plain `sudo nixos-rebuild switch --flake .#darterpro`
(still worth a `boot` + reboot for anything that touches the display manager
or systemd itself).

## 2. Dotfiles must be reachable

Home Manager links `.Xresources.darterpro` and `.xsession.darterpro` by
hostname, so evaluation fails if they aren't in the `dotfiles` input. Either
push them to `github:cwage/dotfiles` and `nix flake update dotfiles`, or build
against the local tree (combine these flags with step 1's on the first run):

```bash
sudo nixos-rebuild switch --flake .#darterpro \
  --override-input dotfiles path:/home/cwage/git/cwage/dotfiles \
  --no-write-lock-file
```

Note that new files in this repo must be at least `git add -N`'d before Nix
can see them — an untracked `hosts/<host>/` is invisible to the flake and
evaluation fails with "not tracked by Git".

## 3. Verify the keyboard remaps

CapsLock → Ctrl and the Esc/grave swap are done at the evdev level by the
hwdb entry in `configuration.nix`, matched on
`svnSystem76:pnDarterPro:pvrdarp11*`. After the switch:

```bash
udevadm info /dev/input/event0 | grep KEYBOARD_KEY
```

Should print `KEYBOARD_KEY_3a=leftctrl`, `KEYBOARD_KEY_29=esc`,
`KEYBOARD_KEY_01=grave`. If it prints nothing, re-check the match against
`cat /sys/class/dmi/id/modalias` (the modalias strips the space out of
"Darter Pro").

## 4. Hibernation: doesn't work on this machine (firmware bug)

Short version: **don't expect hibernation here, and don't spend time on it.**
The lid is configured for plain `suspend`. Suspend (deep S3) works well.

The first switch creates `/swapfile` (32 GiB) via `mkswap-swapfile.service`,
and `boot.resumeDevice` + `resume_offset=` are set in `configuration.nix`.
Those are necessary but **not sufficient**, and the two failure modes look
completely different, so know both:

1. **Without `resume_offset`**, logind refuses outright — it validates the
   configured resume target against the active swap, and `resume=` set with
   `/sys/power/resume_offset` still `0` is a mismatch:
   ```
   busctl call org.freedesktop.login1 /org/freedesktop/login1 \
     org.freedesktop.login1.Manager CanHibernate
   s "na"          # and CanSuspendThenHibernate, so the lid action dies too
   ```
   Fixed by the `resume_offset` kernel param (first extent of the swapfile,
   `sudo filefrag -v /swapfile | awk '$1=="0:" {print $4+0}'`). Being a kernel
   parameter it needs `nixos-rebuild boot` + reboot, not `switch`.

2. **With it set**, `CanHibernate` becomes `yes`, the image writes, the
   `HibernateLocation` EFI variable survives, `systemd-hibernate-resume` finds
   the right device and offset, the kernel reports `Image signature found,
   resuming` — and then rejects it:
   ```
   Hibernate inconsistent memory map detected!
   PM: hibernation: Image mismatch: architecture specific data
   PM: hibernation: resume failed (-1)
   ```
   The firmware hands the kernel a different E820 map on every boot, and x86
   refuses to restore an image whose recorded map doesn't match. You get a cold
   boot and lose the session. Measured across four consecutive boots:
   51/53/53/52 regions, no two identical, so it fails every time.

The full analysis — which regions move, and the three escape routes that were
investigated and ruled out (no newer firmware is published for darp11-b;
`hibernate=relaxed_memmap` wouldn't apply; `memmap=` can't work because the
digest hashes the untouched firmware table) — is in the long comment in
`hosts/darterpro/configuration.nix`.

To re-test after any firmware or firmware-setting change:

```bash
./scripts/e820-check.sh          # prints STABLE or DIFFERS
```

If it ever prints STABLE, `systemctl hibernate` should work, and the two lines
to restore `suspend-then-hibernate` are in that config comment.

Note that changing `HandleLidSwitch` applies on `switch` to the *file* but not
to the *running* logind, which has no `ExecReload` and which `nixos-rebuild`
won't restart. Verify with:

```bash
busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
  org.freedesktop.login1.Manager HandleLidSwitch
```

and if it's stale, `systemctl restart systemd-logind` (breaks `xss-lock`'s
inhibitor, so re-check locking) or reboot.

## 5. Provision the WireGuard key

`hosts/common/homelab.nix` gives this host `10.10.16.6/32` and the unit is
guarded on the key existing, so it stays inert until you do this:

```bash
wg genkey | sudo tee /etc/wireguard/wg0.key | wg pubkey   # note the pubkey
sudo chmod 600 /etc/wireguard/wg0.key
```

Add that public key as a peer with allowed IP `10.10.16.6/32` on the homelab
side, then (from off-LAN, since the endpoint has no hairpin NAT):

```bash
sudo systemctl start wg-quick-wg0
resolvectl status wg0        # should show lan.quietlife.net as a search domain
ls /mnt/nas/                 # autofs mounts on access
```

The tunnel is deliberately not started at boot — see the comments in
`homelab.nix`.

## 6. Git identity (the work profile leaves this to you)

`~/.gitconfig` is a home-manager symlink into the Nix store, so
`git config --global …` fails with **"could not lock config file
/home/cwage/.gitconfig: Read-only file system"**. That's by design: the repo's
`.gitconfig` ends with `[include] path = ~/.gitconfig.local`, and the `work`
profile deliberately leaves `.gitconfig.local` unmanaged so step/onboarding
tooling can write to it. On a fresh machine nothing creates it, so git has no
identity at all until you do.

Write identity to `~/.gitconfig.local`, never `--global`:

```bash
git config --file ~/.gitconfig.local user.name  "Chris Wage"
git config --file ~/.gitconfig.local user.email "cwage@quietlife.net"
```

Split identity by directory (personal default, Smallstep under
`~/git/smallstep/`) via a conditional include. Note this lives only in these
hand-written files — it is **not** in the dotfiles repo, so it does not travel
between machines and has to be recreated on each one:

```bash
git config --file ~/.gitconfig.local \
  'includeIf.gitdir:~/git/smallstep/.path' '~/.gitconfig.smallstep'
git config --file ~/.gitconfig.smallstep user.name  "Chris Wage"
git config --file ~/.gitconfig.smallstep user.email "you@smallstep.com"
```

The `includeIf` must come after the default `[user]` block — later wins. Check
it fires by running `git config --get user.email` inside a repo under each
tree.

## 7. Decommission the stock config

Once the flake build is confirmed good across a reboot, `/etc/nixos/` is dead
weight. Leave it as a fallback for a few days, then remove it so there's no
ambiguity about which config is live.

## Not set up here (by choice)

- `gaming.nix`, `sdr.nix`, `android.nix` — not imported on this host.
- The `cwage` account uses the **work** dotfiles profile, so `~/.ssh/config`
  and `~/.gitconfig.local` are hand-maintained (leaving room for
  `step ssh config`). Same arrangement as macbookpro.
