import Foundation
@preconcurrency import WhisperKit

/// On-device transcription backend using WhisperKit (ANE + GPU optimised).
/// Actor guarantees that the pipeline is loaded and swapped atomically — a
/// concurrent transcription call will await the load rather than racing.
public actor WhisperProvider: TranscriptionProvider {
    public static let shared = WhisperProvider()

    private var pipeline: WhisperKit?
    private var loadedModelId: String?

    // MARK: - Model catalogue

    public struct ModelEntry {
        public let displayName: String
        public let modelId: String
        public let approximateSize: String
    }

    public static let supportedModels: [ModelEntry] = [
        ModelEntry(displayName: "Tiny",           modelId: "tiny",                                           approximateSize: "~39 MB"),
        ModelEntry(displayName: "Base",            modelId: "base",                                           approximateSize: "~74 MB"),
        ModelEntry(displayName: "Small",           modelId: "small",                                          approximateSize: "~244 MB"),
        ModelEntry(displayName: "Medium",          modelId: "medium",                                         approximateSize: "~769 MB"),
        ModelEntry(displayName: "Large v3 Turbo", modelId: "openai_whisper-large-v3-v20240930_turbo_632MB", approximateSize: "~632 MB"),
        ModelEntry(displayName: "Large v3",        modelId: "openai_whisper-large-v3-v20240930_626MB",       approximateSize: "~626 MB"),
    ]

    // MARK: - TranscriptionProvider

    public nonisolated var preferredAudioFormat: AudioFormatPreference { .standard }

    // Known Whisper hallucination phrases collected from the community.
    // These phrases appear when the model is uncertain about the content and
    // falls back to high-frequency strings from its training corpus.
    private static let hallucinationPhrases: [String] = [
        "Thank you.",
        "Thanks for watching.",
        "Thank you for watching.",
        "Please subscribe",
        "请不吝点赞",
        "明镜与点点",
        "订阅转发",
        "点赞订阅",
        "感谢观看",
        "字幕由",
        "[BLANK_AUDIO]",
        "(ambient music)",
        "(upbeat music)",
    ]

    private static func isHallucination(_ text: String) -> Bool {
        let normalised = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return hallucinationPhrases.contains { normalised.contains($0) }
    }

    public func transcribe(audioURL: URL, settings: ProviderSettings) async throws -> String {
        trace("transcribe called, model=\(settings.modelName), audioURL=\(audioURL.lastPathComponent)")
        let pipe = try await loadPipeline(modelId: settings.modelName)
        trace("pipeline ready")

        var options = DecodingOptions()
        options.task = .transcribe
        // Force Chinese context to prevent "Thank you." English hallucination on quantised models.
        // Whisper handles Chinese-English code-switching correctly with language="zh".
        options.language = "zh"
        options.detectLanguage = false
        options.skipSpecialTokens = true

        // Quality gate: reject segments where the model has low average
        // log-probability (uncertain). Default is -1.0; -0.7 is a reasonable
        // strictness for Chinese without being overly aggressive.
        options.logProbThreshold = -0.7
        // Temperature fallback: one retry at T=0.2 if the first greedy pass
        // fails the quality gate. More retries multiply latency × passes.
        options.temperatureIncrementOnFallback = 0.2
        options.temperatureFallbackCount = 1

        // Note: We intentionally do NOT set promptTokens. Whisper's
        // conditioning prompt mechanism expects natural text (previous
        // transcription context) — LLM-style instruction prompts confuse
        // the decoder and degrade quality. The language="zh" setting is
        // sufficient to establish Chinese dictation context.

        let results: [TranscriptionResult]
        do {
            results = try await pipe.transcribe(audioPath: audioURL.path, decodeOptions: options)
            trace("transcribe returned \(results.count) results")
        } catch {
            trace("transcribe threw: \(error)")
            throw TranscriptionError.requestFailed(underlying: error)
        }

        for (i, r) in results.enumerated() {
            trace("result[\(i)].text='\(r.text)' segments=\(r.segments.count)")
        }

        let text = results.compactMap { $0.text }
                          .joined(separator: " ")
                          .trimmingCharacters(in: .whitespacesAndNewlines)
        trace("joined text length=\(text.count) preview='\(text.prefix(80))'")
        if results.contains(where: { !$0.text.isEmpty }) && text.isEmpty {
            trace("WARNING: non-empty segments produced empty joined text (likely separator issue)")
        }
        if results.allSatisfy({ $0.text.isEmpty || $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            trace("WARNING: all segments returned empty text — possible quality-gate rejection or silent audio")
        }

        if WhisperProvider.isHallucination(text) {
            trace("hallucination detected, discarding: '\(text)'")
            throw TranscriptionError.emptyResponse
        }

        guard !text.isEmpty else { throw TranscriptionError.emptyResponse }
        return text
    }

    // MARK: - Pipeline management

    private func loadPipeline(modelId: String) async throws -> WhisperKit {
        if let existing = pipeline, loadedModelId == modelId {
            trace("pipeline cache hit: \(modelId)")
            return existing
        }
        trace("loading model: \(modelId)")
        do {
            // Use saved local folder path to avoid metadata network requests (works offline).
            let config: WhisperKitConfig
            if let savedPath = WhisperProvider.savedModelPath(for: modelId) {
                trace("using saved modelFolder: \(savedPath)")
                config = WhisperKitConfig(modelFolder: savedPath)
            } else {
                // Fallback: resolve from network (requires connectivity).
                let endpoint = Configuration.shared.whisperUseMirror
                    ? Configuration.huggingFaceMirrorEndpoint
                    : "https://huggingface.co"
                trace("no saved path, using endpoint: \(endpoint)")
                config = WhisperKitConfig(model: modelId, modelEndpoint: endpoint)
            }
            let pipe = try await WhisperKit(config)
            self.pipeline = pipe
            self.loadedModelId = modelId
            trace("model loaded OK")
            return pipe
        } catch let error as WhisperError {
            trace("WhisperError loading model: \(error)")
            throw TranscriptionError.modelLoadFailed(underlying: error)
        } catch {
            trace("model load FAILED: \(error)")
            throw TranscriptionError.modelLoadFailed(underlying: error)
        }
    }

    // MARK: - Trace logging

    private static func trace(_ msg: String) {
        let line = "\(Date()): [WhisperProvider] \(msg)\n"
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

    private nonisolated func trace(_ msg: String) {
        Self.trace(msg)
    }

    // MARK: - Model download (called from Settings UI)

    /// Downloads the model by listing files via the plain JSON API and downloading
    /// each file individually with URLSession.
    ///
    /// This bypasses swift-transformers' HubApi.download() which requires an
    /// X-Repo-Commit response header that hf-mirror.com does not return.
    public static func downloadModel(
        modelId: String,
        onProgress: @escaping @MainActor (Double) -> Void
    ) async throws {
        // Short IDs (base, small, …) map to openai_whisper-{id} folders in the repo.
        let repoFolder = (modelId.hasPrefix("openai_whisper-") || modelId.hasPrefix("distil-"))
            ? modelId : "openai_whisper-\(modelId)"

        // 1. Resolve model files from HuggingFace API.
        //    Try huggingface.co first, then fall back to hf-mirror.com for users
        //    behind the GFW who can access the mirror API listing.
        let modelFiles = try await resolveModelFiles(repoFolder: repoFolder)

        // 2. Prepare local target directory (~/Documents/huggingface/…).
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let targetPath = "\(home)/Documents/huggingface/models/argmaxinc/whisperkit-coreml/\(repoFolder)"
        try FileManager.default.createDirectory(atPath: targetPath, withIntermediateDirectories: true)

        // 3. Download each file from the configured endpoint.
        let downloadEndpoint = Self.downloadEndpoint()
        let total = Double(modelFiles.count)
        for (i, repoPath) in modelFiles.enumerated() {
            let relative = String(repoPath.dropFirst(repoFolder.count + 1))
            let destURL = URL(fileURLWithPath: targetPath).appendingPathComponent(relative)

            if !FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let encoded = repoPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repoPath
                let srcURL = URL(string: "\(downloadEndpoint)/argmaxinc/whisperkit-coreml/resolve/main/\(encoded)")!

                // Download with retry: up to 2 attempts per file on network failure.
                var lastError: Error?
                for attempt in 1...2 {
                    do {
                        let (tmp, response) = try await URLSession.shared.download(from: srcURL)
                        guard let httpResponse = response as? HTTPURLResponse,
                              (200...299).contains(httpResponse.statusCode) else {
                            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                            throw NSError(domain: "WhisperProvider", code: code,
                                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(code) for \(relative)"])
                        }
                        if FileManager.default.fileExists(atPath: destURL.path) {
                            try FileManager.default.removeItem(at: destURL)
                        }
                        try FileManager.default.moveItem(at: tmp, to: destURL)
                        lastError = nil
                        break
                    } catch {
                        lastError = error
                        Self.trace("download attempt \(attempt)/2 failed for \(relative): \(error.localizedDescription)")
                        if attempt < 2 { try await Task.sleep(nanoseconds: 2_000_000_000) }
                    }
                }
                if let error = lastError { throw error }
            }
            await MainActor.run { onProgress(Double(i + 1) / total) }
        }

        // 4. Record local path so WhisperKit loads offline next time.
        saveModelPath(targetPath, for: modelId)
        markDownloaded(modelId)
        Self.trace("downloadModel finished: \(modelId) → \(targetPath)")
    }

    /// Lists model files from the HuggingFace JSON API, trying official and mirror endpoints.
    private static func resolveModelFiles(repoFolder: String) async throws -> [String] {
        let apiCandidates: [(name: String, url: URL)] = [
            ("huggingface.co",
             URL(string: "https://huggingface.co/api/models/argmaxinc/whisperkit-coreml/revision/main")!),
            ("hf-mirror.com",
             URL(string: "https://hf-mirror.com/api/models/argmaxinc/whisperkit-coreml/revision/main")!),
        ]

        var lastError: Error?
        for (name, url) in apiCandidates {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw NSError(domain: "WhisperProvider", code: code,
                                  userInfo: [NSLocalizedDescriptionKey: "API HTTP \(code) from \(name)"])
                }
                let json = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                let files = ((json["siblings"] as? [[String: Any]]) ?? [])
                    .compactMap { $0["rfilename"] as? String }
                    .filter { $0.hasPrefix("\(repoFolder)/") }
                if !files.isEmpty {
                    Self.trace("resolveModelFiles: \(name) returned \(files.count) files for \(repoFolder)")
                    return files
                }
                lastError = NSError(domain: "WhisperProvider", code: 2,
                                    userInfo: [NSLocalizedDescriptionKey: "No files for \(repoFolder) at \(name)"])
            } catch {
                lastError = error
                Self.trace("resolveModelFiles: \(name) failed: \(error.localizedDescription), trying next…")
                continue
            }
        }
        throw lastError ?? NSError(domain: "WhisperProvider", code: 3,
                                    userInfo: [NSLocalizedDescriptionKey: "Could not resolve model files for \(repoFolder)"])
    }

    /// Resolves the file-download base endpoint (mirror-aware).
    private static func downloadEndpoint() -> String {
        return (Configuration.shared.whisperUseMirror
            ? Configuration.huggingFaceMirrorEndpoint
            : "https://huggingface.co")
            .trimmingCharacters(in: .init(charactersIn: "/"))
    }

    // MARK: - Download-state and path tracking (UserDefaults)

    internal static func readyKey(for modelId: String) -> String {
        "PressTalk_WhisperReady_\(modelId.replacingOccurrences(of: "/", with: "_"))"
    }

    private static func pathKey(for modelId: String) -> String {
        "PressTalk_WhisperPath_\(modelId.replacingOccurrences(of: "/", with: "_"))"
    }

    public static func isDownloaded(_ modelId: String) -> Bool {
        UserDefaults.standard.bool(forKey: readyKey(for: modelId))
    }

    public static func markDownloaded(_ modelId: String) {
        UserDefaults.standard.set(true, forKey: readyKey(for: modelId))
    }

    /// Clears cached download state so a model can be re-downloaded from scratch.
    public static func clearDownloadState(_ modelId: String) {
        UserDefaults.standard.removeObject(forKey: readyKey(for: modelId))
        UserDefaults.standard.removeObject(forKey: pathKey(for: modelId))
    }

    private static func saveModelPath(_ path: String, for modelId: String) {
        UserDefaults.standard.set(path, forKey: pathKey(for: modelId))
    }

    /// Returns a local model path if one exists, checking UserDefaults first,
    /// then falling back to expected WhisperKit cache directories.
    public static func savedModelPath(for modelId: String) -> String? {
        // 1. Check UserDefaults (set on every successful download).
        if let path = UserDefaults.standard.string(forKey: pathKey(for: modelId)),
           FileManager.default.fileExists(atPath: path) {
            return path
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folderName = (modelId.hasPrefix("openai_whisper-") || modelId.hasPrefix("distil-")) ? modelId : "openai_whisper-\(modelId)"

        // 2. Fallback: custom download path (~/Documents/huggingface/…)
        let docsPath = "\(home)/Documents/huggingface/models/argmaxinc/whisperkit-coreml/\(folderName)"
        if FileManager.default.fileExists(atPath: docsPath) {
            saveModelPath(docsPath, for: modelId)
            markDownloaded(modelId)
            return docsPath
        }

        // 3. Fallback: WhisperKit native cache path (~/Library/Caches/huggingface/…)
        let cachePaths = [
            "\(home)/Library/Caches/huggingface/models/argmaxinc/whisperkit-coreml/\(folderName)",
            "\(home)/Library/Caches/huggingface/argmaxinc/whisperkit-coreml/\(folderName)",
        ]
        for candidate in cachePaths {
            if FileManager.default.fileExists(atPath: candidate) {
                saveModelPath(candidate, for: modelId)
                markDownloaded(modelId)
                return candidate
            }
        }
        return nil
    }

    // MARK: - Factory helpers for tests

    /// Creates a `WhisperKitConfig` with pre-filled sensible defaults.
    internal static func makeConfig(modelId: String, modelFolder: String?) -> WhisperKitConfig {
        let config = WhisperKitConfig(
            model: modelId,
            modelEndpoint: downloadEndpoint(),
            modelFolder: modelFolder,
            prewarm: false,
            load: false,
            download: modelFolder == nil  // only download when no local folder
        )
        config.verbose = false
        config.logLevel = Logging.LogLevel.error
        return config
    }
}
