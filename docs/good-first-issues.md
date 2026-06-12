# Good First Issues（开仓后发布用草稿）

以下草稿在 GitHub 仓库建立后逐条创建为 issue 并打 `good first issue` 标签。正文已按可直接粘贴编写（英文）。

---

## 1. New provider: OpenAI-compatible transcription endpoint

**Labels:** `good first issue` `enhancement` `provider`

PressTalk's transcription is behind a small protocol — `TranscriptionProvider` (`Sources/PressTalk/Providers/TranscriptionProvider.swift`). Today there is one implementation (Gemini). Add a provider for OpenAI-compatible `/v1/audio/transcriptions` endpoints (works with OpenAI, Groq, local servers like LM Studio / faster-whisper-server).

Scope:
- New `Providers/OpenAICompatibleProvider.swift` implementing the protocol (multipart upload, model name + base URL + API key from settings).
- Add the provider to the Settings picker, with base-URL and key fields shown only when selected.
- Map 401/429 onto the existing `TranscriptionError` cases so retry/notification behavior stays consistent.

No state-machine or insertion changes needed — the protocol isolates you from all of that.

## 2. Menu-bar recording animation

**Labels:** `good first issue` `enhancement` `ui`

While recording, the status item shows a static `mic.fill`. A subtle animation (pulsing opacity, or a tiny level meter using the recorder's average power) would make the state much more glanceable.

Scope: `MenuBarController.swift` (+ `AudioRecorder.swift` if using level metering). Keep it CPU-cheap (timer ≤ 10 Hz) and make sure the warning state (near the 5-minute cap) stays visually distinct.

## 3. Additional UI languages

**Labels:** `good first issue` `i18n`

All user-facing strings live in `Sources/PressTalk/Resources/{en,zh-Hans}.lproj/Localizable.strings` — roughly 60 keys. Adding a language means copying one folder, translating, and adding the locale to the test checklist. Japanese, Traditional Chinese, German, and Spanish are natural candidates. Native speakers preferred over machine translation.

## 4. Optional sound feedback on record start/stop

**Labels:** `good first issue` `enhancement`

Push-to-talk users often want an audible cue that recording actually started (and stopped). Add a "Play sound on start/stop" toggle in Settings (default off), using short system sounds (`NSSound(named:)`). Scope: `SettingsView.swift`, `Configuration.swift`, `AppDelegate.swift` — and both `.strings` files for the new labels.

## 5. Show elapsed recording time in the menu

**Labels:** `good first issue` `enhancement` `ui`

While recording, the status menu item reads "Status: recording…". Append a live elapsed timer ("Status: recording… 0:42") so users sense how close they are to the 5-minute cap. Scope: `MenuBarController.swift` (update the existing `NSMenuItem` title on a 1 s timer — do not rebuild the menu).
