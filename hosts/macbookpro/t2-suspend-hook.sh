# Suspend/resume workarounds for the MacBookPro16,1. Called as root with
# "pre" before the kernel suspends and "post" after it resumes; wired up in
# configuration.nix. Background and measurements: issue #54.

state=/run/t2-suspend-hook

# "root_port branch_top" for each Thunderbolt controller behind a PCIe bridge.
tb_branches() {
  local d p parts
  for d in /sys/bus/pci/devices/*; do
    [ "$(cat "$d/vendor")" = 0x8086 ] || continue
    [ "$(cat "$d/class")" = 0x088000 ] || continue
    p=$(readlink -f "$d")
    IFS=/ read -ra parts <<< "${p#/sys/devices/}"
    if [ "${#parts[@]}" -ge 4 ]; then
      echo "${parts[1]} ${parts[2]}"
    fi
  done | sort -u
}

# True if nothing is plugged into the USB-C ports behind this root port.
tb_idle() {
  local vendors
  # USB devices other than the controllers' own root hubs (vendor 1d6b)
  vendors=$(find "$(readlink -f "/sys/bus/pci/devices/$1")" -name idVendor \
    -exec cat {} + 2>/dev/null || true)
  if [ -n "$vendors" ] && grep -qvx 1d6b <<< "$vendors"; then
    return 1
  fi
  # Thunderbolt devices other than the host routers (N-0)
  if find /sys/bus/thunderbolt/devices/ -maxdepth 1 -name '[0-9]*-[1-9]*' 2>/dev/null | grep -q .; then
    return 1
  fi
  # External displays
  if cat /sys/class/drm/card*-DP-*/status /sys/class/drm/card*-HDMI-A-*/status 2>/dev/null \
    | grep -qx connected; then
    return 1
  fi
  return 0
}

set_cpus() {
  local f
  for f in /sys/devices/system/cpu/cpu[1-9]*/online; do
    echo "$1" > "$f" || true
  done
}

case "${1:-}" in
  pre)
    mkdir -p "$state"
    : > "$state/tb-roots"

    # 1. Take every CPU except CPU 0 offline. On T2 Macs, waking secondary
    #    CPUs during early resume is extremely slow; the t2linux 7.x patch set
    #    does this in the kernel, the 6.18 one does not.
    set_cpus 0

    # 2. Remove the Thunderbolt PCI branches if nothing is plugged in. Each of
    #    the two controllers takes ~18 s to power up on resume otherwise
    #    (measured: 38 s of resume with them, ~1 s without).
    while read -r root branch; do
      [ -n "$root" ] || continue
      if tb_idle "$root"; then
        echo "removing Thunderbolt branch $branch (root port $root)"
        if echo 1 > "/sys/bus/pci/devices/$branch/remove"; then
          echo "$root" >> "$state/tb-roots"
        fi
      else
        echo "USB-C in use behind $root, keeping Thunderbolt (slow resume)"
      fi
    done < <(tb_branches)
    ;;

  post)
    set_cpus 1

    if [ -s "$state/tb-roots" ]; then
      while read -r root; do
        echo "rescanning Thunderbolt root port $root"
        echo 1 > "/sys/bus/pci/devices/$root/rescan" || true
      done < "$state/tb-roots"
      rm -f "$state/tb-roots"
    fi

    # 3. Power-cycle the panel. Without this the machine wakes with a black
    #    screen (X on the Intel GPU). Assumes the single local X session of
    #    user cwage on :0.
    xs() {
      runuser -u cwage -- env DISPLAY=:0 XAUTHORITY=/home/cwage/.Xauthority \
        xset "$@" || true
    }
    xs dpms force off
    sleep 1
    xs dpms force on
    ;;

  *)
    echo "usage: t2-suspend-hook pre|post" >&2
    exit 1
    ;;
esac
