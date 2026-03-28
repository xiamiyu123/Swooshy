import Foundation

enum GestureHUDStyle: CaseIterable, Codable, Identifiable, Sendable {
    case classic
    case elegant
    case minimal

    private static let legacyMinimalStorageValue = String(
        decoding: [115, 119, 105, 115, 104, 76, 105, 107, 101],
        as: UTF8.self
    )

    var id: Self { self }

    var storageValue: String {
        switch self {
        case .classic:
            return "classic"
        case .minimal:
            return "minimal_v2"
        case .elegant:
            return "elegant"
        }
    }

    init(storageValue: String?) {
        switch storageValue {
        case "classic":
            self = .classic
        case "elegant", "minimal":
            self = .elegant
        case "minimal_v2", Self.legacyMinimalStorageValue:
            self = .minimal
        default:
            self = .elegant
        }
    }

    func title(
        localeIdentifier: String? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        switch self {
        case .classic:
            return L10n.string(
                "settings.gesture_hud.style.classic",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .elegant:
            return L10n.string(
                "settings.gesture_hud.style.elegant",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .minimal:
            return L10n.string(
                "settings.gesture_hud.style.minimal",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = GestureHUDStyle(storageValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageValue)
    }
}
