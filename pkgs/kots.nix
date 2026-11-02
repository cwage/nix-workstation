{ lib, stdenvNoCC, fetchurl }:

# Replicated KOTS kubectl plugin. Not in nixpkgs; upstream ships a static Go
# binary, so this just unpacks the release tarball. Installed as kubectl-kots
# so `kubectl kots ...` works.
stdenvNoCC.mkDerivation rec {
  pname = "kots";
  version = "1.134.1";

  src = fetchurl {
    url = "https://github.com/replicatedhq/kots/releases/download/v${version}/kots_linux_amd64.tar.gz";
    hash = "sha256-kz+fOK2kyuThtWU2q1W12ap4jHcn1MfT2oiuSktlC8s=";
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 kots $out/bin/kubectl-kots
    runHook postInstall
  '';

  meta = {
    description = "Replicated KOTS kubectl plugin";
    homepage = "https://github.com/replicatedhq/kots";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "kubectl-kots";
    platforms = [ "x86_64-linux" ];
  };
}
