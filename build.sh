#!/bin/bash
# Build MotePad.app from the aarch64 assembly source.
set -euo pipefail
cd "$(dirname "$0")"

APP="MotePad.app"
SRC="motepad.s"
BIN="MotePad"

echo "Assembling + linking $SRC ..."
clang -arch arm64 -x assembler "$SRC" -o "$BIN" -framework Cocoa

echo "Assembling app bundle $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
mv "$BIN" "$APP/Contents/MacOS/MotePad"

# App icon: build MotePad.icns from the retro PNG (regenerate the PNG if the
# generator is present but the PNG is missing).
if [ ! -f assets/motepad-icon.png ] && [ -f assets/make-icon.py ]; then
  python3 assets/make-icon.py
fi
if [ -f assets/motepad-icon.png ]; then
  ICONSET="$(mktemp -d)/MotePad.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" assets/motepad-icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z "$d" "$d" assets/motepad-icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/MotePad.icns"
  rm -rf "$(dirname "$ICONSET")"
fi

# Ad-hoc code signature so the app can be launched/activated normally.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
