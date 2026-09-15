#!/bin/bash
# Instala NaN Usage (macOS) clonando y compilando desde GitHub.
set -euo pipefail

REPO="ConJdeRumba/macos-nan-usage"
BRANCH="${NAN_USAGE_BRANCH:-main}"
APP_NAME="NaN Usage"
DEST_DIR="${1:-/Applications}"

if ! command -v swift >/dev/null 2>&1; then
  echo "Falta Swift. Instala las herramientas de línea de comandos con:" >&2
  echo "    xcode-select --install" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Clonando $REPO"
git clone --depth 1 --branch "$BRANCH" "https://github.com/$REPO.git" "$TMP/src"

echo "==> Compilando"
cd "$TMP/src"
./build.sh

echo "==> Instalando en $DEST_DIR"
mkdir -p "$DEST_DIR"
rm -rf "$DEST_DIR/$APP_NAME.app"
cp -R "build/$APP_NAME.app" "$DEST_DIR/$APP_NAME.app"
xattr -dr com.apple.quarantine "$DEST_DIR/$APP_NAME.app" 2>/dev/null || true

echo "==> Abriendo"
open "$DEST_DIR/$APP_NAME.app"

echo
echo "Instalada en: $DEST_DIR/$APP_NAME.app"
echo "Para que arranque sola: Ajustes del Sistema > General > Ítems de inicio de sesión."
