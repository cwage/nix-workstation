# Android development. Opt-in, and by far the largest chunk of the old
# monolithic hosts/common — the SDK with emulator plus x86_64 system images is
# several GB of closure, so only import it on hosts that build Android apps.

{ pkgs, ... }:

let
  androidSdk = (pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "28" "33" "35" ];
    buildToolsVersions = [ "35.0.0" ];
    includeEmulator = true;
    includeSystemImages = true;
    systemImageTypes = [ "google_apis" ];
    abiVersions = [ "x86_64" ];
  }).androidsdk;
in
{
  nixpkgs.config.android_sdk.accept_license = true;

  environment.systemPackages = with pkgs; [
    jdk21
    androidSdk
    android-tools
    maestro
  ];

  # ANDROID_SDK_ROOT for emulator/gradle (adb udev handled by systemd 258)
  environment.variables.ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
  environment.variables.JAVA_HOME = "${pkgs.jdk21}";
}
