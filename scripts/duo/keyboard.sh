#!/usr/bin/env bash
# The on-screen keyboard on the iPhone Duo simulator, on every display and
# pose, with the sign-in screen's address field focused (fork only; needs no
# account). The overlay prints the keyboard's frame.
#
#   scripts/duo/keyboard.sh <app path> <output folder>
set -uo pipefail
APP=$1
OUT=$2
HERE=$(cd "$(dirname "$0")" && pwd)
BUNDLE_ID=org.bulwarkmail.mobile
mkdir -p "$OUT"
log() { echo "$(date +%H:%M:%S) $*" | tee -a "$OUT/steps.txt"; }

xcrun -sdk iphonesimulator clang -arch arm64 -mios-simulator-version-min=17.0 -fobjc-arc \
  -framework Foundation "$HERE/duo-pose.m" -o "$RUNNER_TEMP/duo-pose" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker "$HERE/duo-pose.entitlements" \
  && codesign -f -s - "$RUNNER_TEMP/duo-pose" \
  || log "pose tool did not build"

# No hardware keyboard, or the simulator hides the on-screen one.
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false

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
# The address field by its id; a point as well where Maestro finds nothing.
focus() { printf -- '- tapOn:\n    id: login-email-input\n    optional: true\n'; [ $# -eq 2 ] && tap "$1" "$2"; }
nl=$'\n'

xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
sleep 30
shot 01-welcome
# Outer display: "Use my email address", then the address field.
step email-step "$(tap 233 444)"; sleep 6
step focus-outer "$(focus 190 152)"; sleep 6; shot 02-outer-keyboard
step type-outer "- inputText: \"ada@example.org\""; sleep 3; shot 03-outer-typed

# Opened flat sideways, upright, then half open both ways. A window change
# closes the keyboard (the app's own rule), so the field is focused again.
pose swap 1;    sleep 10; pose get; shot 10-inner-sideways
step focus-sideways "$(focus)"; sleep 6; shot 11-inner-sideways-keyboard
pose pose 3 3;  sleep 8;  shot 20-inner-upright
step focus-upright "$(focus)"; sleep 6; shot 21-inner-upright-keyboard
pose pose 3 2;  sleep 8;  pose get; shot 30-laptop
step focus-laptop "$(focus)"; sleep 6; shot 31-laptop-keyboard
pose pose 1 2;  sleep 8;  pose get; shot 40-book
step focus-book "$(focus)"; sleep 6; shot 41-book-keyboard
maestro --device "$UDID" hierarchy > "$OUT/hierarchy.json" 2>>"$OUT/maestro.txt" || log "no hierarchy"

cp ~/Library/Logs/DiagnosticReports/BulwarkMobile* "$OUT/" 2>/dev/null || true
xcrun simctl shutdown "$UDID"
