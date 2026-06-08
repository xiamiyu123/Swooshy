import Foundation

enum DockGestureKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case swipeLeft
    case swipeRight
    case swipeDown
    case swipeUp
    case pinchIn
    case pinchOut

    var id: String { rawValue }

    func title(
        localeIdentifier: String? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let localizationKey = switch self {
        case .swipeLeft:
            "settings.dock_gestures.gesture.swipe_left"
        case .swipeRight:
            "settings.dock_gestures.gesture.swipe_right"
        case .swipeDown:
            "settings.dock_gestures.gesture.swipe_down"
        case .swipeUp:
            "settings.dock_gestures.gesture.swipe_up"
        case .pinchIn:
            "settings.dock_gestures.gesture.pinch_in"
        case .pinchOut:
            "settings.dock_gestures.gesture.pinch_out"
        }

        return L10n.string(
            localizationKey,
            localeIdentifier: localeIdentifier,
            preferredLanguages: preferredLanguages
        )
    }
}

enum DockGestureAction: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case minimizeWindow
    case restoreWindow
    case cycleWindowsForward
    case cycleWindowsBackward
    case closeWindow
    case closeTab
    case quitApplication
    case toggleFullScreenWindow
    case exitFullScreenWindow
    case moveWindowToNextDisplay
    case moveWindowToPreviousDisplay

    static let allCases: [DockGestureAction] = [
        .minimizeWindow,
        .restoreWindow,
        .moveWindowToNextDisplay,
        .moveWindowToPreviousDisplay,
        .cycleWindowsForward,
        .cycleWindowsBackward,
        .toggleFullScreenWindow,
        .exitFullScreenWindow,
        .closeWindow,
        .closeTab,
        .quitApplication,
    ]

    var id: String { rawValue }

    var isDisplayMoveAction: Bool {
        self == .moveWindowToNextDisplay || self == .moveWindowToPreviousDisplay
    }

    func title(
        localeIdentifier: String? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let localizationKey = switch self {
        case .minimizeWindow:
            "action.minimize"
        case .restoreWindow:
            "action.restore_window"
        case .cycleWindowsForward:
            "action.cycle_same_app_windows_forward"
        case .cycleWindowsBackward:
            "action.cycle_same_app_windows_backward"
        case .closeWindow:
            "action.close_window"
        case .closeTab:
            "action.close_tab"
        case .quitApplication:
            "action.quit_application"
        case .toggleFullScreenWindow:
            "action.toggle_full_screen"
        case .exitFullScreenWindow:
            "action.exit_full_screen"
        case .moveWindowToNextDisplay:
            "action.move_to_next_display"
        case .moveWindowToPreviousDisplay:
            "action.move_to_previous_display"
        }

        return L10n.string(
            localizationKey,
            localeIdentifier: localeIdentifier,
            preferredLanguages: preferredLanguages
        )
    }
}

struct DockGestureBinding: Codable, Equatable, Hashable, Sendable {
    let gesture: DockGestureKind
    var isEnabled: Bool
    var action: DockGestureAction

    init(gesture: DockGestureKind, isEnabled: Bool = true, action: DockGestureAction) {
        self.gesture = gesture
        self.isEnabled = isEnabled
        self.action = action
    }

    private enum CodingKeys: String, CodingKey {
        case gesture
        case isEnabled
        case action
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gesture = try container.decode(DockGestureKind.self, forKey: .gesture)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        action = try container.decode(DockGestureAction.self, forKey: .action)
    }
}

enum DockGestureBindings {
    static let defaults: [DockGestureBinding] = [
        DockGestureBinding(gesture: .swipeLeft, action: .cycleWindowsForward),
        DockGestureBinding(gesture: .swipeRight, action: .cycleWindowsBackward),
        DockGestureBinding(gesture: .swipeDown, action: .minimizeWindow),
        DockGestureBinding(gesture: .swipeUp, action: .restoreWindow),
        DockGestureBinding(gesture: .pinchIn, action: .quitApplication),
        DockGestureBinding(gesture: .pinchOut, action: .toggleFullScreenWindow),
    ]

    static func fallbackBinding(for gesture: DockGestureKind) -> DockGestureBinding {
        defaults.first(where: { $0.gesture == gesture }) ??
            DockGestureBinding(gesture: gesture, action: .quitApplication)
    }

    static func binding(
        for gesture: DockGestureKind,
        in bindings: [DockGestureBinding]
    ) -> DockGestureBinding {
        bindings.first(where: { $0.gesture == gesture }) ?? fallbackBinding(for: gesture)
    }

}

struct TitleBarGestureBinding: Codable, Equatable, Hashable, Sendable {
    let gesture: DockGestureKind
    var isEnabled: Bool
    var action: WindowAction

    init(gesture: DockGestureKind, isEnabled: Bool = true, action: WindowAction) {
        self.gesture = gesture
        self.isEnabled = isEnabled
        self.action = action
    }

    private enum CodingKeys: String, CodingKey {
        case gesture
        case isEnabled
        case action
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gesture = try container.decode(DockGestureKind.self, forKey: .gesture)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        action = try container.decode(WindowAction.self, forKey: .action)
    }
}

enum TitleBarGestureBindings {
    static let defaults: [TitleBarGestureBinding] = [
        TitleBarGestureBinding(gesture: .swipeLeft, action: .leftHalf),
        TitleBarGestureBinding(gesture: .swipeRight, action: .rightHalf),
        TitleBarGestureBinding(gesture: .swipeDown, action: .minimize),
        TitleBarGestureBinding(gesture: .swipeUp, action: .center),
        TitleBarGestureBinding(gesture: .pinchIn, action: .closeWindow),
        TitleBarGestureBinding(gesture: .pinchOut, action: .toggleFullScreen),
    ]

    static let supportedGestures: [DockGestureKind] = defaults.map(\.gesture)

    static func fallbackBinding(for gesture: DockGestureKind) -> TitleBarGestureBinding {
        defaults.first(where: { $0.gesture == gesture }) ??
            TitleBarGestureBinding(gesture: gesture, action: .center)
    }

    static func binding(
        for gesture: DockGestureKind,
        in bindings: [TitleBarGestureBinding]
    ) -> TitleBarGestureBinding? {
        guard supportedGestures.contains(gesture) else { return nil }
        return bindings.first(where: { $0.gesture == gesture }) ?? fallbackBinding(for: gesture)
    }

}
