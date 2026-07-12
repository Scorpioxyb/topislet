#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="顶屿.app"
APP="$ROOT/.build/package/$APP_NAME"
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$ROOT/Packaging/Info.plist")"

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
  --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$APP" >/dev/null

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
