#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_URL="https://github.com/ungive/mediaremote-adapter.git"
UPSTREAM_COMMIT="3ac3d4bdf862c7b5399b4fba4df5689f5c38609a"
EXPECTED_BINARY_SHA256="3446ebb0889757c8d4cee0ac7a577bbbd530e3ba61225d30b47e3b85d31f95ab"
PATCH="$ROOT/Vendor/MediaRemoteAdapter/patches/topislet-client-targeting.patch"
VENDORED_FRAMEWORK="$ROOT/Vendor/MediaRemoteAdapter/MediaRemoteAdapter.framework"
BUILD_ROOT="$ROOT/.build"
mkdir -p "$BUILD_ROOT"
WORK_DIR="${WORK_DIR:-$(mktemp -d "$BUILD_ROOT/mediaremote-adapter-rebuild.XXXXXX")}"
SOURCE_DIR="$WORK_DIR/source"
OUTPUT_FRAMEWORK="$WORK_DIR/MediaRemoteAdapter.framework"
TOOLCHAIN_DEVELOPER_DIR="${TOOLCHAIN_DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
export DEVELOPER_DIR="$TOOLCHAIN_DEVELOPER_DIR"

mkdir -p "$WORK_DIR/arch"
git clone --quiet --no-checkout "$UPSTREAM_URL" "$SOURCE_DIR"
git -C "$SOURCE_DIR" fetch --quiet --depth 1 origin "$UPSTREAM_COMMIT"
git -C "$SOURCE_DIR" checkout --quiet --detach FETCH_HEAD
test "$(git -C "$SOURCE_DIR" rev-parse HEAD)" = "$UPSTREAM_COMMIT"
git -C "$SOURCE_DIR" apply "$PATCH"

sources=(
  src/adapter/env.m
  src/adapter/client.m
  src/adapter/get.m
  src/adapter/get_client.m
  src/adapter/globals.m
  src/adapter/keys.m
  src/adapter/now_playing.m
  src/adapter/repeat.m
  src/adapter/seek.m
  src/adapter/send.m
  src/adapter/shuffle.m
  src/adapter/speed.m
  src/adapter/stream.m
  src/adapter/stream_client.m
  src/adapter/test.m
  src/private/MediaRemote.m
  src/utility/Debounce.m
  src/utility/helpers.m
)

for arch in arm64 x86_64; do
  (
    cd "$SOURCE_DIR"
    xcrun clang \
      -dynamiclib \
      -arch "$arch" \
      -O2 \
      -fobjc-arc \
      -fvisibility=default \
      -install_name '@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter' \
      -Iinclude \
      -Isrc \
      -framework Foundation \
      -framework AppKit \
      -framework UniformTypeIdentifiers \
      "${sources[@]}" \
      -o "$WORK_DIR/arch/MediaRemoteAdapter-$arch"
  )
done

ditto "$VENDORED_FRAMEWORK" "$OUTPUT_FRAMEWORK"
xcrun lipo -create \
  "$WORK_DIR/arch/MediaRemoteAdapter-arm64" \
  "$WORK_DIR/arch/MediaRemoteAdapter-x86_64" \
  -output "$OUTPUT_FRAMEWORK/Versions/A/MediaRemoteAdapter"
codesign --force --deep --sign - "$OUTPUT_FRAMEWORK" >/dev/null
codesign --verify --deep --strict --verbose=2 "$OUTPUT_FRAMEWORK"

BINARY="$OUTPUT_FRAMEWORK/Versions/A/MediaRemoteAdapter"
ACTUAL_BINARY_SHA256="$(shasum -a 256 "$BINARY" | awk '{print $1}')"
if [[ "$ACTUAL_BINARY_SHA256" != "$EXPECTED_BINARY_SHA256" ]]; then
  echo "error: rebuilt binary hash does not match the vendored release binary" >&2
  echo "expected: $EXPECTED_BINARY_SHA256" >&2
  echo "actual:   $ACTUAL_BINARY_SHA256" >&2
  echo "toolchain: $(xcrun clang --version | head -n 1)" >&2
  exit 1
fi

cmp "$BINARY" "$VENDORED_FRAMEWORK/Versions/A/MediaRemoteAdapter"
cmp "$SOURCE_DIR/bin/mediaremote-adapter.pl" \
  "$ROOT/Vendor/MediaRemoteAdapter/mediaremote-adapter.pl"
cmp "$SOURCE_DIR/LICENSE" "$ROOT/Vendor/MediaRemoteAdapter/LICENSE"

echo "Upstream: $UPSTREAM_URL@$UPSTREAM_COMMIT"
echo "Framework: $OUTPUT_FRAMEWORK"
echo "SHA-256: $ACTUAL_BINARY_SHA256"
echo "Reproducible byte-for-byte match: true"
