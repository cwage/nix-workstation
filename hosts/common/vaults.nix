# Encrypted-at-rest working folders (gocryptfs "vaults", managed by the
# `vault` helper in cwage/bin; design notes in cwage/safe PLAN.md).
#
# A vault is a gocryptfs ciphertext dir (~/vaults/NAME.enc) mounted to a
# plaintext view (~/NAME) while in use. The master password is stored
# age-encrypted to YubiKey (PIV) identities, so opening is plug-in-and-touch.
# Lock policy: vaults survive screen locks and are force-closed only on
# suspend/hibernate, by the systemd unit below — a system unit so a hung X
# session or dead xss-lock can't carry a mounted vault into sleep.

{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    gocryptfs
    age
    age-plugin-yubikey
    yubikey-manager            # ykman, for PIV slot inspection/management
  ];

  # age-plugin-yubikey talks to the YubiKey PIV applet over PC/SC. Note:
  # gpg's scdaemon can contend with pcscd for the reader; the lock wrapper
  # already kills scdaemon on every lock, which keeps this from festering.
  services.pcscd.enable = true;

  # Directory scaffolding for the vault layout (the contents — ciphertext,
  # wrapped passwords, age identity stubs — are mutable user data and are
  # provisioned manually; see the `vault` script header). 0700: the wrapped
  # password and identity stubs are nobody else's business.
  systemd.tmpfiles.rules = [
    "d /home/cwage/vaults 0700 cwage users -"
    "d /home/cwage/.config/age 0700 cwage users -"
  ];

  # Force-close vaults before any sleep state (suspend, hibernate,
  # suspend-then-hibernate all pull in sleep.target). Runs as cwage since
  # the mounts are user FUSE mounts; /run/wrappers provides the setuid
  # fusermount. User units can't order against the system sleep.target,
  # which is why this is a system unit.
  systemd.services.lock-vaults = {
    description = "Force-close gocryptfs vaults before sleep";
    wantedBy = [ "sleep.target" ];
    before = [ "sleep.target" ];
    unitConfig.ConditionPathExists = "/home/cwage/bin/vault";
    path = [ "/run/wrappers" pkgs.gocryptfs pkgs.procps pkgs.psmisc pkgs.coreutils ];
    # systemd >= 255 no longer sets $HOME for User= services unless
    # SetLoginEnvironment is on; the vault script locates everything under
    # $HOME, so without this it silently finds no vaults and no-ops.
    environment.HOME = "/home/cwage";
    serviceConfig = {
      Type = "oneshot";
      User = "cwage";
      ExecStart = "/home/cwage/bin/vault close --all --force";
    };
  };
}
