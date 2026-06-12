# PressTalk

**Push-to-talk dictation for macOS, powered by your own API key.**

[简体中文 README](README.zh-Hans.md)

PressTalk lives in your menu bar. Hold a hotkey, speak, release — your words are transcribed and typed right where your cursor is, in any app. It uses Google's Gemini 2.5 Flash through **your own** Google AI Studio API key (BYOK), which makes it exceptionally good at mixed Chinese-English speech, technical jargon, and smart punctuation — and free to run within Google's free tier.

## Demo

Hold <kbd>⌥ Option</kbd> + <kbd>D</kbd> anywhere — a browser, your editor, a chat box — speak naturally (mixing languages is fine), release the key, and the transcribed text appears at your cursor about a second later.

<!-- demo.gif goes here: screen recording of the flow above (menu bar icon changing idle → recording → transcribing, text appearing in a text field) -->

## Features

- **Hold-to-talk global hotkey** — default <kbd>⌥ Option</kbd> + <kbd>D</kbd>, fully customizable in Settings, re-binds instantly without restart.
- **Gemini 2.5 Flash transcription** — excellent mixed Chinese/English recognition, smart punctuation, automatic filler-word removal ("uh", "嗯", "那个"). Model name is configurable.
- **Custom prompt & hint words** — teach the model your domain terms (product names, industry vocabulary) so they come out spelled exactly right.
- **Cursor-aware insertion** — tries the macOS Accessibility API first, falls back to a clipboard paste that backs up and restores your entire clipboard, images included.
- **Privacy by construction** — your API key lives in the macOS Keychain, audio files are deleted immediately after transcription, and logs never contain your words (event types only, viewable in Console.app). No analytics, no telemetry, no middleman server: audio goes from your Mac straight to Google.
- **Stays out of your way** — menu-bar only, no Dock icon. Recordings are capped at 5 minutes (API limit) with a menu-bar warning 30 seconds before auto-stop.
- **Launch at login**, English and Simplified Chinese UI.

## Install

### Download (recommended)

1. Grab the latest `PressTalk.zip` from the **Releases** page and unzip it.
2. Drag `PressTalk.app` into `/Applications`.
3. **First launch: right-click the app → Open → Open.** The open-source build is ad-hoc signed (no Apple Developer certificate), so Gatekeeper will refuse a normal double-click the first time. Right-click → Open is the standard, safe way around this; you only need to do it once.

### Build from source

Requires macOS 13+ and Xcode command line tools.

```bash
git clone <this repo>
cd PressTalk
./build_app.sh        # produces PressTalk.app, ad-hoc signed
```

Or for a quick run during development: `swift run`.

## Setup (bring your own key)

1. Get a free API key at [Google AI Studio](https://aistudio.google.com/apikey).
2. Click the PressTalk menu-bar icon → **Settings…** → paste the key → **Save**.
3. The first time you hold the hotkey, macOS asks for **Microphone** permission — allow it.
4. For text insertion, enable PressTalk under **System Settings → Privacy & Security → Accessibility**. PressTalk will notify you if this is missing.
5. Put your cursor in any text field, hold <kbd>⌥ Option</kbd> + <kbd>D</kbd>, speak, release. Done.

## Privacy

Read this before dictating anything sensitive:

- **Audio is sent to Google's Gemini API** for transcription, authenticated with your own key. The local audio file is deleted from disk the moment transcription finishes. PressTalk keeps no history of your audio or text.
- **Google may use free-tier requests for model training.** This is Google's policy for AI Studio free-tier keys, not something PressTalk can change. For sensitive content, use a paid-tier key.
- PressTalk's own logs record events only ("transcription succeeded, 42 chars"), never content, never your key.
- No accounts, no telemetry, no servers of ours. The code is GPL-licensed and auditable — that's the point.

## Requirements

- macOS 13 Ventura or later (Apple Silicon and Intel).

## Contributing

PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) and the [good first issues](docs/good-first-issues.md) list.

## License

[GPL-3.0](LICENSE). Dependencies: [HotKey](https://github.com/soffes/HotKey) (MIT).
