import Foundation

enum WindowAction: Int, CaseIterable, Codable, Hashable, Sendable {
    case leftHalf = 0
    case rightHalf = 1
    case maximize = 2
    case center = 3
    case minimize = 4
    case closeWindow = 5
    case closeTab = 10
    case quitApplication = 6
    case cycleSameAppWindowsForward = 7
    case cycleSameAppWindowsBackward = 8
    case toggleFullScreen = 9

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
        case .closeTab:
            return L10n.string(
                "action.close_tab",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .quitApplication:
            return L10n.string(
                "action.quit_application",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .cycleSameAppWindowsForward:
            return L10n.string(
                "action.cycle_same_app_windows_forward",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .cycleSameAppWindowsBackward:
            return L10n.string(
                "action.cycle_same_app_windows_backward",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .toggleFullScreen:
            return L10n.string(
                "action.toggle_full_screen",
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
        case .closeTab:
            return ""
        case .quitApplication:
            return "7"
        case .cycleSameAppWindowsForward:
            return "8"
        case .cycleSameAppWindowsBackward:
            return "9"
        case .toggleFullScreen:
            return "0"
        }
    }
}
