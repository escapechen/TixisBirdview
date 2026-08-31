#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Release-tooling Git test skipped (source archive has no Git metadata)."
    exit 0
fi

readonly FIXTURE_NAME=".public-safety-test.$$"
readonly FIXTURE_PATH="$SCRIPT_DIR/$FIXTURE_NAME"
readonly TEMPORARY_INDEX="$(mktemp "${TMPDIR:-/tmp}/TixisBirdview-index.XXXXXX")"
readonly BAD_CHANGELOG="$(mktemp "${TMPDIR:-/tmp}/TixisBirdview-changelog.XXXXXX")"

cleanup() {
    /bin/rm -f "$FIXTURE_PATH" "$TEMPORARY_INDEX" "$BAD_CHANGELOG"
}
trap cleanup EXIT

/bin/cp "$SCRIPT_DIR/.git/index" "$TEMPORARY_INDEX"
/usr/bin/printf '%s%s\n' 'TEAM_' 'ID=ZYXWVUTSRQ' > "$FIXTURE_PATH"
GIT_INDEX_FILE="$TEMPORARY_INDEX" git add "$FIXTURE_NAME"

if GIT_INDEX_FILE="$TEMPORARY_INDEX" "$SCRIPT_DIR/scripts/check-public-safety.sh" --staged >/dev/null 2>&1; then
    echo "Public-safety check accepted a staged Team ID fixture." >&2
    exit 1
fi

"$SCRIPT_DIR/scripts/check-release-metadata.sh" >/dev/null
"$SCRIPT_DIR/publish-release.sh" --help >/dev/null

/usr/bin/sed -E 's/^(## \[[0-9]+\.[0-9]+\.[0-9]+\] — )[0-9]{4}-[0-9]{2}-[0-9]{2}$/\1Unreleased/' \
    "$SCRIPT_DIR/CHANGELOG.md" > "$BAD_CHANGELOG"
if CHANGELOG_FILE="$BAD_CHANGELOG" "$SCRIPT_DIR/scripts/check-release-metadata.sh" >/dev/null 2>&1; then
    echo "Release metadata check accepted an unreleased changelog fixture." >&2
    exit 1
fi

echo "Release-tooling regression test passed."
