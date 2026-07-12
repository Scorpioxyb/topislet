#!/usr/bin/env bash
set -euo pipefail

DMG="${1:?usage: notarize-release.sh PATH_TO_SIGNED_DMG}"
DMG="$(cd "$(dirname "$DMG")" && pwd)/$(basename "$DMG")"
NOTARY_PROFILE="${NOTARY_PROFILE:-TopIslet-Notary}"
CHECKSUM="$DMG.sha256"

codesign --verify --verbose=4 "$DMG"
xcrun notarytool submit "$DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -vv -t open --context context:primary-signature "$DMG"

(
  cd "$(dirname "$DMG")"
  shasum -a 256 "$(basename "$DMG")" > "$(basename "$CHECKSUM")"
  shasum -a 256 -c "$(basename "$CHECKSUM")"
)

echo "Notarized and stapled: $DMG"
echo "SHA-256: $CHECKSUM"
