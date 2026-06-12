import Foundation
@testable import PressTalk

/// In-memory SecretStore so Configuration tests never touch the real keychain.
final class InMemorySecretStore: SecretStore {
    private(set) var values: [String: String] = [:]

    init(_ values: [String: String] = [:]) {
        self.values = values
    }

    func string(forAccount account: String) -> String? {
        values[account]
    }

    @discardableResult
    func setString(_ value: String, forAccount account: String) -> Bool {
        values[account] = value
        return true
    }

    @discardableResult
    func removeString(forAccount account: String) -> Bool {
        values.removeValue(forKey: account)
        return true
    }
}

/// URLProtocol stub: every request is answered by the current handler.
final class MockURLProtocol: URLProtocol {
    /// Set per test. Receives the request (with body resolved) and returns
    /// the HTTP response payload.
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var seenRequests: [URLRequest] = []

    static func reset() {
        handler = nil
        seenRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        // httpBody is converted to httpBodyStream by URLSession; read it back
        // so tests can assert on the payload.
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            request.httpBody = Data(reading: stream)
        }
        Self.seenRequests.append(request)
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension Data {
    init(reading stream: InputStream) {
        self.init()
        stream.open()
        defer { stream.close() }
        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            append(buffer, count: read)
        }
    }
}

func makeMockedProvider() -> GeminiProvider {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let provider = GeminiProvider(session: URLSession(configuration: config))
    provider.apiKeyProvider = { "test-api-key" }
    provider.sleeper = { _ in }
    return provider
}

func httpResponse(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://generativelanguage.googleapis.com/")!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: headers
    )!
}

func geminiSuccessBody(text: String) -> Data {
    let json = """
    {"candidates":[{"content":{"parts":[{"text":"\(text)"}]}}]}
    """
    return Data(json.utf8)
}

func writeTempAudioFile(_ bytes: [UInt8] = [0x52, 0x49, 0x46, 0x46]) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("presstalk_test_\(UUID().uuidString).wav")
    try Data(bytes).write(to: url)
    return url
}
