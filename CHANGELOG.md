# Changelog

All notable user-facing changes are recorded here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses semantic
versioning when releases are tagged.

## [1.1.0] — Unreleased

### Fixed

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
