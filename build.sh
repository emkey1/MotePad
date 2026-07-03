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

# Ad-hoc code signature so the app can be launched/activated normally.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
