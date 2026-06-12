# Contributing to PressTalk

Thanks for your interest! PressTalk is a small, focused codebase (~1k lines of Swift) — most contributions can land quickly.

## Getting started

```bash
git clone <this repo>
cd PressTalk
swift build          # debug build
swift run            # run the menu-bar app directly
./build_app.sh       # full .app bundle, ad-hoc signed
```

Requirements: macOS 13+, Xcode command line tools. The only dependency ([HotKey](https://github.com/soffes/HotKey)) is fetched by SPM.

Note: running via `swift run` uses your terminal's microphone/accessibility permissions. For permission-related work, test with the built `.app` bundle — macOS resets permission grants when the bundle ID or signature changes.

## Project layout

```
Sources/PressTalk/
├── main.swift                  # entry point
├── AppDelegate.swift           # thin orchestration layer
├── DictationStateMachine.swift # idle/recording/transcribing with generation counting
├── HotkeyManager.swift         # global push-to-talk hotkey (HotKey wrapper)
├── AudioRecorder.swift         # WAV capture, 5-min cap, format from provider preference
├── Providers/
│   ├── TranscriptionProvider.swift  # the protocol: audio URL in, text out
│   └── GeminiProvider.swift         # Gemini 2.5 Flash implementation
├── TextInsertionEngine.swift   # AX-first insertion, clipboard-paste fallback
├── MenuBarController.swift     # status item & menu
├── SettingsView.swift          # SwiftUI settings window
├── Configuration.swift         # UserDefaults-backed settings, Keychain-backed API key
├── KeychainStore.swift         # Security.framework wrapper + AppIdentity constants
└── Resources/                  # en / zh-Hans localization
```

## Ground rules

- **Privacy is non-negotiable.** No log statement may contain transcribed text, audio paths' content, request URLs with credentials, or raw response bodies. Events and counts only.
- **No new hard-coded user-facing strings.** Add them to both `Resources/en.lproj` and `Resources/zh-Hans.lproj` and use the `L(...)` helper.
- **Identity constants live in `AppIdentity`** (`KeychainStore.swift`). Never read `Bundle.main.bundleIdentifier` for keychain/logging — it is nil under `swift run` and tests.
- New transcription services implement `TranscriptionProvider` — keep provider-specific logic (auth, retry, error mapping) inside the provider.
- Match the existing code style; Swift API Design Guidelines apply.

## Pull requests

1. Keep PRs focused — one fix or feature each.
2. `swift build` must pass; once the test target lands, `swift test` must be green (CI enforces both).
3. For UI/permission behavior that can't be unit-tested, describe your manual test steps in the PR.
4. By contributing you agree your work is licensed under [GPL-3.0](LICENSE).

## Where to start

See [docs/good-first-issues.md](docs/good-first-issues.md) for curated starter tasks, or open an issue to discuss anything bigger before you build it.
