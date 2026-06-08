import Foundation

enum GestureHUDStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case classic
    case elegant
    case minimal = "minimal_v2"

    private static let legacyMinimalStorageValue = "swishLike"

    var id: Self { self }

    var storageValue: String {
        rawValue
    }

    init(storageValue: String?) {
        self = switch storageValue {
        case "classic":
            .classic
        case Self.minimal.rawValue, Self.legacyMinimalStorageValue:
            .minimal
        default:
            .elegant
        }
    }

    func title(
        localeIdentifier: String? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let localizationKey = switch self {
        case .classic:
            "settings.gesture_hud.style.classic"
        case .elegant:
            "settings.gesture_hud.style.elegant"
        case .minimal:
            "settings.gesture_hud.style.minimal"
        }

        return L10n.string(
            localizationKey,
            localeIdentifier: localeIdentifier,
            preferredLanguages: preferredLanguages
        )
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
