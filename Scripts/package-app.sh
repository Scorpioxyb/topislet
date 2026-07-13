#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="顶屿.app"
APP="$ROOT/.build/package/$APP_NAME"
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$ROOT/Packaging/Info.plist")"

move_to_trash_if_present() {
  local path="$1"
  if [ ! -e "$path" ]; then
    return
  fi
  /usr/bin/swift "$ROOT/Scripts/move-to-trash.swift" "$path"
}

swift build --package-path "$ROOT" -debug-info-format none
move_to_trash_if_present "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Packaging/IslandAppIcon.icns" "$APP/Contents/Resources/IslandAppIcon.icns"
cp "$ROOT/.build/debug/MacBookIsland" "$APP/Contents/MacOS/MacBookIsland"
if [ -d "$ROOT/Vendor/MediaRemoteAdapter" ]; then
  ditto --norsrc --noextattr --noqtn --noacl \
    "$ROOT/Vendor/MediaRemoteAdapter" \
    "$APP/Contents/Resources/MediaRemoteAdapter"
fi
chmod +x "$APP/Contents/MacOS/MacBookIsland"
xattr -cr "$APP"
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -dr 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
codesign --force --deep --sign - \
  --entitlements "$ROOT/Packaging/TopIslet.entitlements" \
  --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$APP" >/dev/null

INSTALL_DIR="/Applications"
if [ ! -w "$INSTALL_DIR" ]; then
  INSTALL_DIR="$HOME/Applications"
  mkdir -p "$INSTALL_DIR"
fi
INSTALLED_APP="$INSTALL_DIR/$APP_NAME"
move_to_trash_if_present "$INSTALLED_APP"
ditto --norsrc --noextattr --noqtn --noacl "$APP" "$INSTALLED_APP"
xattr -cr "$INSTALLED_APP"

echo "Packaged: $APP"
echo "Installed: $INSTALLED_APP"
