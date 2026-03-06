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
- **Pinned binaries** (Bitwarden CLI, VS Launcher, r2modman, Codex, Proton Mail Bridge) are handled separately from standard system packages.
- **ufw is unnecessary** — NixOS has networking.firewall built-in.

## Conventions
- Keep changes scoped and modular; avoid monolithic configs.
- The user prefers to handle git commits and PRs. Don't commit or push without being asked.
- When suggesting system commands (rebuilds, deploys), prefer telling the user the command rather than running it automatically.
