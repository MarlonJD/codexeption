# Contributing

Thank you for helping shape Codexeption. The project is still intentionally small, so the best contributions are focused, native, and easy to reason about.

## Development Setup

Requirements:

- macOS 26
- Xcode 26
- Swift 6.3
- `codex-cli 0.132.0` or a compatible `codex app-server`
- Existing `codex login` auth and `~/.codex` configuration

Build:

```sh
xcodebuild build \
  -project CodexNative.xcodeproj \
  -scheme CodexNative \
  -destination 'platform=macOS'
```

Test:

```sh
xcodebuild test \
  -project CodexNative.xcodeproj \
  -scheme CodexNative \
  -destination 'platform=macOS'
```

## Contribution Scope

Good first areas:

- Typed app-server payloads for methods already used by the app.
- Transcript, diff, approval, and command-output rendering improvements.
- Swift 6 strict-concurrency fixes.
- Tests for JSON-RPC framing, notification decoding, payload encoding, and failure paths.
- Small UI polish that improves scanning, repeated work, or live feedback.

Out of scope for now:

- Electron, WebView, or browser-rendered transcript surfaces.
- Cloud Codex history sync.
- Full terminal emulation.
- Full plugin marketplace support.
- Continuous polling or always-on background workers.
- Third-party dependencies added only for convenience.

## Code Style

- Use Swift 6.3 language mode and keep strict concurrency warnings clean.
- Prefer `struct` value models and typed `Codable` DTOs for app-server payloads.
- Keep UI-facing state isolated on `@MainActor`.
- Prefer `async`/`await` over callback chains.
- Make protocol handling tolerant: unknown notifications and fields should not crash the app.
- Avoid large global mutable state. Prefer explicit ownership in services and view models.
- Add comments only where they clarify non-obvious protocol, concurrency, or lifecycle behavior.
- Keep source files focused. Add a type only when it represents a real boundary in the app.
- Do not introduce third-party SPM packages without explaining why the standard library, SwiftUI, AppKit, or local helpers are not enough.

## UI Style

- Build a native macOS developer tool, not a landing page.
- Keep the primary layout familiar: sidebar, transcript, composer, and inspector.
- Favor compact controls, predictable spacing, and text that is easy to scan during long sessions.
- Use native SwiftUI/AppKit controls before custom controls.
- Use subtle animation for live state changes, such as file change counts, but avoid animation that slows repeated work.
- Keep command output, code blocks, and diffs visually distinct from assistant text.
- Keep large histories lazy, incremental, or bounded. Do not render an entire thread as one huge string.
- Keep user-facing strings in `Localizable.xcstrings`; Turkish is the first UI language.

## Performance Rules

- The app should do almost nothing when idle.
- Start `codex app-server --listen stdio://` on demand.
- Shut down the app-server after the configured idle window when there is no active turn or approval.
- Refresh git and file state on events such as turn completion, manual refresh, or foregrounding.
- Avoid watchers and timers unless the change includes a clear reason and a bounded lifecycle.
- Use `OSLog` and signposts for meaningful lifecycle and latency measurements.

## Testing Expectations

Add or update tests when changing:

- JSON-RPC framing.
- Request id matching.
- Notification decoding.
- Unknown message tolerance.
- `turn/start` payload generation.
- Approval response encoding.
- Diff parsing or live change summaries.
- Any behavior that affects app-server lifecycle.

Manual checks should include:

- Launching the app with an existing Codex CLI login.
- Listing local threads.
- Starting a new turn.
- Handling an approval request.
- Viewing command output.
- Opening the diff inspector.

## Pull Request Checklist

- The change is scoped to one clear behavior or improvement.
- Build passes with `xcodebuild build`.
- Tests pass with `xcodebuild test`, or the PR explains why they were not run.
- New user-facing strings are localizable.
- The app does not add idle polling.
- The app-server still starts on demand and can shut down when idle.
- README or CONTRIBUTING is updated when behavior, setup, or style expectations change.
