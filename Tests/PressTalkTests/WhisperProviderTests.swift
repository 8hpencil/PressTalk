import XCTest
@testable import PressTalk

final class WhisperProviderTests: XCTestCase {

    // MARK: - ProviderType serialization

    func testProviderTypeRoundTrip() {
        XCTAssertEqual(ProviderType(rawValue: "gemini"), .gemini)
        XCTAssertEqual(ProviderType(rawValue: "whisper"), .whisper)
        XCTAssertNil(ProviderType(rawValue: "unknown"))
        XCTAssertEqual(ProviderType.gemini.rawValue, "gemini")
        XCTAssertEqual(ProviderType.whisper.rawValue, "whisper")
    }

    // MARK: - Configuration defaults

    func testTranscriptionProviderDefaultsToGemini() {
        let config = Configuration(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertEqual(config.transcriptionProvider, .gemini)
    }

    func testWhisperModelDefaultsToBase() {
        let config = Configuration(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertEqual(config.whisperModelName, Configuration.defaultWhisperModel)
    }

    func testTranscriptionProviderPersists() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let config = Configuration(defaults: defaults)
        config.transcriptionProvider = .whisper
        let config2 = Configuration(defaults: defaults)
        XCTAssertEqual(config2.transcriptionProvider, .whisper)
    }

    func testWhisperModelNamePersists() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let config = Configuration(defaults: defaults)
        config.whisperModelName = "openai/whisper-small"
        let config2 = Configuration(defaults: defaults)
        XCTAssertEqual(config2.whisperModelName, "openai/whisper-small")
    }

    // MARK: - Model catalogue

    func testSupportedModelsNotEmpty() {
        XCTAssertFalse(WhisperProvider.supportedModels.isEmpty)
    }

    func testDefaultModelIsInCatalogue() {
        let ids = WhisperProvider.supportedModels.map(\.modelId)
        XCTAssertTrue(ids.contains(Configuration.defaultWhisperModel))
    }

    // MARK: - Download state tracking

    func testIsDownloadedFalseByDefault() {
        let fakeId = "openai/whisper-test-\(UUID().uuidString)"
        XCTAssertFalse(WhisperProvider.isDownloaded(fakeId))
    }

    func testMarkDownloadedPersists() {
        let fakeId = "openai/whisper-test-\(UUID().uuidString)"
        XCTAssertFalse(WhisperProvider.isDownloaded(fakeId))
        WhisperProvider.markDownloaded(fakeId)
        XCTAssertTrue(WhisperProvider.isDownloaded(fakeId))
        // Cleanup
        let key = "PressTalk_WhisperReady_\(fakeId.replacingOccurrences(of: "/", with: "_"))"
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Error coverage

    func testModelLoadFailedCaseName() {
        let err = TranscriptionError.modelLoadFailed(underlying: NSError(domain: "test", code: 42))
        XCTAssertEqual(err.caseName, "modelLoadFailed")
        XCTAssertNotNil(err.errorDescription)
    }
}
