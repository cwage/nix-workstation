# NixOS Workstation - Project Guide

## Goal
This repo is a **temporary standalone** NixOS config for the ThinkPad, migrated from the Ansible-based setup at ~/git/cwage/thinkpad. The primary goal is to eventually fold this into the **homelab monorepo** (https://github.com/cwage/homelab) per https://github.com/cwage/homelab/issues/133, where it will coexist alongside Proxmox VM configs, with hosts like `thinkpad/` and `workstation/` using Home Manager for user-level config.

Everything done here should be structured with that integration in mind — keep configs modular, avoid hard-coding thinkpad-specific assumptions where possible, and follow the target structure outlined in the homelab issue.

## Build & Deploy
```bash
sudo nixos-rebuild switch --flake .#thinkpad
```

## Architecture
- `flake.nix` — Entry point, defines inputs (nixpkgs, home-manager, dotfiles)
- `hosts/thinkpad/` — Host-specific config (configuration.nix, hardware-configuration.nix)
- Dotfiles managed via a separate flake at ~/git/cwage/dotfiles, imported as a Home Manager module

## Migration Notes (from ansible)
- **No music production.** The old ansible config had JACK/ardour/fluidsynth for audio production — this is no longer a goal. Standard desktop audio (pipewire + pulse + alsa) is sufficient.
- **Build dependencies (libssl-dev, etc.) belong in per-project devShells**, not in global system packages.
- **Pinned binaries** (Bitwarden CLI, VS Launcher, r2modman, Proton Mail Bridge) are handled separately from standard system packages.
- **ufw is unnecessary** — NixOS has networking.firewall built-in.

## Updating Packages
All packages are pinned to a specific nixpkgs commit via `flake.lock`. To update:

```bash
# Update all flake inputs (nixpkgs, home-manager, dotfiles)
nix flake update

# Or update only nixpkgs
nix flake update nixpkgs

# Then rebuild to apply
sudo nixos-rebuild switch --flake .#thinkpad
```

Nothing changes on your running system until you rebuild. If something breaks after a rebuild:
```bash
sudo nixos-rebuild switch --rollback
```

There is no way to update a single package independently — all packages come from the same pinned nixpkgs commit. If you need to pin a specific version of one package ahead of nixpkgs, use an overlay in `flake.nix` to override that package's version and hash.

## Conventions
- Keep changes scoped and modular; avoid monolithic configs.
- The user prefers to handle git commits and PRs. Don't commit or push without being asked.
- When suggesting system commands (rebuilds, deploys), prefer telling the user the command rather than running it automatically.

## Debugging defaults / unwanted behavior

When diagnosing unwanted default behavior in NixOS or any well-established
ecosystem (systemd, pipewire, X11, etc.), there are two phases — and they have
different right-tools:

1. **Identify the responsible component.** First-principles investigation
   (mute layers one at a time, capture events with `pactl subscribe` / `pw-mon`
   / `journalctl -f`, find the actual process/module emitting the behavior) is
   the right approach here. Don't shortcut this; the wrong component leads to
   wrong fixes.

2. **Look up the known knob — DO NOT reverse-engineer config syntax.** Once
   a specific component is named (e.g. `libpipewire-module-x11-bell`), STOP
   guessing. Search `"how to disable X in nixos"`, check the NixOS Wiki, the
   upstream project's docs, NixOS Discourse. Most common annoyances have
   documented one-line fixes. Guessing at config syntax based on partial recall
   (e.g. trying `flags = [ disabled ]`, env-var workarounds, custom drop-ins)
   wastes a lot of time and risks brittle hacks when a clean documented option
   already exists.

Pattern to avoid: spending an hour layering speculative fixes on top of each
other when 30 seconds of web search would have surfaced the canonical answer.
Rebuilding packages, patching modules, or shipping custom systemd overrides
should be **fallbacks** when no documented option exists, never first moves.
