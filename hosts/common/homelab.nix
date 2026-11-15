# Homelab connectivity: the WireGuard tunnel to h.quietlife.net and the NFS
# shares behind it. Opt-in, because each host needs its own tunnel address and
# a matching peer entry on the server side.
#
# The per-host part is just the address:
#
#   networking.wg-quick.interfaces.wg0.address = [ "10.10.16.N/32" ];
#
# Allocated so far: .4 thinkpad, .5 macbookpro, .6 darterpro.

{ config, lib, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    wireguard-tools
    nfs-utils
  ];

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

  # Accept everything arriving over the WireGuard tunnel. WireGuard's
  # cryptokey routing already drops packets whose source isn't in the
  # peer's allowedIPs, so this trusts exactly the homelab subnets.
  networking.firewall.trustedInterfaces = [ "wg0" ];
}
