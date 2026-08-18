#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly PROJECT_FILE="$SCRIPT_DIR/TixisBirdview.xcodeproj/project.pbxproj"
readonly CHANGELOG="$SCRIPT_DIR/CHANGELOG.md"

unique_setting() {
    local name="$1"
    /usr/bin/awk -F ' = ' -v key="$name" \
        '$1 ~ "^[[:space:]]*" key "$" { value=$2; sub(/;$/, "", value); print value }' \
        "$PROJECT_FILE" | /usr/bin/sort -u
}

VERSION="$(unique_setting MARKETING_VERSION)"
BUILD="$(unique_setting CURRENT_PROJECT_VERSION)"

if [[ "$VERSION" == *$'\n'* || ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "MARKETING_VERSION must be one consistent semantic version (MAJOR.MINOR.PATCH)." >&2
    exit 1
fi

if [[ "$BUILD" == *$'\n'* || ! "$BUILD" =~ ^[1-9][0-9]*$ ]]; then
    echo "CURRENT_PROJECT_VERSION must be one consistent positive integer." >&2
    exit 1
fi

if ! /usr/bin/grep -Fq "## [$VERSION]" "$CHANGELOG"; then
    echo "CHANGELOG.md has no section for version $VERSION." >&2
    exit 1
fi

echo "Version $VERSION (build $BUILD) is consistent."
