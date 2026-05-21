# Codexeption

Codexeption is an Apple-native macOS client experiment for Codex. It builds a lightweight SwiftUI interface on top of `codex app-server --listen stdio://` without Electron, WebView, or idle polling.

The project is intentionally not a clone of the official Codex Desktop app. It explores a native, low-overhead Codex client focused on local threads, live turn feedback, approvals, diffs, and command output timelines.

## GitHub Metadata

Description:

```text
Apple-native macOS Codex client built with SwiftUI on top of codex app-server.
```

Topics:

```text
swift, swiftui, macos, codex, codex-cli, xcode, json-rpc, developer-tools, native-app, swift-concurrency, app-server, mit-license
```

## Goals

- macOS 26 SwiftUI app with Swift 6.3 strict-concurrency compatibility.
- Apple-only native UI over the local Codex app-server process.
- No Electron, no WebView, no continuous idle polling.
- Very low idle CPU by starting `codex app-server` on demand and shutting it down after inactivity.
- First-version scope: local Codex chats, project and thread lists, model and reasoning effort selection, new turns, approvals, diff review, and command output timeline.

## Current Features

- Native sidebar, transcript, composer, and inspector layout.
- JSON-RPC transport for newline-delimited `codex app-server` messages.
- Typed `Codable` subset for the app-server methods used by the app.
- Tolerant unknown-message handling so protocol additions do not break the UI.
- Local thread discovery, thread reading, turn start/interruption, model listing, config reading, and approval responses.
- Native diff/change summary rendering, including animated live file change counters during a turn.
- SwiftData-backed app settings and UI cache, while Codex remains the source of truth for thread history.

## Requirements

- macOS 26
- Xcode 26
- Swift 6.3
- `codex-cli 0.132.0` or a compatible `codex app-server`
- Existing `codex login` auth and `~/.codex` configuration

## Build

Debug build:

```sh
xcodebuild build \
  -project CodexNative.xcodeproj \
  -scheme CodexNative \
  -destination 'platform=macOS'
```

Release build:

```sh
xcodebuild build \
  -project CodexNative.xcodeproj \
  -scheme CodexNative \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/codex-native-release
```

The release app product will be created at:

```text
/private/tmp/codex-native-release/Build/Products/Release/CodexNative.app
```

## Test

```sh
xcodebuild test \
  -project CodexNative.xcodeproj \
  -scheme CodexNative \
  -destination 'platform=macOS'
```

## Project Structure

```text
CodexNative/
  Models/       Core app models, JSON values, and app-server protocol DTOs
  Services/     Codex transport, app-server client, and system helpers
  ViewModels/   MainActor application state
  Views/        SwiftUI views for sidebar, transcript, composer, and inspector
  Resources/    Localized strings and app resources

CodexNativeTests/
  JSON-RPC framing, protocol payload, and tolerant decoding tests
```

## Style Rules

- Keep the app Apple-native: SwiftUI/AppKit only, no Electron, no WebView, and no browser-based rendering.
- Keep idle behavior event-driven: avoid timers, watchers, and polling unless there is a measured need.
- Keep concurrency explicit: prefer `async`/`await`, isolate UI state on `@MainActor`, and satisfy Swift strict concurrency.
- Keep protocol handling typed but tolerant: known app-server methods should use `Codable` payloads, while unknown messages should be logged without breaking the UI.
- Keep UI language Turkish-first and store user-facing strings in `Localizable.xcstrings`.
- Keep UI surfaces compact, calm, and developer-tool oriented. Avoid decorative layouts that make repeated work slower.
- Keep diffs and transcripts lazy or bounded; never render the whole thread as one giant string.
- Keep dependencies minimal. Do not add third-party SPM packages without a clear project-level reason.

More contribution and style details are in [CONTRIBUTING.md](CONTRIBUTING.md).

## Contributing

Contributions should keep the project small, native, and low-overhead. Before opening a pull request, run the build and tests above, then check that the app still starts without requiring a custom login flow or cloud-only state.

See [CONTRIBUTING.md](CONTRIBUTING.md) for workflow, code style, UI style, testing expectations, and pull request checklist.

## License

MIT License. Copyright (c) 2026 Burak Karahan.
