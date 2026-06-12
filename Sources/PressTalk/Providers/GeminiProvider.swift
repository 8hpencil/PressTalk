import Foundation

/// Gemini transcription backend (migrated from GeminiSTTClient in U6).
public final class GeminiProvider: TranscriptionProvider {
    private static let maxAttempts = 3

    private let session: URLSession
    /// Injectable for tests; production reads the shared Configuration.
    var apiKeyProvider: () -> String = { Configuration.shared.apiKey }
    /// Injectable for tests so retry paths don't sleep for real.
    var sleeper: (TimeInterval) async -> Void = { delay in
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    public init() {
        let config = URLSessionConfiguration.ephemeral
        // Dual timeouts (E1/R3): 30 s idle, 120 s total — the resource timeout
        // must accommodate a 5-minute recording (~12.8 MB base64) on a slow
        // uplink, so do NOT collapse this into a single 30 s total timeout.
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config)
    }

    init(session: URLSession) {
        self.session = session
    }

    // Request payload structures
    private struct RequestPayload: Codable {
        let contents: [Content]
    }

    private struct Content: Codable {
        let parts: [Part]
    }

    private struct Part: Codable {
        let inlineData: InlineData?
        let text: String?

        init(mimeType: String, base64Data: String) {
            self.inlineData = InlineData(mimeType: mimeType, data: base64Data)
            self.text = nil
        }

        init(text: String) {
            self.inlineData = nil
            self.text = text
        }
    }

    private struct InlineData: Codable {
        let mimeType: String
        let data: String
    }

    // Response payload structures
    private struct ResponsePayload: Codable {
        let candidates: [Candidate]?
    }

    private struct Candidate: Codable {
        let content: ResponseContent?
    }

    private struct ResponseContent: Codable {
        let parts: [ResponsePart]?
    }

    private struct ResponsePart: Codable {
        let text: String?
    }

    public func transcribe(audioURL: URL, settings: ProviderSettings) async throws -> String {
        let apiKey = apiKeyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw TranscriptionError.missingAPIKey
        }

        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw TranscriptionError.invalidAudioData
        }

        let payload = RequestPayload(contents: [
            Content(parts: [
                Part(mimeType: "audio/wav", base64Data: audioData.base64EncodedString()),
                Part(text: settings.prompt)
            ])
        ])

        guard let jsonData = try? JSONEncoder().encode(payload) else {
            throw TranscriptionError.invalidAudioData
        }

        // API key travels in a header, never in the URL: query strings end up
        // in proxy and server logs (A2).
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(settings.modelName):generateContent") else {
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

            // Error grading (E1): 401/403 and other 4xx are never retried;
            // 429 retries honoring Retry-After; only 503/504 of the 5xx
            // family are treated as transient.
            switch http.statusCode {
            case 200:
                return try parse(data)
            case 401, 403:
                throw TranscriptionError.invalidAPIKey
            case 429 where attempt < Self.maxAttempts:
                retryDelay = retryAfterSeconds(from: http) ?? Double(attempt) * 1.5
                Log.stt.warning("Rate limited (429); retrying attempt \(attempt + 1) in \(retryDelay)s")
            case 429:
                throw TranscriptionError.rateLimited
            case 503, 504:
                guard attempt < Self.maxAttempts else {
                    throw TranscriptionError.serverError(statusCode: http.statusCode)
                }
                retryDelay = Double(attempt) * 1.5
                Log.stt.warning("Gemini API transient error \(http.statusCode); retrying attempt \(attempt + 1) in \(retryDelay)s")
            default:
                throw TranscriptionError.serverError(statusCode: http.statusCode)
            }
        } catch let error as TranscriptionError {
            throw error
        } catch {
            guard attempt < Self.maxAttempts else {
                throw TranscriptionError.requestFailed(underlying: error)
            }
            retryDelay = Double(attempt) * 1.5
            // Log the error code only — descriptions can embed the request URL (E6).
            Log.stt.warning("Network error (code \((error as NSError).code)); retrying attempt \(attempt + 1) in \(retryDelay)s")
        }

        await sleeper(retryDelay)
        return try await send(request, attempt: attempt + 1)
    }

    private func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(raw), seconds > 0 else {
            return nil
        }
        return min(seconds, 30) // cap so a hostile header can't stall the app
    }

    private func parse(_ data: Data) throws -> String {
        guard let payload = try? JSONDecoder().decode(ResponsePayload.self, from: data) else {
            throw TranscriptionError.parsingError
        }
        guard let text = payload.candidates?.first?.content?.parts?.first?.text else {
            throw TranscriptionError.emptyResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
