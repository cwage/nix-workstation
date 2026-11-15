#!/bin/sh
# Compare the firmware's E820 memory map between two boots, ignoring timestamps.
#
# This is the pass/fail test for whether hibernation can work on darterpro: its
# firmware places one constant-size ACPI/reserved cluster at a varying address
# each boot, and arch/x86/power/hibernate.c refuses to restore an image whose
# recorded firmware map doesn't match ("Hibernate inconsistent memory map
# detected!"). See the long comment in hosts/darterpro/configuration.nix.
#
# Run it bare after any firmware or firmware-setting change. If it ever reports
# STABLE, restore suspend-then-hibernate (those two lines are in that comment).
#
# Note: journalctl's default output prefixes every line with a timestamp, so a
# naive `journalctl -k | grep BIOS-e820 | diff` marks all lines as changed.
# This uses -o cat to strip that.
#
# Related: to check whether System76 has published newer firmware (the CLI has
# no read-only verb, and firmware.system76.com pins its own CA so curl cannot
# reach the buildchain endpoint), ask the daemon over D-Bus:
#   D="com.system76.FirmwareDaemon /com/system76/FirmwareDaemon com.system76.FirmwareDaemon"
#   sudo busctl call $D Bios        # installed: (model, version)
#   sudo busctl call $D Download    # published: (digest, changelog json)
# Download populates /var/cache/system76-firmware-daemon; it does NOT flash.
# Only Schedule(digest) arms an install, and Unschedule cancels it.
#
# Usage: e820-check.sh [bootA] [bootB]      (default: -1 0 = previous vs current)

A=${1:--1}; B=${2:-0}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

norm() {
  journalctl -b "$1" -k --no-pager -o cat 2>/dev/null \
    | grep 'BIOS-e820' | sed 's/.*BIOS-e820: //'
}
norm "$A" > "$T/a"
norm "$B" > "$T/b"

if [ ! -s "$T/a" ] || [ ! -s "$T/b" ]; then
  echo "no e820 data for boot $A and/or $B (try: journalctl --list-boots)"
  exit 2
fi

printf 'boot %-3s %2d regions\nboot %-3s %2d regions\n\n' \
  "$A" "$(wc -l < "$T/a")" "$B" "$(wc -l < "$T/b")"

if cmp -s "$T/a" "$T/b"; then
  echo "VERDICT: memory map is STABLE across these boots."
  echo "         -> hibernation resume should work; try: systemctl hibernate"
  echo "         -> then restore suspend-then-hibernate in hosts/darterpro/configuration.nix"
  exit 0
fi

echo "VERDICT: memory map DIFFERS -> the kernel will reject a hibernation image"
echo "         (Hibernate inconsistent memory map detected! / Image mismatch)"
echo
echo "regions that moved:"
diff "$T/a" "$T/b" | grep -E '^[<>]' | sed 's/^/  /'
echo
sort "$T/a" > "$T/as"; sort "$T/b" > "$T/bs"
echo "identical regions: $(comm -12 "$T/as" "$T/bs" | wc -l)"
exit 1
