#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTROLLER="$ROOT/Sources/MacBookIsland/QishuiSemanticAXController.swift"

violations="$(
  rg -n 'kAXMinimizedAttribute' "$CONTROLLER" \
    | rg -v 'boolAttribute\(' \
    || true
)"

if [[ -n "$violations" ]]; then
  echo "error: Qishui controls must not write or otherwise mutate AXMinimized" >&2
  echo "$violations" >&2
  exit 1
fi

if rg -n 'temporarilyUnminimize|restoreMinimizedWindow' "$CONTROLLER"; then
  echo "error: legacy Qishui window restoration path must not return" >&2
  exit 1
fi

echo "Qishui control safety verification passed"
