# Shared, host-agnostic workstation configuration.
#
# Everything here applies to every host (thinkpad, macbookpro, …). Host-specific
# bits — bootloader, the generated hardware scan, system.stateVersion, and any
# per-machine hardware quirks (e.g. the Apple T2 options on macbookpro) — live in
# the individual hosts/<host>/ directories.

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

  agentpen = pkgs.callPackage ../../pkgs/agentpen.nix { };

  # Shadow `claude` / `codex` in PATH with agentpen wrappers. The wrappers
  # reference the real binaries by absolute store path so agentpen's own
  # PATH lookup can't recurse into the wrapper. Sibling `*-raw` shims expose
  # the unwrapped binaries for when sandboxing isn't wanted.
  wrapAgent = name: realPath: pkgs.writeShellScriptBin name ''
    exec ${agentpen}/bin/agentpen --agent ${name} ${realPath} "$@"
  '';
  rawAgent = name: realPath: pkgs.writeShellScriptBin "${name}-raw" ''
    exec ${realPath} "$@"
  '';
  agentWrappers = [
    (wrapAgent "claude" "${pkgs.claude-code}/bin/claude")
    (rawAgent  "claude" "${pkgs.claude-code}/bin/claude")
    (wrapAgent "codex"  "${pkgs.codex}/bin/codex")
    (rawAgent  "codex"  "${pkgs.codex}/bin/codex")
  ];
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
  nixpkgs.config.android_sdk.accept_license = true;

  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    # Basics
    vim
    tmux
    mosh
    agentpen
    opencode
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
    # mitmproxy - HTTPS proxy for allowlisting outbound API traffic.
    # Temporarily disabled: broken upstream in current nixpkgs. mitmproxy
    # 12.2.3 pins msgpack<=1.1.2 but nixpkgs ships msgpack 1.2.1, so the
    # pythonRuntimeDepsCheck hook fails the build. Re-enable once nixpkgs
    # bumps mitmproxy (or relaxes the msgpack bound).
    # mitmproxy
    strace                           # syscall tracer (useful for building seccomp profiles)
    libseccomp                       # seccomp library + scmp_sys_resolver CLI
    rubyPackages.seccomp-tools       # seccomp BPF dumping/analysis (david942j)

    # SDR
    hackrf
    rtl-sdr
    gqrx
    # gnuradio  # disabled: pyqtgraph 0.14.0 SVGExporter tests fail in current nixpkgs
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
    flyctl                           # fly.io CLI (binary is `fly`)
    pass
    swaks
    ddgr
    yt-dlp
    exfatprogs
    python3Packages.grip
    pinentry-gnome3
  ] ++ agentWrappers;

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

  # Steam
  programs.steam.enable = true;

  # WireGuard VPN (client connection to homelab). `address` is host-specific
  # (each client needs its own tunnel IP) and is set in the per-host config.
  networking.wg-quick.interfaces.wg0 = {
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

  # Don't try to bring wg0 up if the key isn't provisioned yet (e.g. on a
  # fresh install before the peer side has been set up). Without this guard
  # wg-quick partially activates — assigns the address and registers wg0's
  # DNS server (10.10.15.1) via resolvconf — then fails when it can't read
  # the key, leaving the system pointed at an unreachable resolver.
  systemd.services.wg-quick-wg0.unitConfig.ConditionPathExists =
    "/etc/wireguard/wg0.key";

  # Don't auto-start at boot. From the home LAN the endpoint hostname
  # resolves to the WAN IP, and without router hairpin NAT the handshake
  # never completes — meanwhile wg-quick has already added a route for
  # 10.10.15.0/24 via wg0 that shadows the connected LAN route. Start it
  # manually with `systemctl start wg-quick-wg0` when roaming.
  systemd.services.wg-quick-wg0.wantedBy = lib.mkForce [ ];

  # wg0 is manually controlled (see wantedBy override above). Don't let a
  # nixos-rebuild switch bounce the running tunnel: the restart resolves the
  # endpoint hostname at start time, and if it lands in a DNS-unavailable
  # window during the rebuild (the tunnel-only resolver 10.10.15.1 was just
  # torn down), wg-quick fails the whole unit. Config changes to wg0 apply on
  # the next manual `systemctl restart wg-quick-wg0`.
  systemd.services.wg-quick-wg0.restartIfChanged = false;

  # NFS client + autofs (NAS shares over WireGuard tunnel)
  services.autofs = {
    enable = true;
    autoMaster = ''
      /mnt/nas /etc/auto.nas --timeout=300
    '';
  };

  environment.etc."auto.nas".text = ''
    # Wildcard map: /mnt/nas/<share> → 10.10.15.4:/volume1/<share>
    # Soft mount with aggressive timeouts for roaming laptop use.
    # actimeo=60: attribute cache must outlive a directory listing, or every
    # ls/stat pays one ~20ms VPN round trip per file (54s for 3.4k files at 3s)
    * -fstype=nfs,soft,timeo=30,retrans=2,actimeo=60 10.10.15.4:/volume1/&
  '';

  # Firewall (NixOS iptables-based, replaces ufw)
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 1234 ]; # SSH, rtl_tcp
    # allowedUDPPorts = [ ];
  };
}
