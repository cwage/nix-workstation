# Smallstep contract tooling (Nov 2026 - ~Feb 2027), as a Home Manager module so
# a host can give it to whichever account does the contract work:
#
#   home-manager.users.<name>.imports = [ ../common/smallstep-tools.nix ];
#
# At contract end: drop those imports and rebuild.
{ pkgs, ... }:

{
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
}
