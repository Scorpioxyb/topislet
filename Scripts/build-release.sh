#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DISPLAY_NAME="顶屿"
EXECUTABLE_NAME="MacBookIsland"
VERSION="${VERSION:-$(plutil -extract CFBundleShortVersionString raw "$ROOT/Packaging/Info.plist")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(plutil -extract CFBundleVersion raw "$ROOT/Packaging/Info.plist")}"
BUNDLE_ID="${BUNDLE_ID:-$(plutil -extract CFBundleIdentifier raw "$ROOT/Packaging/Info.plist")}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/.build/release-artifacts}"
WORK_DIR="${WORK_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/topislet-release.XXXXXX")}"
APP="$WORK_DIR/$APP_DISPLAY_NAME.app"
ARCHIVE_BASENAME="TopIslet-v$VERSION-arm64"
DISK_IMAGE="$OUTPUT_DIR/$ARCHIVE_BASENAME.dmg"
CHECKSUM="$DISK_IMAGE.sha256"
MOUNT_POINT=""

cleanup() {
  if [[ -n "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ "$BUNDLE_ID" == local.* && "${ALLOW_PROTOTYPE_BUNDLE_ID:-0}" != "1" ]]; then
  echo "error: release Bundle ID must not use the local.* prototype namespace" >&2
  echo "set BUNDLE_ID=io.github.scorpioxyb.topislet" >&2
  exit 2
fi

if [[ ! -f "$ROOT/LICENSE" && "${ALLOW_MISSING_LICENSE:-0}" != "1" ]]; then
  echo "error: top-level LICENSE is required before building a public release" >&2
  exit 2
fi

mkdir -p "$OUTPUT_DIR" "$APP/Contents/MacOS" "$APP/Contents/Resources/Licenses"

swift build --package-path "$ROOT" -c release --arch arm64
MAIN_BINARY="$ROOT/.build/arm64-apple-macosx/release/$EXECUTABLE_NAME"
if [[ ! -x "$MAIN_BINARY" ]]; then
  echo "error: release binary not found at $MAIN_BINARY" >&2
  exit 1
fi

cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"

cp "$MAIN_BINARY" "$APP/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ROOT/Packaging/IslandAppIcon.icns" "$APP/Contents/Resources/IslandAppIcon.icns"
COPYFILE_DISABLE=1 ditto --norsrc \
  "$ROOT/Vendor/MediaRemoteAdapter" \
  "$APP/Contents/Resources/MediaRemoteAdapter"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/Licenses/THIRD_PARTY_NOTICES.md"
cp "$ROOT/Vendor/MediaRemoteAdapter/LICENSE" \
  "$APP/Contents/Resources/Licenses/MediaRemoteAdapter-BSD-3-Clause.txt"
if [[ -f "$ROOT/LICENSE" ]]; then
  cp "$ROOT/LICENSE" "$APP/Contents/Resources/Licenses/PROJECT_LICENSE.txt"
fi

chmod +x "$APP/Contents/MacOS/$EXECUTABLE_NAME"
xattr -cr "$APP"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP"
else
  codesign --force --deep --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
fi

codesign --verify --deep --strict --verbose=2 "$APP"
plutil -lint "$APP/Contents/Info.plist"
file "$APP/Contents/MacOS/$EXECUTABLE_NAME" | grep -q 'arm64'
vtool -show-build "$APP/Contents/MacOS/$EXECUTABLE_NAME" | grep -q 'minos 26.0'
vtool -show-build \
  "$APP/Contents/Resources/MediaRemoteAdapter/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter" \
  | grep -q 'minos 26.0'

DMG_SOURCE="$WORK_DIR/dmg-source"
mkdir -p "$DMG_SOURCE"
COPYFILE_DISABLE=1 ditto --norsrc "$APP" "$DMG_SOURCE/$APP_DISPLAY_NAME.app"
ln -s /Applications "$DMG_SOURCE/Applications"
hdiutil create \
  -volname "$APP_DISPLAY_NAME" \
  -srcfolder "$DMG_SOURCE" \
  -ov \
  -format UDZO \
  "$DISK_IMAGE"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DISK_IMAGE"
  codesign --verify --verbose=2 "$DISK_IMAGE"
fi
hdiutil verify "$DISK_IMAGE" >/dev/null

(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$(basename "$DISK_IMAGE")" > "$(basename "$CHECKSUM")"
)

MOUNT_POINT="$(hdiutil attach "$DISK_IMAGE" -readonly -nobrowse -noautoopen | awk -F '\t' 'END {print $NF}')"
if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
  echo "error: failed to mount disk image" >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$MOUNT_POINT/$APP_DISPLAY_NAME.app"
test -L "$MOUNT_POINT/Applications"
test "$(readlink "$MOUNT_POINT/Applications")" = "/Applications"
hdiutil detach "$MOUNT_POINT" >/dev/null
MOUNT_POINT=""
(
  cd "$OUTPUT_DIR"
  shasum -a 256 -c "$(basename "$CHECKSUM")"
)

echo "App: $APP"
echo "Disk image: $DISK_IMAGE"
echo "SHA-256: $CHECKSUM"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "warning: app is ad-hoc signed and the disk image is not notarized; publish only as a developer preview" >&2
fi
