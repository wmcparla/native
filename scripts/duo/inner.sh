#!/usr/bin/env bash
# Open the iPhone Duo simulator by script and photograph the app on both
# displays (fork only).
#
#   scripts/duo/inner.sh <app path> <output folder>
#
# Needs LOGIN and PASSWORD in the environment for the Maestro sign-in. Steps:
# closed (sign in, list, a message open), opened flat, turned, closed again.
# Every step is logged to steps.txt; a step that fails does not stop the rest.
set -uo pipefail
APP=$1
OUT=$2
HERE=$(cd "$(dirname "$0")" && pwd)
BUNDLE_ID=org.bulwarkmail.mobile
mkdir -p "$OUT"
log() { echo "$(date +%H:%M:%S) $*" | tee -a "$OUT/steps.txt"; }

# The pose tool, signed with the two SpringBoard entitlements, as a section
# too (the simulator reads entitlements from either, depending on the check).
xcrun -sdk iphonesimulator clang -arch arm64 -mios-simulator-version-min=17.0 -fobjc-arc \
  -framework Foundation "$HERE/duo-pose.m" -o "$RUNNER_TEMP/duo-pose" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker "$HERE/duo-pose.entitlements" \
  && codesign -f -s - --entitlements "$HERE/duo-pose.entitlements" "$RUNNER_TEMP/duo-pose" \
  || log "pose tool did not build"

UDID=$(xcrun simctl list devices available -j | jq -r '[.devices[][] | select(.name | test("Duo"))] | last | .udid // empty')
[ -n "$UDID" ] || { echo "::error::No iPhone Duo simulator"; exit 1; }
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

# Apple's own tool, if the runtime has it.
RUNTIME_ROOT=$(xcrun simctl list runtimes -j | jq -r '[.runtimes[] | select(.name | test("iOS 27"))] | last | .runtimeRoot // empty')
find "$RUNTIME_ROOT" -iname '*suiatool*' > "$OUT/suiatool.txt" 2>/dev/null
log "suiatool in the runtime: $(wc -l < "$OUT/suiatool.txt") hits"

pose() { log "duo-pose $*: $(xcrun simctl spawn "$UDID" "$RUNNER_TEMP/duo-pose" "$@" 2>&1 | tr '\n' ' ')"; }
shot() {
  xcrun simctl io "$UDID" enumerate 2>/dev/null | grep -E "Device Name|UI Orientation" | paste - - > "$OUT/$1-orientation.txt"
  for screen in primary primary-1; do
    xcrun simctl io "$UDID" screenshot --display="$screen" "$OUT/$1-$screen.png" >/dev/null 2>&1 \
      || log "no screenshot $1 $screen"
  done
  log "shot $1"
}

pose get
shot closed-home

# Sign in on the outer display with Maestro.
if [ -n "${PASSWORD:-}" ] && command -v maestro >/dev/null; then
  if maestro --device "$UDID" test -e LOGIN="$LOGIN" -e PASSWORD="$PASSWORD" "$HERE/signin.yaml" \
      > "$OUT/maestro.txt" 2>&1; then
    log "signed in"
  else
    log "maestro sign-in failed (maestro.txt)"
  fi
else
  log "no sign-in (no PASSWORD or no maestro)"
  xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
fi
sleep 15
shot closed-list

# Open the first message on the outer display.
cat > "$RUNNER_TEMP/open-first.yaml" <<FLOW
appId: $BUNDLE_ID
---
- tapOn:
    point: "40%,25%"
FLOW
maestro --device "$UDID" test "$RUNNER_TEMP/open-first.yaml" >> "$OUT/maestro.txt" 2>&1 || log "tap failed"
sleep 10
shot closed-message

pose swap 1
sleep 10
pose get
shot open

pose pose 3 3
sleep 8
pose get
shot open-turn3
pose pose 4 3
sleep 8
shot open-turn4
pose pose 1 3
sleep 8
shot open-turn1

pose swap 0
sleep 10
pose get
shot closed-again

xcrun simctl spawn "$UDID" log show --last 15m --style compact \
  --predicate 'eventMessage CONTAINS[c] "displaytool" OR eventMessage CONTAINS[c] "devicepose" OR eventMessage CONTAINS[c] "entitle"' \
  > "$OUT/springboard.log" 2>&1
cp ~/Library/Logs/DiagnosticReports/BulwarkMobile* "$OUT/" 2>/dev/null || true
xcrun simctl shutdown "$UDID"
# Maestro echoes the text it types: the password leaves the output folder.
if [ -n "${PASSWORD:-}" ]; then
  PASSWORD="$PASSWORD" python3 -c 'import os,sys,pathlib
for f in pathlib.Path(sys.argv[1]).glob("*.txt"):
    t = f.read_text(errors="replace")
    if os.environ["PASSWORD"] in t: f.write_text(t.replace(os.environ["PASSWORD"], "[password]"))' "$OUT"
fi
