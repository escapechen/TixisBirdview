# TixisBirdview release-readiness TODO

Audit baseline: 2026-08-18. The signed and notarized 1.1.0 (build 2) DMG was
accepted by Gatekeeper and installed successfully on a second Mac. The unsigned
Release build, Xcode static analyzer, property-list validation, shell syntax
check, and all 63 XCTest cases also pass. This file is the source of truth for
remaining public-release work.

## P0 — before publishing a signed binary

- [x] Add `NSLocalNetworkUsageDescription` with a clear explanation that the
  app connects to the user-configured Frigate server and optional MQTT broker.
  A regression test verifies the purpose string is present in the built app.
- [x] Scope Frigate Keychain entries to the normalized server origin **and**
  username. Safely migrate or remove the legacy username-only item. Add a test
  proving that changing servers with an empty password cannot reuse or send the
  previous server's password.
- [x] Harden plaintext transport handling: assume `https://` when the scheme is
  omitted; clearly warn and require confirmation for explicit Frigate HTTP or
  MQTT without TLS. Never silently weaken TLS validation.
- [x] Add an authenticated-request redirect policy that rejects HTTPS-to-HTTP
  downgrades and cross-origin redirects. Cover 307/308 login redirects in tests.
- [x] Remove the personal `DEVELOPMENT_TEAM` from the shared Xcode project and
  keep it in ignored local configuration/Xcode settings only. The Team ID is
  not a signing secret, but tracking it contradicts the release documentation
  and makes the project less portable.
- [x] Keep the already-public Git history as published. The old Team ID is not a
  signing secret; the current tree no longer contains it or the absolute
  workspace path. Repeat current-tree and image-metadata scans before release.
- [x] Support Intel and Apple Silicon Macs. Release builds explicitly contain
  `arm64` and `x86_64`, and the installer rejects an incomplete Release build.
- [x] Add a reproducible local release script that requires Developer ID,
  runs tests and leak/version checks, archives with Hardened Runtime, notarizes
  and staples the app and DMG, verifies Gatekeeper, and writes a SHA-256 file.
- [x] Run that workflow with the release owner's Developer ID certificate and
  verify the signed, notarized DMG on a second Mac.
- [ ] Publish the exact DMG and checksum produced by the release workflow. Do
  not publish the local installer-script output.

## P1 — release quality and security

- [x] Add `SECURITY.md` with a private vulnerability-reporting route, supported
  versions, and expected response process.
- [ ] Confirm **Settings > Code security > Private vulnerability reporting** is
  enabled on GitHub so the `SECURITY.md` private-report link accepts reports.
- [ ] Confirm GitHub **Secret Protection**, secret scanning, and repository
  push protection are enabled under **Settings > Advanced Security**.
- [x] Keep release validation owner-controlled and local. The signed-release
  workflow runs tests, leak/version checks, a universal Release archive,
  signing, notarization, and Gatekeeper verification without uploading signing
  credentials to hosted automation.
- [x] Add release and opt-in pre-commit leak guards for signing Team IDs,
  pinned Developer ID selections, private keys/profiles, tokens, private hosts,
  and machine-specific paths.
- [x] Restore `.accessory` activation policy after Settings/About closes when
  **Show Dock Icon** is disabled; keep explicit Settings activation behavior.
- [x] Bound or age out `seenEventIDs` and `seenReviewItemIDs` so a long-running
  menu-bar process does not grow these sets indefinitely.
- [x] Refresh the Frigate camera-to-live-stream mapping when a camera is missing
  or Frigate configuration changes, without bypassing authenticated HTTPS/WSS.
- [ ] Update README screenshots for the current four-pane native settings UI
  and current popup controls. Create separate App Store-ready 16:10 screenshots
  without alpha if pursuing store distribution.
- [ ] Complete manual accessibility/HIG QA: VoiceOver, Full Keyboard Access,
  Reduce Motion, Reduce Transparency, increased contrast, light/dark appearance,
  small displays, and long strings. Confirm status notices are announced without
  moving focus.
- [x] Add an in-app reset/delete-data action for preferences and both Keychain
  credential sets; document retention and deletion in `PRIVACY.md`.
- [ ] Add at least one integration smoke-test path using disposable local HTTPS
  and MQTT fixtures. Unit tests currently cover the contracts but not a real TLS
  broker or full Frigate session.

## P2 — maintainability and compatibility

- [ ] Split `FrigateMonitor.swift`, `SettingsMenuView.swift`,
  `FrigateMSEStreamView.swift`, and the large test file into focused modules.
- [ ] Remove unused SwiftUI-template files (`ContentView.swift` and `Item.swift`)
  if Xcode confirms they have no target/runtime use.
- [ ] Enable complete Swift concurrency checking, resolve warnings, and plan the
  Swift 6 language-mode migration.
- [ ] Accept bracketed IPv6 Frigate URLs and add validation tests.
- [ ] Move MSE JavaScript into a separately testable resource, add a restrictive
  content-security policy/navigation policy, and retain JPEG fallback.
- [ ] Replace diagnostic `print` calls with privacy-redacted unified logging and
  keep verbose live-player diagnostics opt-in.
- [ ] Localize user-visible strings after the English UI and accessibility pass
  stabilizes.

## Separate Mac App Store track

- [ ] Add a dedicated App Store build configuration that removes/disables the
  GitHub update channel; store builds must use Mac App Store updates.
- [ ] Bundle license, privacy, and third-party notices inside the app so the
  distributed app is self-contained.
- [ ] Create the App Store Connect record and complete support/privacy URLs,
  App Privacy answers, category, age rating, description, keywords, review
  notes, and compliant screenshots.
- [ ] Give App Review a usable demo Frigate environment/account or precise
  review instructions that exercise the app without private home infrastructure.
- [ ] Determine export-compliance treatment for TLS/network cryptography and set
  the matching App Store Connect answer/Info.plist declaration.
- [ ] Archive with Apple Distribution signing, validate in Organizer, test the
  submitted build through TestFlight, and resolve App Review feedback.

## Definition of release-ready

All P0 items are complete, the complete local test suite passes from a clean
checkout, the published artifact passes the checks in
`docs/RELEASING.md`, and no real credentials, private service URLs, or
identifying image metadata are present.
