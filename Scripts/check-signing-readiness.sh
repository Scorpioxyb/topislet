#!/usr/bin/env bash
set -euo pipefail

ready=1

echo "Developer directory: $(xcode-select -p 2>/dev/null || echo unavailable)"
if xcodebuild -version >/dev/null 2>&1; then
  xcodebuild -version
else
  echo "Xcode: not ready (finish installation, open Xcode once, and accept the license)"
  ready=0
fi

if xcrun notarytool --version >/dev/null 2>&1; then
  echo "notarytool: available"
else
  echo "notarytool: unavailable"
  ready=0
fi

identity_count="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application:/ {count++} END {print count + 0}')"
echo "Developer ID Application identities: $identity_count"
if [[ "$identity_count" == "0" ]]; then
  ready=0
fi

if [[ "$ready" == "1" ]]; then
  echo "Signing readiness: ready"
else
  echo "Signing readiness: waiting for Xcode/license/certificate"
  exit 2
fi
