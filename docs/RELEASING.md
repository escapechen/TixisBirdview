# Releasing TixisBirdview

This page is for the person publishing the app. End users should install the
signed release and never need Xcode.

## Is a public release possible?

Yes. The recommended first release is **direct macOS distribution**:

```text
Developer ID Application signing → Apple notarization → DMG → release page
```

It avoids Mac App Store review while still letting Gatekeeper verify that the
app is from you and has not been altered. The app already has Hardened Runtime
and App Sandbox enabled, which are the relevant starting settings for a
notarized macOS app.

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

The project currently uses automatic signing with **Apple Development** for
both Debug and Release. That is correct for local development, but it is not a
public-release signature. A direct release must use **Developer ID
Application** during export/notarization.

## One-time preparation

1. Enroll in the Apple Developer Program if the account is currently shown as
   **Personal Team** in Xcode.
2. In Xcode, open **Settings > Accounts**, select the enrolled team, and let
   Xcode manage/download the signing certificates.
3. Confirm that a **Developer ID Application** certificate is available in
   Keychain Access or Xcode's signing settings.
4. Decide the release version. Update `MARKETING_VERSION` and increment
   `CURRENT_PROJECT_VERSION` before every published build.
5. TixisBirdview's own code is MIT-licensed. Keep `LICENSE`,
   `THIRD_PARTY_NOTICES.md`, and `AUTHORS.md` in every source release.

## Create a signed, notarized release in Xcode

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

Xcode owns the signing key and notarization credentials. Keep them out of this
repository, shell history, and CI logs.

## Verify the exact file you will publish

Run these against the exported app and final DMG, not the local build under
`DerivedData`:

```bash
codesign --verify --deep --strict --verbose=2 TixisBirdview.app
spctl -a -vvv -t exec TixisBirdview.app
xcrun stapler validate TixisBirdview.app
shasum -a 256 TixisBirdview-<version>.dmg
```

The Gatekeeper assessment should identify your **Developer ID** and the
notarization ticket should validate. Finally, test the released DMG on a Mac
that has never built the project and is not signed into your developer account.

## App Store later?

Possible, but not recommended for the first release. It requires an App Store
Connect record, Apple Distribution signing, store metadata, privacy details,
and App Review. Direct, notarized Developer ID distribution is much faster for
this small homelab utility.

## Updating the app

For every update:

1. Change version and build number.
2. Archive, Developer ID-sign, notarize, and staple again.
3. Verify the exported artifacts.
4. Publish the new DMG and checksum with clear release notes.

The app has no built-in updater today. Users install an update by dragging the
new app into Applications and choosing **Replace**.
