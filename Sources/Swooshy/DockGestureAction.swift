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
    private static let defaultActionsByGesture: [(DockGestureKind, DockGestureAction)] = [
        (.swipeLeft, .cycleWindowsForward),
        (.swipeRight, .cycleWindowsBackward),
        (.swipeDown, .minimizeWindow),
        (.swipeUp, .restoreWindow),
        (.pinchIn, .quitApplication),
        (.pinchOut, .toggleFullScreenWindow),
    ]

    static let defaults: [DockGestureBinding] = defaultActionsByGesture.map { gesture, action in
        DockGestureBinding(gesture: gesture, action: action)
    }

    static func fallbackBinding(for gesture: DockGestureKind) -> DockGestureBinding {
        if let action = defaultActionsByGesture.first(where: { $0.0 == gesture })?.1 {
            return DockGestureBinding(gesture: gesture, action: action)
        }

        return DockGestureBinding(gesture: gesture, action: .quitApplication)
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

    private static let defaultActionsByGesture: [(DockGestureKind, WindowAction)] = [
        (.swipeLeft, .leftHalf),
        (.swipeRight, .rightHalf),
        (.swipeDown, .minimize),
        (.swipeUp, .center),
        (.pinchIn, .closeWindow),
        (.pinchOut, .toggleFullScreen),
    ]

    static let defaults: [TitleBarGestureBinding] = defaultActionsByGesture.map { gesture, action in
        TitleBarGestureBinding(gesture: gesture, action: action)
    }

    static func fallbackBinding(for gesture: DockGestureKind) -> TitleBarGestureBinding {
        if let action = defaultActionsByGesture.first(where: { $0.0 == gesture })?.1 {
            return TitleBarGestureBinding(gesture: gesture, action: action)
        }

        return TitleBarGestureBinding(gesture: gesture, action: .center)
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
