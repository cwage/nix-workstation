# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # USB boot crap

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.device = "nodev";
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  # Mount the Ubuntu install on the NVMe for reference
  fileSystems."/mnt/ubuntu" = {
    device = "/dev/disk/by-uuid/241f5c57-9de4-4b42-a61f-cb8106de2fa0";
    fsType = "ext4";
    options = [ "defaults" "nofail" ];  # nofail prevents boot failure if drive is missing
  };

  # Hostname is set in hosts/thinkpad/default.nix

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # X11 with LightDM
  services.xserver.enable = true;
  services.xserver.displayManager.lightdm.enable = true;

  # Custom session that runs ~/.xsession
  services.xserver.displayManager.session = [{
    manage = "window";
    name = "xsession";
    start = ''
      exec $HOME/.xsession
    '';
  }];
  services.displayManager.defaultSession = "none+xsession";

  # Enable sound with pipewire
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
  };

  # Enable touchpad support
  services.libinput.enable = true;

  # Power management (battery info for xfce4-power-manager)
  services.upower.enable = true;

  # UDisks2 (required for udiskie automount/tray)
  services.udisks2.enable = true;

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.cwage = {
    isNormalUser = true;
    extraGroups = [ "wheel" "audio" "video" "networkmanager" ];
    packages = with pkgs; [
      tree
    ];
  };

  # Enable flakes and the new nix CLI
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Allow non-free
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    # Basics
    vim
    tmux
    mosh
    claude-code
    git
    curl
    unzip
    ripgrep

    # X11 / Xorg tools
    xkbcomp
    xrdb
    xsetroot
    setxkbmap
    xauth

    # Window manager and session
    awesome
    xterm

    # Session/lock management
    xss-lock
    xsecurelock
    xautolock

    # Desktop utilities
    dunst                          # notifications
    networkmanagerapplet           # nm-applet
    xfce4-power-manager
    xfconf                         # settings daemon for xfce4-power-manager
    volumeicon                     # systray volume icon
    pavucontrol                    # PulseAudio volume control GUI
    brightnessctl                  # backlight control
    polkit_gnome                   # policykit auth agent
    udiskie                        # automount
    arandr                         # xrandr GUI
    scrot                          # screenshots
    xclip                          # clipboard

    # Browser
    brave

    # Apps
    emacs
    signal-desktop
    slack

    # Media
    ffmpeg
    mpv
    mplayer
    pulsemixer
    mpd
    mpc

    # Image tools
    gthumb
    imagemagick

    # Network / system tools
    nmap
    socat
    wireguard-tools
    plocate

    # Gaming
    dotnet-runtime_8

    # Utilities
    btop
    w3m
    mutt
    gh
    pass
    swaks
    ddgr
    yt-dlp
    exfatprogs
    grip
    pinentry-gnome3
  ];

  # Enable gnome-keyring for secrets (optional, used by some apps)
  services.gnome.gnome-keyring.enable = true;

  # Polkit for privilege escalation dialogs
  security.polkit.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = false;  # You use ssh-agent in .xsession
  };

  # OpenSSH daemon
  services.openssh.enable = true;

  # Flatpak (for apps like ncspot, Zoom)
  services.flatpak.enable = true;
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  xdg.portal.config.common.default = "*";

  # Steam
  programs.steam.enable = true;

  # Firewall (NixOS iptables-based, replaces ufw)
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];      # SSH
    # allowedUDPPorts = [ ];
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken.
  system.stateVersion = "25.11"; # Did you read the comment?
}
