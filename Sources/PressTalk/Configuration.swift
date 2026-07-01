import Foundation
import Cocoa

public enum ProviderType: String {
    case gemini = "gemini"
    case whisper = "whisper"
    case gcpChirp = "gcpChirp"
    case localASR = "localASR"
}

public final class Configuration {
    public static let shared = Configuration()

    private let hotkeyKeyCodeStoreKey = "PressTalk_HotkeyKeyCode"
    private let hotkeyModifiersStoreKey = "PressTalk_HotkeyModifiers"
    private let modelNameStoreKey = "PressTalk_ModelName"
    private let customPromptStoreKey = "PressTalk_CustomPrompt"
    private let hintWordsStoreKey = "PressTalk_HintWords"
    private let providerTypeStoreKey = "PressTalk_ProviderType"
    private let whisperModelStoreKey = "PressTalk_WhisperModel"
    private let whisperUseMirrorStoreKey = "PressTalk_WhisperUseMirror"
    private let apiKeyAccount = "GeminiAPIKey"

    private let gcpProjectIdStoreKey = "PressTalk_GCPProjectId"
    private let gcpLocationStoreKey = "PressTalk_GCPLocation"
    private let gcpModelNameStoreKey = "PressTalk_GCPModelName"
    private let gcpApiKeyAccount = "GCPAPIKey"
    
    private let localASRApiUrlStoreKey = "PressTalk_LocalASRApiUrl"

    /// Legacy GCPDictation-era UserDefaults keys (U11 migration only).
    private let legacyAPIStoreKey = "GCPDictation_GeminiAPIKey"
    private let legacyDefaultsKeyMap = [
        "GCPDictation_HotkeyKeyCode": "PressTalk_HotkeyKeyCode",
        "GCPDictation_HotkeyModifiers": "PressTalk_HotkeyModifiers",
        "GCPDictation_ModelName": "PressTalk_ModelName",
        "GCPDictation_CustomPrompt": "PressTalk_CustomPrompt",
        "GCPDictation_HintWords": "PressTalk_HintWords"
    ]

    public static let defaultModelName = "gemini-2.5-flash"
    public static let defaultWhisperModel = "base"
    public static let defaultGcpModelName = "chirp_3"
    public static let defaultLocalASRApiUrl = "http://192.168.50.155:8000/v1/audio/transcriptions"

    private let defaults: UserDefaults
    private let keychain: SecretStore
    private let legacyKeychain: SecretStore
    private let legacyDefaultsDomain: String

    /// Injectable for tests; the app always goes through `shared`.
    init(
        defaults: UserDefaults = .standard,
        keychain: SecretStore = KeychainStore(),
        legacyKeychain: SecretStore = KeychainStore(service: AppIdentity.legacyKeychainService),
        legacyDefaultsDomain: String = AppIdentity.legacyBundleID
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.legacyKeychain = legacyKeychain
        self.legacyDefaultsDomain = legacyDefaultsDomain
        migrateLegacyDefaults()
    }

    public var apiKey: String {
        get {
            if let stored = keychain.string(forAccount: apiKeyAccount) {
                return stored
            }
            // U11 migration: drain the GCPDictation-era keychain service.
            if let legacy = legacyKeychain.string(forAccount: apiKeyAccount), !legacy.isEmpty {
                if keychain.setString(legacy, forAccount: apiKeyAccount) {
                    legacyKeychain.removeString(forAccount: apiKeyAccount)
                }
                return legacy
            }
            // U1 migration: drain the pre-keychain UserDefaults plaintext storage.
            if let legacy = defaults.string(forKey: legacyAPIStoreKey), !legacy.isEmpty {
                if keychain.setString(legacy, forAccount: apiKeyAccount) {
                    defaults.removeObject(forKey: legacyAPIStoreKey)
                }
                return legacy
            }
            return ""
        }
        set {
            if newValue.isEmpty {
                keychain.removeString(forAccount: apiKeyAccount)
            } else {
                keychain.setString(newValue, forAccount: apiKeyAccount)
            }
        }
    }

    // Default to Option + D
    // KeyCode for 'D' is 2 (from Carbon Events/HIToolbox/Events.h)
    // Option modifier is 524288 (NSEvent.ModifierFlags.option.rawValue)
    public var hotkeyKeyCode: Int {
        get {
            // `object(forKey:)` distinguishes "never set" from a stored 0 —
            // keycode 0 is the letter A and must stay bindable (B1).
            guard defaults.object(forKey: hotkeyKeyCodeStoreKey) != nil else {
                return 2 // default: D
            }
            return defaults.integer(forKey: hotkeyKeyCodeStoreKey)
        }
        set {
            defaults.set(newValue, forKey: hotkeyKeyCodeStoreKey)
        }
    }

    public var hotkeyModifiers: Int {
        get {
            guard defaults.object(forKey: hotkeyModifiersStoreKey) != nil else {
                return Int(NSEvent.ModifierFlags.option.rawValue)
            }
            return defaults.integer(forKey: hotkeyModifiersStoreKey)
        }
        set {
            defaults.set(newValue, forKey: hotkeyModifiersStoreKey)
        }
    }

    public var modelName: String {
        get {
            let stored = defaults.string(forKey: modelNameStoreKey) ?? ""
            return stored.isEmpty ? Self.defaultModelName : stored
        }
        set {
            defaults.set(newValue, forKey: modelNameStoreKey)
        }
    }

    /// Empty means "use PromptBuilder.defaultPrompt".
    public var customPrompt: String {
        get { defaults.string(forKey: customPromptStoreKey) ?? "" }
        set { defaults.set(newValue, forKey: customPromptStoreKey) }
    }

    /// Raw hint-word list as entered by the user, one term per line.
    public var hintWordsRaw: String {
        get { defaults.string(forKey: hintWordsStoreKey) ?? "" }
        set { defaults.set(newValue, forKey: hintWordsStoreKey) }
    }

    /// Parsed hint words: split on newlines and commas, trimmed, empties dropped.
    public var hintWords: [String] {
        hintWordsRaw
            .split(whereSeparator: { $0.isNewline || $0 == "," || $0 == "，" || $0 == "、" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public var transcriptionProvider: ProviderType {
        get { ProviderType(rawValue: defaults.string(forKey: providerTypeStoreKey) ?? "") ?? .gemini }
        set { defaults.set(newValue.rawValue, forKey: providerTypeStoreKey) }
    }

    public var gcpProjectId: String {
        get { defaults.string(forKey: gcpProjectIdStoreKey) ?? "" }
        set { defaults.set(newValue, forKey: gcpProjectIdStoreKey) }
    }

    public var gcpLocation: String {
        get {
            let stored = defaults.string(forKey: gcpLocationStoreKey) ?? ""
            return stored.isEmpty ? "us-central1" : stored
        }
        set { defaults.set(newValue, forKey: gcpLocationStoreKey) }
    }

    public var gcpModelName: String {
        get {
            let stored = defaults.string(forKey: gcpModelNameStoreKey) ?? ""
            return stored.isEmpty ? Self.defaultGcpModelName : stored
        }
        set { defaults.set(newValue, forKey: gcpModelNameStoreKey) }
    }

    public var gcpApiKey: String {
        get { keychain.string(forAccount: gcpApiKeyAccount) ?? "" }
        set {
            if newValue.isEmpty {
                keychain.removeString(forAccount: gcpApiKeyAccount)
            } else {
                keychain.setString(newValue, forAccount: gcpApiKeyAccount)
            }
        }
    }

    /// Short model IDs used in earlier builds that have been replaced with precise
    /// folder names to avoid HuggingFace multi-match errors.
    private static let whisperModelMigrations: [String: String] = [
        "large-v3":       "openai_whisper-large-v3-v20240930_626MB",
        "large-v3-turbo": "openai_whisper-large-v3-v20240930_turbo_632MB",
    ]

    public var whisperModelName: String {
        get {
            var stored = defaults.string(forKey: whisperModelStoreKey) ?? ""
            if stored.isEmpty { stored = Self.defaultWhisperModel }
            if let migrated = Self.whisperModelMigrations[stored] {
                defaults.set(migrated, forKey: whisperModelStoreKey)
                return migrated
            }
            return stored
        }
        set { defaults.set(newValue, forKey: whisperModelStoreKey) }
    }

    /// When true, model downloads go through hf-mirror.com instead of huggingface.co.
    public var whisperUseMirror: Bool {
        get { defaults.bool(forKey: whisperUseMirrorStoreKey) }
        set { defaults.set(newValue, forKey: whisperUseMirrorStoreKey) }
    }

    public var localASRApiUrl: String {
        get {
            let stored = defaults.string(forKey: localASRApiUrlStoreKey) ?? ""
            return stored.isEmpty ? Self.defaultLocalASRApiUrl : stored
        }
        set {
            defaults.set(newValue, forKey: localASRApiUrlStoreKey)
        }
    }

    public static let huggingFaceMirrorEndpoint = "https://hf-mirror.com"

    /// One-time U11 migration of GCPDictation_* defaults to PressTalk_*.
    /// Covers both the same defaults domain (swift run, in-place upgrades)
    /// and the old app bundle's separate domain (bundle ID changed in U11).
    private func migrateLegacyDefaults() {
        for (oldKey, newKey) in legacyDefaultsKeyMap {
            if defaults.object(forKey: newKey) == nil, let value = defaults.object(forKey: oldKey) {
                defaults.set(value, forKey: newKey)
            }
            defaults.removeObject(forKey: oldKey)
        }

        if let legacyDomain = defaults.persistentDomain(forName: legacyDefaultsDomain) {
            for (oldKey, newKey) in legacyDefaultsKeyMap {
                if defaults.object(forKey: newKey) == nil, let value = legacyDomain[oldKey] {
                    defaults.set(value, forKey: newKey)
                }
            }
            // Pre-U1 builds kept the API key as plaintext defaults in the old
            // domain; it must reach the keychain before the domain is removed.
            if keychain.string(forAccount: apiKeyAccount) == nil,
               let legacyKey = legacyDomain[legacyAPIStoreKey] as? String, !legacyKey.isEmpty {
                keychain.setString(legacyKey, forAccount: apiKeyAccount)
            }
            defaults.removePersistentDomain(forName: legacyDefaultsDomain)
        }
    }
}
