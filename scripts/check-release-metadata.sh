#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly PROJECT_FILE="${PROJECT_FILE:-$SCRIPT_DIR/TixisBirdview.xcodeproj/project.pbxproj}"
readonly CHANGELOG_FILE="${CHANGELOG_FILE:-$SCRIPT_DIR/CHANGELOG.md}"
readonly README_FILE="${README_FILE:-$SCRIPT_DIR/README.md}"

unique_setting() {
    local name="$1"
    /usr/bin/awk -F ' = ' -v key="$name" \
        '$1 ~ "^[[:space:]]*" key "$" { value=$2; sub(/;$/, "", value); print value }' \
        "$PROJECT_FILE" | /usr/bin/sort -u
}

VERSION="$(unique_setting MARKETING_VERSION)"
BUILD="$(unique_setting CURRENT_PROJECT_VERSION)"

if [[ "$VERSION" == *$'\n'* || ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "The Xcode project has no single semantic release version." >&2
    exit 1
fi
if [[ "$BUILD" == *$'\n'* || ! "$BUILD" =~ ^[1-9][0-9]*$ ]]; then
    echo "The Xcode project has no single positive release build number." >&2
    exit 1
fi

if ! /usr/bin/grep -Eq "^## \[$VERSION\] — [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$CHANGELOG_FILE"; then
    echo "CHANGELOG.md must finalize version $VERSION with an ISO release date." >&2
    exit 1
fi
if /usr/bin/grep -Fq "## [$VERSION] — Unreleased" "$CHANGELOG_FILE"; then
    echo "CHANGELOG.md still marks version $VERSION as unreleased." >&2
    exit 1
fi
if ! /usr/bin/grep -Fq "[$VERSION]: https://github.com/escapechen/TixisBirdview/releases/tag/v$VERSION" "$CHANGELOG_FILE"; then
    echo "CHANGELOG.md must link version $VERSION to its GitHub release tag." >&2
    exit 1
fi

if ! /usr/bin/grep -Fq "The current release is **$VERSION (build $BUILD)**" "$README_FILE"; then
    echo "README.md does not name $VERSION (build $BUILD) as the current release." >&2
    exit 1
fi
if ! /usr/bin/grep -Fq "TixisBirdview-$VERSION-$BUILD.dmg" "$README_FILE" || \
   ! /usr/bin/grep -Fq "TixisBirdview-$VERSION-$BUILD.dmg.sha256" "$README_FILE"; then
    echo "README.md does not name the expected release artifacts." >&2
    exit 1
fi

echo "Release metadata $VERSION (build $BUILD) is finalized."
