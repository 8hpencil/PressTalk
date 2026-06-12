import XCTest
import AppKit
@testable import PressTalk

final class ConfigurationTests: XCTestCase {
    private var suiteName: String!
    private var legacyDomainName: String!
    private var defaults: UserDefaults!
    private var keychain: InMemorySecretStore!
    private var legacyKeychain: InMemorySecretStore!

    override func setUp() {
        super.setUp()
        suiteName = "PressTalkTests.\(UUID().uuidString)"
        legacyDomainName = "PressTalkTests.legacy.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        keychain = InMemorySecretStore()
        legacyKeychain = InMemorySecretStore()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults.removePersistentDomain(forName: legacyDomainName)
        super.tearDown()
    }

    private func makeConfiguration() -> Configuration {
        Configuration(
            defaults: defaults,
            keychain: keychain,
            legacyKeychain: legacyKeychain,
            legacyDefaultsDomain: legacyDomainName
        )
    }

    // MARK: Defaults & B-series regressions

    func testDefaultHotkeyIsOptionD() {
        let config = makeConfiguration()
        XCTAssertEqual(config.hotkeyKeyCode, 2)
        XCTAssertEqual(config.hotkeyModifiers, Int(NSEvent.ModifierFlags.option.rawValue))
    }

    func testKeycodeZeroStaysBindable() {
        // B1: keycode 0 is the letter A and must not be treated as "unset".
        let config = makeConfiguration()
        config.hotkeyKeyCode = 0
        XCTAssertEqual(config.hotkeyKeyCode, 0)
    }

    func testModelNameFallsBackToDefault() {
        let config = makeConfiguration()
        XCTAssertEqual(config.modelName, Configuration.defaultModelName)
        config.modelName = "gemini-exp"
        XCTAssertEqual(config.modelName, "gemini-exp")
        config.modelName = ""
        XCTAssertEqual(config.modelName, Configuration.defaultModelName)
    }

    func testHintWordsParsing() {
        let config = makeConfiguration()
        config.hintWordsRaw = "炭滤池\n臭氧, foo，bar、baz  \n\n"
        XCTAssertEqual(config.hintWords, ["炭滤池", "臭氧", "foo", "bar", "baz"])
    }

    // MARK: API key storage & migration chain

    func testAPIKeyRoundTripUsesKeychain() {
        let config = makeConfiguration()
        config.apiKey = "k-123"
        XCTAssertEqual(keychain.values["GeminiAPIKey"], "k-123")
        XCTAssertEqual(config.apiKey, "k-123")
        config.apiKey = ""
        XCTAssertNil(keychain.values["GeminiAPIKey"])
    }

    func testLegacyKeychainServiceIsDrained() {
        // U11: key stored under the GCPDictation-era keychain service moves
        // to the new service on first read.
        legacyKeychain.setString("old-service-key", forAccount: "GeminiAPIKey")
        let config = makeConfiguration()
        XCTAssertEqual(config.apiKey, "old-service-key")
        XCTAssertEqual(keychain.values["GeminiAPIKey"], "old-service-key")
        XCTAssertNil(legacyKeychain.values["GeminiAPIKey"])
    }

    func testLegacyPlaintextDefaultsKeyIsDrained() {
        // U1: pre-keychain builds stored the key as plaintext defaults in the
        // same domain.
        defaults.set("plaintext-key", forKey: "GCPDictation_GeminiAPIKey")
        let config = makeConfiguration()
        XCTAssertEqual(config.apiKey, "plaintext-key")
        XCTAssertEqual(keychain.values["GeminiAPIKey"], "plaintext-key")
        XCTAssertNil(defaults.string(forKey: "GCPDictation_GeminiAPIKey"))
    }

    func testNewKeychainValueWinsOverLegacySources() {
        keychain.setString("new", forAccount: "GeminiAPIKey")
        legacyKeychain.setString("old", forAccount: "GeminiAPIKey")
        defaults.set("older", forKey: "GCPDictation_GeminiAPIKey")
        let config = makeConfiguration()
        XCTAssertEqual(config.apiKey, "new")
        XCTAssertEqual(legacyKeychain.values["GeminiAPIKey"], "old", "untouched until keychain misses")
    }

    // MARK: U11 defaults-domain migration

    func testSameDomainLegacyKeysAreRenamed() {
        defaults.set(7, forKey: "GCPDictation_HotkeyKeyCode")
        defaults.set("custom prompt", forKey: "GCPDictation_CustomPrompt")
        let config = makeConfiguration()
        XCTAssertEqual(config.hotkeyKeyCode, 7)
        XCTAssertEqual(config.customPrompt, "custom prompt")
        XCTAssertNil(defaults.object(forKey: "GCPDictation_HotkeyKeyCode"))
        XCTAssertNil(defaults.object(forKey: "GCPDictation_CustomPrompt"))
    }

    func testLegacyBundleDomainIsMigratedAndRemoved() {
        // The old app bundle wrote to its own defaults domain; values —
        // including the pre-U1 plaintext API key — must move over before the
        // domain is removed.
        defaults.setPersistentDomain(
            [
                "GCPDictation_ModelName": "legacy-model",
                "GCPDictation_GeminiAPIKey": "legacy-domain-key"
            ],
            forName: legacyDomainName
        )
        let config = makeConfiguration()
        XCTAssertEqual(config.modelName, "legacy-model")
        XCTAssertEqual(keychain.values["GeminiAPIKey"], "legacy-domain-key")
        XCTAssertNil(defaults.persistentDomain(forName: legacyDomainName))
    }

    func testExistingNewValuesAreNotOverwrittenByMigration() {
        defaults.set("kept", forKey: "PressTalk_ModelName")
        defaults.set("discarded", forKey: "GCPDictation_ModelName")
        let config = makeConfiguration()
        XCTAssertEqual(config.modelName, "kept")
    }
}
