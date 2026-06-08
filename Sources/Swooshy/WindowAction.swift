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
    case moveToNextDisplay = 16
    case moveToPreviousDisplay = 17

    static let allCases: [WindowAction] = [
        .leftHalf,
        .rightHalf,
        .maximize,
        .center,
        .topLeftQuarter,
        .topRightQuarter,
        .bottomLeftQuarter,
        .bottomRightQuarter,
        .moveToNextDisplay,
        .moveToPreviousDisplay,
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

    var isDisplayMoveAction: Bool {
        self == .moveToNextDisplay || self == .moveToPreviousDisplay
    }

    var supportsSnapPreview: Bool {
        previewBehavior != nil
    }

    var supportsBrowserTabCloseReplacement: Bool {
        self == .closeWindow || self == .quitApplication
    }

    var previewBehavior: WindowActionPreviewBehavior? {
        switch self {
        case .leftHalf,
             .maximize,
             .center,
             .bottomLeftQuarter:
            .area(defaultHorizontalAnchor: .leadingEdge, defaultVerticalAnchor: .leadingEdge)
        case .rightHalf,
             .bottomRightQuarter:
            .area(defaultHorizontalAnchor: .trailingEdge, defaultVerticalAnchor: .leadingEdge)
        case .topLeftQuarter:
            .area(defaultHorizontalAnchor: .leadingEdge, defaultVerticalAnchor: .trailingEdge)
        case .topRightQuarter:
            .area(defaultHorizontalAnchor: .trailingEdge, defaultVerticalAnchor: .trailingEdge)
        case .minimize,
             .closeWindow,
             .closeTab,
             .quitApplication,
             .cycleSameAppWindowsForward,
             .cycleSameAppWindowsBackward,
             .toggleFullScreen,
             .exitFullScreen,
             .moveToNextDisplay,
             .moveToPreviousDisplay:
            nil
        }
    }

    func title(
        localeIdentifier: String? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let localizationKey = switch self {
        case .leftHalf:
            "action.left_half"
        case .rightHalf:
            "action.right_half"
        case .maximize:
            "action.maximize"
        case .center:
            "action.center"
        case .topLeftQuarter:
            "action.top_left_quarter"
        case .topRightQuarter:
            "action.top_right_quarter"
        case .bottomLeftQuarter:
            "action.bottom_left_quarter"
        case .bottomRightQuarter:
            "action.bottom_right_quarter"
        case .minimize:
            "action.minimize"
        case .closeWindow:
            "action.close_window"
        case .closeTab:
            "action.close_tab"
        case .quitApplication:
            "action.quit_application"
        case .cycleSameAppWindowsForward:
            "action.cycle_same_app_windows_forward"
        case .cycleSameAppWindowsBackward:
            "action.cycle_same_app_windows_backward"
        case .toggleFullScreen:
            "action.toggle_full_screen"
        case .exitFullScreen:
            "action.exit_full_screen"
        case .moveToNextDisplay:
            "action.move_to_next_display"
        case .moveToPreviousDisplay:
            "action.move_to_previous_display"
        }

        return L10n.string(
            localizationKey,
            localeIdentifier: localeIdentifier,
            preferredLanguages: preferredLanguages
        )
    }

    var menuKeyEquivalent: String {
        switch self {
        case .leftHalf:
            "1"
        case .rightHalf:
            "2"
        case .maximize:
            "3"
        case .center:
            "4"
        case .topLeftQuarter,
             .topRightQuarter,
             .bottomLeftQuarter,
             .bottomRightQuarter,
             .moveToNextDisplay,
             .moveToPreviousDisplay,
             .closeTab,
             .exitFullScreen:
            ""
        case .minimize:
            "5"
        case .closeWindow:
            "6"
        case .quitApplication:
            "7"
        case .cycleSameAppWindowsForward:
            "8"
        case .cycleSameAppWindowsBackward:
            "9"
        case .toggleFullScreen:
            "0"
        }
    }
}

enum WindowActionPreviewBehavior: Equatable, Sendable {
    case area(
        defaultHorizontalAnchor: WindowActionPreview.AxisAnchor,
        defaultVerticalAnchor: WindowActionPreview.AxisAnchor
    )
}
