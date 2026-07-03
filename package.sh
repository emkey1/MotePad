#!/bin/bash
# Build MotePad.app and wrap it in a double-click .pkg installer that installs
# into /Applications.  If Developer ID certificates and a notarytool credential
# profile are available, the app and installer are signed for distribution and
# the package is notarized + stapled; otherwise it falls back to ad-hoc signing
# (fine for local use, but Gatekeeper will warn on other machines).
#
# Configuration (all optional; auto-detected from the keychain when unset):
#   MOTEPAD_APP_IDENTITY   "Developer ID Application: NAME (TEAMID)"
#   MOTEPAD_PKG_IDENTITY   "Developer ID Installer: NAME (TEAMID)"
#   MOTEPAD_NOTARY_PROFILE  notarytool keychain-profile name (see setup below)
#
# One-time distribution setup:
#   1. Create the two Developer ID certs (Account Holder/Admin only):
#        Xcode > Settings > Accounts > (team) > Manage Certificates > +
#        > "Developer ID Application"  and  "Developer ID Installer"
#   2. Store notarization credentials in the keychain (enter your own secret):
#        xcrun notarytool store-credentials "MotePad" \
#          --apple-id "<your-apple-id-email>" --team-id "T82K6293RB" \
#          --password "<app-specific-password>"
#      then run:  MOTEPAD_NOTARY_PROFILE=MotePad ./package.sh
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.0"
IDENTIFIER="com.plummerssoftware.motepad"
APP="MotePad.app"
OUT="dist/MotePad-${VERSION}.pkg"

APP_IDENTITY="${MOTEPAD_APP_IDENTITY:-}"
PKG_IDENTITY="${MOTEPAD_PKG_IDENTITY:-}"
NOTARY_PROFILE="${MOTEPAD_NOTARY_PROFILE:-}"

# Auto-detect Developer ID identities from the keychain if not given explicitly.
if [ -z "$APP_IDENTITY" ]; then
  APP_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$PKG_IDENTITY" ]; then
  PKG_IDENTITY="$(security find-identity -v 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Installer: [^"]*\)".*/\1/p' | head -1)"
fi

# 1. Build the app bundle (ad-hoc signed inside build.sh).
./build.sh

# 2. Re-sign the app with Developer ID + hardened runtime + secure timestamp.
if [ -n "$APP_IDENTITY" ]; then
  echo "Signing app: $APP_IDENTITY"
  codesign --force --options runtime --timestamp --sign "$APP_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  echo "No Developer ID Application cert found -> keeping ad-hoc signature."
fi

# 3. Stage (ditto = clean bundle copy, preserves signature) and build the pkg.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$APP"
mkdir -p dist
if [ -n "$PKG_IDENTITY" ]; then
  echo "Signing installer: $PKG_IDENTITY"
  pkgbuild --root "$STAGE" --identifier "$IDENTIFIER" --version "$VERSION" \
           --install-location /Applications --sign "$PKG_IDENTITY" "$OUT"
else
  echo "No Developer ID Installer cert found -> unsigned pkg."
  pkgbuild --root "$STAGE" --identifier "$IDENTIFIER" --version "$VERSION" \
           --install-location /Applications "$OUT"
fi

# 4. Notarize + staple (needs a signed installer and a notary profile).
if [ -n "$NOTARY_PROFILE" ] && [ -n "$PKG_IDENTITY" ]; then
  echo "Submitting to Apple notary service (profile: $NOTARY_PROFILE)..."
  xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUT"
  xcrun stapler validate "$OUT"
  echo "Notarized + stapled."
else
  echo "Skipping notarization (set MOTEPAD_NOTARY_PROFILE + a Developer ID Installer cert)."
fi

echo "Built $OUT"
