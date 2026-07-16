#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="顶屿.app"
PACKAGE_APP="$ROOT/.build/package/$APP_NAME"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/topislet-package.XXXXXX")"
APP="$WORK_DIR/$APP_NAME"
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$ROOT/Packaging/Info.plist")"

move_to_trash_if_present() {
  local path="$1"
  if [ ! -e "$path" ]; then
    return
  fi
  /usr/bin/swift "$ROOT/Scripts/move-to-trash.swift" "$path"
}

clean_bundle_extended_attributes() {
  local path="$1"
  xattr -cr "$path"
  xattr -dr com.apple.FinderInfo "$path" 2>/dev/null || true
  xattr -dr 'com.apple.fileprovider.fpfs#P' "$path" 2>/dev/null || true
}

cleanup() {
  if [ -d "$WORK_DIR" ]; then
    /usr/bin/swift "$ROOT/Scripts/move-to-trash.swift" "$WORK_DIR" || true
  fi
}
trap cleanup EXIT

swift build --package-path "$ROOT" -debug-info-format none
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
clean_bundle_extended_attributes "$APP"
codesign --force --deep --sign - \
  --entitlements "$ROOT/Packaging/TopIslet.entitlements" \
  --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$APP" >/dev/null

move_to_trash_if_present "$PACKAGE_APP"
mkdir -p "$(dirname "$PACKAGE_APP")"
ditto --norsrc --noextattr --noqtn --noacl "$APP" "$PACKAGE_APP"
clean_bundle_extended_attributes "$PACKAGE_APP"
codesign --verify --deep --verbose=2 "$PACKAGE_APP" >/dev/null

INSTALL_DIR="/Applications"
if [ ! -w "$INSTALL_DIR" ]; then
  INSTALL_DIR="$HOME/Applications"
  mkdir -p "$INSTALL_DIR"
fi
INSTALLED_APP="$INSTALL_DIR/$APP_NAME"
move_to_trash_if_present "$INSTALLED_APP"
ditto --norsrc --noextattr --noqtn --noacl "$APP" "$INSTALLED_APP"
clean_bundle_extended_attributes "$INSTALLED_APP"
codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP" >/dev/null

echo "Packaged: $PACKAGE_APP"
echo "Installed: $INSTALLED_APP"
