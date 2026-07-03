#!/bin/bash
# Build MotePad.app and wrap it in a double-click .pkg installer that installs
# into /Applications. Output: dist/MotePad-<version>.pkg
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.0"
IDENTIFIER="com.plummerssoftware.motepad"
APP="MotePad.app"
OUT="dist/MotePad-${VERSION}.pkg"

# 1. Build the app bundle.
./build.sh

# 2. Stage the app so it maps to /Applications/MotePad.app.
#    Use ditto (not cp -R) to copy the bundle cleanly, preserving the code
#    signature and without emitting AppleDouble (._*) files.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$APP"

# 3. Build the component installer package.
mkdir -p dist
pkgbuild \
  --root "$STAGE" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location /Applications \
  "$OUT"

echo "Built $OUT"
