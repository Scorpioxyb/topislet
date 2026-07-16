#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_TAG="${RELEASE_TAG:-${1:-}}"
PACKAGING_PLIST="$ROOT/Packaging/Info.plist"
PACKAGED_VERSION="$(plutil -extract CFBundleShortVersionString raw "$PACKAGING_PLIST")"
VERSION="${VERSION:-$PACKAGED_VERSION}"

require_exact_release_tag() {
  if [[ -z "$RELEASE_TAG" ]]; then
    echo "error: RELEASE_TAG is required" >&2
    exit 2
  fi

  if ! git -C "$ROOT" rev-parse --verify --quiet "refs/tags/$RELEASE_TAG^{commit}" >/dev/null; then
    echo "error: release tag does not exist locally: $RELEASE_TAG" >&2
    exit 2
  fi

  local head_commit
  local tag_commit
  head_commit="$(git -C "$ROOT" rev-parse HEAD)"
  tag_commit="$(git -C "$ROOT" rev-parse "refs/tags/$RELEASE_TAG^{commit}")"
  if [[ "$head_commit" != "$tag_commit" ]]; then
    echo "error: HEAD is not the commit referenced by $RELEASE_TAG" >&2
    echo "HEAD: $head_commit" >&2
    echo "tag:  $tag_commit" >&2
    exit 2
  fi

  if [[ "$RELEASE_TAG" != "v$VERSION" && "$RELEASE_TAG" != "v$VERSION-"* ]]; then
    echo "error: release tag $RELEASE_TAG does not match version $VERSION" >&2
    exit 2
  fi

  if [[ "$VERSION" != "$PACKAGED_VERSION" ]]; then
    echo "error: requested version $VERSION does not match Packaging/Info.plist $PACKAGED_VERSION" >&2
    exit 2
  fi
}

require_clean_worktree() {
  local changes
  changes="$(git -C "$ROOT" status --porcelain --untracked-files=all)"
  if [[ -n "$changes" ]]; then
    echo "error: release source worktree is not clean" >&2
    printf '%s\n' "$changes" >&2
    exit 2
  fi
}

run_release_regression_tests() {
  swift test --package-path "$ROOT"
}

require_exact_release_tag
require_clean_worktree
run_release_regression_tests

echo "Release source verification passed: $RELEASE_TAG"
