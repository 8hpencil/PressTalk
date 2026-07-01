import SwiftUI
import ServiceManagement
import HotKey
@preconcurrency import WhisperKit

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
    @State private var selectedProvider: ProviderType = Configuration.shared.transcriptionProvider
    @State private var gcpApiKey: String = Configuration.shared.gcpApiKey
    @State private var gcpProjectId: String = Configuration.shared.gcpProjectId
    @State private var gcpLocation: String = Configuration.shared.gcpLocation
    @State private var gcpModelName: String = Configuration.shared.gcpModelName
    @State private var whisperModel: String = Configuration.shared.whisperModelName
    @State private var whisperUseMirror: Bool = Configuration.shared.whisperUseMirror
    @State private var downloadProgress: Double = 0
    @State private var isDownloading: Bool = false
    @State private var downloadError: String?
    @State private var downloadedModels: Set<String> = {
        Set(WhisperProvider.supportedModels.map(\.modelId).filter { WhisperProvider.savedModelPath(for: $0) != nil })
    }()
    @State private var localASRApiUrl: String = Configuration.shared.localASRApiUrl

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
        .frame(width: 560, height: 700)
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

            // Provider picker
            VStack(alignment: .leading, spacing: 6) {
                Text(L("settings.provider.label"))
                    .fontWeight(.medium)
                Picker("", selection: $selectedProvider) {
                    Text(L("settings.provider.gemini")).tag(ProviderType.gemini)
                    Text(L("settings.provider.gcpChirp")).tag(ProviderType.gcpChirp)
                    Text(L("settings.provider.whisper")).tag(ProviderType.whisper)
                    Text(L("settings.provider.localASR")).tag(ProviderType.localASR)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
            }

            Divider().padding(.vertical, 2)

            if selectedProvider == .gemini {
                geminiFields
            } else if selectedProvider == .gcpChirp {
                gcpChirpFields
            } else if selectedProvider == .whisper {
                whisperFields
            } else {
                localASRFields
            }

            // Shared: prompt + hint words apply to both providers
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

    private var localASRFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("settings.localASR.apiUrl.label"))
                .fontWeight(.medium)
            TextField(L("settings.localASR.apiUrl.placeholder"), text: $localASRApiUrl)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            Text(L("settings.localASR.privacy.note"))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var geminiFields: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                Text(L("settings.model.label"))
                    .fontWeight(.medium)
                TextField(Configuration.defaultModelName, text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: 260)
            }
        }
    }

    private var gcpChirpFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("settings.gcp.apiKey.label"))
                .fontWeight(.medium)
            SecureField(L("settings.gcp.apiKey.placeholder"), text: $gcpApiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            Text(L("settings.gcp.projectId.label"))
                .fontWeight(.medium)
            TextField(L("settings.gcp.projectId.placeholder"), text: $gcpProjectId)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("settings.gcp.location.label"))
                        .fontWeight(.medium)
                    TextField("us-central1", text: $gcpLocation)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("settings.gcp.modelName.label"))
                        .fontWeight(.medium)
                    TextField(Configuration.defaultGcpModelName, text: $gcpModelName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }

            Text(L("settings.gcp.privacy.note"))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var whisperFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("settings.whisper.privacy.note"))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("settings.whisperModel.label"))
                        .fontWeight(.medium)
                    Picker("", selection: $whisperModel) {
                        ForEach(WhisperProvider.supportedModels, id: \.modelId) { entry in
                            HStack {
                                Text(entry.displayName)
                                Text(entry.approximateSize)
                                    .foregroundColor(.secondary)
                            }
                            .tag(entry.modelId)
                        }
                    }
                    .frame(maxWidth: 260)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    if downloadedModels.contains(whisperModel) {
                        Label(L("settings.whisperModel.ready"), systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.subheadline)
                    } else if isDownloading {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(L("settings.whisperModel.downloading"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ProgressView(value: downloadProgress)
                                .frame(width: 120)
                            Text(String(format: "%.0f%%", downloadProgress * 100))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button(L("settings.whisperModel.download")) {
                            startDownload()
                        }
                        .buttonStyle(.bordered)
                    }

                    if let err = downloadError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 160, alignment: .trailing)
                    }
                }
            }

            Toggle(L("settings.whisperModel.useMirror"), isOn: $whisperUseMirror)
            Text(L("settings.whisperModel.mirrorNote"))
                .font(.caption)
                .foregroundColor(.secondary)
                .onChange(of: whisperModel) { _, _ in
                    downloadError = nil
                }

            Text(L("settings.whisperModel.storageNote"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func startDownload() {
        isDownloading = true
        downloadError = nil
        downloadProgress = 0
        let modelId = whisperModel
        // Clear stale download state so a failed/corrupted download gets retried fresh.
        WhisperProvider.clearDownloadState(modelId)
        Task {
            do {
                try await WhisperProvider.downloadModel(modelId: modelId) { @MainActor fraction in
                    downloadProgress = fraction
                }
                downloadedModels.insert(modelId)
            } catch {
                downloadError = error.localizedDescription
            }
            isDownloading = false
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
                .onChange(of: launchAtLogin) { _, enabled in
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
        Configuration.shared.transcriptionProvider = selectedProvider
        Configuration.shared.gcpApiKey = gcpApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Configuration.shared.gcpProjectId = gcpProjectId.trimmingCharacters(in: .whitespacesAndNewlines)
        Configuration.shared.gcpLocation = gcpLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        Configuration.shared.gcpModelName = gcpModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        Configuration.shared.whisperModelName = whisperModel
        Configuration.shared.whisperUseMirror = whisperUseMirror
        Configuration.shared.localASRApiUrl = localASRApiUrl.trimmingCharacters(in: .whitespacesAndNewlines)

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
