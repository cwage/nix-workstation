# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

let
  androidSdk = (pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "28" "33" "35" ];
    buildToolsVersions = [ "35.0.0" ];
    includeEmulator = true;
    includeSystemImages = true;
    systemImageTypes = [ "google_apis" ];
    abiVersions = [ "x86_64" ];
  }).androidsdk;
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Bootloader (GRUB with EFI on NVMe)
  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.device = "nodev";
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub.useOSProber = true;

  # Disable the legacy PC speaker / TTY beep.
  boot.blacklistedKernelModules = [ "pcspkr" "snd_pcsp" ];

  # Hostname is set in hosts/thinkpad/default.nix

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  # systemd-resolved for DNS (required for WireGuard split-DNS via resolvectl)
  services.resolved.enable = true;

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

    # Disable the X11 bell module. PipeWire's upstream pipewire.conf loads
    # libpipewire-module-x11-bell with `condition = [ { module.x11.bell = !false } ]`,
    # so setting this context property to false makes the conditional skip the load.
    # Without this, every X11 BellNotify event (e.g. readline bell-on-error over SSH)
    # gets caught by the module and played as freedesktop bell.oga via libcanberra
    # through the default audio sink — independent of `xset b`, pcspkr blacklisting,
    # xterm bell settings, or anything else you'd normally tweak.
    extraConfig.pipewire."92-no-x11-bell" = {
      "context.properties" = {
        "module.x11.bell" = false;
      };
    };
  };

  # SDR hardware support (udev rules, plugdev group, kernel module blacklists)
  hardware.rtl-sdr.enable = true;
  hardware.hackrf.enable = true;

  # Enable touchpad support
  services.libinput.enable = true;

  # Power management
  services.upower.enable = true;
  services.logind.settings.Login.HandleLidSwitch = "suspend";

  # UDisks2 (required for udiskie automount/tray)
  services.udisks2.enable = true;

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.cwage = {
    isNormalUser = true;
    extraGroups = [ "wheel" "audio" "video" "networkmanager" "plugdev" "kvm" ];
    packages = with pkgs; [
      tree
    ];
  };

  # Enable flakes and the new nix CLI
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Automatic Nix store garbage collection (weekly, keep last 30 days)
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Allow non-free
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.android_sdk.accept_license = true;

  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    # Basics
    vim
    tmux
    mosh
    claude-code
    codex
    opencode
    git
    curl
    unzip
    ripgrep
    nvd                              # nix version diff (compare system profiles)
    gnumake                          # make for Makefiles (no full toolchain)

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
    cbatticon                      # lightweight battery tray icon
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
    nfs-utils
    plocate
    passt                            # pasta networking for rootless Docker
    nftables                         # nft CLI for inspecting firewall ruleset

    # Sandboxing / isolation
    # Experimenting with confining LLM coding agents (Claude Code, codex,
    # opencode) against prompt-injection threats when working in untrusted repos.
    bubblewrap                       # unprivileged namespace sandbox
    firejail                         # profile-based sandbox wrapper
    nsjail                           # namespaces + seccomp + cgroups in one tool
    podman-compose                   # rootless container compose (podman enabled below)
    mitmproxy                        # HTTPS proxy for allowlisting outbound API traffic
    strace                           # syscall tracer (useful for building seccomp profiles)
    libseccomp                       # seccomp library + scmp_sys_resolver CLI
    rubyPackages.seccomp-tools       # seccomp BPF dumping/analysis (david942j)

    # SDR
    hackrf
    rtl-sdr
    gqrx
    gnuradio
    soapysdr-with-plugins
    rtl_433
    multimon-ng
    sox

    # Android development
    jdk21
    androidSdk
    android-tools
    maestro

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
    python3Packages.grip
    pinentry-gnome3
  ];

  # Android: ANDROID_SDK_ROOT for emulator/gradle (adb udev handled by systemd 258)
  environment.variables.ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
  environment.variables.JAVA_HOME = "${pkgs.jdk21}";

  # Enable gnome-keyring for secrets (optional, used by some apps)
  services.gnome.gnome-keyring.enable = true;

  # Polkit for privilege escalation dialogs
  security.polkit.enable = true;

  # nix-index with prebuilt database + comma (run any nixpkgs binary with ", cmd")
  programs.nix-index-database.comma.enable = true;

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

  # Docker — rootless mode (daemon runs as user, no root-equivalent group)
  # Uses pasta (passt) instead of slirp4netns for container networking so that
  # the host's DNS stack (systemd-resolved, including WireGuard split-DNS for
  # lan.quietlife.net) works transparently inside containers.
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };
  systemd.user.services.docker = {
    environment.DOCKERD_ROOTLESS_ROOTLESSKIT_NET = "pasta";
    path = [ pkgs.passt ];
  };

  # Podman — alternative rootless container runtime, for sandboxing experiments.
  # dockerCompat is off because rootless docker above already owns that alias.
  virtualisation.podman = {
    enable = true;
    dockerCompat = false;
  };

  # Steam
  programs.steam.enable = true;

  # WireGuard VPN (client connection to homelab)
  networking.wg-quick.interfaces.wg0 = {
    address = [ "10.10.16.4/32" ];
    privateKeyFile = "/etc/wireguard/wg0.key";
    dns = [ "10.10.15.1" ];

    postUp = ''
      ${pkgs.systemd}/bin/resolvectl domain wg0 lan.quietlife.net
    '';
    postDown = ''
      # Lazy-unmount any NFS shares under /mnt/nas before tunnel goes away
      for mnt in $(${pkgs.gawk}/bin/awk -v base="/mnt/nas/" '$2 ~ "^"base {print $2}' /proc/mounts); do
        ${pkgs.util-linux}/bin/logger -t nas-wg-unmount "WireGuard down: lazy-unmounting $mnt"
        ${pkgs.util-linux}/bin/umount -l "$mnt" 2>/dev/null
      done
      ${pkgs.systemd}/bin/resolvectl revert wg0
    '';

    peers = [{
      publicKey = "CzGpUVSwJah7pXfkWi2ZvpYdtYQWgFM46qvzOSYy038=";
      endpoint = "h.quietlife.net:51923";
      allowedIPs = [ "10.10.15.0/24" "10.10.16.0/24" ];
      persistentKeepalive = 25;
    }];
  };

  # NFS client + autofs (NAS shares over WireGuard tunnel)
  services.autofs = {
    enable = true;
    autoMaster = ''
      /mnt/nas /etc/auto.nas --timeout=300
    '';
  };

  environment.etc."auto.nas".text = ''
    # Wildcard map: /mnt/nas/<share> → 10.10.15.4:/volume1/<share>
    # Soft mount with aggressive timeouts for roaming laptop use
    * -fstype=nfs,soft,timeo=30,retrans=2,actimeo=3 10.10.15.4:/volume1/&
  '';

  # Firewall (NixOS iptables-based, replaces ufw)
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 1234 ]; # SSH, rtl_tcp
    # allowedUDPPorts = [ ];
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken.
  system.stateVersion = "25.11"; # Did you read the comment?
}
