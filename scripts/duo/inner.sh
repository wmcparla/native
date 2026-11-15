#!/usr/bin/env bash
# The app on the iPhone Duo simulator, signed in, folded, opened and stood as
# a tent by script (fork only).
#
#   scripts/duo/inner.sh <app path> <output folder>
#
# Needs LOGIN and PASSWORD in the environment for the sign-in. Every step is
# logged to steps.txt and photographed on both displays; a step that fails
# does not stop the rest.
set -uo pipefail
APP=$1
OUT=$2
HERE=$(cd "$(dirname "$0")" && pwd)
BUNDLE_ID=org.bulwarkmail.mobile
mkdir -p "$OUT"
log() { echo "$(date +%H:%M:%S) $*" | tee -a "$OUT/steps.txt"; }

# The pose tool. A simulator binary carries its entitlements in a linker
# section, as Xcode builds them; macOS refuses private ones in an ad hoc
# signature ("Codesigning issue", run 43743225777).
xcrun -sdk iphonesimulator clang -arch arm64 -mios-simulator-version-min=17.0 -fobjc-arc \
  -framework Foundation "$HERE/duo-pose.m" -o "$RUNNER_TEMP/duo-pose" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker "$HERE/duo-pose.entitlements" \
  && codesign -f -s - "$RUNNER_TEMP/duo-pose" \
  || log "pose tool did not build"

UDID=$(xcrun simctl list devices available -j | jq -r '[.devices[][] | select(.name | test("Duo"))] | last | .udid // empty')
[ -n "$UDID" ] || { echo "::error::No iPhone Duo simulator"; exit 1; }
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

pose() { log "duo-pose $*: $(xcrun simctl spawn "$UDID" "$RUNNER_TEMP/duo-pose" "$@" 2>&1 | tr '\n' ' ')"; }
shot() {
  for screen in primary primary-1; do
    xcrun simctl io "$UDID" screenshot --display="$screen" "$OUT/$1-$screen.png" >/dev/null 2>&1 \
      || log "no screenshot $1 $screen"
  done
  log "shot $1"
}

# Maestro drives taps and typing. It finds no text on the Duo (run 43744912285:
# "Use my email address" not visible), so the flows tap points, measured on
# Birch's Duo VM on the same 466x678 outer display (birch/signin.py).
export MAESTRO_DRIVER_STARTUP_TIMEOUT=600000
step() { # step <name> <yaml commands...>
  local name=$1; shift
  printf 'appId: %s\n---\n%s\n' "$BUNDLE_ID" "$*" > "$RUNNER_TEMP/$name.yaml"
  if maestro --device "$UDID" test "$RUNNER_TEMP/$name.yaml" >> "$OUT/maestro.txt" 2>&1; then
    log "step $name"
  else
    log "step $name FAILED (maestro.txt)"
  fi
}
tap() { printf -- '- tapOn:\n    point: "%s,%s"\n' "$1" "$2"; }
type_text() { printf -- '- inputText: "%s"\n' "$1"; }
nl=$'\n'  # command substitution drops the trailing newline between two commands

xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
sleep 30
shot 01-welcome
maestro --device "$UDID" hierarchy > "$OUT/hierarchy-welcome.json" 2>>"$OUT/maestro.txt" || log "no hierarchy"
if [ -n "${PASSWORD:-}" ]; then
  step use-email "$(tap 233 444)"; sleep 8; shot 02-email
  step email "$(tap 190 152)${nl}$(type_text "$LOGIN")"; sleep 3
  step continue "$(tap 190 230)"; sleep 12; shot 03-found
  step password-instead "$(tap 190 352)"; sleep 8; shot 04-password
  step password "$(tap 180 280)${nl}$(type_text "$PASSWORD")"; sleep 3
  step sign-in "$(tap 190 334)"; sleep 30; shot 05-signed-in
  step not-now "$(tap 189 548)"; sleep 8
else
  log "no PASSWORD: not signing in"
fi
shot 06-closed-list

# Closed, a message: the toolbars in the status column.
step open-message "$(tap 190 245)"; sleep 10; shot 07-closed-message
step back "$(tap 424 200)"; sleep 6

# Closed and turned sideways: the desk inbox (this build skips the hinge
# angle, which no scripted pose produces; see EXPO_PUBLIC_DESK_WITHOUT_ANGLE).
pose get
pose pose 3 1;    sleep 10; shot 10-desk
maestro --device "$UDID" hierarchy > "$OUT/hierarchy-desk.json" 2>>"$OUT/maestro.txt" || log "no hierarchy"
step desk-open "$(tap 300 160)"; sleep 10; shot 11-desk-message
pose pose 1 1;    sleep 10; shot 12-closed-upright-again

# Opened: flat sideways, then upright, then half open like a book.
pose swap 1;      sleep 10; pose get; shot 20-open
pose pose 3 3;    sleep 8;  shot 21-open-upright
pose pose 1 3;    sleep 8
pose swap 0.55;   sleep 10; pose get; shot 22-book
pose swap 0;      sleep 10; shot 23-closed-again

xcrun simctl spawn "$UDID" log show --last 20m --style compact \
  --predicate 'eventMessage CONTAINS[c] "hinge" OR eventMessage CONTAINS[c] "tent" OR eventMessage CONTAINS[c] "devicepose"' \
  > "$OUT/springboard.log" 2>&1
cp ~/Library/Logs/DiagnosticReports/BulwarkMobile* "$OUT/" 2>/dev/null || true
xcrun simctl shutdown "$UDID"
# Maestro echoes the text it types: the password leaves the output folder.
if [ -n "${PASSWORD:-}" ]; then
  PASSWORD="$PASSWORD" python3 -c 'import os,sys,pathlib
for f in pathlib.Path(sys.argv[1]).glob("*"):
    if f.suffix not in (".txt", ".json", ".log", ".yaml"): continue
    t = f.read_text(errors="replace")
    if os.environ["PASSWORD"] in t: f.write_text(t.replace(os.environ["PASSWORD"], "[password]"))' "$OUT"
fi
