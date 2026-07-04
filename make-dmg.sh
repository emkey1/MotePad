#!/bin/bash
# Build a drag-to-Applications .dmg around a Developer ID-signed MotePad.app and
# (if a notary profile is configured) notarize + staple it. A .dmg only needs the
# Developer ID Application certificate — no Developer ID Installer cert required.
#
# Configuration (optional; auto-detected from the keychain when unset):
#   MOTEPAD_APP_IDENTITY   "Developer ID Application: NAME (TEAMID)"
#   MOTEPAD_NOTARY_PROFILE  notarytool keychain-profile name
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.2"
APP="MotePad.app"
VOL="MotePad ${VERSION}"
OUT="dist/MotePad-${VERSION}.dmg"

APP_IDENTITY="${MOTEPAD_APP_IDENTITY:-}"
NOTARY_PROFILE="${MOTEPAD_NOTARY_PROFILE:-}"

if [ -z "$APP_IDENTITY" ]; then
  APP_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi

# 1. Build the app bundle.
./build.sh

# 2. Sign with Developer ID + hardened runtime + secure timestamp (required to
#    notarize). --force replaces the ad-hoc signature from build.sh.
if [ -n "$APP_IDENTITY" ]; then
  echo "Signing app: $APP_IDENTITY"
  codesign --force --options runtime --timestamp --sign "$APP_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  echo "No Developer ID Application cert found -> keeping ad-hoc signature."
fi

# 3. Stage the app plus an /Applications shortcut for drag-installing.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"

# 4. Build the compressed disk image, then Developer ID-sign the image itself so
#    Gatekeeper accepts it by signature as well as by the stapled ticket.
mkdir -p dist
rm -f "$OUT"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
if [ -n "$APP_IDENTITY" ]; then
  codesign --force --timestamp --sign "$APP_IDENTITY" "$OUT"
fi

# 5. Notarize + staple the ticket onto the .dmg.
if [ -n "$NOTARY_PROFILE" ] && [ -n "$APP_IDENTITY" ]; then
  echo "Submitting to Apple notary service (profile: $NOTARY_PROFILE)..."
  xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUT"
  xcrun stapler validate "$OUT"
  echo "Notarized + stapled."
else
  echo "Skipping notarization (set MOTEPAD_NOTARY_PROFILE + a Developer ID cert)."
fi

echo "Built $OUT"
