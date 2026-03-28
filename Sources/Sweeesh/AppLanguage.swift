import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var preferredLanguages: [String]? {
        switch self {
        case .system:
            return nil
        case .english:
            return ["en"]
        case .simplifiedChinese:
            return ["zh-Hans"]
        }
    }
}
