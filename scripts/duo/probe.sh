#!/usr/bin/env bash
# Start the app on the iPhone Duo simulator and record what it does.
#
#   scripts/duo/probe.sh <app path> <output folder>
#
# Writes screenshots, the simulator's display list, the app's launch log and
# any crash report. It also saves the help text of the simulator tools: how to
# open, close, fold and rotate the Duo from a script is not documented yet.
set -uo pipefail
APP=$1
OUT=$2
BUNDLE_ID=org.bulwarkmail.mobile
mkdir -p "$OUT"

xcodebuild -version > "$OUT/toolchain.txt"
xcrun simctl list devices available > "$OUT/devices.txt"
xcrun simctl help > "$OUT/simctl-help.txt" 2>&1
for sub in io ui status_bar; do
  xcrun simctl help "$sub" > "$OUT/simctl-help-$sub.txt" 2>&1
done
xcrun devicectl help > "$OUT/devicectl-help.txt" 2>&1 || true

UDID=$(xcrun simctl list devices available -j | jq -r '[.devices[][] | select(.name | test("Duo"))] | last | .udid // empty')
if [ -z "$UDID" ]; then
  echo "::error::No iPhone Duo simulator on this image"
  exit 1
fi
xcrun simctl list devices -j | jq --arg u "$UDID" '.devices | to_entries[] | select(.value[] | .udid == $u) | .key' > "$OUT/runtime.txt"

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl io "$UDID" enumerate > "$OUT/displays.txt" 2>&1
xcrun simctl install "$UDID" "$APP"

# Two built-in screens: "primary" is the outer display, "primary-1" the inner.
shot() {
  for screen in primary primary-1; do
    xcrun simctl io "$UDID" screenshot --display="$screen" "$OUT/$1-$screen.png" >> "$OUT/screenshot.log" 2>&1 \
      || echo "no screenshot $1 $screen" >> "$OUT/notes.txt"
  done
}

shot home
xcrun simctl spawn "$UDID" log stream --style compact \
  --predicate 'process == "BulwarkMobile" OR eventMessage CONTAINS "BulwarkMobile"' > "$OUT/app.log" 2>&1 &
LOG_PID=$!
xcrun simctl launch "$UDID" "$BUNDLE_ID" > "$OUT/launch.txt" 2>&1
sleep 30
shot open
if xcrun simctl spawn "$UDID" launchctl list | grep -q "$BUNDLE_ID"; then
  echo "running after 30 s" >> "$OUT/notes.txt"
else
  echo "NOT running after 30 s" >> "$OUT/notes.txt"
fi

# A guess at closing the device: the inner screen off.
xcrun simctl io "$UDID" screenConfig --display=primary-1 power off >> "$OUT/screenconfig.log" 2>&1
sleep 8
xcrun simctl io "$UDID" enumerate > "$OUT/displays-inner-off.txt" 2>&1
shot inner-off
xcrun simctl io "$UDID" screenConfig --display=primary-1 power on >> "$OUT/screenconfig.log" 2>&1
sleep 8
shot inner-on-again
kill "$LOG_PID" 2>/dev/null

cp ~/Library/Logs/DiagnosticReports/BulwarkMobile* "$OUT/" 2>/dev/null || true
file "$OUT"/*.png > "$OUT/screenshot-sizes.txt" 2>/dev/null || true
xcrun simctl shutdown "$UDID"
cat "$OUT/notes.txt"
