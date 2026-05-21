# Codexeption

Native Swift macOS client experiment for Codex.

## Goals

- macOS 26 SwiftUI app, Swift 6 strict-concurrency friendly.
- Apple-native UI over `codex app-server --listen stdio://`.
- No Electron, no WebView, no idle polling.
- First pass covers local thread listing, transcript rendering, composer input, model/effort selection, approvals, diff review, and command output timeline.

## Requirements

- macOS 26
- Xcode 26
- Swift 6.3
- `codex-cli 0.132.0` or compatible `codex app-server`
- Existing `codex login` auth and `~/.codex` config

## Build

```sh
xcodebuild build \
  -project CodexNative.xcodeproj \
  -scheme CodexNative \
  -destination 'platform=macOS'
```

## Test

```sh
xcodebuild test \
  -project CodexNative.xcodeproj \
  -scheme CodexNative \
  -destination 'platform=macOS'
```
