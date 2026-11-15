# Gaming. Opt-in: imported by hosts that want Steam and friends, skipped on
# machines where the closure isn't worth it.

{ pkgs, ... }:

{
  programs.steam.enable = true;

  environment.systemPackages = with pkgs; [
    dotnet-runtime_8
    prismlauncher                    # Minecraft launcher
  ];
}
