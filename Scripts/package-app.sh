#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MacBook 灵动岛.app"
APP="$ROOT/$APP_NAME"
LEGACY_APP="$ROOT/MacBookIsland.app"

swift build --package-path "$ROOT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Packaging/IslandAppIcon.icns" "$APP/Contents/Resources/IslandAppIcon.icns"
cp "$ROOT/.build/debug/MacBookIsland" "$APP/Contents/MacOS/MacBookIsland"
if [ -d "$ROOT/Vendor/MediaRemoteAdapter" ]; then
  ditto "$ROOT/Vendor/MediaRemoteAdapter" "$APP/Contents/Resources/MediaRemoteAdapter"
fi
chmod +x "$APP/Contents/MacOS/MacBookIsland"
xattr -cr "$APP"
codesign --force --deep --sign - \
  --identifier "local.macbook-island.prototype" \
  --requirements '=designated => identifier "local.macbook-island.prototype"' \
  "$APP" >/dev/null

ditto "$APP" "$LEGACY_APP"

INSTALL_DIR="/Applications"
if [ ! -w "$INSTALL_DIR" ]; then
  INSTALL_DIR="$HOME/Applications"
  mkdir -p "$INSTALL_DIR"
fi
INSTALLED_APP="$INSTALL_DIR/$APP_NAME"
ditto "$APP" "$INSTALLED_APP"
xattr -cr "$INSTALLED_APP"

echo "Packaged: $APP"
echo "Installed: $INSTALLED_APP"
