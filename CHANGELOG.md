# Changelog

All notable user-facing changes are recorded here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses semantic
versioning when releases are tagged.

## [1.0.0] — Unreleased

### Added

- Menu-bar monitoring for Frigate events and review activity.
- Temporary non-activating popup feed with event reason, camera, countdown,
  remembered display position, drag control, and resize control.
- Selectable classifications, including custom labels and Frigate sub-labels.
- JPEG snapshots and authenticated go2rtc MSE live-stream playback.
- Frigate login support with passwords held in the macOS Keychain.
- Connection-lost/restored notices and a red menu-bar icon for unavailable
  servers.
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

### Security

- Uses normal macOS TLS validation, ephemeral web storage, and no plaintext
  password preferences.

[1.0.0]: https://github.com/escapechen/TixisBirdview/releases/tag/v1.0.0
