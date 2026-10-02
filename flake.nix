{
  description = "NixOS workstation configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Fast-moving packages (coding agents that need frequent updates for new
    # model support) come from unstable via unstableOverlay below. Everything
    # else stays on the stable release above.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      # Must match the nixpkgs release branch above.
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dotfiles = {
      url = "github:cwage/dotfiles";
      flake = true;
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Apple T2 hardware support (patched apple-bce kernel, Wi-Fi/BT firmware,
    # audio profiles, touchbar, suspend params) for the macbookpro host.
    nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, dotfiles, nix-index-database, nixos-hardware, ... }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    unstableOverlay = (final: prev:
      let
        unstable = import nixpkgs-unstable {
          inherit system;
          config = prev.config; # carry allowUnfree etc. from the host config
        };
      in {
        claude-code = unstable.claude-code;
        codex = unstable.codex;
      });
  in
  {
    packages.${system} = {
      agentpen = pkgs.callPackage ./pkgs/agentpen.nix { };
    };

    nixosConfigurations =
      let
        # Shared host scaffolding: overlays, the host module, nix-index, and
        # home-manager wiring. Per-host specifics live in hosts/<hostname>;
        # extraModules adds hardware modules (e.g. nixos-hardware apple-t2).
        mkHost = { hostname, extraModules ? [ ] }: nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            { nixpkgs.overlays = [ unstableOverlay ]; }
            ./hosts/${hostname}
            nix-index-database.nixosModules.nix-index
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.cwage = { pkgs, config, ... }: {
                imports = [ dotfiles.homeManagerModules.default ];
                home.stateVersion = "24.05";
                home.file.".claude/CLAUDE.md".source =
                  config.lib.file.mkOutOfStoreSymlink "/home/cwage/git/cwage/ai/AGENT.md";
                home.file.".codex/AGENTS.md".source =
                  config.lib.file.mkOutOfStoreSymlink "/home/cwage/git/cwage/ai/AGENT.md";
              };
            }
          ] ++ extraModules;
        };
      in
      {
        thinkpad = mkHost { hostname = "thinkpad"; };

        # MacBookPro16,1 (Apple T2). apple-t2 brings the patched kernel,
        # firmware, audio, touchbar and suspend params; host options live in
        # hosts/macbookpro.
        macbookpro = mkHost {
          hostname = "macbookpro";
          extraModules = [ nixos-hardware.nixosModules.apple-t2 ];
        };
      };
  };
}
