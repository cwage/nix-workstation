{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "agentpen";
  version = "0.2.1";

  src = fetchFromGitHub {
    owner = "cwage";
    repo = "agentpen";
    rev = "v${version}";
    hash = "sha256-JHitzosD6lsAoUq2gPwgEA2PqcOvB9s3z2ljFogR2vc=";
  };

  vendorHash = "sha256-LXR8/S1x5FOxgcp8uXppc2foxwHZq6KANA3WCtX0MoE=";

  ldflags = [
    "-s" "-w"
    "-X main.version=${version}"
  ];

  # TestStageEtc_HostsAndResolvConf reads /etc/resolv.conf on the host, which
  # isn't visible inside the nix build sandbox.
  checkFlags = [ "-skip=^TestStageEtc_HostsAndResolvConf$" ];

  meta = {
    description = "Confinement wrapper for LLM coding agents";
    homepage = "https://github.com/cwage/agentpen";
    license = lib.licenses.mit;
    mainProgram = "agentpen";
    platforms = [ "x86_64-linux" ];
  };
}
