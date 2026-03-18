{
  description = "NixOS workstation configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dotfiles = {
      url = "github:cwage/dotfiles";
      flake = true;
    };
  };

  outputs = { self, nixpkgs, home-manager, dotfiles, ... }:
  {
    nixosConfigurations.thinkpad = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hosts/thinkpad
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.cwage = { pkgs, ... }: {
            imports = [ dotfiles.homeManagerModules.default ];
            home.stateVersion = "24.05";
          };
        }
      ];
    };
  };
}
