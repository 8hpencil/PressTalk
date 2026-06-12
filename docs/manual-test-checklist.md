# Manual Test Checklist

Behaviors that involve macOS permissions, global hotkeys, or real UI cannot be
unit-tested. Run through this list before every release — and **always after
changing the bundle ID or code signature**, because macOS silently resets the
microphone / accessibility / notification grants in both cases.

Build under test: `./build_app.sh`, launch `PressTalk.app` (not `swift run` —
permissions attach to the bundle).

## Permissions (fresh install / after bundle ID or signature change)

- [ ] First launch shows the accessibility prompt; after enabling PressTalk in
      System Settings → Privacy & Security → Accessibility, insertion works.
- [ ] First hotkey press triggers the microphone permission prompt; recording
      works after allowing.
- [ ] With accessibility **denied**, dictating shows a notification guiding to
      the permission — the text is not silently lost.
- [ ] With no API key configured, launch shows the welcome notification and a
      hotkey press shows the "no key" notification.

## Dictation flow

- [ ] Hold hotkey → menu bar icon switches to recording; release → transcribing
      → text appears at the cursor → icon back to idle.
- [ ] Pressing the hotkey **while a transcription is in flight** does not start
      a second recording; a brief "still transcribing" hint appears in the menu.
- [ ] Dictating silence shows the "nothing recognized" notice and returns to
      idle (no notification on normal success).
- [ ] Recording past 4:30 shows the warning state; at 5:00 it auto-stops and
      transcribes normally.

## Text insertion

- [ ] Apple Notes (AX-friendly): text inserts, clipboard content unchanged.
- [ ] Terminal / a browser form: clipboard-paste path inserts the text and the
      previous clipboard content — including an image — is restored afterwards.

## Settings

- [ ] Changing the hotkey (e.g. ⌥S) takes effect immediately, old binding dead,
      and survives relaunch. Binding the key **A** (keycode 0) works.
- [ ] Custom prompt and hint words round-trip and influence transcription.
- [ ] Launch-at-login toggle is reflected in System Settings → Login Items.

## Upgrade & migration

- [ ] With a key stored by an older GCPDictation build (defaults domain
      `com.kenny.gcp-dictation-service` or its keychain service): first launch
      migrates the key into the `com.kenny.presstalk` keychain, old storage is
      emptied, dictation works without re-entering the key.

## Localization

- [ ] System language English: menu, settings, notifications all English.
- [ ] System language 简体中文: all of the above in Chinese, no stray English.

## Distribution artifact (release builds)

- [ ] Fresh download of the Release zip: first open requires right-click →
      Open (Gatekeeper), afterwards opens normally.
- [ ] `lipo -archs PressTalk.app/Contents/MacOS/PressTalk` prints
      `x86_64 arm64`.
- [ ] About/`CFBundleShortVersionString` matches the release tag.
