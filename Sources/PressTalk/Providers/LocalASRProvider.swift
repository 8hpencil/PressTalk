import Foundation

/// On-premise ASR service provider (e.g. SenseVoice-Small running locally on Windows/Linux).
public final class LocalASRProvider: TranscriptionProvider {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config)
    }

    public func transcribe(audioURL: URL, settings: ProviderSettings) async throws -> String {
        let apiUrlString = Configuration.shared.localASRApiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: apiUrlString) else {
            throw TranscriptionError.serverError(statusCode: 0)
        }

        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw TranscriptionError.invalidAudioData
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("sensevoice\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TranscriptionError.serverError(statusCode: 0)
            }

            guard http.statusCode == 200 else {
                throw TranscriptionError.serverError(statusCode: http.statusCode)
            }

            struct LocalResponse: Codable {
                let text: String
            }
            guard let localResult = try? JSONDecoder().decode(LocalResponse.self, from: data) else {
                throw TranscriptionError.parsingError
            }
            return localResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw TranscriptionError.requestFailed(underlying: error)
        }
    }
}
