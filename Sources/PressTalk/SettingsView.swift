import SwiftUI
import ServiceManagement
import HotKey

public extension Notification.Name {
    /// Posted after settings are saved so HotkeyManager re-registers (B3).
    static let hotkeyConfigurationChanged = Notification.Name("HotkeyConfigurationChanged")
}

struct SettingsView: View {
    @State private var apiKey: String = Configuration.shared.apiKey
    @State private var modelName: String = Configuration.shared.modelName
    @State private var customPrompt: String = Configuration.shared.customPrompt
    @State private var hintWordsRaw: String = Configuration.shared.hintWordsRaw
    @State private var hotkeyKeyCode: Int = Configuration.shared.hotkeyKeyCode
    @State private var hotkeyModifiers: Int = Configuration.shared.hotkeyModifiers
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?
    @State private var isCapturingHotkey = false
    @State private var keyMonitor: Any?
    @State private var showSavedAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    transcriptionSection
                    Divider()
                    hotkeySection
                    Divider()
                    generalSection
                }
                .padding(20)
            }

            Divider()

            footer
                .padding(16)
        }
        .frame(width: 560, height: 640)
        .onDisappear { endHotkeyCapture() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 32))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(L("settings.title"))
                    .font(.headline)
                Text(L("settings.subtitle"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("settings.section.transcription"))
                .font(.title3)
                .fontWeight(.semibold)

            Text(L("settings.apiKey.label"))
                .fontWeight(.medium)
            SecureField(L("settings.apiKey.placeholder"), text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            HStack {
                Link(L("settings.apiKey.getKey"), destination: URL(string: "https://aistudio.google.com/")!)
                    .font(.caption)
                Spacer()
            }

            Text(L("settings.privacy.note"))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(L("settings.provider.label"))
                    .fontWeight(.medium)
                // Only implemented providers are listed (no empty-shell
                // options); whisper.cpp joins in v1.1 (U7).
                Text("Gemini")
                Text(L("settings.provider.note"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text(L("settings.model.label"))
                    .fontWeight(.medium)
                TextField(Configuration.defaultModelName, text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: 260)
            }

            Text(L("settings.prompt.label"))
                .fontWeight(.medium)
            TextEditor(text: $customPrompt)
                .font(.system(.body))
                .frame(height: 64)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
            Text(L("settings.prompt.note"))
                .font(.caption)
                .foregroundColor(.secondary)

            Text(L("settings.hintWords.label"))
                .fontWeight(.medium)
            TextEditor(text: $hintWordsRaw)
                .font(.system(.body, design: .monospaced))
                .frame(height: 64)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
            Text(L("settings.hintWords.note"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("settings.section.hotkey"))
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                Text(L("settings.hotkey.label"))
                    .fontWeight(.medium)

                Text(isCapturingHotkey ? L("settings.hotkey.capturing") : hotkeyDisplay)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isCapturingHotkey ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                Button(L("settings.hotkey.capture")) {
                    isCapturingHotkey ? endHotkeyCapture() : beginHotkeyCapture()
                }
            }

            Text(L("settings.hotkey.note"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("settings.section.general"))
                .font(.title3)
                .fontWeight(.semibold)

            Toggle(L("settings.launchAtLogin"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        launchAtLoginError = nil
                    } catch {
                        launchAtLoginError = L("settings.launchAtLogin.error")
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            if let errorText = launchAtLoginError {
                Text(errorText)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()

            if showSavedAlert {
                Text(L("settings.saved"))
                    .foregroundColor(.green)
                    .font(.subheadline)
                    .transition(.opacity)
            }

            Button(action: save) {
                Text(L("settings.save"))
                    .frame(width: 90)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Hotkey capture

    private var hotkeyDisplay: String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifiers))
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        let keyName = Key(carbonKeyCode: UInt32(hotkeyKeyCode)).map { String(describing: $0).uppercased() } ?? "?"
        return symbols + " " + keyName
    }

    private func beginHotkeyCapture() {
        isCapturingHotkey = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc cancels
                endHotkeyCapture()
                return nil
            }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isEmpty else { return nil } // a global hotkey needs a modifier
            hotkeyKeyCode = Int(event.keyCode)
            hotkeyModifiers = Int(mods.rawValue)
            endHotkeyCapture()
            return nil
        }
    }

    private func endHotkeyCapture() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        isCapturingHotkey = false
    }

    // MARK: - Save

    private func save() {
        Configuration.shared.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Configuration.shared.modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        Configuration.shared.customPrompt = customPrompt
        Configuration.shared.hintWordsRaw = hintWordsRaw
        Configuration.shared.hotkeyKeyCode = hotkeyKeyCode
        Configuration.shared.hotkeyModifiers = hotkeyModifiers

        // Re-register the hotkey right away (B3: settings used to be display-only).
        NotificationCenter.default.post(name: .hotkeyConfigurationChanged, object: nil)

        showSavedAlert = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showSavedAlert = false
        }
    }
}

#Preview {
    SettingsView()
}
