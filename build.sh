#!/bin/bash
# Build, sign and relaunch LaserPointer.
#
# The .app bundle is assembled here rather than committed, so a fresh clone
# builds a complete app with one command and `build/` stays gitignored.
#
# Signing: an ad-hoc signature (-) is derived from the binary's contents and so
# changes on every rebuild. This app needs no TCC permissions, so unlike its
# sibling EDRBoost that costs nothing today — but signing with a fixed local
# certificate when one exists keeps the Designated Requirement stable, which
# matters the moment anything (login item, firewall, a future permission) starts
# identifying the app by signature.
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/LaserPointer.app"
CERT_NAME="LaserPointer Local Signing"
SDK=$(xcrun --show-sdk-path --sdk macosx)

killall LaserPointer 2>/dev/null || true
sleep 1

# Bundle skeleton.
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

xcrun swiftc -O -target arm64-apple-macos13.0 -sdk "$SDK" \
  -o "$APP/Contents/MacOS/LaserPointer" "$ROOT"/LaserPointer/*.swift

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  codesign --force --sign "$CERT_NAME" --entitlements "$ROOT/LaserPointer.entitlements" "$APP"
  echo "signed with stable local identity"
else
  codesign --force --sign - --entitlements "$ROOT/LaserPointer.entitlements" "$APP"
  echo "ad-hoc signed (no local certificate found — fine for this app, it needs no permissions)"
fi

open "$APP"
echo "launched — look for the cursor icon in the menu bar"
