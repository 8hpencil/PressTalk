import Foundation
import Cocoa

public final class Configuration {
    public static let shared = Configuration()

    private let hotkeyKeyCodeStoreKey = "PressTalk_HotkeyKeyCode"
    private let hotkeyModifiersStoreKey = "PressTalk_HotkeyModifiers"
    private let modelNameStoreKey = "PressTalk_ModelName"
    private let customPromptStoreKey = "PressTalk_CustomPrompt"
    private let hintWordsStoreKey = "PressTalk_HintWords"
    private let apiKeyAccount = "GeminiAPIKey"

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

    private let keychain = KeychainStore()
    private let legacyKeychain = KeychainStore(service: AppIdentity.legacyKeychainService)

    private init() {
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
            if let legacy = UserDefaults.standard.string(forKey: legacyAPIStoreKey), !legacy.isEmpty {
                if keychain.setString(legacy, forAccount: apiKeyAccount) {
                    UserDefaults.standard.removeObject(forKey: legacyAPIStoreKey)
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
            guard UserDefaults.standard.object(forKey: hotkeyKeyCodeStoreKey) != nil else {
                return 2 // default: D
            }
            return UserDefaults.standard.integer(forKey: hotkeyKeyCodeStoreKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hotkeyKeyCodeStoreKey)
        }
    }

    public var hotkeyModifiers: Int {
        get {
            guard UserDefaults.standard.object(forKey: hotkeyModifiersStoreKey) != nil else {
                return Int(NSEvent.ModifierFlags.option.rawValue)
            }
            return UserDefaults.standard.integer(forKey: hotkeyModifiersStoreKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hotkeyModifiersStoreKey)
        }
    }

    public var modelName: String {
        get {
            let stored = UserDefaults.standard.string(forKey: modelNameStoreKey) ?? ""
            return stored.isEmpty ? Self.defaultModelName : stored
        }
        set {
            UserDefaults.standard.set(newValue, forKey: modelNameStoreKey)
        }
    }

    /// Empty means "use PromptBuilder.defaultPrompt".
    public var customPrompt: String {
        get { UserDefaults.standard.string(forKey: customPromptStoreKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: customPromptStoreKey) }
    }

    /// Raw hint-word list as entered by the user, one term per line.
    public var hintWordsRaw: String {
        get { UserDefaults.standard.string(forKey: hintWordsStoreKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: hintWordsStoreKey) }
    }

    /// Parsed hint words: split on newlines and commas, trimmed, empties dropped.
    public var hintWords: [String] {
        hintWordsRaw
            .split(whereSeparator: { $0.isNewline || $0 == "," || $0 == "，" || $0 == "、" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// One-time U11 migration of GCPDictation_* defaults to PressTalk_*.
    /// Covers both the same defaults domain (swift run, in-place upgrades)
    /// and the old app bundle's separate domain (bundle ID changed in U11).
    private func migrateLegacyDefaults() {
        let defaults = UserDefaults.standard

        for (oldKey, newKey) in legacyDefaultsKeyMap {
            if defaults.object(forKey: newKey) == nil, let value = defaults.object(forKey: oldKey) {
                defaults.set(value, forKey: newKey)
            }
            defaults.removeObject(forKey: oldKey)
        }

        if let legacyDomain = defaults.persistentDomain(forName: AppIdentity.legacyBundleID) {
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
            defaults.removePersistentDomain(forName: AppIdentity.legacyBundleID)
        }
    }
}
