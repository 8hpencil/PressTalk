import Foundation

/// Audio format a provider expects (E4). All built-in providers currently use
/// the 16 kHz/mono/16-bit default; there is no resampling or negotiation —
/// providers that need something else are a post-v1 concern (KTD4).
public struct AudioFormatPreference: Equatable {
    public let sampleRate: Double
    public let channels: Int
    public let bitDepth: Int

    public static let standard = AudioFormatPreference(sampleRate: 16000, channels: 1, bitDepth: 16)

    public init(sampleRate: Double, channels: Int, bitDepth: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
    }
}

/// Provider-agnostic transcription errors (E1).
public enum TranscriptionError: Error, LocalizedError {
    case missingAPIKey
    /// 401/403 — the configured key is wrong or revoked. Never retried.
    case invalidAPIKey
    /// 429 — retries (honoring Retry-After) exhausted.
    case rateLimited
    case invalidAudioData
    case requestFailed(underlying: Error)
    case serverError(statusCode: Int)
    case emptyResponse
    case parsingError

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return L("error.missingAPIKey")
        case .invalidAPIKey:
            return L("error.invalidAPIKey")
        case .rateLimited:
            return L("error.rateLimited")
        case .invalidAudioData:
            return L("error.invalidAudioData")
        case .requestFailed(let err):
            return String(format: L("error.requestFailed"), err.localizedDescription)
        case .serverError(let code):
            return String(format: L("error.serverError"), code)
        case .emptyResponse:
            return L("error.emptyResponse")
        case .parsingError:
            return L("error.parsingError")
        }
    }

    /// Stable, URL-free identifier for logging (E6).
    public var caseName: String {
        switch self {
        case .missingAPIKey: return "missingAPIKey"
        case .invalidAPIKey: return "invalidAPIKey"
        case .rateLimited: return "rateLimited"
        case .invalidAudioData: return "invalidAudioData"
        case .requestFailed: return "requestFailed"
        case .serverError(let code): return "serverError(\(code))"
        case .emptyResponse: return "emptyResponse"
        case .parsingError: return "parsingError"
        }
    }
}

/// Per-request settings handed to a provider.
public struct ProviderSettings {
    public let modelName: String
    public let prompt: String

    public init(modelName: String, prompt: String) {
        self.modelName = modelName
        self.prompt = prompt
    }
}

/// A transcription backend (KTD4). Gemini is the first implementation;
/// local whisper.cpp and domestic ASR providers plug in behind the same
/// protocol (whisper.cpp is scheduled for v1.1, see U7).
public protocol TranscriptionProvider {
    var preferredAudioFormat: AudioFormatPreference { get }
    func transcribe(audioURL: URL, settings: ProviderSettings) async throws -> String
}

public extension TranscriptionProvider {
    var preferredAudioFormat: AudioFormatPreference { .standard }
}

/// Assembles the final prompt from the default template, an optional user
/// override, and the user's hint-word list (D6: no more hardcoded prompt).
public enum PromptBuilder {
    /// Localized: the default instruction follows the user's system language.
    public static var defaultPrompt: String { L("prompt.default") }

    public static func build(customPrompt: String, hintWords: [String]) -> String {
        let trimmed = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var prompt = trimmed.isEmpty ? defaultPrompt : trimmed
        if !hintWords.isEmpty {
            prompt += String(format: L("prompt.hintPrefix"), hintWords.joined(separator: "、"))
        }
        return prompt
    }
}
