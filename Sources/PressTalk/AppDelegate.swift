import Cocoa
import AVFoundation
import UserNotifications

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var hotkeyManager: HotkeyManager?
    private let audioRecorder = AudioRecorder()
    private let textInsertionEngine = TextInsertionEngine()
    private let stateMachine = DictationStateMachine()
    private var provider: TranscriptionProvider = GeminiProvider()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Setup Menu Bar Status Item
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menuBarController = MenuBarController(statusItem: statusItem)

        // 2. Request Microphone Access
        requestMicrophonePermission()

        // 3. Request User Notifications Access
        requestNotificationPermission()

        // 4. Request Accessibility Permission (Required for text insertion)
        checkAccessibilityPermission()

        // 5. Initialize Hotkey Manager and bind events; re-register whenever
        // settings change the hotkey (B3). Also refresh provider on settings save.
        hotkeyManager = HotkeyManager()
        setupHotkeyBindings()
        refreshProvider()
        NotificationCenter.default.addObserver(
            forName: .hotkeyConfigurationChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hotkeyManager?.registerHotkey()
            self?.refreshProvider()
        }

        // 6. Recording duration cap (U4): warn near the limit, then auto-stop
        // through the same path as a hotkey release.
        audioRecorder.onDurationWarning = { [weak self] in
            self?.menuBarController?.updateState(.recordingWarning)
        }
        audioRecorder.onDurationLimitReached = { [weak self] in
            self?.stopDictationAndTranscribe()
        }

        // 7. Check if API key is configured
        if Configuration.shared.transcriptionProvider == .gemini && Configuration.shared.apiKey.isEmpty {
            sendNotification(title: L("notif.welcome.title"), body: L("notif.welcome.body"))
        } else if Configuration.shared.transcriptionProvider == .gcpChirp && (Configuration.shared.gcpApiKey.isEmpty || Configuration.shared.gcpProjectId.isEmpty) {
            sendNotification(title: L("notif.welcome.title"), body: L("notif.gcp.welcome.body"))
        }
    }

    private func refreshProvider() {
        switch Configuration.shared.transcriptionProvider {
        case .gemini:
            provider = GeminiProvider()
        case .whisper:
            provider = WhisperProvider.shared
        case .gcpChirp:
            provider = GCPChirpProvider()
        }
        Log.app.info("Active provider: \(Configuration.shared.transcriptionProvider.rawValue)")
    }

    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        Log.app.info("Accessibility permission trusted status: \(isTrusted)")
    }

    private func setupHotkeyBindings() {
        hotkeyManager?.onKeyDown = { [weak self] in
            self?.startDictation()
        }

        hotkeyManager?.onKeyUp = { [weak self] in
            self?.stopDictationAndTranscribe()
        }
    }

    private func startDictation() {
        // Guard: check if API key is configured
        if Configuration.shared.transcriptionProvider == .gemini && Configuration.shared.apiKey.isEmpty {
            sendNotification(title: L("notif.noKey.title"), body: L("notif.noKey.body"))
            return
        }
        if Configuration.shared.transcriptionProvider == .gcpChirp {
            if Configuration.shared.gcpApiKey.isEmpty {
                sendNotification(title: L("notif.gcp.noKey.title"), body: L("notif.gcp.noKey.body"))
                return
            }
            if Configuration.shared.gcpProjectId.isEmpty {
                sendNotification(title: L("notif.gcp.noProjectId.title"), body: L("notif.gcp.noProjectId.body"))
                return
            }
        }

        // Guard: Check microphone permissions
        let permission = AVCaptureDevice.authorizationStatus(for: .audio)
        if permission == .denied || permission == .restricted {
            sendNotification(title: L("notif.micDenied.title"), body: L("notif.micDenied.body"))
            return
        }

        switch stateMachine.requestStart() {
        case .ignoredAlreadyRecording:
            return
        case .ignoredTranscriptionInFlight:
            // Default policy (U5): ignore the press, hint briefly.
            menuBarController?.flashBusyHint()
            return
        case .started(let generation):
            menuBarController?.updateState(.recording)
            // Local Whisper has no cloud size limit; allow up to 10 minutes.
            let maxDuration: TimeInterval = Configuration.shared.transcriptionProvider == .whisper ? 600 : 300
            if audioRecorder.startRecording(format: provider.preferredAudioFormat, maxDuration: maxDuration) != nil {
                Log.audio.info("Recording started (generation \(generation), maxDuration \(Int(maxDuration))s)")
            } else {
                stateMachine.recordingFailed(generation: generation)
                menuBarController?.updateState(.idle)
                sendNotification(title: L("notif.recordFailed.title"), body: L("notif.recordFailed.body"))
            }
        }
    }

    private func stopDictationAndTranscribe() {
        // Stray key-up (no active recording, e.g. the duration cap already
        // auto-stopped it) leaves state and UI alone.
        guard let generation = stateMachine.requestStop() else { return }

        guard let audioURL = audioRecorder.stopRecording() else {
            // Recorder disagreed with the state machine; roll back cleanly.
            stateMachine.transcriptionCompleted(generation: generation)
            menuBarController?.updateState(.idle)
            return
        }

        menuBarController?.updateState(.transcribing)
        Log.audio.info("Recording stopped; starting transcription (generation \(generation))")
        transcribe(audioURL, generation: generation)
    }

    /// Single transcription entry point (U5 Patterns): the state machine owns
    /// everything around it; providers only ever change the inside.
    private func transcribe(_ audioURL: URL, generation: Int) {
        let modelName: String
        switch Configuration.shared.transcriptionProvider {
        case .gemini:   modelName = Configuration.shared.modelName
        case .whisper:  modelName = Configuration.shared.whisperModelName
        case .gcpChirp: modelName = Configuration.shared.gcpModelName
        }
        let settings = ProviderSettings(
            modelName: modelName,
            prompt: PromptBuilder.build(
                customPrompt: Configuration.shared.customPrompt,
                hintWords: Configuration.shared.hintWords
            )
        )

        Task { @MainActor [weak self] in
            guard let self = self else { return }

            appTrace("provider type=\(Configuration.shared.transcriptionProvider.rawValue) model=\(settings.modelName)")
            appTrace("audioURL exists=\(FileManager.default.fileExists(atPath: audioURL.path)) size=\((try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? nil as Int? ?? -1)")

            let result: Result<String, TranscriptionError>
            do {
                let text = try await self.provider.transcribe(audioURL: audioURL, settings: settings)
                appTrace("provider returned text length=\(text.count) preview='\(String(text.prefix(50)))'")
                result = .success(text)
            } catch let error as TranscriptionError {
                appTrace("TranscriptionError: \(error.caseName) — \(error.localizedDescription)")
                result = .failure(error)
            } catch {
                appTrace("Unknown error: \(error)")
                result = .failure(.requestFailed(underlying: error))
            }

            // Clean up temp audio file regardless of outcome or staleness.
            self.audioRecorder.cleanup(url: audioURL)

            // Late callbacks from an older generation must not touch UI (B5).
            guard self.stateMachine.transcriptionCompleted(generation: generation) else {
                Log.app.info("Discarding stale transcription callback (generation \(generation))")
                appTrace("stale generation \(generation), discarding")
                return
            }

            switch result {
            case .success(let transcribedText):
                appTrace("success, inserting \(transcribedText.count) chars")
                Log.app.info("Transcription succeeded (\(transcribedText.count) characters)")
                if transcribedText.isEmpty {
                    // E2: don't silently swallow empty results.
                    self.sendNotification(title: L("notif.empty.title"), body: L("notif.empty.body"))
                } else {
                    self.textInsertionEngine.insert(text: transcribedText) { [weak self] success in
                        if !success {
                            // E2: both insertion paths failed — almost always
                            // missing accessibility permission.
                            self?.sendNotification(
                                title: L("notif.insertFailed.title"),
                                body: L("notif.insertFailed.body")
                            )
                        }
                    }
                }

            case .failure(let error):
                // Log only the error kind — descriptions can embed URLs (E6).
                Log.app.error("Transcription failed (\(error.caseName))")
                self.sendNotification(
                    title: L("notif.sttFailed.title"),
                    body: error.localizedDescription
                )
            }

            self.menuBarController?.updateState(.idle)
        }
    }

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Log.app.info("Microphone permission granted: \(granted)")
        }
    }

    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if error != nil {
                Log.app.error("Notification authorization failed")
            } else {
                Log.app.info("Notification permission status: \(granted)")
            }
        }
    }

    func appTrace(_ msg: String) {
        let line = "\(Date()): [AppDelegate] \(msg)\n"
        let path = "/tmp/pt_trace.txt"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    private func sendNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if error != nil {
                Log.app.error("Failed to deliver notification")
            }
        }
    }
}
