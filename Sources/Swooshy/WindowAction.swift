import Foundation

enum WindowAction: Int, CaseIterable, Codable, Hashable, Sendable {
    case leftHalf = 0
    case rightHalf = 1
    case maximize = 2
    case center = 3
    case topLeftQuarter = 4
    case topRightQuarter = 5
    case bottomLeftQuarter = 6
    case bottomRightQuarter = 7
    case minimize = 8
    case closeWindow = 9
    case closeTab = 10
    case quitApplication = 11
    case cycleSameAppWindowsForward = 12
    case cycleSameAppWindowsBackward = 13
    case toggleFullScreen = 14
    case exitFullScreen = 15

    static let allCases: [WindowAction] = [
        .leftHalf,
        .rightHalf,
        .maximize,
        .center,
        .topLeftQuarter,
        .topRightQuarter,
        .bottomLeftQuarter,
        .bottomRightQuarter,
        .minimize,
        .closeWindow,
        .closeTab,
        .quitApplication,
        .cycleSameAppWindowsForward,
        .cycleSameAppWindowsBackward,
        .toggleFullScreen,
    ]

    static let gestureCases: [WindowAction] = allCases + [.exitFullScreen]

    var title: String {
        title()
    }

    var supportsSnapPreview: Bool {
        previewBehavior != nil
    }

    var previewBehavior: WindowActionPreviewBehavior? {
        switch self {
        case .leftHalf:
            return .area(
                defaultHorizontalAnchor: .leadingEdge,
                defaultVerticalAnchor: .leadingEdge
            )
        case .rightHalf:
            return .area(
                defaultHorizontalAnchor: .trailingEdge,
                defaultVerticalAnchor: .leadingEdge
            )
        case .maximize, .center:
            return .area(
                defaultHorizontalAnchor: .leadingEdge,
                defaultVerticalAnchor: .leadingEdge
            )
        case .topLeftQuarter:
            return .area(
                defaultHorizontalAnchor: .leadingEdge,
                defaultVerticalAnchor: .trailingEdge
            )
        case .topRightQuarter:
            return .area(
                defaultHorizontalAnchor: .trailingEdge,
                defaultVerticalAnchor: .trailingEdge
            )
        case .bottomLeftQuarter:
            return .area(
                defaultHorizontalAnchor: .leadingEdge,
                defaultVerticalAnchor: .leadingEdge
            )
        case .bottomRightQuarter:
            return .area(
                defaultHorizontalAnchor: .trailingEdge,
                defaultVerticalAnchor: .leadingEdge
            )
        case .minimize,
             .closeWindow,
             .closeTab,
             .quitApplication,
             .cycleSameAppWindowsForward,
             .cycleSameAppWindowsBackward,
             .toggleFullScreen,
             .exitFullScreen:
            return nil
        }
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
        case .topLeftQuarter:
            return L10n.string(
                "action.top_left_quarter",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .topRightQuarter:
            return L10n.string(
                "action.top_right_quarter",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .bottomLeftQuarter:
            return L10n.string(
                "action.bottom_left_quarter",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .bottomRightQuarter:
            return L10n.string(
                "action.bottom_right_quarter",
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
        case .exitFullScreen:
            return L10n.string(
                "action.exit_full_screen",
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
        case .topLeftQuarter,
             .topRightQuarter,
             .bottomLeftQuarter,
             .bottomRightQuarter:
            return ""
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
        case .exitFullScreen:
            return ""
        }
    }
}

enum WindowActionPreviewBehavior: Equatable, Sendable {
    case area(
        defaultHorizontalAnchor: WindowActionPreview.AxisAnchor,
        defaultVerticalAnchor: WindowActionPreview.AxisAnchor
    )
}
