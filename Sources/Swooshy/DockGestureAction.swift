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
        switch self {
        case .swipeLeft:
            return L10n.string(
                "settings.dock_gestures.gesture.swipe_left",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .swipeRight:
            return L10n.string(
                "settings.dock_gestures.gesture.swipe_right",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .swipeDown:
            return L10n.string(
                "settings.dock_gestures.gesture.swipe_down",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .swipeUp:
            return L10n.string(
                "settings.dock_gestures.gesture.swipe_up",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .pinchIn:
            return L10n.string(
                "settings.dock_gestures.gesture.pinch_in",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .pinchOut:
            return L10n.string(
                "settings.dock_gestures.gesture.pinch_out",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        }
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

    var id: String { rawValue }

    func title(
        localeIdentifier: String? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        switch self {
        case .minimizeWindow:
            return L10n.string(
                "action.minimize",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .restoreWindow:
            return L10n.string(
                "action.restore_window",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .cycleWindowsForward:
            return L10n.string(
                "action.cycle_same_app_windows_forward",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .cycleWindowsBackward:
            return L10n.string(
                "action.cycle_same_app_windows_backward",
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
        case .toggleFullScreenWindow:
            return L10n.string(
                "action.toggle_full_screen",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        case .exitFullScreenWindow:
            return L10n.string(
                "action.exit_full_screen",
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        }
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
        switch gesture {
        case .swipeLeft:
            return DockGestureBinding(gesture: .swipeLeft, action: .cycleWindowsForward)
        case .swipeRight:
            return DockGestureBinding(gesture: .swipeRight, action: .cycleWindowsBackward)
        case .swipeDown:
            return DockGestureBinding(gesture: .swipeDown, action: .minimizeWindow)
        case .swipeUp:
            return DockGestureBinding(gesture: .swipeUp, action: .restoreWindow)
        case .pinchIn:
            return DockGestureBinding(gesture: .pinchIn, action: .quitApplication)
        case .pinchOut:
            return DockGestureBinding(gesture: .pinchOut, action: .toggleFullScreenWindow)
        }
    }

    static func binding(
        for gesture: DockGestureKind,
        in bindings: [DockGestureBinding]
    ) -> DockGestureBinding {
        bindings.first(where: { $0.gesture == gesture }) ?? fallbackBinding(for: gesture)
    }

    static func action(
        for gesture: DockGestureKind,
        in bindings: [DockGestureBinding]
    ) -> DockGestureAction {
        binding(for: gesture, in: bindings).action
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
    static let supportedGestures: [DockGestureKind] = [
        .swipeLeft,
        .swipeRight,
        .swipeDown,
        .swipeUp,
        .pinchIn,
        .pinchOut,
    ]

    static let defaults: [TitleBarGestureBinding] = [
        TitleBarGestureBinding(gesture: .swipeLeft, action: .leftHalf),
        TitleBarGestureBinding(gesture: .swipeRight, action: .rightHalf),
        TitleBarGestureBinding(gesture: .swipeDown, action: .minimize),
        TitleBarGestureBinding(gesture: .swipeUp, action: .center),
        TitleBarGestureBinding(gesture: .pinchIn, action: .closeWindow),
        TitleBarGestureBinding(gesture: .pinchOut, action: .toggleFullScreen),
    ]

    static func fallbackBinding(for gesture: DockGestureKind) -> TitleBarGestureBinding {
        switch gesture {
        case .swipeLeft:
            return TitleBarGestureBinding(gesture: .swipeLeft, action: .leftHalf)
        case .swipeRight:
            return TitleBarGestureBinding(gesture: .swipeRight, action: .rightHalf)
        case .swipeDown:
            return TitleBarGestureBinding(gesture: .swipeDown, action: .minimize)
        case .swipeUp:
            return TitleBarGestureBinding(gesture: .swipeUp, action: .center)
        case .pinchIn:
            return TitleBarGestureBinding(gesture: .pinchIn, action: .closeWindow)
        case .pinchOut:
            return TitleBarGestureBinding(gesture: .pinchOut, action: .toggleFullScreen)
        }
    }

    static func binding(
        for gesture: DockGestureKind,
        in bindings: [TitleBarGestureBinding]
    ) -> TitleBarGestureBinding? {
        guard supportedGestures.contains(gesture) else { return nil }
        return bindings.first(where: { $0.gesture == gesture }) ?? fallbackBinding(for: gesture)
    }

    static func action(
        for gesture: DockGestureKind,
        in bindings: [TitleBarGestureBinding]
    ) -> WindowAction? {
        binding(for: gesture, in: bindings)?.action
    }
}
