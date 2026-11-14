#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTROLLER="$ROOT/Sources/MacBookIsland/QishuiSemanticAXController.swift"

violations="$(
  grep -n 'kAXMinimizedAttribute' "$CONTROLLER" \
    | grep -vF 'boolAttribute(' \
    || true
)"

if [[ -n "$violations" ]]; then
  echo "error: Qishui controls must not write or otherwise mutate AXMinimized" >&2
  echo "$violations" >&2
  exit 1
fi

if grep -nE 'temporarilyUnminimize|restoreMinimizedWindow' "$CONTROLLER"; then
  echo "error: legacy Qishui window restoration path must not return" >&2
  exit 1
fi

# The guarded Qishui seek is the only control that follows the system media
# focus instead of a verified source (owner-approved exception, see the
# "安全硬门禁" section of Docs/qa/QA_CHECKLIST.md). Its preconditions must stay.
MEDIA_ADAPTER="$ROOT/Sources/MacBookIsland/MediaAdapter.swift"
if ! grep -qF 'static let supportsTargetedSeek = false' "$MEDIA_ADAPTER"; then
  echo "error: QishuiSeekSafety.supportsTargetedSeek must stay false" >&2
  exit 1
fi
for condition in '&& hasVerifiedQishuiSource' '&& hasCurrentTrack' '&& hasDuration' \
                 '&& !isCached' '&& !hasCompetingPlayback'; do
  if ! grep -qF -- "$condition" "$MEDIA_ADAPTER"; then
    echo "error: guarded Qishui seek lost its precondition: $condition" >&2
    exit 1
  fi
done

echo "Qishui control safety verification passed"
