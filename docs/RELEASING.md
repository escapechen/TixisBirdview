# Releasing TixisBirdview

This page is for the person publishing the app. End users should install the
signed release and never need Xcode.

Complete every P0 item in the [release-readiness TODO](../TODO.md) before
publishing a signed binary.

## Is a public release possible?

Yes. The recommended first release is **direct macOS distribution**:

```text
Developer ID Application signing → Apple notarization → DMG → release page
```

It avoids Mac App Store review while still letting Gatekeeper verify that the
app is from you and has not been altered. The app already has Hardened Runtime
and App Sandbox enabled, which are the relevant starting settings for a
notarized macOS app.

The app also includes a privacy manifest, a local-network purpose string, and
immutable bundle version/build values. The shared project contains no developer
Team ID; local signing configuration must remain untracked.

Do not publish the output of `build-and-install.sh`. That script is for local
installation and signs with the identity selected by the project.

## Frigate attribution and branding

TixisBirdview interoperates with Frigate over its API. It also contains MSE playback
handling adapted from Frigate, which is MIT-licensed. Keep
[`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) with every source and
binary release.

Use this wording in public documentation and the About window:

> TixisBirdview is an independent application compatible with Frigate. It is not
> affiliated with or endorsed by Frigate, Inc.

Do not use Frigate's logo or imply an official partnership without permission.
The MIT license is a copyright license; it does not grant trademark rights.

## Which Apple account works?

| Account | Suitable use | Public release? |
| --- | --- | --- |
| Free Xcode **Personal Team** | Build/test on your own Mac. | No. It cannot create a Developer ID certificate or notarize the app. |
| Paid Apple Developer Program, enrolled as an **individual** | Build, Developer ID-sign, notarize, and distribute under your personal legal name. | Yes. No company is required. |
| Paid Apple Developer Program, enrolled as an organization | Same workflow, released under the organization. | Yes. |

Local builds use automatic **Apple Development** signing selected from the
ignored `build.local.env`. That is correct for local development, but it is not
a public-release signature. A direct release must use **Developer ID
Application** during archive/notarization.

The Developer ID certificate's public legal name and Team ID are intentionally
visible in every signed app so Gatekeeper can identify its publisher. The
private key and Apple Account email are not embedded in the app. Never export
the certificate/private key to this repository.

## One-time preparation

1. Enroll in the Apple Developer Program if the account is currently shown as
   **Personal Team** in Xcode.
2. In Xcode, open **Settings > Accounts**, select the enrolled team, and let
   Xcode manage/download the signing certificates.
3. Create a **Developer ID Application** certificate in the Apple Developer
   portal or Xcode and confirm that it and its private key appear under **My
   Certificates** in Keychain Access. An Apple Development certificate is not
   sufficient for public distribution.
4. Install the repository's local leak guard once:

   ```bash
   ./scripts/install-git-hooks.sh
   ```

   On GitHub, also open **Settings > Advanced Security** and confirm **Secret
   Protection**, **secret scanning**, and repository **push protection** are
   enabled. GitHub's protection covers recognized credentials; the local hook
   additionally covers this project's signing and private-infrastructure rules.

5. Store notarization credentials directly in Keychain. The helper asks for
   the Apple Account email interactively and `notarytool` securely prompts for
   an [app-specific password](https://support.apple.com/102654); neither is
   written to a file:

   ```bash
   ./scripts/configure-notarization.sh
   ```

6. Decide the release version. `MARKETING_VERSION` follows semantic
   `MAJOR.MINOR.PATCH`; increment the integer `CURRENT_PROJECT_VERSION` for
   every distributed build, even when retrying the same public version. Verify
   both with `./scripts/check-versioning.sh`.
7. TixisBirdview's own code is MIT-licensed. Keep `LICENSE`,
   `THIRD_PARTY_NOTICES.md`, `PRIVACY.md`, and `AUTHORS.md` in every source
   release.

## Build the signed and notarized DMG

After the one-time preparation, run:

```bash
./build-signed-release.sh
```

The script refuses to continue unless the public-tree safety scan, version
check, and complete XCTest suite pass. It then selects a local Developer ID
Application identity, creates a universal hardened-runtime archive, notarizes
and staples the app, creates and notarizes a DMG, verifies Gatekeeper, and
writes both files below `dist/`:

```text
TixisBirdview-<version>-<build>.dmg
TixisBirdview-<version>-<build>.dmg.sha256
```

`dist/`, Xcode archives, certificates, profiles, API keys, and all local
signing configuration are ignored by Git. If the Mac has multiple Developer ID
Application identities, copy `release.local.env.example` to
`release.local.env` and select the certificate by its SHA-1 fingerprint there.

## Alternative: create a signed, notarized release in Xcode

1. Select the **TixisBirdview** scheme and **Any Mac** destination.
2. Choose **Product > Archive**.
3. In the Organizer, select the archive and choose **Distribute App**.
4. Choose **Direct Distribution** (or **Developer ID**, depending on the Xcode
   wording), then choose Apple notarization/upload.
5. Let Xcode sign with **Developer ID Application**, submit to the notary
   service, and staple the accepted ticket.
6. Export the notarized `.app`.
7. Put that app, `LICENSE`, and `THIRD_PARTY_NOTICES.md` into a read-only DMG
   named `TixisBirdview-<version>.dmg`, then attach the DMG to your release page
   with release notes and its SHA-256 checksum.

Xcode and Keychain own the signing key and notarization credentials. Keep them
out of this repository, shell history, and captured build logs.

## Verify the exact file you will publish

Run these against the exported app and final DMG, not the local build under
`DerivedData`:

```bash
codesign --verify --deep --strict --verbose=2 TixisBirdview.app
spctl -a -vvv -t exec TixisBirdview.app
xcrun stapler validate TixisBirdview.app
lipo -archs TixisBirdview.app/Contents/MacOS/TixisBirdview
plutil -lint TixisBirdview.app/Contents/Resources/PrivacyInfo.xcprivacy
shasum -a 256 TixisBirdview-<version>.dmg
```

The Gatekeeper assessment should identify your **Developer ID** and the
notarization ticket should validate. A universal release should report both
`arm64` and `x86_64`. Finally, test the released DMG on a Mac that has never
built the project and is not signed into your developer account.

## App Store later?

Possible, but not recommended for the first release. It requires an App Store
Connect record, Apple Distribution signing, store metadata, privacy details,
and App Review. Direct, notarized Developer ID distribution is much faster for
this small homelab utility.

Before App Store submission:

1. Create the macOS app record using the existing bundle identifier.
2. Provide the public `PRIVACY.md` URL and answer App Privacy questions from
   the app's actual behavior; the app declares no analytics or tracking.
3. Archive with Apple Distribution signing and validate the archive in Xcode.
4. Disable the GitHub release channel for the App Store build and let the Mac
   App Store distribute updates. The informational checker intentionally has
   no self-updater, downloader, or installer.
5. Capture current settings and activity-popup screenshots and complete the
   remaining store metadata before review.

## Updating the app

For every update:

1. Change version and build number.
2. Archive, Developer ID-sign, notarize, and staple again.
3. Verify the exported artifacts.
4. Publish the new DMG and checksum with clear release notes.

TixisBirdview checks the repository's latest stable GitHub Release at most once
per day by default. It also provides **Check for Updates…** in the app and
menu-bar menus. The check only informs the user and opens the trusted GitHub
release page; it does not download or replace the signed app. Users install a
direct update by dragging the newer app into Applications and choosing
**Replace**.
