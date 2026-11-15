#!/bin/bash
# Ad-hoc sign an unsigned device build so it carries its entitlements, for the vphone-linux VMs
# (fork only). The guest re-signs the app on install; the keychain groups the app and its
# extensions share have to be in the signature for expo-secure-store to work.
#
#   scripts/vphone/sign-adhoc.sh BulwarkMobile.app ios TEAM_ID
set -euo pipefail
app=$1 iosdir=$2 team=$3

# Entitlements for one bundle: its target's .entitlements file from the generated project, plus
# the application-identifier and team-identifier a provisioning profile would have added.
ents() {
  local bundle=$1 name id src out
  name=$(basename "$bundle"); name=${name%.*}
  id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Info.plist")
  src=$(ls "$iosdir/$name/$name.entitlements" 2>/dev/null || true)
  out=$(mktemp -t ents).plist
  if [ -n "$src" ]; then cp "$src" "$out"; else plutil -create xml1 "$out"; fi
  plutil -replace application-identifier -string "$team.$id" "$out"
  plutil -replace com.apple.developer.team-identifier -string "$team" "$out"
  echo "$out"
}

# Inside out: frameworks and dylibs, then extensions, then the app.
find "$app" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0 |
  while IFS= read -r -d '' f; do codesign -f -s - "$f"; done
find "$app/PlugIns" -maxdepth 1 -name '*.appex' -print0 2>/dev/null |
  while IFS= read -r -d '' x; do codesign -f -s - --entitlements "$(ents "$x")" "$x"; done
codesign -f -s - --entitlements "$(ents "$app")" "$app"
codesign -d --entitlements - "$app" | head -n 40
