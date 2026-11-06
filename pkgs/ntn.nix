{ lib, stdenvNoCC, fetchurl }:

# Notion CLI. Not in nixpkgs; upstream ships a static musl binary, so this just
# unpacks the release tarball. `ntn update` can't replace a binary in the Nix
# store: bump version and hash here instead.
stdenvNoCC.mkDerivation rec {
  pname = "ntn";
  version = "0.23.28";

  src = fetchurl {
    url = "https://ntn.dev/releases/v${version}/ntn-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-y73AMRe3hsMeHJJE+I1TWL7y+QkW/s2cLgYDre8C+2Q=";
  };

  installPhase = ''
    runHook preInstall
    install -Dm755 ntn $out/bin/ntn
    runHook postInstall
  '';

  meta = {
    description = "Notion CLI";
    homepage = "https://developers.notion.com/cli";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "ntn";
    platforms = [ "x86_64-linux" ];
  };
}
