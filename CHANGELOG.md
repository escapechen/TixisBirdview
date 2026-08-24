# Changelog

All notable user-facing changes are recorded here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses semantic
versioning when releases are tagged.

## [1.1.1] — Unreleased

### Added

- Feed settings now offer either the camera from the latest accepted activity
  or Frigate's server-side Birdseye composite. The composite keeps one
  authenticated stream connection while Frigate displays several active
  cameras in its mosaic.

### Changed

- A qualifying event from another camera can refresh an already visible popup
  without reopening the window. Popup and sound cooldowns remain independent;
  a popup-cooldown rejection no longer changes the camera visible in an open
  last-camera feed.

### Fixed

- Live MSE playback now performs a cooldown-protected forward resynchronization
  after WebKit drifts more than three seconds behind, before resorting to a full
  player rebuild. Playback speed remains fixed and JPEG stays visible until the
  live player has decoded a frame.
- The visible activity badge now incorporates sub-classifications that Frigate
  reports later for the same event or review. Each name appears only once per
  popup session, and additional animals on the same camera are appended without
  restarting the feed or replacing names already shown.
- MQTT event decoding now accepts Frigate's live `[name, confidence]` sublabel
  representation as well as the plain string returned by the HTTP events API.
- Frigate's internal `*-verified` review marker is normalized to its base label,
  so a selected classification such as `cat` still accepts a later named pet.

## [1.1.0] — 2026-08-18

### Added

- The Dock icon now has a native context menu with connection status, last
  activity, monitoring, feed, duration, Settings, update, and About commands.
  This keeps the app usable when macOS hides its menu-bar icon.
- A standard **Check for Updates…** command and General settings pane can check
  GitHub Releases automatically or on demand. The checker only reports and
  opens releases, shows at most one non-activating notice per version, and
  never downloads or installs an update silently.
- A privacy policy and bundled Apple privacy manifest document local settings,
  Keychain use, configured network connections, and the GitHub update check.
- A destructive-confirmation **Delete All App Data…** action removes app
  preferences and all TixisBirdview Frigate/MQTT Keychain credentials, then
  quits so the next launch starts clean.
- A public security policy provides private vulnerability reporting, while the
  local release workflow runs tests and release-safety checks before signing.
- A one-command Developer ID release workflow builds, notarizes, staples, and
  verifies a DMG and produces its SHA-256 checksum without storing credentials
  in the repository.
- Public-tree, staged-commit, and release guards reject signing identities,
  private key/profile files, private infrastructure, tokens, and machine-local
  paths.

### Changed

- Settings now use four stable native toolbar panes, restore the last pane,
  present the selected pane name as the window title, and expose application
  and update preferences under **General**.
- The application and menu-bar menus use standard macOS command naming,
  grouping, ellipses, Services, and Undo/Redo commands.
- About now displays only the signed bundle's version and build number instead
  of appending a launch counter.
- The app is categorized as a macOS utility and no longer requests unused
  user-selected-file or app-group capabilities.
- Lowered the deployment target from macOS 26.5 to macOS 14 Sonoma after an
  unsigned compatibility build, so release builds can support more Macs.
- Release builds are now universal (`arm64` and `x86_64`), and the local
  installer verifies both architectures before replacing the installed app.
- Event and review deduplication histories now use bounded 512-entry caches,
  preventing memory growth in a long-running menu-bar session.
- Frigate's authenticated camera-to-go2rtc mapping refreshes every five minutes
  and retries missing cameras after 30 seconds, so configuration changes no
  longer require restarting the app.
- Release versions now consistently use semantic `MAJOR.MINOR.PATCH` numbering
  and a separate monotonically increasing integer build number.

### Fixed

- When the Dock icon is disabled, closing the last Settings/About window now
  restores accessory-app behavior; the app remains regular while either
  user-requested window is open.
- Live-player teardown no longer starts a blank replacement page while WebKit
  is already destroying the view, reducing harmless RunningBoard assertion
  warnings after closing a feed or quitting the app.
- Live video keeps a user-visible activity assertion while its non-activating
  overlay is open, preventing macOS from deferring WebKit playback when the
  menu-bar app is inactive. Normal idle system sleep remains allowed.
- The popup now selects the camera with the newest relevant event or review
  activity instead of always preferring an older event.
- Alert titles now suppress repeated verified sub-labels from Frigate.
- The muted live MSE player now requests video only, avoiding camera-audio clock
  problems, and no longer seeks or accelerates WebKit playback. A player that
  falls excessively behind is rebuilt cleanly while JPEG remains available.
- The macOS player now resumes WebKit after transient pause/end states whenever
  fresh MSE data arrives, matching Frigate's ManagedMediaSource lifecycle.
- Live MSE duration remains open-ended, preventing an ended-state replay from
  resetting the feed several seconds into the past when a new fragment arrives.
- Closing or hiding a feed now explicitly closes even a still-negotiating MSE
  WebSocket, preventing abandoned players from exhausting future live upgrades.
- If go2rtc negotiates video-only MSE but sends only its initializer, the player
  retries once with Frigate's standard codec set and reports a source failure
  separately from a genuine macOS decoding failure.

### Security

- Frigate passwords are now scoped to the normalized server and username. A
  legacy username-only Keychain item migrates only to the previously saved
  server, so changing servers cannot reuse its password.
- Server addresses without a scheme now default to HTTPS. Explicit Frigate HTTP
  and MQTT without TLS show persistent warnings and require confirmation.
- Authenticated HTTP redirects are limited to the same origin, preventing
  cross-origin credential redirects and HTTPS-to-HTTP downgrades.
- Added the macOS local-network privacy purpose string for user-configured
  Frigate and MQTT connections.

## [1.0.0]

### Added

- Menu-bar monitoring for Frigate events and review activity.
- Temporary non-activating popup feed with event reason, camera, countdown,
  remembered display position, drag control, and resize control.
- Selectable classifications, including custom labels and Frigate sub-labels;
  several discovered labels can be selected and added together.
- JPEG snapshots and authenticated go2rtc MSE live-stream playback.
- Frigate login support with passwords held in the macOS Keychain.
- Connection-lost/restored notices and a red menu-bar icon for unavailable
  servers.
- Optional popup sound alerts with a selectable macOS sound, volume, and
  preview control.
- Independent, configurable popup and sound cooldowns, each with an enable
  checkbox and seconds field; manual feed display is unaffected.
- Build, installation, release, and source-build documentation.
- A Tixi-inspired app icon and monochrome menu-bar template mark.

### Changed

- Renamed the app and public repository to **TixisBirdview**. “Frigate” now
  appears only as a compatibility reference with an independence disclaimer.
- Fresh installations now start with an intentionally unreachable HTTPS
  placeholder server address instead of a private network address.
- Source headers and the About window credit Marcel Kühn and OpenAI Codex
  (GPT-5.6 Terra, Extra High reasoning).
- The shared project no longer contains a personal Apple Developer Team ID;
  local builds use an ignored per-Mac Team ID setting.
- The popup now persists its width and display position while deriving height
  from each JPEG or live-stream aspect ratio, avoiding cropped wide feeds.
- Live playback now keeps JPEG snapshots visible while WebKit establishes or
  retries MSE video, switching only after a decoded frame arrives. The
  1–15-second **Retry live player after** setting (default 5 seconds)
  controls each connection attempt instead of permanently falling back.
- Live popups now show compact JPEG/live-player status badges. Optional,
  privacy-safe live-player diagnostics can be written to terminal output.

### Security

- Uses normal macOS TLS validation, ephemeral web storage, and no plaintext
  password preferences.

[1.0.0]: https://github.com/escapechen/TixisBirdview/releases/tag/v1.0.0
[1.1.0]: https://github.com/escapechen/TixisBirdview/releases/tag/v1.1.0
[1.1.1]: https://github.com/escapechen/TixisBirdview/compare/v1.1.0...HEAD
