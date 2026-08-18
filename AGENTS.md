# TixisBirdview — agent handoff

## Scope and ownership

- TixisBirdview is a native macOS menu-bar companion compatible with Frigate.
- Marcel Kühn owns the repository, release signing, commits, and pushes. Do not
  commit, sign, publish, or push unless he explicitly asks.
- Keep responses concise and base conclusions on this repository.

## Start here

1. Read `README.md`, then `TODO.md`, then the relevant document under `docs/`.
2. Use codebase-memory MCP for code discovery (`search_graph`, `trace_path`,
   then `get_code_snippet`). Use `rg` for literal strings and non-code files.
3. Check `git status --short` before editing; preserve unrelated user changes.

## Architecture

- `FrigateMonitor.swift`: settings, Keychain password storage, Frigate login,
  session cookies, polling, classification filtering, and go2rtc stream lookup.
- `VideoFeedView.swift`: JPEG feed, event badge, countdown, and feed controls.
- `FrigateMSEStreamView.swift`: isolated `WKWebView` MSE live playback.
- `OverlayWindowController.swift`: non-activating floating overlay and saved
  display geometry.
- `SettingsMenuView.swift`: settings UI and classification selection.
- `StatusItemController.swift`: menu-bar state and connection notices.
- `UpdateChecker.swift`: daily/manual GitHub release discovery and semantic
  version comparison. It informs only; it never downloads or installs updates.

Live stream routing must use the Frigate config mapping
`cameras.<camera>.live.streams`; an event camera name is not necessarily the
go2rtc stream name. JPEG snapshots are the compatible fallback.

- TixisBirdview must work with a Frigate installation as configured. Access
  live media only through Frigate's existing authenticated HTTPS/WSS proxy;
  never require users to expose extra go2rtc ports or unencrypted/unauthenticated
  streams.
- The sibling repository `../frigateHOMELAN` is the
  server-side source used by Marcel's custom Frigate installation. Inspect and,
  when explicitly requested, coordinate compatible changes across both repos.

## Security and privacy

- Passwords belong only in the macOS Keychain. Never log, commit, or display
  credentials, cookies, tokens, or configured server URLs.
- Keep normal TLS validation; do not add certificate bypasses.
- The default server URL is intentionally an unreachable HTTPS placeholder.
  Connection failures must show the disconnected state, never terminate the app.
- Do not add production/home-lab URLs, private paths, key material, or EXIF
  location data to source, docs, images, or tests.

## Build and verification

- Source-build instructions: `docs/BUILD_FROM_SOURCE.md`.
- Installer: `./build-and-install.sh`; it builds and replaces
  `/Applications/TixisBirdview.app` after sudo confirmation.
- `build.local.env` is an ignored, per-Mac configuration for the script's
  required `TEAM_ID` and optional `CONFIGURATION`/`DEVELOPER_DIR`; keep only
  the example file tracked. Do not infer the Team ID from a development
  certificate's displayed member ID.
- Versioning is semantic `MARKETING_VERSION` plus a monotonically increasing
  integer `CURRENT_PROJECT_VERSION`; validate with
  `./scripts/check-versioning.sh`. Current source is 1.1.0 (build 2).
- Fast checks: `./scripts/check-public-safety.sh`,
  `./scripts/check-versioning.sh`, `git diff --check`, and shell syntax checks.
- `./build-and-install.sh --test` runs the complete local suite without signing
  or installing the app.
- After Swift behavior changes, run the XCTest suite:

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
    -project TixisBirdview.xcodeproj -scheme TixisBirdview -configuration Debug \
    -derivedDataPath /private/tmp/TixisBirdview-DerivedData \
    CODE_SIGNING_ALLOWED=NO test
  ```

- Preserve the automated core-alert contracts: Frigate login request/cookie
  handling, MQTT credentials and `events`/`reviews` subscriptions, MQTT event
  to matching-camera popup routing, JPEG-preview to playable-MSE transition,
  one-click dismissal, and a permanently non-key/non-main overlay. Tests must
  remain local and must not need real credentials, cameras, or a broker.
- Every new or changed user-visible behavior needs focused automated coverage
  in the same change. If a behavior can’t be meaningfully automated (for
  example, a system-provided visual treatment), add the smallest testable
  contract and document the required manual check in the handoff.

- Debug build:

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
    -project TixisBirdview.xcodeproj -scheme TixisBirdview -configuration Debug \
    -derivedDataPath /private/tmp/TixisBirdview-DerivedData \
    CODE_SIGNING_ALLOWED=NO build
  ```

  `Info.plist` is excluded from Copy Bundle Resources. Treat a recurrence of
  that warning as a project-configuration regression.

## Release and collaboration

- Read `TODO.md` and `docs/RELEASING.md` before release work. Do not describe a
  signed-binary release as ready while a P0 item remains open.
- `./build-signed-release.sh` is the Developer ID/notarization/DMG workflow;
  `scripts/configure-notarization.sh` stores its credential profile in Keychain.
  `release.local.env`, `dist/`, identities, certificates, and profiles are
  local-only. Never expose their values in output or commit them.
- The local release workflow runs the public-tree leak guard. Contributors
  should install the staged pre-commit guard once with
  `./scripts/install-git-hooks.sh`.
- Direct releases use the informational GitHub channel. App Store builds must
  disable it and use Mac App Store updates instead.
- Current code is MIT licensed; keep `LICENSE`, `AUTHORS.md`, and
  `THIRD_PARTY_NOTICES.md` accurate when changing attribution.
- The app credits Marcel Kühn and OpenAI Codex (GPT-5.6 Terra, Extra High
  reasoning). Preserve that acknowledgement unless asked otherwise.
- GitHub is `origin`; the legacy internal mirror is `gitea`. See
  `docs/GIT_MIRRORS.md` for the safe two-remote workflow.
