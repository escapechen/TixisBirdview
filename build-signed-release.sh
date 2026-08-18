#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOCAL_RELEASE_ENV="$SCRIPT_DIR/release.local.env"

if [[ -f "$LOCAL_RELEASE_ENV" ]]; then
    # Local certificate selection is deliberately ignored by Git.
    # shellcheck disable=SC1090
    source "$LOCAL_RELEASE_ENV"
fi

readonly PROJECT_PATH="$SCRIPT_DIR/TixisBirdview.xcodeproj"
readonly SCHEME="TixisBirdview"
readonly DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
readonly NOTARY_PROFILE="${NOTARY_PROFILE:-TixisBirdview-notary}"
readonly DIST_DIR="${DIST_DIR:-$SCRIPT_DIR/dist}"
readonly BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/TixisBirdview-release.XXXXXX")"
readonly ARCHIVE_PATH="$BUILD_ROOT/$SCHEME.xcarchive"
readonly APP_PATH="$ARCHIVE_PATH/Products/Applications/$SCHEME.app"

if (( $# > 0 )); then
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: ./build-signed-release.sh"
        echo "Builds, Developer ID-signs, notarizes, and verifies a release DMG."
        exit 0
    fi
    echo "Unknown option: $1" >&2
    exit 2
fi

cleanup() {
    /bin/rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" || ! -x "$DEVELOPER_DIR/usr/bin/notarytool" ]]; then
    echo "The full Xcode toolchain was not found at: $DEVELOPER_DIR" >&2
    exit 1
fi

IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/awk '/"Developer ID Application:/{ print $2 }')"
IDENTITY_HASH="${DEVELOPER_ID_SHA1:-}"

if [[ -z "$IDENTITY_HASH" ]]; then
    IDENTITY_COUNT="$(printf '%s\n' "$IDENTITIES" | /usr/bin/awk 'NF { count++ } END { print count+0 }')"
    if [[ "$IDENTITY_COUNT" -eq 0 ]]; then
        echo "No Developer ID Application certificate with its private key was found." >&2
        echo "An Apple Development identity cannot sign a public release." >&2
        echo "See docs/RELEASING.md for certificate setup." >&2
        exit 1
    fi
    if [[ "$IDENTITY_COUNT" -gt 1 ]]; then
        echo "Multiple Developer ID Application identities were found." >&2
        echo "Set DEVELOPER_ID_SHA1 in ignored release.local.env to select one." >&2
        exit 1
    fi
    IDENTITY_HASH="$IDENTITIES"
fi

if [[ ! "$IDENTITY_HASH" =~ ^[A-Fa-f0-9]{40}$ ]] || ! printf '%s\n' "$IDENTITIES" | /usr/bin/grep -Fqx "$IDENTITY_HASH"; then
    echo "DEVELOPER_ID_SHA1 does not select an available Developer ID Application identity." >&2
    exit 1
fi

IDENTITY_LINE="$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/awk -v identity="$IDENTITY_HASH" '$2 == identity { print; exit }')"
TEAM_ID="$(printf '%s' "$IDENTITY_LINE" | /usr/bin/sed -nE 's/.*\(([A-Z0-9]{10})\)".*/\1/p')"
if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "Could not derive the signing team from the selected Developer ID certificate." >&2
    exit 1
fi

"$SCRIPT_DIR/scripts/check-public-safety.sh"
"$SCRIPT_DIR/scripts/check-versioning.sh"
"$SCRIPT_DIR/build-and-install.sh" --test

echo "Archiving a Developer ID-signed universal Release..."
"$DEVELOPER_DIR/usr/bin/xcodebuild" -quiet \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY_HASH" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    clean archive

if [[ ! -d "$APP_PATH" ]]; then
    echo "Archive succeeded but the app was not found." >&2
    exit 1
fi

/usr/bin/codesign --verify --deep --strict "$APP_PATH"
SIGNATURE_DETAILS="$(/usr/bin/codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
if ! printf '%s\n' "$SIGNATURE_DETAILS" | /usr/bin/grep -q 'flags=.*runtime'; then
    echo "The archived app does not have Hardened Runtime enabled." >&2
    exit 1
fi
if ! printf '%s\n' "$SIGNATURE_DETAILS" | /usr/bin/grep -q '^Timestamp='; then
    echo "The archived app does not have a secure signing timestamp." >&2
    exit 1
fi

ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_PATH/Contents/MacOS/$SCHEME")"
for REQUIRED_ARCHITECTURE in arm64 x86_64; do
    if [[ " $ARCHITECTURES " != *" $REQUIRED_ARCHITECTURE "* ]]; then
        echo "Release is missing required architecture: $REQUIRED_ARCHITECTURE" >&2
        exit 1
    fi
done

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
readonly ARTIFACT_BASENAME="$SCHEME-$VERSION-$BUILD"
readonly SUBMISSION_ZIP="$BUILD_ROOT/$ARTIFACT_BASENAME-notary.zip"
readonly DMG_ROOT="$BUILD_ROOT/dmg"
readonly DMG_PATH="$DIST_DIR/$ARTIFACT_BASENAME.dmg"

if [[ -e "$DMG_PATH" || -e "$DMG_PATH.sha256" ]]; then
    echo "Refusing to overwrite an existing release artifact: $DMG_PATH" >&2
    echo "Increment the build number before producing another distributed build." >&2
    exit 1
fi

echo "Submitting the signed app to Apple notarization..."
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$SUBMISSION_ZIP"
"$DEVELOPER_DIR/usr/bin/notarytool" submit "$SUBMISSION_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
"$DEVELOPER_DIR/usr/bin/stapler" staple "$APP_PATH"
"$DEVELOPER_DIR/usr/bin/stapler" validate "$APP_PATH"
/usr/sbin/spctl -a -t exec "$APP_PATH"

/bin/mkdir -p "$DMG_ROOT" "$DIST_DIR"
/usr/bin/ditto "$APP_PATH" "$DMG_ROOT/$SCHEME.app"
/bin/cp "$SCRIPT_DIR/LICENSE" "$SCRIPT_DIR/THIRD_PARTY_NOTICES.md" "$DMG_ROOT/"
/bin/ln -s /Applications "$DMG_ROOT/Applications"

echo "Creating and notarizing $ARTIFACT_BASENAME.dmg..."
/usr/bin/hdiutil create -quiet -volname "$SCHEME" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH"
/usr/bin/codesign --force --timestamp --sign "$IDENTITY_HASH" "$DMG_PATH"
"$DEVELOPER_DIR/usr/bin/notarytool" submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
"$DEVELOPER_DIR/usr/bin/stapler" staple "$DMG_PATH"
"$DEVELOPER_DIR/usr/bin/stapler" validate "$DMG_PATH"
/usr/sbin/spctl -a -t open --context context:primary-signature "$DMG_PATH"

(cd "$DIST_DIR" && /usr/bin/shasum -a 256 "$ARTIFACT_BASENAME.dmg" > "$ARTIFACT_BASENAME.dmg.sha256")

echo "Release ready: $DMG_PATH"
echo "Checksum: $DMG_PATH.sha256"
