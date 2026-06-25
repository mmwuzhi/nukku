import Foundation

enum L10n {
    static var locale: Locale {
        switch Bundle.module.preferredLocalizations.first?.lowercased() {
        case "ja":
            Locale(identifier: "ja_JP")
        case "zh-hans":
            Locale(identifier: "zh_Hans")
        default:
            Locale(identifier: "en_US")
        }
    }

    static func tr(_ key: String, _ fallback: String) -> String {
        Bundle.module.localizedString(forKey: key, value: fallback, table: nil)
    }

    static func dateFormat(_ key: String, _ fallback: String) -> String {
        tr(key, fallback)
    }
}
