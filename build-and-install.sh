#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOCAL_BUILD_ENV="$SCRIPT_DIR/build.local.env"

if [[ -f "$LOCAL_BUILD_ENV" ]]; then
    # Local build settings are deliberately ignored by Git.
    # shellcheck disable=SC1090
    source "$LOCAL_BUILD_ENV"
fi

readonly PROJECT_PATH="$SCRIPT_DIR/TixisBirdview.xcodeproj"
readonly SCHEME="TixisBirdview"
readonly CONFIGURATION="${CONFIGURATION:-Release}"
readonly DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
readonly TEAM_ID="${TEAM_ID:-}"
readonly BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/TixisBirdview-build.XXXXXX")"
readonly DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
readonly TEST_DERIVED_DATA_PATH="$BUILD_ROOT/TestDerivedData"
readonly BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$SCHEME.app"
readonly INSTALLED_APP="/Applications/$SCHEME.app"
readonly STAGED_APP="/Applications/.$SCHEME.app.stage.$$"
readonly BACKUP_APP="/Applications/.$SCHEME.app.backup.$$"

cleanup() {
    rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

usage() {
    cat <<'EOF'
Usage: ./build-and-install.sh [--test]

Without arguments, runs the local XCTest suite, builds a signed app, and
installs it in /Applications. --test only runs the XCTest suite; it does not
need a Team ID, build an installable app, or use sudo.
EOF
}

TEST_ONLY=false
while (( $# > 0 )); do
    case "$1" in
        --test)
            TEST_ONLY=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
    echo "Xcode was not found at: $DEVELOPER_DIR" >&2
    echo "Install Xcode or set DEVELOPER_DIR to its Contents/Developer directory." >&2
    exit 1
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "Project not found: $PROJECT_PATH" >&2
    exit 1
fi

run_tests() {
    "$SCRIPT_DIR/scripts/check-public-safety.sh"
    "$SCRIPT_DIR/scripts/check-versioning.sh"
    "$SCRIPT_DIR/scripts/test-release-tooling.sh"
    echo "Testing $SCHEME..."
    "$DEVELOPER_DIR/usr/bin/xcodebuild" \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -derivedDataPath "$TEST_DERIVED_DATA_PATH" \
        CODE_SIGNING_ALLOWED=NO \
        test
}

run_tests

if [[ "$TEST_ONLY" == true ]]; then
    echo "Tests passed. No app was built or installed."
    exit 0
fi

detect_project_team_id() {
    "$DEVELOPER_DIR/usr/bin/xcodebuild" \
        -showBuildSettings \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        2>/dev/null | \
        awk -F ' = ' '/^[[:space:]]*DEVELOPMENT_TEAM =/ { print $2; exit }' || true
}

RESOLVED_TEAM_ID="$TEAM_ID"
TEAM_ID_SOURCE="build.local.env or the TEAM_ID environment variable"

if [[ ! "$RESOLVED_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    RESOLVED_TEAM_ID="$(detect_project_team_id)"
    TEAM_ID_SOURCE="the Team selected in Xcode"
fi

if [[ ! "$RESOLVED_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    cat >&2 <<'EOF'
No valid Apple Developer Team ID was configured.
The script checked build.local.env and the Team selected in Xcode.

Free Personal Team: open TixisBirdview.xcodeproj in Xcode, select the
TixisBirdview target > Signing & Capabilities, choose your Personal Team, save,
quit Xcode, then run this script again.

Paid membership: copy build.local.env.example to build.local.env and replace
ABCDEFGHIJ with the Team ID from developer.apple.com/account > Membership details.

Full instructions: docs/BUILD_FROM_SOURCE.md
EOF
    exit 1
fi

echo "Building $SCHEME ($CONFIGURATION)..."
echo "Using the Apple Development team from $TEAM_ID_SOURCE (ID redacted)."
"$DEVELOPER_DIR/usr/bin/xcodebuild" \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$RESOLVED_TEAM_ID" \
    build

if [[ ! -d "$BUILT_APP" ]]; then
    echo "Build succeeded but the app bundle was not found: $BUILT_APP" >&2
    exit 1
fi

if [[ "$CONFIGURATION" == "Release" ]]; then
    BUILT_ARCHITECTURES="$(/usr/bin/lipo -archs "$BUILT_APP/Contents/MacOS/$SCHEME")"
    for REQUIRED_ARCHITECTURE in arm64 x86_64; do
        if [[ " $BUILT_ARCHITECTURES " != *" $REQUIRED_ARCHITECTURE "* ]]; then
            echo "Release build is missing required architecture: $REQUIRED_ARCHITECTURE" >&2
            echo "Built architectures: $BUILT_ARCHITECTURES" >&2
            exit 1
        fi
    done
    echo "Universal Release architectures: $BUILT_ARCHITECTURES"
fi

echo "Installing $INSTALLED_APP (sudo may prompt)..."
sudo /bin/rm -rf "$STAGED_APP" "$BACKUP_APP"
sudo /usr/bin/ditto "$BUILT_APP" "$STAGED_APP"

if [[ -e "$INSTALLED_APP" ]]; then
    sudo /bin/mv "$INSTALLED_APP" "$BACKUP_APP"
fi

if ! sudo /bin/mv "$STAGED_APP" "$INSTALLED_APP"; then
    echo "Install failed; restoring the previous app bundle." >&2
    if [[ -e "$BACKUP_APP" ]]; then
        sudo /bin/mv "$BACKUP_APP" "$INSTALLED_APP"
    fi
    exit 1
fi

sudo /bin/rm -rf "$BACKUP_APP"

echo "Installed: $INSTALLED_APP"
echo "Quit and relaunch TixisBirdview if it is already running."
