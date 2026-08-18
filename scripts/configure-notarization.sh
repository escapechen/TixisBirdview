#!/bin/bash
set -euo pipefail

readonly DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
readonly PROFILE_NAME="${NOTARY_PROFILE:-TixisBirdview-notary}"

if [[ ! -x "$DEVELOPER_DIR/usr/bin/notarytool" ]]; then
    echo "notarytool was not found. Install and select the full Xcode app." >&2
    exit 1
fi

IDENTITY_LINE="$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/awk '/"Developer ID Application:/{ print; exit }')"
TEAM_ID="$(printf '%s' "$IDENTITY_LINE" | /usr/bin/sed -nE 's/.*\(([A-Z0-9]{10})\)".*/\1/p')"

if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "No Developer ID Application certificate with a private key was found." >&2
    echo "Create one in the Apple Developer portal or Xcode, then retry." >&2
    exit 1
fi

printf 'Apple Account email (stored by notarytool in Keychain): '
IFS= read -r APPLE_ID
if [[ -z "$APPLE_ID" ]]; then
    echo "Apple Account email cannot be empty." >&2
    exit 1
fi

echo "notarytool will securely prompt for an app-specific password."
"$DEVELOPER_DIR/usr/bin/notarytool" store-credentials "$PROFILE_NAME" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID"

unset APPLE_ID
echo "Saved notarization profile '$PROFILE_NAME' in your macOS Keychain."
