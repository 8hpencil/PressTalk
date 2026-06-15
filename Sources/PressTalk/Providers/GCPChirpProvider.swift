import Foundation

/// GCP Speech-to-Text v2 Chirp provider.
public final class GCPChirpProvider: TranscriptionProvider {
    private static let maxAttempts = 3

    private let session: URLSession
    /// Injectables for tests
    var apiKeyProvider: () -> String = { Configuration.shared.gcpApiKey }
    var projectIdProvider: () -> String = { Configuration.shared.gcpProjectId }
    var locationProvider: () -> String = { Configuration.shared.gcpLocation }
    var sleeper: (TimeInterval) async -> Void = { delay in
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config)
    }

    init(session: URLSession) {
        self.session = session
    }

    // Request payload structures
    private struct RequestPayload: Codable {
        let recognizer: String
        let config: RecognitionConfig
        let content: String
    }

    private struct RecognitionConfig: Codable {
        let autoDecodingConfig: AutoDecodingConfig
        let languageCodes: [String]
        let model: String
        let adaptation: AdaptationConfig?
    }

    private struct AutoDecodingConfig: Codable {}

    private struct AdaptationConfig: Codable {
        let phraseSets: [PhraseSetConfig]
    }

    private struct PhraseSetConfig: Codable {
        let inlinePhraseSet: InlinePhraseSet
    }

    private struct InlinePhraseSet: Codable {
        let phrases: [Phrase]
    }

    private struct Phrase: Codable {
        let value: String
        let boost: Double
    }

    // Response payload structures
    private struct ResponsePayload: Codable {
        let results: [SpeechRecognitionResult]?
    }

    private struct SpeechRecognitionResult: Codable {
        let alternatives: [SpeechRecognitionAlternative]?
    }

    private struct SpeechRecognitionAlternative: Codable {
        let transcript: String?
    }

    public func transcribe(audioURL: URL, settings: ProviderSettings) async throws -> String {
        let apiKey = apiKeyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw TranscriptionError.missingAPIKey
        }

        let projectId = projectIdProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectId.isEmpty else {
            throw TranscriptionError.requestFailed(underlying: NSError(domain: "PressTalk", code: 1001, userInfo: [NSLocalizedDescriptionKey: L("error.gcp.missingProjectId")]))
        }

        let location = locationProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.modelName.isEmpty ? "chirp_3" : settings.modelName

        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw TranscriptionError.invalidAudioData
        }

        let hintWords = Configuration.shared.hintWords
        let adaptation: AdaptationConfig?
        if !hintWords.isEmpty {
            let phrases = hintWords.map { Phrase(value: $0, boost: 20.0) }
            adaptation = AdaptationConfig(phraseSets: [
                PhraseSetConfig(inlinePhraseSet: InlinePhraseSet(phrases: phrases))
            ])
        } else {
            adaptation = nil
        }

        let recognizerPath = "projects/\(projectId)/locations/\(location)/recognizers/_"
        
        let recognitionConfig = RecognitionConfig(
            autoDecodingConfig: AutoDecodingConfig(),
            languageCodes: ["zh-CN", "en-US"],
            model: model,
            adaptation: adaptation
        )

        let payload = RequestPayload(
            recognizer: recognizerPath,
            config: recognitionConfig,
            content: audioData.base64EncodedString()
        )

        guard let jsonData = try? JSONEncoder().encode(payload) else {
            throw TranscriptionError.invalidAudioData
        }

        guard let url = URL(string: "https://speech.googleapis.com/v2/projects/\(projectId)/locations/\(location)/recognizers/_:recognize") else {
            throw TranscriptionError.serverError(statusCode: 0)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = jsonData

        return try await send(request, attempt: 1)
    }

    private func send(_ request: URLRequest, attempt: Int) async throws -> String {
        let retryDelay: TimeInterval
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TranscriptionError.serverError(statusCode: 0)
            }

            switch http.statusCode {
            case 200:
                return try parse(data)
            case 401, 403:
                throw TranscriptionError.invalidAPIKey
            case 429 where attempt < Self.maxAttempts:
                retryDelay = retryAfterSeconds(from: http) ?? Double(attempt) * 1.5
                Log.stt.warning("GCP STT Rate limited (429); retrying attempt \(attempt + 1) in \(retryDelay)s")
            case 429:
                throw TranscriptionError.rateLimited
            case 503, 504:
                guard attempt < Self.maxAttempts else {
                    throw TranscriptionError.serverError(statusCode: http.statusCode)
                }
                retryDelay = Double(attempt) * 1.5
                Log.stt.warning("GCP STT transient error \(http.statusCode); retrying attempt \(attempt + 1) in \(retryDelay)s")
            default:
                if let errorObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorDict = errorObj["error"] as? [String: Any],
                   let message = errorDict["message"] as? String {
                    throw TranscriptionError.requestFailed(underlying: NSError(domain: "GCPSTT", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message]))
                }
                throw TranscriptionError.serverError(statusCode: http.statusCode)
            }
        } catch let error as TranscriptionError {
            throw error
        } catch {
            guard attempt < Self.maxAttempts else {
                throw TranscriptionError.requestFailed(underlying: error)
            }
            retryDelay = Double(attempt) * 1.5
            Log.stt.warning("GCP STT Network error (code \((error as NSError).code)); retrying attempt \(attempt + 1) in \(retryDelay)s")
        }

        await sleeper(retryDelay)
        return try await send(request, attempt: attempt + 1)
    }

    private func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(raw), seconds > 0 else {
            return nil
        }
        return min(seconds, 30)
    }

    private func parse(_ data: Data) throws -> String {
        guard let payload = try? JSONDecoder().decode(ResponsePayload.self, from: data) else {
            throw TranscriptionError.parsingError
        }
        guard let results = payload.results, !results.isEmpty else {
            throw TranscriptionError.emptyResponse
        }
        let transcripts = results.compactMap { $0.alternatives?.first?.transcript }
        guard !transcripts.isEmpty else {
            throw TranscriptionError.emptyResponse
        }
        return transcripts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
