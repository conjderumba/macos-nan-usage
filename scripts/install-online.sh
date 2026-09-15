#!/bin/bash
# Installs NaN Usage (macOS) by cloning and building from GitHub.
set -euo pipefail

REPO="conjderumba/macos-nan-usage"
BRANCH="${NAN_USAGE_BRANCH:-main}"
APP_NAME="NaN Usage"
DEST_DIR="${1:-/Applications}"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift is missing. Install the command line tools with:" >&2
  echo "    xcode-select --install" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Cloning $REPO"
git clone --depth 1 --branch "$BRANCH" "https://github.com/$REPO.git" "$TMP/src"

echo "==> Building"
cd "$TMP/src"
./build.sh

echo "==> Installing into $DEST_DIR"
mkdir -p "$DEST_DIR"
rm -rf "$DEST_DIR/$APP_NAME.app"
cp -R "build/$APP_NAME.app" "$DEST_DIR/$APP_NAME.app"

# The app is ad-hoc signed (not notarized), so clear the quarantine flag.
# Review the source before running this script if you prefer to keep Gatekeeper on.
xattr -dr com.apple.quarantine "$DEST_DIR/$APP_NAME.app" 2>/dev/null || true

echo "==> Opening"
open "$DEST_DIR/$APP_NAME.app"

echo
echo "Installed at: $DEST_DIR/$APP_NAME.app"
echo "To launch at login: System Settings > General > Login Items."
