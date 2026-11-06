{ lib, rustPlatform, fetchFromGitHub, makeWrapper, libsecret }:

# Linear CLI (schpet/linear-cli). Not in nixpkgs; built from source. Installs
# the `linear` binary.
rustPlatform.buildRustPackage rec {
  pname = "linear-cli";
  version = "3.1.0";

  src = fetchFromGitHub {
    owner = "schpet";
    repo = "linear-cli";
    rev = "v${version}";
    hash = "sha256-Bk4UPFqKVFH51iqiEhCSVfy/CX8CBnD8pHMMCIT83Pw=";
  };

  cargoHash = "sha256-FTm/RheZVjqILLM+T9JF5agZQOZF2OILI8znfZvw4Ms=";

  cargoBuildFlags = [ "-p" "linear" ];

  nativeBuildInputs = [ makeWrapper ];

  # Unit tests only: the integration tests (tests/cli) drive a terminal through
  # `script` and are already covered by upstream CI.
  cargoTestFlags = [ "--lib" ];

  # These tests call /bin/cat, /bin/sleep, /bin/kill and /usr/bin/mkfifo by
  # absolute path, none of which exist inside the nix build sandbox.
  checkFlags = [
    "--skip=auth::file::tests::a_fifo_is_refused_without_blocking"
    "--skip=auth::keyring::process::tests::a_hung_tool_is_killed_at_the_deadline"
    "--skip=auth::keyring::process::tests::secret_tool_store_reads_the_secret_from_stdin"
    "--skip=auth::keyring::process::tests::security_store_sends_the_command_on_stdin"
  ];

  # API keys are stored by running `secret-tool` from PATH.
  postInstall = ''
    wrapProgram $out/bin/linear \
      --suffix PATH : ${lib.makeBinPath [ libsecret ]}
  '';

  meta = {
    description = "Work with Linear issues, projects and teams from the command line";
    homepage = "https://github.com/schpet/linear-cli";
    license = lib.licenses.isc;
    mainProgram = "linear";
    platforms = [ "x86_64-linux" ];
  };
}
