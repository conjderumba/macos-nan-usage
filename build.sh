#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="NaN Usage"
BUNDLE="build/${APP_NAME}.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> Packaging ${BUNDLE}"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_DIR/NanMenubar" "$BUNDLE/Contents/MacOS/NanMenubar"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/menubar-icon.png "$BUNDLE/Contents/Resources/menubar-icon.png"
cp Resources/NaN.icns "$BUNDLE/Contents/Resources/NaN.icns" 2>/dev/null || true

echo "==> Ad-hoc signing"
if codesign --force --sign - --timestamp=none "$BUNDLE" >/dev/null 2>&1; then
	echo "==> Ad-hoc signed"
else
	echo "==> Warning: ad-hoc signing failed; the app will still run" >&2
fi

echo "==> Done: $BUNDLE"
echo "    open \"$BUNDLE\""
