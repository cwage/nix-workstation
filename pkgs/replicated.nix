{ lib, stdenvNoCC, fetchurl }:

# Replicated vendor CLI. Not in nixpkgs; upstream ships a static Go binary, so
# this just unpacks the release tarball.
stdenvNoCC.mkDerivation rec {
  pname = "replicated";
  version = "0.129.15";

  src = fetchurl {
    url = "https://github.com/replicatedhq/replicated/releases/download/v${version}/replicated_${version}_linux_amd64.tar.gz";
    hash = "sha256-4iuct7WPi1DOReVO1i5grj6YkrTYFmL92XPj2G/lvGM=";
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 replicated $out/bin/replicated
    runHook postInstall
  '';

  meta = {
    description = "Replicated vendor CLI";
    homepage = "https://github.com/replicatedhq/replicated";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "replicated";
    platforms = [ "x86_64-linux" ];
  };
}
