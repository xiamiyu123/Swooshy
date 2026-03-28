import Foundation

enum WindowAction: Int, CaseIterable, Codable, Hashable, Sendable {
    case leftHalf
    case rightHalf
    case maximize
    case center
    case minimize
    case closeWindow
    case quitApplication
    case cycleSameAppWindows

    var title: String {
        title()
    }

    func title(
        localeIdentifier: String? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        switch self {
        case .leftHalf:
            return L10n.string(
                "action.left_half",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .rightHalf:
            return L10n.string(
                "action.right_half",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .maximize:
            return L10n.string(
                "action.maximize",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .center:
            return L10n.string(
                "action.center",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .minimize:
            return L10n.string(
                "action.minimize",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .closeWindow:
            return L10n.string(
                "action.close_window",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .quitApplication:
            return L10n.string(
                "action.quit_application",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .cycleSameAppWindows:
            return L10n.string(
                "action.cycle_same_app_windows",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        }
    }

    var menuKeyEquivalent: String {
        switch self {
        case .leftHalf:
            return "1"
        case .rightHalf:
            return "2"
        case .maximize:
            return "3"
        case .center:
            return "4"
        case .minimize:
            return "5"
        case .closeWindow:
            return "6"
        case .quitApplication:
            return "7"
        case .cycleSameAppWindows:
            return "8"
        }
    }
}
