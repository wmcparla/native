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

shot() {
  xcrun simctl io "$UDID" screenshot "$OUT/$1.png" > /dev/null 2>&1 || echo "no screenshot $1" >> "$OUT/notes.txt"
}

shot home
xcrun simctl spawn "$UDID" log stream --style compact \
  --predicate 'process == "BulwarkMobile" OR eventMessage CONTAINS "BulwarkMobile"' > "$OUT/app.log" 2>&1 &
LOG_PID=$!
xcrun simctl launch "$UDID" "$BUNDLE_ID" > "$OUT/launch.txt" 2>&1
sleep 5
shot launch-5s
sleep 25
shot launch-30s
if xcrun simctl spawn "$UDID" launchctl list | grep -q "$BUNDLE_ID"; then
  echo "running after 30 s" >> "$OUT/notes.txt"
else
  echo "NOT running after 30 s" >> "$OUT/notes.txt"
fi
kill "$LOG_PID" 2>/dev/null

cp ~/Library/Logs/DiagnosticReports/BulwarkMobile* "$OUT/" 2>/dev/null || true
file "$OUT"/*.png > "$OUT/screenshot-sizes.txt" 2>/dev/null || true
xcrun simctl shutdown "$UDID"
cat "$OUT/notes.txt"
