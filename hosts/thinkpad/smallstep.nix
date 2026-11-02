# Separate local account for the Smallstep contract (Nov 2026 - ~Feb 2027).
# Shares the desktop dotfiles with cwage via the "work" dotfiles profile, which
# leaves ~/.ssh and ~/.gitconfig.local unmanaged so Smallstep onboarding
# (`step ssh config`, etc.) can write to them.
#
# Password is set imperatively (mutableUsers), same as cwage.
#
# At contract end: drop this import, rebuild, then remove the account and
# home directory (`userdel -r smallstep`).
{ config, lib, pkgs, dotfiles, ... }:

{
  users.users.smallstep = {
    isNormalUser = true;
    description = "Smallstep contract";
    extraGroups = [ "wheel" "audio" "video" "networkmanager" "plugdev" "kvm" "tss" ];
  };

  home-manager.users.smallstep = {
    imports = [ dotfiles.homeManagerModules.default ];
    dotfiles.profile = "work";
    home.stateVersion = "26.05";

    # Contract tooling lives on this account only, so it goes away with it.
    # terraform is unfree (BSL); allowUnfree is already set in hosts/common.
    home.packages = with pkgs; [
      kubectl
      kustomize
      kubernetes-helm
      yq-go # mikefarah yq, what the appliance/gitops Makefiles expect
      terraform
      # kubectl can't auth to GKE without the auth plugin.
      (google-cloud-sdk.withExtraComponents [
        google-cloud-sdk.components.gke-gcloud-auth-plugin
      ])
      go
      gopls
      step-cli
      (callPackage ../../pkgs/kots.nix { })
      (callPackage ../../pkgs/replicated.nix { })

      k9s
      stern
      kind # local clusters for trying KOTS installs
      grpcurl
      postgresql # for psql
      dbmate # migration format used by pgm
      awscli2 # Run Anywhere on AWS
      skopeo # image copy/inspect for air-gap bundles
      shellcheck
    ];
  };
}
