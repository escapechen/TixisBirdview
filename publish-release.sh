#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly REPOSITORY="escapechen/TixisBirdview"
readonly EXPECTED_ORIGIN_PATH="escapechen/TixisBirdview.git"

usage() {
    cat <<'EOF'
Usage: ./publish-release.sh [--yes] [--reuse-artifacts]

Runs all tests and public-safety checks, builds a Developer ID-signed and
Apple-notarized DMG, creates a signed Git tag, and publishes both the DMG and
SHA-256 file as a GitHub Release.

The source version, changelog, README, and release commit must already be
finalized. The script may push the current main commit and release tag to
GitHub, but never commits source changes or uploads signing credentials.

Options:
  --yes              Skip the final interactive publication confirmation.
  --reuse-artifacts  Reuse and verify matching files already under dist/.
EOF
}

ASSUME_YES=false
REUSE_ARTIFACTS=false
while (( $# > 0 )); do
    case "$1" in
        --yes)
            ASSUME_YES=true
            ;;
        --reuse-artifacts)
            REUSE_ARTIFACTS=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

cd "$SCRIPT_DIR"

for command in git gh; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Required command not found: $command" >&2
        exit 1
    fi
done

if [[ -n "$(git status --porcelain)" ]]; then
    echo "The worktree is not clean. Commit or stash every change first." >&2
    exit 1
fi
if [[ "$(git branch --show-current)" != "main" ]]; then
    echo "Public releases must be made from the main branch." >&2
    exit 1
fi

ORIGIN_URL="$(git remote get-url origin)"
case "$ORIGIN_URL" in
    git@github.com:$EXPECTED_ORIGIN_PATH|https://github.com/$EXPECTED_ORIGIN_PATH|ssh://git@github.com/$EXPECTED_ORIGIN_PATH)
        ;;
    *)
        echo "origin is not the expected public TixisBirdview repository." >&2
        exit 1
        ;;
esac

"$SCRIPT_DIR/scripts/check-public-safety.sh"
"$SCRIPT_DIR/scripts/check-versioning.sh"
"$SCRIPT_DIR/scripts/check-release-metadata.sh"

VERSION="$(/usr/bin/awk -F ' = ' \
    '$1 ~ /^[[:space:]]*MARKETING_VERSION$/ { value=$2; sub(/;$/, "", value); print value }' \
    TixisBirdview.xcodeproj/project.pbxproj | /usr/bin/sort -u)"
BUILD="$(/usr/bin/awk -F ' = ' \
    '$1 ~ /^[[:space:]]*CURRENT_PROJECT_VERSION$/ { value=$2; sub(/;$/, "", value); print value }' \
    TixisBirdview.xcodeproj/project.pbxproj | /usr/bin/sort -u)"
readonly VERSION BUILD
readonly TAG="v$VERSION"
readonly ARTIFACT_BASENAME="TixisBirdview-$VERSION-$BUILD"
readonly DMG_PATH="$SCRIPT_DIR/dist/$ARTIFACT_BASENAME.dmg"
readonly CHECKSUM_PATH="$DMG_PATH.sha256"
readonly RELEASE_NOTES="$(mktemp "${TMPDIR:-/tmp}/TixisBirdview-release-notes.XXXXXX")"
readonly VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/TixisBirdview-release-verify.XXXXXX")"

cleanup() {
    /bin/rm -f "$RELEASE_NOTES"
    /bin/rm -rf "$VERIFY_DIR"
}
trap cleanup EXIT

/usr/bin/awk -v version="$VERSION" '
    $0 ~ "^## \\[" version "\\]" { found=1; next }
    found && /^## \[/ { exit }
    found { print }
' CHANGELOG.md > "$RELEASE_NOTES"
if [[ ! -s "$RELEASE_NOTES" ]]; then
    echo "Could not extract release notes for $VERSION from CHANGELOG.md." >&2
    exit 1
fi

if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    echo "GitHub CLI is not authenticated. Run: gh auth login" >&2
    exit 1
fi
gh api rate_limit >/dev/null
git fetch --quiet origin main --tags

if ! git merge-base --is-ancestor origin/main HEAD; then
    echo "origin/main contains work not present in this checkout. Pull it first." >&2
    exit 1
fi

if gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
    echo "GitHub release $TAG already exists." >&2
    exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    if [[ "$(git rev-list -n 1 "$TAG")" != "$(git rev-parse HEAD)" ]]; then
        echo "Existing local tag $TAG does not point to HEAD." >&2
        exit 1
    fi
    git verify-tag "$TAG" >/dev/null
fi

REMOTE_TAG="$(git ls-remote --tags origin "refs/tags/$TAG^{}" | /usr/bin/awk '{ print $1 }')"
if [[ -z "$REMOTE_TAG" ]]; then
    REMOTE_TAG="$(git ls-remote --tags origin "refs/tags/$TAG" | /usr/bin/awk '{ print $1 }')"
fi
if [[ -n "$REMOTE_TAG" && "$REMOTE_TAG" != "$(git rev-parse HEAD)" ]]; then
    echo "Existing remote tag $TAG does not point to HEAD." >&2
    exit 1
fi

if [[ "$ASSUME_YES" == false ]]; then
    echo "Ready to publish $TAG ($ARTIFACT_BASENAME) from $(git rev-parse --short HEAD)."
    echo "This will build/notarize locally, push main and a signed tag, then create a public GitHub Release."
    read -r -p "Continue? [y/N] " answer
    case "$answer" in
        y|Y|yes|YES)
            ;;
        *)
            echo "Release cancelled."
            exit 0
            ;;
    esac
fi

if [[ "$REUSE_ARTIFACTS" == true ]]; then
    if [[ ! -f "$DMG_PATH" || ! -f "$CHECKSUM_PATH" ]]; then
        echo "Matching release artifacts are missing under dist/." >&2
        exit 1
    fi
else
    "$SCRIPT_DIR/build-signed-release.sh"
fi

(cd "$SCRIPT_DIR/dist" && /usr/bin/shasum -a 256 -c "$(basename "$CHECKSUM_PATH")")
/usr/bin/codesign --verify --strict "$DMG_PATH"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
"$DEVELOPER_DIR/usr/bin/stapler" validate "$DMG_PATH"
/usr/sbin/spctl -a -t open --context context:primary-signature "$DMG_PATH"

if [[ "$(git rev-parse origin/main)" != "$(git rev-parse HEAD)" ]]; then
    git push origin HEAD:main
fi

if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    git tag -s "$TAG" -m "TixisBirdview $VERSION (build $BUILD)"
    git verify-tag "$TAG" >/dev/null
fi
if [[ -z "$REMOTE_TAG" ]]; then
    git push origin "$TAG"
fi

gh release create "$TAG" \
    "$DMG_PATH" \
    "$CHECKSUM_PATH" \
    --repo "$REPOSITORY" \
    --verify-tag \
    --title "TixisBirdview $VERSION" \
    --notes-file "$RELEASE_NOTES"

gh release download "$TAG" \
    --repo "$REPOSITORY" \
    --pattern "$ARTIFACT_BASENAME.dmg" \
    --pattern "$ARTIFACT_BASENAME.dmg.sha256" \
    --dir "$VERIFY_DIR"

/usr/bin/cmp "$DMG_PATH" "$VERIFY_DIR/$ARTIFACT_BASENAME.dmg"
/usr/bin/cmp "$CHECKSUM_PATH" "$VERIFY_DIR/$ARTIFACT_BASENAME.dmg.sha256"
(cd "$VERIFY_DIR" && /usr/bin/shasum -a 256 -c "$ARTIFACT_BASENAME.dmg.sha256")

RELEASE_URL="$(gh release view "$TAG" --repo "$REPOSITORY" --json url --jq .url)"
echo "Published and verified: $RELEASE_URL"
echo "Gitea is not modified; sync it separately if desired."
