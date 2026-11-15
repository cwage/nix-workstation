#!/bin/sh
# Measure real S3 battery drain + detect spurious wakes.
# Run once BEFORE closing the lid (on battery!), once AFTER reopening.
B=/sys/class/power_supply/BAT0
S="${TMPDIR:-/tmp}/s3-drain.state"
uah=$(cat $B/charge_now); uv=$(cat $B/voltage_now); t=$(date +%s)
ac=$(cat /sys/class/power_supply/AC/online)

if [ ! -f "$S" ]; then
  [ "$ac" = "1" ] && echo "WARNING: still on AC — unplug first or the numbers are meaningless"
  printf '%s %s %s\n' "$t" "$uah" "$uv" > "$S"
  echo "baseline: $((uah/1000)) mAh, $(date '+%H:%M:%S')"
  echo "now unplug (if needed), close the lid, wait >=30 min, reopen, run this again."
else
  read t0 uah0 uv0 < "$S"
  dt=$((t - t0)); duah=$((uah0 - uah))
  awk -v duah="$duah" -v dt="$dt" -v uv="$uv" 'BEGIN{
    h = dt/3600; wh = (duah/1e6) * (uv/1e6);
    printf "elapsed:        %.1f min\n", dt/60;
    printf "charge used:    %d mAh (%.2f Wh)\n", duah/1000, wh;
    if (h > 0.05) {
      printf "average draw:   %.2f W\n", wh/h;
      printf "projected:      %.1f%% of the 77 Wh pack per 8 h in a bag\n", (wh/h)*8/77*100;
    } else print "too short to be meaningful - wait longer";
  }'
  echo
  echo "--- did it STAY asleep? (the thinkpad's real failure was waking up hung) ---"
  echo "suspend entries this boot: $(journalctl -b -k --no-pager | grep -c 'PM: suspend entry')"
  echo "suspend exits this boot:   $(journalctl -b -k --no-pager | grep -c 'PM: suspend exit')"
  echo "(more than one pair per lid-close = spurious wakes, which is what burns power and heat)"
  rm -f "$S"
fi
