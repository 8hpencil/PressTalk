import XCTest
@testable import PressTalk

final class GeminiProviderTests: XCTestCase {
    private var audioURL: URL!
    private let audioBytes: [UInt8] = [0x52, 0x49, 0x46, 0x46, 0x00, 0x01]

    override func setUpWithError() throws {
        try super.setUpWithError()
        MockURLProtocol.reset()
        audioURL = try writeTempAudioFile(audioBytes)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: audioURL)
        MockURLProtocol.reset()
        try super.tearDownWithError()
    }

    private var settings: ProviderSettings {
        ProviderSettings(modelName: "gemini-2.5-flash", prompt: "transcribe with 炭滤池")
    }

    // MARK: Request construction (A2, U6)

    func testRequestCarriesKeyInHeaderNotURL() async throws {
        let provider = makeMockedProvider()
        MockURLProtocol.handler = { _ in (httpResponse(200), geminiSuccessBody(text: "ok")) }

        _ = try await provider.transcribe(audioURL: audioURL, settings: settings)

        let request = try XCTUnwrap(MockURLProtocol.seenRequests.first)
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertFalse(url.contains("key="), "API key must never appear in the URL (A2)")
        XCTAssertTrue(url.contains("gemini-2.5-flash"), "model name comes from settings")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test-api-key")
    }

    func testPayloadContainsAudioAndPrompt() async throws {
        let provider = makeMockedProvider()
        MockURLProtocol.handler = { _ in (httpResponse(200), geminiSuccessBody(text: "ok")) }

        _ = try await provider.transcribe(audioURL: audioURL, settings: settings)

        struct Body: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    struct Inline: Decodable {
                        let mimeType: String
                        let data: String
                    }
                    let inlineData: Inline?
                    let text: String?
                }
                let parts: [Part]
            }
            let contents: [Content]
        }

        let body = try XCTUnwrap(MockURLProtocol.seenRequests.first?.httpBody)
        let parts = try XCTUnwrap(JSONDecoder().decode(Body.self, from: body).contents.first?.parts)
        XCTAssertEqual(parts.first?.inlineData?.mimeType, "audio/wav")
        XCTAssertEqual(parts.first?.inlineData?.data, Data(audioBytes).base64EncodedString(),
                       "audio travels as inline base64")
        XCTAssertEqual(parts.last?.text, "transcribe with 炭滤池",
                       "assembled prompt is sent alongside audio")
    }

    func testSuccessReturnsTrimmedText() async throws {
        let provider = makeMockedProvider()
        MockURLProtocol.handler = { _ in (httpResponse(200), geminiSuccessBody(text: "  你好 world\\n")) }

        let text = try await provider.transcribe(audioURL: audioURL, settings: settings)
        XCTAssertEqual(text, "你好 world")
    }

    func testMissingKeyFailsBeforeAnyRequest() async {
        let provider = makeMockedProvider()
        provider.apiKeyProvider = { "  " }
        MockURLProtocol.handler = { _ in (httpResponse(200), geminiSuccessBody(text: "ok")) }

        await assertThrows(.missingAPIKey) {
            _ = try await provider.transcribe(audioURL: self.audioURL, settings: self.settings)
        }
        XCTAssertTrue(MockURLProtocol.seenRequests.isEmpty)
    }

    // MARK: Error grading (E1)

    func testUnauthorizedIsNeverRetried() async {
        let provider = makeMockedProvider()
        MockURLProtocol.handler = { _ in (httpResponse(401), Data()) }

        await assertThrows(.invalidAPIKey) {
            _ = try await provider.transcribe(audioURL: self.audioURL, settings: self.settings)
        }
        XCTAssertEqual(MockURLProtocol.seenRequests.count, 1, "401 must not be retried")
    }

    func testPlainClientErrorIsNeverRetried() async {
        let provider = makeMockedProvider()
        MockURLProtocol.handler = { _ in (httpResponse(400), Data()) }

        await assertThrows(.serverError(statusCode: 400)) {
            _ = try await provider.transcribe(audioURL: self.audioURL, settings: self.settings)
        }
        XCTAssertEqual(MockURLProtocol.seenRequests.count, 1)
    }

    func testRateLimitRetriesHonoringRetryAfter() async throws {
        let provider = makeMockedProvider()
        let delays = DelayRecorder()
        provider.sleeper = { await delays.record($0) }

        let counter = Counter()
        MockURLProtocol.handler = { _ in
            if counter.next() < 3 {
                return (httpResponse(429, headers: ["Retry-After": "2"]), Data())
            }
            return (httpResponse(200), geminiSuccessBody(text: "after retries"))
        }

        let text = try await provider.transcribe(audioURL: audioURL, settings: settings)
        XCTAssertEqual(text, "after retries")
        XCTAssertEqual(MockURLProtocol.seenRequests.count, 3)
        let recorded = await delays.values
        XCTAssertEqual(recorded, [2.0, 2.0], "Retry-After header dictates the backoff")
    }

    func testRateLimitExhaustionThrows() async {
        let provider = makeMockedProvider()
        MockURLProtocol.handler = { _ in (httpResponse(429), Data()) }

        await assertThrows(.rateLimited) {
            _ = try await provider.transcribe(audioURL: self.audioURL, settings: self.settings)
        }
        XCTAssertEqual(MockURLProtocol.seenRequests.count, 3, "429 retries are capped at maxAttempts")
    }

    func testTransientServerErrorRetriesThenSucceeds() async throws {
        let provider = makeMockedProvider()
        let counter = Counter()
        MockURLProtocol.handler = { _ in
            if counter.next() < 2 {
                return (httpResponse(503), Data())
            }
            return (httpResponse(200), geminiSuccessBody(text: "recovered"))
        }

        let text = try await provider.transcribe(audioURL: audioURL, settings: settings)
        XCTAssertEqual(text, "recovered")
        XCTAssertEqual(MockURLProtocol.seenRequests.count, 2)
    }

    // MARK: Response parsing

    func testEmptyCandidatesThrowsEmptyResponse() async {
        let provider = makeMockedProvider()
        MockURLProtocol.handler = { _ in (httpResponse(200), Data(#"{"candidates":[]}"#.utf8)) }

        await assertThrows(.emptyResponse) {
            _ = try await provider.transcribe(audioURL: self.audioURL, settings: self.settings)
        }
    }

    func testGarbageBodyThrowsParsingError() async {
        let provider = makeMockedProvider()
        MockURLProtocol.handler = { _ in (httpResponse(200), Data("not json".utf8)) }

        await assertThrows(.parsingError) {
            _ = try await provider.transcribe(audioURL: self.audioURL, settings: self.settings)
        }
    }

    // MARK: Helpers

    private func assertThrows(
        _ expected: TranscriptionError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected.caseName) to be thrown", file: file, line: line)
        } catch let error as TranscriptionError {
            XCTAssertEqual(error.caseName, expected.caseName, file: file, line: line)
        } catch {
            XCTFail("unexpected error type: \(error)", file: file, line: line)
        }
    }
}

/// Thread-safe response counter for sequential mock responses.
private final class Counter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private actor DelayRecorder {
    private(set) var values: [TimeInterval] = []

    func record(_ delay: TimeInterval) {
        values.append(delay)
    }
}
