#!/usr/bin/env bash
# The scene life cycle build on an iPhone simulator (fork only): a signed-out
# start, a sign-in link while running, and a cold start from a sign-in link.
#
#   scripts/scenes/run.sh <app path> <output folder>
set -uo pipefail
APP=$1
OUT=$2
BUNDLE_ID=org.bulwarkmail.mobile
LINK='bulwarkmail://pair?server=https%3A%2F%2Fmail.example.org&code=ABCDEF123456'
mkdir -p "$OUT"
log() { echo "$(date +%H:%M:%S) $*" | tee -a "$OUT/steps.txt"; }

xcodebuild -version | tr '\n' ' ' | tee -a "$OUT/steps.txt"; echo >> "$OUT/steps.txt"
UDID=$(xcrun simctl list devices available -j | jq -r '[.devices | to_entries[] | select(.key | test("iOS")) | .value[] | select(.name | test("^iPhone 1[67]( Pro)?$"))] | last | .udid // empty')
[ -n "$UDID" ] || { echo "::error::No iPhone simulator"; exit 1; }
log "simulator: $(xcrun simctl list devices available | grep "$UDID")"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
shot() { xcrun simctl io "$UDID" screenshot "$OUT/$1.png" >/dev/null 2>&1 && log "shot $1" || log "no screenshot $1"; }

# iOS asks "Open in Bulwark Mobile?" before it hands a link over: Maestro taps Open.
confirm() {
  printf 'appId: %s\n---\n- tapOn:\n    text: "Open"\n    optional: true\n' "$BUNDLE_ID" > "$RUNNER_TEMP/open.yaml"
  maestro --device "$UDID" test "$RUNNER_TEMP/open.yaml" >> "$OUT/maestro.txt" 2>&1 && log "tapped Open" || log "Open not tapped (maestro.txt)"
}

xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null && log "launched"
sleep 40; shot 01-signed-out-start
xcrun simctl openurl "$UDID" "$LINK" && log "link while running"
sleep 8; confirm; sleep 10; shot 02-link-while-running
# Cancel the app's own question so the cold start begins clean.
xcrun simctl terminate "$UDID" "$BUNDLE_ID" && log "terminated"
sleep 5
xcrun simctl openurl "$UDID" "$LINK" && log "link, cold start"
sleep 8; confirm; sleep 40; shot 03-link-cold-start
xcrun simctl spawn "$UDID" launchctl list | grep -c "$BUNDLE_ID" | xargs -I{} echo "running: {}" | tee -a "$OUT/steps.txt"
cp ~/Library/Logs/DiagnosticReports/BulwarkMobile* "$OUT/" 2>/dev/null || true
xcrun simctl shutdown "$UDID"
