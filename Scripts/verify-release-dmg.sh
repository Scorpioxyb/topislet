#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG="${1:?usage: verify-release-dmg.sh PATH_TO_DMG}"
DMG="$(cd "$(dirname "$DMG")" && pwd)/$(basename "$DMG")"
EXPECTED_VERSION="${VERSION:-$(plutil -extract CFBundleShortVersionString raw "$ROOT/Packaging/Info.plist")}"
EXPECTED_BUILD_NUMBER="${BUILD_NUMBER:-$(plutil -extract CFBundleVersion raw "$ROOT/Packaging/Info.plist")}"
CHECKSUM="$DMG.sha256"
VERIFY_ROOT="$ROOT/.build/dmg-verify-$$"
MOUNT_POINT="$VERIFY_ROOT/volume"
APP="$MOUNT_POINT/顶屿.app"
MOUNTED=0

cleanup() {
  if [[ "$MOUNTED" == "1" ]]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

test -f "$DMG"
test -f "$CHECKSUM"
if [[ "$(basename "$DMG")" != "TopIslet-v${EXPECTED_VERSION}-arm64.dmg" ]]; then
  echo "error: DMG filename does not match version $EXPECTED_VERSION: $(basename "$DMG")" >&2
  exit 1
fi
hdiutil verify "$DMG" >/dev/null
(
  cd "$(dirname "$DMG")"
  shasum -a 256 -c "$(basename "$CHECKSUM")"
)

if find "$(dirname "$DMG")" -maxdepth 1 -name 'TopIslet-*.zip*' -print -quit | grep -q .; then
  echo "error: obsolete ZIP artifact found next to the DMG" >&2
  exit 1
fi

mkdir -p "$MOUNT_POINT"
hdiutil attach "$DMG" \
  -readonly \
  -nobrowse \
  -verify \
  -noautoopen \
  -mountpoint "$MOUNT_POINT" >/dev/null
MOUNTED=1

while IFS= read -r -d '' item; do
  case "$(basename "$item")" in
    "顶屿.app"|Applications|.DS_Store|.background) ;;
    *)
      echo "error: unexpected top-level DMG item: $(basename "$item")" >&2
      exit 1
      ;;
  esac
done < <(find "$MOUNT_POINT" -mindepth 1 -maxdepth 1 -print0)

test -d "$APP"
test -L "$MOUNT_POINT/Applications"
test "$(readlink "$MOUNT_POINT/Applications")" = "/Applications"
test -s "$MOUNT_POINT/.DS_Store"
test -s "$MOUNT_POINT/.background/background.png"
test "$(sips -g pixelWidth "$MOUNT_POINT/.background/background.png" | awk '/pixelWidth/ {print $2}')" = "1320"
test "$(sips -g pixelHeight "$MOUNT_POINT/.background/background.png" | awk '/pixelHeight/ {print $2}')" = "800"

PLIST="$APP/Contents/Info.plist"
test "$(plutil -extract CFBundleIdentifier raw "$PLIST")" = "io.github.scorpioxyb.topislet"
test "$(plutil -extract CFBundleDisplayName raw "$PLIST")" = "顶屿"
test "$(plutil -extract CFBundleShortVersionString raw "$PLIST")" = "$EXPECTED_VERSION"
test "$(plutil -extract CFBundleVersion raw "$PLIST")" = "$EXPECTED_BUILD_NUMBER"
test "$(plutil -extract LSMinimumSystemVersion raw "$PLIST")" = "26.0"
EXECUTABLE="$(plutil -extract CFBundleExecutable raw "$PLIST")"
MAIN_BINARY="$APP/Contents/MacOS/$EXECUTABLE"
VENDOR_BINARY="$APP/Contents/Resources/MediaRemoteAdapter/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter"

test -x "$MAIN_BINARY"
codesign --verify --deep --strict --verbose=2 "$APP"
test "$(xcrun lipo -archs "$MAIN_BINARY")" = "arm64"
xcrun vtool -show-build "$MAIN_BINARY" | grep -q 'minos 26.0'
xcrun lipo -archs "$VENDOR_BINARY" | grep -qw arm64
xcrun lipo -archs "$VENDOR_BINARY" | grep -qw x86_64
xcrun vtool -show-build "$VENDOR_BINARY" | grep -q 'minos 26.0'

cmp "$ROOT/LICENSE" "$APP/Contents/Resources/Licenses/PROJECT_LICENSE.txt"
cmp "$ROOT/Vendor/MediaRemoteAdapter/LICENSE" \
  "$APP/Contents/Resources/Licenses/MediaRemoteAdapter-BSD-3-Clause.txt"
cmp "$ROOT/THIRD_PARTY_NOTICES.md" \
  "$APP/Contents/Resources/Licenses/THIRD_PARTY_NOTICES.md"

if [[ "${REQUIRE_NOTARIZATION:-0}" == "1" ]]; then
  codesign --verify --verbose=4 "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -vv -t open --context context:primary-signature "$DMG"
  spctl -a -vv -t exec "$APP"
fi

hdiutil detach "$MOUNT_POINT" >/dev/null
MOUNTED=0
echo "DMG verification passed: $DMG"
