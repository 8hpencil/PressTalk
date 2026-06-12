import Foundation

/// Shorthand for localized UI strings (U10). All user-visible text lives in
/// Resources/<locale>.lproj/Localizable.strings (en is the default, zh-Hans
/// provided). Logs are intentionally NOT localized — they stay English.
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}
