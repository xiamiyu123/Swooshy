import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var preferredLanguages: [String]? {
        switch self {
        case .system:
            nil
        case .english:
            ["en"]
        case .simplifiedChinese:
            ["zh-Hans"]
        }
    }

    func title(
        localeIdentifier: String? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let localizationKey = switch self {
        case .system:
            "settings.language.system"
        case .english:
            "settings.language.english"
        case .simplifiedChinese:
            "settings.language.simplified_chinese"
        }

        return L10n.string(
            localizationKey,
            localeIdentifier: localeIdentifier,
            preferredLanguages: preferredLanguages
        )
    }
}
