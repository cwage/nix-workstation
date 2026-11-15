# Software-defined radio. Opt-in: the hardware.* options here install udev
# rules and module blacklists, so only import it on hosts the SDR dongles
# actually get plugged into.

{ pkgs, ... }:

{
  # udev rules, plugdev group access, and kernel module blacklists for the
  # DVB drivers that would otherwise claim RTL dongles.
  hardware.rtl-sdr.enable = true;
  hardware.hackrf.enable = true;

  environment.systemPackages = with pkgs; [
    hackrf
    rtl-sdr
    gqrx
    # gnuradio  # disabled: pyqtgraph 0.14.0 SVGExporter tests fail in current nixpkgs
    soapysdr-with-plugins
    rtl_433
    multimon-ng
    sox
  ];

  # rtl_tcp, for streaming IQ samples to another machine on the LAN.
  networking.firewall.allowedTCPPorts = [ 1234 ];
}
