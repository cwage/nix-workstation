{
  description = "NixOS workstation configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Pinned to a pre-2026-05-08 nixos-unstable commit for awesome 4.3, which
    # broke against the lgi/cairo bump that landed via staging-next on
    # 2026-05-08. Both build and runtime fail in lgi/override/cairo.lua.
    # Tracked upstream in NixOS/nixpkgs#523345 — when that's fixed, drop this
    # input and the overlay below.
    nixpkgs-awesome.url = "github:NixOS/nixpkgs/549bd84d6279f9852cae6225e372cc67fb91a4c1";

    home-manager = {
      url = "github:nix-community/home-manager";
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
  };

  outputs = { self, nixpkgs, nixpkgs-awesome, home-manager, dotfiles, nix-index-database, ... }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    awesomeOverlay = (final: prev: {
      awesome = nixpkgs-awesome.legacyPackages.${system}.awesome;
    });
  in
  {
    packages.${system} = {
      agentpen = pkgs.callPackage ./pkgs/agentpen.nix { };
    };

    nixosConfigurations.thinkpad = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        { nixpkgs.overlays = [ awesomeOverlay ]; }
        ./hosts/thinkpad
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
      ];
    };
  };
}
