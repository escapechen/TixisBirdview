# TixisBirdview — agent handoff

## Scope and ownership

- TixisBirdview is a native macOS menu-bar companion compatible with Frigate.
- Marcel Kühn owns the repository, release signing, commits, and pushes. Do not
  commit, sign, publish, or push unless he explicitly asks.
- Keep responses concise and base conclusions on this repository.

## Start here

1. Read `README.md`, then the relevant document under `docs/`.
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

Live stream routing must use the Frigate config mapping
`cameras.<camera>.live.streams`; an event camera name is not necessarily the
go2rtc stream name. JPEG snapshots are the compatible fallback.

- TixisBirdview must work with a Frigate installation as configured. Access
  live media only through Frigate's existing authenticated HTTPS/WSS proxy;
  never require users to expose extra go2rtc ports or unencrypted/unauthenticated
  streams.
- The sibling repository `/Users/marcel/Documents/repos/frigateHOMELAN` is the
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
- Fast checks: `git diff --check` and `bash -n build-and-install.sh`.
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

  The project may emit an existing warning that `Info.plist` appears in Copy
  Bundle Resources; report it, but do not confuse it with a build failure.

## Release and collaboration

- Read `docs/RELEASING.md` before release work.
- Current code is MIT licensed; keep `LICENSE`, `AUTHORS.md`, and
  `THIRD_PARTY_NOTICES.md` accurate when changing attribution.
- The app credits Marcel Kühn and OpenAI Codex (GPT-5.6 Terra, Extra High
  reasoning). Preserve that acknowledgement unless asked otherwise.
- GitHub is `origin`; the legacy internal mirror is `gitea`. See
  `docs/GIT_MIRRORS.md` for the safe two-remote workflow.
