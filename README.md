# nix-workstation

NixOS configuration for the thinkpad, managed via flakes with Home Manager for dotfiles.

## Prerequisites

- Fresh NixOS install (USB boot, minimal ISO)
- Git available (`nix-shell -p git` if not yet installed)

## Bootstrap

Clone the required repos:

```bash
mkdir -p ~/git/cwage
cd ~/git/cwage
git clone git@github.com:cwage/nix-workstation.git
git clone git@github.com:cwage/dotfiles.git
git clone git@github.com:cwage/bin.git
```

Build and activate:

```bash
cd ~/git/cwage/nix-workstation
sudo nixos-rebuild switch --flake .#thinkpad
```

## Rebuilding after changes

### NixOS config changes (this repo)

Edit files in `hosts/thinkpad/` or `flake.nix`, then:

```bash
sudo nixos-rebuild switch --flake .#thinkpad
```

### Dotfiles changes

The `dotfiles` flake input points at `github:cwage/dotfiles`, so a plain `nix flake update dotfiles` only picks up changes that are already **pushed**. To test local, uncommitted edits in `~/git/cwage/dotfiles` first, override the input with a `path:` reference for that one rebuild:

```bash
cd ~/git/cwage/nix-workstation
sudo nixos-rebuild switch --flake .#thinkpad --override-input dotfiles path:/home/cwage/git/cwage/dotfiles --no-write-lock-file
```

- `path:` (not `git+file:`) is used so the dirty working tree is included, not just committed files.
- `--no-write-lock-file` keeps the override from being written into `flake.lock`; without the flag, `flake.lock` stays pointed at the GitHub revision anyway, but this avoids a root-owned edit to it.
- `sudo nixos-rebuild test ...` with the same flags works too if you don't want the test build added to the bootloader.

Once you're happy, commit and push the dotfiles, then update the lock to the pushed revision and rebuild normally:

```bash
cd ~/git/cwage/nix-workstation
nix flake update dotfiles
sudo nixos-rebuild switch --flake .#thinkpad
```

### Useful build variants

```bash
# Dry run - evaluate only, don't build or activate
nixos-rebuild dry-build --flake .#thinkpad

# Build without activating (test that it compiles)
nixos-rebuild build --flake .#thinkpad

# Build and activate, but don't add to bootloader (reverts on reboot)
sudo nixos-rebuild test --flake .#thinkpad

# Build and switch (activate + set as boot default)
sudo nixos-rebuild switch --flake .#thinkpad
```

## Updating packages

The system tracks the stable NixOS release (`nixos-26.05`), with home-manager on the matching `release-26.05` branch. A handful of fast-moving packages (currently `claude-code` and `codex`) come from `nixos-unstable` instead, via `unstableOverlay` in `flake.nix`. Every input is pinned to a specific commit via `flake.lock`. Nothing changes on your running system until you rebuild.

```bash
# Update all flake inputs (nixpkgs, nixpkgs-unstable, home-manager, dotfiles)
nix flake update

# Or update only the unstable packages (e.g. to pick up a new claude-code)
nix flake update nixpkgs-unstable

# Or update only the stable base
nix flake update nixpkgs
```

To move another package to unstable, add it to `unstableOverlay` in `flake.nix`.

### Moving to a new NixOS release

Releases come out every May and November. To upgrade, change the `nixos-YY.MM` branch on the `nixpkgs` input and the `release-YY.MM` branch on the `home-manager` input together, then run `nix flake lock` and rebuild. Don't change `system.stateVersion` as part of a release upgrade. Prefer `nixos-rebuild boot` plus a reboot over `switch`, since core components like systemd change version.

### Previewing what changed

After updating `flake.lock`, build without activating, then use `nvd` to see a version diff (similar to `apt-get -s upgrade`):

```bash
nixos-rebuild build --flake .#thinkpad
nvd diff /run/current-system result
```

To see *why* a package changed, `scripts/whatchanged.sh` takes each upgrade nvd lists (or the package names you pass it) and prints what on the system depends on it plus the nixpkgs commits between the old and new locked revisions that mention it, with PR links. The PR body is usually where the upstream changelog is linked. It compares `flake.lock` in HEAD against the working tree, so run it before committing the lock update:

```bash
scripts/whatchanged.sh            # every version change
scripts/whatchanged.sh boringssl  # one package
```

If you're happy with the changes:

```bash
sudo nixos-rebuild switch --flake .#thinkpad
```

To roll back if something breaks:

```bash
sudo nixos-rebuild switch --rollback
```

## Updating local packages (`pkgs/`)

Packages defined in `pkgs/` are pinned to an upstream version with one or more content hashes. These hashes are **not** the same as anything GitHub displays — Nix unpacks the source and re-hashes it in NAR (Nix archive) format, so you can't just paste a release SHA from a GitHub release page.

Most packages have at least:

- A source `hash` inside `fetchFromGitHub` / `fetchurl` / etc. — hash of the unpacked source tree.
- A dependency-closure hash, named per ecosystem:
  - Go: `vendorHash` (vendored Go modules)
  - Rust: `cargoHash` / `cargoLock`
  - Node: `npmDepsHash`, `pnpmDeps.hash`, `yarnDeps.hash`
  - Python: varies by builder

The dependency-closure hash changes whenever the lockfile (`go.sum`, `Cargo.lock`, etc.) changes upstream, even across patch releases.

### Bumping a version

Two workflows, pick whichever:

**1. `nix-update` (easiest):** automates version bump + hash recompute.

```bash
nix-update --flake --version 0.2.2 agentpen
```

**2. Fake-hash dance (manual, always works):** edit the package file, bump `version`, replace each hash with `lib.fakeHash` (add `lib` to the function args if needed), then rebuild. Nix will fail with the actual hash in the error message — paste it back in. Repeat for each hash field.

```nix
src = fetchFromGitHub {
  # ...
  rev = "v${version}";
  hash = lib.fakeHash;   # rebuild, copy real hash from error, paste here
};

vendorHash = lib.fakeHash;  # same dance
```

Then rebuild as normal:

```bash
sudo nixos-rebuild switch --flake .#thinkpad
```

## Repo structure

```
nix-workstation/
├── flake.nix                          # Root flake (nixpkgs, home-manager, dotfiles inputs)
├── flake.lock                         # Pinned input versions
└── hosts/
    └── thinkpad/
        ├── default.nix                # Host entry point (hostname, imports)
        ├── configuration.nix          # System config (packages, services, users)
        └── hardware-configuration.nix # Hardware-specific (generated, machine-specific)
```

## Notes

- The dotfiles flake input is `github:cwage/dotfiles`. Use `--override-input dotfiles path:...` (see "Dotfiles changes" above) to test local edits before pushing.
- Home Manager symlinks dotfiles into the Nix store, so dotfile edits require a rebuild to take effect.
- `hardware-configuration.nix` is machine-specific and generated by `nixos-generate-config`.
