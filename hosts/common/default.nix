# Shared, host-agnostic workstation configuration: the desktop every host
# gets. Host-specific bits — bootloader, the generated hardware scan,
# system.stateVersion, and any per-machine hardware quirks (e.g. the Apple T2
# options on macbookpro) — live in the individual hosts/<host>/ directories.
#
# Optional feature sets live in sibling modules here and are imported per host,
# so a machine can leave out what it doesn't need:
#
#   ./homelab.nix  WireGuard tunnel + NFS shares (needs a per-host tunnel IP)
#   ./gaming.nix   Steam, Prismlauncher
#   ./sdr.nix      rtl-sdr/hackrf udev rules + radio tooling
#   ./android.nix  Android SDK, emulator, system images, JDK

{ config, lib, pkgs, ... }:

let
  agentpen = pkgs.callPackage ../../pkgs/agentpen.nix { };
in
{
  imports = [
    ./vaults.nix
  ];

  # Disable the legacy PC speaker / TTY beep.
  boot.blacklistedKernelModules = [ "pcspkr" "snd_pcsp" ];

  # Hostname is set per-host in hosts/<host>/default.nix

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

  # Bluetooth. The stack is bluez + PipeWire's native backend, which handles
  # both A2DP (stereo media, no mic) and HFP (mic live, mono) without ofono or
  # hsphfpd. powerOnBoot is off so the adapter only comes up when asked --
  # relevant when working somewhere a stray auto-connect is unwelcome.
  # Experimental exposes the BLE battery-level interface that UPower/blueman
  # read to show headset charge.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
    settings.General.Experimental = true;
  };

  # blueman: systray pairing/connection GUI (blueman-applet, started from
  # .xsession) plus the blueman-mechanism D-Bus service and polkit rules that
  # let pairing happen without a root prompt.
  services.blueman.enable = true;

  # Enable touchpad support
  services.libinput.enable = true;

  # Power management
  services.upower.enable = true;
  services.logind.settings.Login.HandleLidSwitch = "suspend";

  # UDisks2 (required for udiskie automount/tray)
  services.udisks2.enable = true;

  # TPM 2.0 userland access: creates the tss group and udev rules so
  # /dev/tpmrm0 (kernel resource manager) is group-accessible instead of
  # root-only. tctiEnvironment sets TPM2TOOLS_TCTI/TPM2_PKCS11_TCTI to point
  # tools at /dev/tpmrm0. No-op on hosts without a TPM (macbookpro/T2).
  security.tpm2 = {
    enable = true;
    tctiEnvironment.enable = true;
  };

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.cwage = {
    isNormalUser = true;
    extraGroups = [ "wheel" "audio" "video" "networkmanager" "plugdev" "kvm" "tss" ];
    packages = with pkgs; [
      tree
    ];
  };

  # Enable flakes and the new nix CLI
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Automatic Nix store garbage collection. Frequent flake updates churn a lot
  # of store paths, so keep only two weeks of generations.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Deduplicate identical store files via hard links as they're added.
  nix.settings.auto-optimise-store = true;

  # Allow non-free
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    # Basics
    vim
    tmux
    mosh
    (callPackage ../../pkgs/linear-cli.nix { })
    (callPackage ../../pkgs/ntn.nix { })

    # Coding agents, unwrapped: plain `claude` / `codex` in PATH. agentpen is
    # still installed, but you opt into the sandbox per invocation
    # (`agentpen --agent claude claude …`) rather than it shadowing the real
    # binaries, which silently confined every session and was surprising.
    claude-code
    codex
    opencode
    agentpen
    git
    curl
    unzip
    ripgrep
    jq
    openssl
    nvd                              # nix version diff (compare system profiles)
    nix-update                       # bump version + recompute hashes for pkgs/*.nix
    gnumake                          # make for Makefiles (no full toolchain)

    # X11 / Xorg tools
    xkbcomp
    xrdb
    xsetroot
    setxkbmap
    xauth

    # Window manager and session
    awesome
    # xterm, linked against libXcursor so it uses the cursor theme. libX11
    # loads libXcursor.so.1 by bare name at runtime, which fails on NixOS (no
    # global library path), leaving xterm with the tiny built-in X cursors.
    # Adding it as a direct dependency makes that load succeed. Preferred over
    # an LD_LIBRARY_PATH wrapper, which would leak into every shell.
    (xterm.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ patchelf ];
      postFixup = (old.postFixup or "") + ''
        patchelf --add-needed libXcursor.so.1 \
          --add-rpath ${libxcursor}/lib $out/bin/.xterm-wrapped
      '';
    }))

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
    alsa-utils                     # amixer/alsamixer -- mixer layer below PipeWire
    brightnessctl                  # backlight control
    polkit_gnome                   # policykit auth agent
    udiskie                        # automount
    # arandr                       # xrandr GUI — broken upstream in current nixpkgs, rarely used
    scrot                          # screenshots
    xclip                          # clipboard

    # Browser
    brave

    # Apps
    emacs
    copilot-language-server         # backs copilot.el in the spacemacs github-copilot layer
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
    mtr
    tpm2-tools                       # tpm2_getcap / tpm2_pcrread / etc.
    dnsutils                         # dig, nslookup, etc.
    socat
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
    # mitmproxy - HTTPS proxy for allowlisting outbound API traffic.
    # Temporarily disabled: broken upstream in current nixpkgs. mitmproxy
    # 12.2.3 pins msgpack<=1.1.2 but nixpkgs ships msgpack 1.2.1, so the
    # pythonRuntimeDepsCheck hook fails the build. Re-enable once nixpkgs
    # bumps mitmproxy (or relaxes the msgpack bound).
    # mitmproxy
    strace                           # syscall tracer (useful for building seccomp profiles)
    libseccomp                       # seccomp library + scmp_sys_resolver CLI
    rubyPackages.seccomp-tools       # seccomp BPF dumping/analysis (david942j)

    # Utilities
    btop
    w3m
    mutt
    gh
    flyctl                           # fly.io CLI (binary is `fly`)
    pass
    swaks
    ddgr
    yt-dlp
    exfatprogs
    python3Packages.grip
    pinentry-gnome3
  ];

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
  xdg.portal.extraPortals = [
    pkgs.xdg-desktop-portal-gtk
    pkgs.kdePackages.xdg-desktop-portal-kde  # file chooser only (thumbnails/preview)
  ];
  xdg.portal.config.common.default = [ "gtk" ];
  xdg.portal.config.common."org.freedesktop.impl.portal.FileChooser" = [ "kde" ];

  # dconf: GSettings backend so GTK apps/portals persist settings
  # (e.g. file chooser window size — without it every picker opens at
  # natural size, which can exceed the screen)
  programs.dconf.enable = true;

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

  # Firewall (NixOS iptables-based, replaces ufw). Feature modules add their
  # own ports (e.g. sdr.nix opens 1234 for rtl_tcp, homelab.nix trusts wg0).
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ]; # SSH
    # mDNS: resolved's .local queries get answered to the multicast group,
    # not back to our address, so conntrack sees them as unsolicited inbound
    allowedUDPPorts = [ 5353 ];
  };
}
