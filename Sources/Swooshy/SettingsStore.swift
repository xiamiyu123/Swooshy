import Foundation
import Observation

struct SettingsChangeCategory: OptionSet {
    let rawValue: Int

    static let localization = SettingsChangeCategory(rawValue: 1 << 0)
    static let hotKeys = SettingsChangeCategory(rawValue: 1 << 1)
    static let gestureMonitoring = SettingsChangeCategory(rawValue: 1 << 2)
    static let statusItemAppearance = SettingsChangeCategory(rawValue: 1 << 3)
    static let statusMenu = SettingsChangeCategory(rawValue: 1 << 4)
    static let gestureHUD = SettingsChangeCategory(rawValue: 1 << 5)
    static let advancedGestureBehavior = SettingsChangeCategory(rawValue: 1 << 6)
}

extension Notification.Name {
    static let settingsDidChange = Notification.Name("Swooshy.settingsDidChange")
}

extension Notification {
    fileprivate static let settingsChangeCategoriesUserInfoKey = "settingsChangeCategories"

    var settingsChangeCategories: SettingsChangeCategory {
        SettingsChangeCategory(
            rawValue: userInfo?[Self.settingsChangeCategoriesUserInfoKey] as? Int ?? 0
        )
    }
}

@MainActor
@Observable
final class SettingsStore {
    @ObservationIgnored
    private let userDefaults: UserDefaults
    @ObservationIgnored
    private var notificationDispatchPending = false
    @ObservationIgnored
    private var pendingChangeCategories: SettingsChangeCategory = []

    var languageOverride: AppLanguage {
        didSet {
            guard oldValue != languageOverride else { return }
            userDefaults.set(languageOverride.rawValue, forKey: Keys.languageOverride)
            L10n.setPreferredLanguagesOverride(preferredLanguages)
            notifyDidChange(.localization)
        }
    }

    var hotKeysEnabled: Bool {
        didSet {
            guard oldValue != hotKeysEnabled else { return }
            userDefaults.set(hotKeysEnabled, forKey: Keys.hotKeysEnabled)
            notifyDidChange(.hotKeys)
        }
    }

    var dockGesturesEnabled: Bool {
        didSet {
            guard oldValue != dockGesturesEnabled else { return }
            userDefaults.set(dockGesturesEnabled, forKey: Keys.dockGesturesEnabled)
            DebugLog.info(DebugLog.settings, "Dock gestures enabled set to \(dockGesturesEnabled)")
            notifyDidChange(.gestureMonitoring)
        }
    }

    var titleBarGesturesEnabled: Bool {
        didSet {
            guard oldValue != titleBarGesturesEnabled else { return }
            userDefaults.set(titleBarGesturesEnabled, forKey: Keys.titleBarGesturesEnabled)
            DebugLog.info(DebugLog.settings, "Title-bar gestures enabled set to \(titleBarGesturesEnabled)")
            notifyDidChange(.gestureMonitoring)
        }
    }

    var dockCornerDragSnapEnabled: Bool {
        didSet {
            guard oldValue != dockCornerDragSnapEnabled else { return }
            userDefaults.set(dockCornerDragSnapEnabled, forKey: Keys.dockCornerDragSnapEnabled)
            DebugLog.info(DebugLog.settings, "Dock corner drag snap enabled set to \(dockCornerDragSnapEnabled)")
            notifyDidChange([.gestureMonitoring, .advancedGestureBehavior])
        }
    }

    var titleBarCornerDragSnapEnabled: Bool {
        didSet {
            guard oldValue != titleBarCornerDragSnapEnabled else { return }
            userDefaults.set(titleBarCornerDragSnapEnabled, forKey: Keys.titleBarCornerDragSnapEnabled)
            DebugLog.info(DebugLog.settings, "Title-bar corner drag snap enabled set to \(titleBarCornerDragSnapEnabled)")
            notifyDidChange([.gestureMonitoring, .advancedGestureBehavior])
        }
    }

    var titleBarOverlayProtectionEnabled: Bool {
        didSet {
            guard oldValue != titleBarOverlayProtectionEnabled else { return }
            userDefaults.set(titleBarOverlayProtectionEnabled, forKey: Keys.titleBarOverlayProtectionEnabled)
            DebugLog.info(
                DebugLog.settings,
                "Title-bar overlay protection enabled set to \(titleBarOverlayProtectionEnabled)"
            )
            notifyDidChange(.advancedGestureBehavior)
        }
    }

    var smartPinchExitFullScreenEnabled: Bool {
        didSet {
            guard oldValue != smartPinchExitFullScreenEnabled else { return }
            userDefaults.set(smartPinchExitFullScreenEnabled, forKey: Keys.smartPinchExitFullScreenEnabled)
            DebugLog.info(
                DebugLog.settings,
                "Smart pinch out of Full Screen enabled set to \(smartPinchExitFullScreenEnabled)"
            )
            notifyDidChange(.advancedGestureBehavior)
        }
    }

    var smartBrowserTabCloseEnabled: Bool {
        didSet {
            if smartBrowserTabCloseEnabled, !experimentalBrowserTabCloseEnabled {
                smartBrowserTabCloseEnabled = false
                return
            }
            guard oldValue != smartBrowserTabCloseEnabled else { return }
            userDefaults.set(smartBrowserTabCloseEnabled, forKey: Keys.smartBrowserTabCloseEnabled)
            DebugLog.info(
                DebugLog.settings,
                "Smart browser tab close enabled set to \(smartBrowserTabCloseEnabled)"
            )
            notifyDidChange(.advancedGestureBehavior)
        }
    }

    var pinchCloseConfirmationEnabled: Bool {
        didSet {
            if pinchCloseConfirmationEnabled, !experimentalBrowserTabCloseEnabled {
                pinchCloseConfirmationEnabled = false
                return
            }
            guard oldValue != pinchCloseConfirmationEnabled else { return }
            userDefaults.set(pinchCloseConfirmationEnabled, forKey: Keys.pinchCloseConfirmationEnabled)
            DebugLog.info(
                DebugLog.settings,
                "Pinch close confirmation enabled set to \(pinchCloseConfirmationEnabled)"
            )
            notifyDidChange(.advancedGestureBehavior)
        }
    }

    var closeAndQuitConfirmationEnabled: Bool {
        didSet {
            guard oldValue != closeAndQuitConfirmationEnabled else { return }
            userDefaults.set(closeAndQuitConfirmationEnabled, forKey: Keys.closeAndQuitConfirmationEnabled)
            DebugLog.info(
                DebugLog.settings,
                "Close and quit confirmation enabled set to \(closeAndQuitConfirmationEnabled)"
            )
            notifyDidChange(.advancedGestureBehavior)
        }
    }

    var experimentalBrowserTabCloseEnabled: Bool {
        didSet {
            guard oldValue != experimentalBrowserTabCloseEnabled else { return }
            userDefaults.set(experimentalBrowserTabCloseEnabled, forKey: Keys.experimentalBrowserTabCloseEnabled)
            if !experimentalBrowserTabCloseEnabled {
                smartBrowserTabCloseEnabled = false
                pinchCloseConfirmationEnabled = false
                removeBrowserTabCloseGestureActions()
            } else if userDefaults.object(forKey: Keys.pinchCloseConfirmationEnabled) == nil {
                pinchCloseConfirmationEnabled = true
            }
            DebugLog.info(
                DebugLog.settings,
                "Experimental browser tab close enabled set to \(experimentalBrowserTabCloseEnabled)"
            )
            notifyDidChange(.advancedGestureBehavior)
        }
    }

    var experimentalDisplayMoveActionsEnabled: Bool {
        didSet {
            guard oldValue != experimentalDisplayMoveActionsEnabled else { return }
            userDefaults.set(experimentalDisplayMoveActionsEnabled, forKey: Keys.experimentalDisplayMoveActionsEnabled)
            DebugLog.info(
                DebugLog.settings,
                "Experimental display move actions enabled set to \(experimentalDisplayMoveActionsEnabled)"
            )
            notifyDidChange([
                .hotKeys,
                .gestureMonitoring,
                .statusMenu,
                .gestureHUD,
                .advancedGestureBehavior,
            ])
        }
    }

    // Deprecated: retained for the legacy preview-mode flow that defers gesture
    // commits until finger release. Keep persisting it until that path is
    // removed from DockGestureController and the onboarding/settings UI.
    var executeGestureOnRelease: Bool {
        didSet {
            guard oldValue != executeGestureOnRelease else { return }
            userDefaults.set(executeGestureOnRelease, forKey: Keys.executeGestureOnRelease)
            DebugLog.info(DebugLog.settings, "Execute gesture on release set to \(executeGestureOnRelease)")
            notifyDidChange(.advancedGestureBehavior)
        }
    }

    // Deprecated: reverse cancel only affects the legacy preview-mode flow
    // above, but the value is still persisted for compatibility.
    var reverseCancelEnabled: Bool {
        didSet {
            guard oldValue != reverseCancelEnabled else { return }
            userDefaults.set(reverseCancelEnabled, forKey: Keys.reverseCancelEnabled)
            DebugLog.info(DebugLog.settings, "Reverse cancel enabled set to \(reverseCancelEnabled)")
            notifyDidChange(.advancedGestureBehavior)
        }
    }

    // Deprecated: sensitivity tuning for the legacy preview-mode reverse-cancel
    // behavior. Remove with executeGestureOnRelease once that path is gone.
    var reverseCancelSensitivity: Double {
        didSet {
            if let clampedValue = clampedAdvancedGestureDouble(
                currentValue: reverseCancelSensitivity,
                oldValue: oldValue,
                clamp: Self.clampSensitivity,
                forKey: Keys.reverseCancelSensitivity,
                logLabel: "Reverse cancel sensitivity"
            ) {
                reverseCancelSensitivity = clampedValue
            }
        }
    }

    var swipeSensitivity: Double {
        didSet {
            if let clampedValue = clampedAdvancedGestureDouble(
                currentValue: swipeSensitivity,
                oldValue: oldValue,
                clamp: Self.clampSensitivity,
                forKey: Keys.swipeSensitivity,
                logLabel: "Swipe sensitivity"
            ) {
                swipeSensitivity = clampedValue
            }
        }
    }

    var pinchSensitivity: Double {
        didSet {
            if let clampedValue = clampedAdvancedGestureDouble(
                currentValue: pinchSensitivity,
                oldValue: oldValue,
                clamp: Self.clampSensitivity,
                forKey: Keys.pinchSensitivity,
                logLabel: "Pinch sensitivity"
            ) {
                pinchSensitivity = clampedValue
            }
        }
    }

    var titleBarTriggerHeight: Double {
        didSet {
            if let clampedValue = clampedAdvancedGestureDouble(
                currentValue: titleBarTriggerHeight,
                oldValue: oldValue,
                clamp: Self.clampTitleBarTriggerHeight,
                forKey: Keys.titleBarTriggerHeight,
                logLabel: "Title-bar trigger height"
            ) {
                titleBarTriggerHeight = clampedValue
            }
        }
    }

    var titleBarCornerDragHoldDuration: Double {
        didSet {
            if let clampedValue = clampedAdvancedGestureDouble(
                currentValue: titleBarCornerDragHoldDuration,
                oldValue: oldValue,
                clamp: Self.clampTitleBarCornerDragHoldDuration,
                forKey: Keys.titleBarCornerDragHoldDuration,
                logLabel: "Title-bar corner drag hold duration"
            ) {
                titleBarCornerDragHoldDuration = clampedValue
            }
        }
    }

    var gestureHUDStyle: GestureHUDStyle {
        didSet {
            guard oldValue != gestureHUDStyle else { return }
            userDefaults.set(gestureHUDStyle.storageValue, forKey: Keys.gestureHUDStyle)
            DebugLog.info(DebugLog.settings, "Gesture HUD style set to \(gestureHUDStyle.storageValue)")
            notifyDidChange(.gestureHUD)
        }
    }

    var statusItemIcon: StatusItemIcon {
        didSet {
            guard oldValue != statusItemIcon else { return }
            userDefaults.set(statusItemIcon.storageValue, forKey: Keys.statusItemIcon)
            DebugLog.info(DebugLog.settings, "Status item icon set to \(statusItemIcon.storageValue)")
            notifyDidChange([.statusItemAppearance, .statusMenu])
        }
    }

    var collapseStatusItemWindowActions: Bool {
        didSet {
            guard oldValue != collapseStatusItemWindowActions else { return }
            userDefaults.set(collapseStatusItemWindowActions, forKey: Keys.collapseStatusItemWindowActions)
            DebugLog.info(
                DebugLog.settings,
                "Collapse status-item window actions set to \(collapseStatusItemWindowActions)"
            )
            notifyDidChange(.statusMenu)
        }
    }

    var hasSeenWelcomeGuide: Bool {
        didSet {
            guard oldValue != hasSeenWelcomeGuide else { return }
            userDefaults.set(hasSeenWelcomeGuide, forKey: Keys.hasSeenWelcomeGuide)
        }
    }

    var debugLoggingEnabled: Bool {
        didSet {
            guard oldValue != debugLoggingEnabled else { return }
            userDefaults.set(debugLoggingEnabled, forKey: Keys.debugLoggingEnabled)
            DebugLog.info(DebugLog.settings, "Debug logging enabled set to \(debugLoggingEnabled)")
            notifyDidChange()
        }
    }

    var hotKeyBindings: [HotKeyBinding] {
        didSet {
            guard oldValue != hotKeyBindings else { return }
            persistHotKeyBindings()
            DebugLog.debug(DebugLog.settings, "Persisted \(hotKeyBindings.count) hot key bindings")
            notifyDidChange(.hotKeys)
        }
    }

    var dockGestureBindings: [DockGestureBinding] {
        didSet {
            guard oldValue != dockGestureBindings else { return }
            persistDockGestureBindings()
            DebugLog.debug(DebugLog.settings, "Persisted \(dockGestureBindings.count) Dock gesture bindings")
            notifyDidChange([.gestureMonitoring, .gestureHUD])
        }
    }

    var titleBarGestureBindings: [TitleBarGestureBinding] {
        didSet {
            guard oldValue != titleBarGestureBindings else { return }
            persistTitleBarGestureBindings()
            DebugLog.debug(DebugLog.settings, "Persisted \(titleBarGestureBindings.count) title-bar gesture bindings")
            notifyDidChange([.gestureMonitoring, .gestureHUD])
        }
    }

    var preferredLanguages: [String] {
        languageOverride.preferredLanguages ?? Locale.preferredLanguages
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.languageOverride = AppLanguage(
            rawValue: userDefaults.string(forKey: Keys.languageOverride) ?? ""
        ) ?? .system
        self.hotKeysEnabled = Self.boolValue(
            forKey: Keys.hotKeysEnabled,
            defaultValue: true,
            in: userDefaults
        )
        self.dockGesturesEnabled = Self.boolValue(
            forKey: Keys.dockGesturesEnabled,
            defaultValue: true,
            in: userDefaults
        )
        self.titleBarGesturesEnabled = Self.boolValue(
            forKey: Keys.titleBarGesturesEnabled,
            defaultValue: true,
            in: userDefaults
        )
        self.dockCornerDragSnapEnabled = Self.boolValue(
            forKey: Keys.dockCornerDragSnapEnabled,
            defaultValue: true,
            in: userDefaults
        )
        self.titleBarCornerDragSnapEnabled = Self.boolValue(
            forKey: Keys.titleBarCornerDragSnapEnabled,
            defaultValue: true,
            in: userDefaults
        )
        self.smartPinchExitFullScreenEnabled = Self.boolValue(
            forKey: Keys.smartPinchExitFullScreenEnabled,
            defaultValue: true,
            in: userDefaults
        )
        let experimentalBrowserTabCloseEnabled = Self.boolValue(
            forKey: Keys.experimentalBrowserTabCloseEnabled,
            defaultValue: false,
            in: userDefaults
        )
        let smartBrowserTabCloseEnabled = Self.boolValue(
            forKey: Keys.smartBrowserTabCloseEnabled,
            defaultValue: false,
            in: userDefaults
        )
        let pinchCloseConfirmationEnabled = Self.boolValue(
            forKey: Keys.pinchCloseConfirmationEnabled,
            defaultValue: false,
            in: userDefaults
        )
        self.smartBrowserTabCloseEnabled = experimentalBrowserTabCloseEnabled ? smartBrowserTabCloseEnabled : false
        self.experimentalBrowserTabCloseEnabled = experimentalBrowserTabCloseEnabled
        self.pinchCloseConfirmationEnabled = experimentalBrowserTabCloseEnabled ? pinchCloseConfirmationEnabled : false
        self.experimentalDisplayMoveActionsEnabled = Self.boolValue(
            forKey: Keys.experimentalDisplayMoveActionsEnabled,
            defaultValue: false,
            in: userDefaults
        )
        self.closeAndQuitConfirmationEnabled = Self.boolValue(
            forKey: Keys.closeAndQuitConfirmationEnabled,
            defaultValue: false,
            in: userDefaults
        )
        self.titleBarOverlayProtectionEnabled = Self.boolValue(
            forKey: Keys.titleBarOverlayProtectionEnabled,
            defaultValue: true,
            in: userDefaults
        )
        
        // Deprecated preview-mode settings still load from UserDefaults so
        // older installs keep behaving consistently until the flow is removed.
        self.executeGestureOnRelease = Self.boolValue(
            forKey: Keys.executeGestureOnRelease,
            defaultValue: false,
            in: userDefaults
        )
        self.reverseCancelEnabled = Self.boolValue(
            forKey: Keys.reverseCancelEnabled,
            defaultValue: true,
            in: userDefaults
        )
        self.reverseCancelSensitivity = Self.clampSensitivity(
            Self.doubleValue(
                forKey: Keys.reverseCancelSensitivity,
                defaultValue: 0.5,
                in: userDefaults
            )
        )
        self.swipeSensitivity = Self.clampSensitivity(
            Self.doubleValue(
                forKey: Keys.swipeSensitivity,
                defaultValue: 0.5,
                in: userDefaults
            )
        )
        self.pinchSensitivity = Self.clampSensitivity(
            Self.doubleValue(
                forKey: Keys.pinchSensitivity,
                defaultValue: 0.5,
                in: userDefaults
            )
        )
        self.titleBarTriggerHeight = Self.clampTitleBarTriggerHeight(
            Self.doubleValue(
                forKey: Keys.titleBarTriggerHeight,
                defaultValue: Self.defaultTitleBarTriggerHeight,
                in: userDefaults
            )
        )
        self.titleBarCornerDragHoldDuration = Self.clampTitleBarCornerDragHoldDuration(
            Self.doubleValue(
                forKey: Keys.titleBarCornerDragHoldDuration,
                defaultValue: Self.defaultTitleBarCornerDragHoldDuration,
                in: userDefaults
            )
        )
        self.gestureHUDStyle = GestureHUDStyle(
            storageValue: userDefaults.string(forKey: Keys.gestureHUDStyle)
        )
        self.statusItemIcon = StatusItemIcon(
            storageValue: userDefaults.string(forKey: Keys.statusItemIcon)
        )
        self.collapseStatusItemWindowActions = Self.boolValue(
            forKey: Keys.collapseStatusItemWindowActions,
            defaultValue: true,
            in: userDefaults
        )
        self.hasSeenWelcomeGuide = Self.boolValue(
            forKey: Keys.hasSeenWelcomeGuide,
            defaultValue: false,
            in: userDefaults
        )
        self.debugLoggingEnabled = Self.boolValue(
            forKey: Keys.debugLoggingEnabled,
            defaultValue: false,
            in: userDefaults
        )
        self.hotKeyBindings = Self.decodeHotKeyBindings(from: userDefaults) ?? HotKeyBindings.defaults
        let decodedDockGestureBindings = Self.decodeDockGestureBindings(from: userDefaults) ?? DockGestureBindings.defaults
        let decodedTitleBarGestureBindings = Self.decodeTitleBarGestureBindings(from: userDefaults) ?? TitleBarGestureBindings.defaults

        if experimentalBrowserTabCloseEnabled {
            self.dockGestureBindings = decodedDockGestureBindings
            self.titleBarGestureBindings = decodedTitleBarGestureBindings
        } else {
            self.dockGestureBindings = Self.dockGestureBindingsWithoutBrowserTabClose(decodedDockGestureBindings)
            self.titleBarGestureBindings = Self.titleBarGestureBindingsWithoutBrowserTabClose(decodedTitleBarGestureBindings)
        }

        L10n.setPreferredLanguagesOverride(self.preferredLanguages)

        if dockGestureBindings != decodedDockGestureBindings {
            persistDockGestureBindings()
        }
        if titleBarGestureBindings != decodedTitleBarGestureBindings {
            persistTitleBarGestureBindings()
        }
        if !experimentalBrowserTabCloseEnabled {
            if smartBrowserTabCloseEnabled {
                userDefaults.set(false, forKey: Keys.smartBrowserTabCloseEnabled)
            }
            if pinchCloseConfirmationEnabled {
                userDefaults.set(false, forKey: Keys.pinchCloseConfirmationEnabled)
            }
        }
    }

    static func resetPersistedConfiguration(in userDefaults: UserDefaults = .standard) {
        let keysToReset = [
            Keys.languageOverride,
            Keys.hotKeysEnabled,
            Keys.dockGesturesEnabled,
            Keys.titleBarGesturesEnabled,
            Keys.dockCornerDragSnapEnabled,
            Keys.titleBarCornerDragSnapEnabled,
            Keys.titleBarOverlayProtectionEnabled,
            Keys.smartPinchExitFullScreenEnabled,
            Keys.smartBrowserTabCloseEnabled,
            Keys.pinchCloseConfirmationEnabled,
            Keys.closeAndQuitConfirmationEnabled,
            Keys.executeGestureOnRelease,
            Keys.reverseCancelEnabled,
            Keys.reverseCancelSensitivity,
            Keys.swipeSensitivity,
            Keys.pinchSensitivity,
            Keys.titleBarTriggerHeight,
            Keys.titleBarCornerDragHoldDuration,
            Keys.gestureHUDStyle,
            Keys.statusItemIcon,
            Keys.collapseStatusItemWindowActions,
            Keys.debugLoggingEnabled,
            Keys.hotKeyBindings,
            Keys.dockGestureBindings,
            Keys.titleBarGestureBindings,
            Keys.hasSeenWelcomeGuide,
        ]

        // Intentionally preserve experimental opt-in flags here.
        // `--reset-user-config` is meant to restore everyday preferences while
        // keeping the user's explicit experimental opt-in state across launches.

        for key in keysToReset {
            userDefaults.removeObject(forKey: key)
        }
    }

    func localized(_ key: String) -> String {
        L10n.string(key, preferredLanguages: preferredLanguages)
    }

    func hotKeyBinding(for action: WindowAction) -> HotKeyBinding {
        hotKeyBindings.first(where: { $0.action == action }) ?? fallbackBinding(for: action)
    }

    var availableWindowActions: [WindowAction] {
        WindowAction.allCases.filter(isWindowActionAvailable)
    }

    var availableWindowGestureActions: [WindowAction] {
        WindowAction.gestureCases.filter(isWindowActionAvailable)
    }

    var availableDockGestureActions: [DockGestureAction] {
        DockGestureAction.allCases.filter(isDockGestureActionAvailable)
    }

    func isWindowActionAvailable(_ action: WindowAction) -> Bool {
        experimentalDisplayMoveActionsEnabled || !action.isDisplayMoveAction
    }

    func isDockGestureActionAvailable(_ action: DockGestureAction) -> Bool {
        experimentalDisplayMoveActionsEnabled || !action.isDisplayMoveAction
    }

    func updateHotKeyKey(_ key: ShortcutKey, for action: WindowAction) {
        let current = hotKeyBinding(for: action)
        updateHotKeyBinding(
            HotKeyBinding(action: action, key: key, modifiers: current.modifiers)
        )
    }

    func updateHotKeyModifiers(_ modifiers: ShortcutModifierSet, for action: WindowAction) {
        let current = hotKeyBinding(for: action)
        updateHotKeyBinding(
            HotKeyBinding(action: action, key: current.key, modifiers: modifiers)
        )
    }

    func updateHotKeyBinding(_ binding: HotKeyBinding) {
        var newBindings = hotKeyBindings
        let currentBinding = hotKeyBinding(for: binding.action)

        if let conflictIndex = newBindings.firstIndex(where: {
            $0.action != binding.action && $0.key == binding.key && $0.modifiers == binding.modifiers
        }) {
            let conflictingAction = newBindings[conflictIndex].action
            newBindings[conflictIndex] = HotKeyBinding(
                action: conflictingAction,
                key: currentBinding.key,
                modifiers: currentBinding.modifiers
            )
        }

        if let currentIndex = newBindings.firstIndex(where: { $0.action == binding.action }) {
            newBindings[currentIndex] = binding
        } else {
            newBindings.append(binding)
        }

        hotKeyBindings = newBindings.sorted { $0.action.rawValue < $1.action.rawValue }
    }

    func resetHotKeysToDefaults() {
        hotKeyBindings = HotKeyBindings.defaults
    }

    func dockGestureBinding(for gesture: DockGestureKind) -> DockGestureBinding {
        DockGestureBindings.binding(for: gesture, in: dockGestureBindings)
    }

    func dockGestureAction(for gesture: DockGestureKind) -> DockGestureAction {
        let binding = dockGestureBinding(for: gesture)
        return dockGestureActionIfAvailable(binding.action, for: gesture)
    }

    func dockGestureIsEnabled(for gesture: DockGestureKind) -> Bool {
        dockGestureBinding(for: gesture).isEnabled
    }

    func updateDockGestureEnabled(_ isEnabled: Bool, for gesture: DockGestureKind) {
        updateDockGestureBinding(
            DockGestureBinding(
                gesture: gesture,
                isEnabled: isEnabled,
                action: dockGestureBinding(for: gesture).action
            )
        )
    }

    func updateDockGestureAction(_ action: DockGestureAction, for gesture: DockGestureKind) {
        let current = dockGestureBinding(for: gesture)
        let nextAction = experimentalBrowserTabCloseEnabled
            ? action
            : Self.dockGestureActionWithoutBrowserTabClose(action, for: gesture)
        let availableAction = dockGestureActionIfAvailable(nextAction, for: gesture)
        updateDockGestureBinding(
            DockGestureBinding(
                gesture: gesture,
                isEnabled: current.isEnabled,
                action: availableAction
            )
        )
    }

    func resetDockGestureActionsToDefaults() {
        dockGestureBindings = DockGestureBindings.defaults
    }

    private func updateDockGestureBinding(_ binding: DockGestureBinding) {
        guard let newBindings = Self.updatedGestureBindings(
            dockGestureBindings,
            replacing: binding,
            gestureOf: \.gesture
        ) else { return }

        dockGestureBindings = newBindings
    }

    func titleBarGestureBinding(for gesture: DockGestureKind) -> TitleBarGestureBinding? {
        TitleBarGestureBindings.binding(for: gesture, in: titleBarGestureBindings)
    }

    func titleBarGestureAction(for gesture: DockGestureKind) -> WindowAction? {
        guard let binding = titleBarGestureBinding(for: gesture) else { return nil }
        return titleBarGestureActionIfAvailable(binding.action, for: gesture)
    }

    func titleBarGestureIsEnabled(for gesture: DockGestureKind) -> Bool {
        titleBarGestureBinding(for: gesture)?.isEnabled ?? false
    }

    func updateTitleBarGestureEnabled(_ isEnabled: Bool, for gesture: DockGestureKind) {
        guard let current = titleBarGestureBinding(for: gesture) else { return }
        updateTitleBarGestureBinding(
            TitleBarGestureBinding(
                gesture: gesture,
                isEnabled: isEnabled,
                action: current.action
            )
        )
    }

    func updateTitleBarGestureAction(_ action: WindowAction, for gesture: DockGestureKind) {
        guard let current = titleBarGestureBinding(for: gesture) else { return }
        let nextAction = experimentalBrowserTabCloseEnabled
            ? action
            : Self.titleBarGestureActionWithoutBrowserTabClose(action, for: gesture)
        let availableAction = titleBarGestureActionIfAvailable(nextAction, for: gesture)
        updateTitleBarGestureBinding(
            TitleBarGestureBinding(
                gesture: gesture,
                isEnabled: current.isEnabled,
                action: availableAction
            )
        )
    }

    func resetTitleBarGestureActionsToDefaults() {
        titleBarGestureBindings = TitleBarGestureBindings.defaults
    }

    func consumeWelcomeGuidePresentationFlag() -> Bool {
        guard !hasSeenWelcomeGuide else {
            return false
        }

        hasSeenWelcomeGuide = true
        return true
    }

    private func updateTitleBarGestureBinding(_ binding: TitleBarGestureBinding) {
        guard let newBindings = Self.updatedGestureBindings(
            titleBarGestureBindings,
            replacing: binding,
            gestureOf: \.gesture
        ) else { return }

        titleBarGestureBindings = newBindings
    }

    private static func updatedGestureBindings<Binding: Equatable>(
        _ bindings: [Binding],
        replacing binding: Binding,
        gestureOf: (Binding) -> DockGestureKind
    ) -> [Binding]? {
        var newBindings = bindings
        let bindingGesture = gestureOf(binding)

        if let index = newBindings.firstIndex(where: { gestureOf($0) == bindingGesture }) {
            guard newBindings[index] != binding else { return nil }
            newBindings[index] = binding
        } else {
            newBindings.append(binding)
        }

        return newBindings.sorted { lhs, rhs in
            gestureOf(lhs).rawValue < gestureOf(rhs).rawValue
        }
    }

    private func removeBrowserTabCloseGestureActions() {
        let nextDockGestureBindings = Self.dockGestureBindingsWithoutBrowserTabClose(dockGestureBindings)
        if nextDockGestureBindings != dockGestureBindings {
            dockGestureBindings = nextDockGestureBindings
        }

        let nextTitleBarGestureBindings = Self.titleBarGestureBindingsWithoutBrowserTabClose(titleBarGestureBindings)
        if nextTitleBarGestureBindings != titleBarGestureBindings {
            titleBarGestureBindings = nextTitleBarGestureBindings
        }
    }

    private static func dockGestureBindingsWithoutBrowserTabClose(
        _ bindings: [DockGestureBinding]
    ) -> [DockGestureBinding] {
        bindings.map { binding in
            DockGestureBinding(
                gesture: binding.gesture,
                isEnabled: binding.isEnabled,
                action: dockGestureActionWithoutBrowserTabClose(
                    binding.action,
                    for: binding.gesture
                )
            )
        }
    }

    private static func titleBarGestureBindingsWithoutBrowserTabClose(
        _ bindings: [TitleBarGestureBinding]
    ) -> [TitleBarGestureBinding] {
        bindings.map { binding in
            TitleBarGestureBinding(
                gesture: binding.gesture,
                isEnabled: binding.isEnabled,
                action: titleBarGestureActionWithoutBrowserTabClose(
                    binding.action,
                    for: binding.gesture
                )
            )
        }
    }

    private static func dockGestureActionWithoutBrowserTabClose(
        _ action: DockGestureAction,
        for gesture: DockGestureKind
    ) -> DockGestureAction {
        action == .closeTab ? DockGestureBindings.fallbackBinding(for: gesture).action : action
    }

    private static func titleBarGestureActionWithoutBrowserTabClose(
        _ action: WindowAction,
        for gesture: DockGestureKind
    ) -> WindowAction {
        action == .closeTab ? TitleBarGestureBindings.fallbackBinding(for: gesture).action : action
    }

    private func dockGestureActionIfAvailable(
        _ action: DockGestureAction,
        for gesture: DockGestureKind
    ) -> DockGestureAction {
        isDockGestureActionAvailable(action) ? action : DockGestureBindings.fallbackBinding(for: gesture).action
    }

    private func titleBarGestureActionIfAvailable(
        _ action: WindowAction,
        for gesture: DockGestureKind
    ) -> WindowAction {
        isWindowActionAvailable(action) ? action : TitleBarGestureBindings.fallbackBinding(for: gesture).action
    }

    private func notifyDidChange(_ categories: SettingsChangeCategory = []) {
        pendingChangeCategories.formUnion(categories)

        // Multiple settings often flip together from one UI interaction; coalesce
        // them into a single notification so observers rebuild once per run loop.
        guard !notificationDispatchPending else {
            return
        }

        notificationDispatchPending = true
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.notificationDispatchPending = false
            let categories = self.pendingChangeCategories
            self.pendingChangeCategories = []
            NotificationCenter.default.post(
                name: .settingsDidChange,
                object: self,
                userInfo: [Notification.settingsChangeCategoriesUserInfoKey: categories.rawValue]
            )
        }
    }

    private func fallbackBinding(for action: WindowAction) -> HotKeyBinding {
        HotKeyBindings.binding(for: action) ?? HotKeyBinding(
            action: action,
            key: .a,
            modifiers: .commandOptionControl
        )
    }

    private static func boolValue(
        forKey key: String,
        defaultValue: Bool,
        in userDefaults: UserDefaults
    ) -> Bool {
        guard userDefaults.object(forKey: key) != nil else {
            return defaultValue
        }

        return userDefaults.bool(forKey: key)
    }

    private static func doubleValue(
        forKey key: String,
        defaultValue: Double,
        in userDefaults: UserDefaults
    ) -> Double {
        guard userDefaults.object(forKey: key) != nil else {
            return defaultValue
        }

        return userDefaults.double(forKey: key)
    }

    func resetAdvancedSettingsToDefaults() {
        reverseCancelEnabled = true
        reverseCancelSensitivity = 0.5
        swipeSensitivity = 0.5
        pinchSensitivity = 0.5
        titleBarTriggerHeight = Self.defaultTitleBarTriggerHeight
        titleBarCornerDragHoldDuration = Self.defaultTitleBarCornerDragHoldDuration
        titleBarOverlayProtectionEnabled = true
        smartPinchExitFullScreenEnabled = true
        smartBrowserTabCloseEnabled = false
        pinchCloseConfirmationEnabled = false
        closeAndQuitConfirmationEnabled = false
        experimentalBrowserTabCloseEnabled = false
        experimentalDisplayMoveActionsEnabled = false
    }

    static let defaultTitleBarTriggerHeight: Double = 32
    static let minimumTitleBarTriggerHeight: Double = 24
    static let maximumTitleBarTriggerHeight: Double = 56
    static let defaultTitleBarCornerDragHoldDuration: Double = 0.2
    static let minimumTitleBarCornerDragHoldDuration: Double = 0.2
    static let maximumTitleBarCornerDragHoldDuration: Double = 1.5

    static func clampTitleBarTriggerHeight(_ value: Double) -> Double {
        min(maximumTitleBarTriggerHeight, max(minimumTitleBarTriggerHeight, value))
    }

    static func clampTitleBarCornerDragHoldDuration(_ value: Double) -> Double {
        min(maximumTitleBarCornerDragHoldDuration, max(minimumTitleBarCornerDragHoldDuration, value))
    }

    private static func clampSensitivity(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0.5
        }

        return min(1, max(0, value))
    }

    private func persistAdvancedGestureDouble(
        _ value: Double,
        forKey key: String,
        logMessage: String
    ) {
        userDefaults.set(value, forKey: key)
        DebugLog.info(DebugLog.settings, logMessage)
        notifyDidChange([.gestureMonitoring, .advancedGestureBehavior])
    }

    private func clampedAdvancedGestureDouble(
        currentValue: Double,
        oldValue: Double,
        clamp: (Double) -> Double,
        forKey key: String,
        logLabel: String
    ) -> Double? {
        let clampedValue = clamp(currentValue)

        guard currentValue == clampedValue else {
            return clampedValue
        }

        guard oldValue != clampedValue else {
            return nil
        }

        persistAdvancedGestureDouble(
            clampedValue,
            forKey: key,
            logMessage: "\(logLabel) set to \(clampedValue)"
        )
        return nil
    }

    private func persistHotKeyBindings() {
        persistEncoded(hotKeyBindings, key: Keys.hotKeyBindings, description: "hot key bindings")
    }

    private func persistDockGestureBindings() {
        persistEncoded(dockGestureBindings, key: Keys.dockGestureBindings, description: "Dock gesture bindings")
    }

    private func persistTitleBarGestureBindings() {
        persistEncoded(
            titleBarGestureBindings,
            key: Keys.titleBarGestureBindings,
            description: "title-bar gesture bindings"
        )
    }

    private func persistEncoded<Value: Encodable>(
        _ value: Value,
        key: String,
        description: String
    ) {
        do {
            let data = try JSONEncoder().encode(value)
            userDefaults.set(data, forKey: key)
        } catch {
            DebugLog.error(DebugLog.settings, "Failed to encode \(description): \(error.localizedDescription)")
        }
    }

    private static func decodeHotKeyBindings(from userDefaults: UserDefaults) -> [HotKeyBinding]? {
        decodePersistedBindings(
            [HotKeyBinding].self,
            forKey: Keys.hotKeyBindings,
            in: userDefaults,
            failureDescription: "hot key bindings"
        )
    }

    private static func decodeDockGestureBindings(from userDefaults: UserDefaults) -> [DockGestureBinding]? {
        decodePersistedBindings(
            [DockGestureBinding].self,
            forKey: Keys.dockGestureBindings,
            in: userDefaults,
            failureDescription: "Dock gesture bindings"
        )
    }

    private static func decodeTitleBarGestureBindings(from userDefaults: UserDefaults) -> [TitleBarGestureBinding]? {
        decodePersistedBindings(
            [TitleBarGestureBinding].self,
            forKey: Keys.titleBarGestureBindings,
            in: userDefaults,
            failureDescription: "title-bar gesture bindings"
        )
    }

    private static func decodePersistedBindings<Value: Decodable>(
        _ type: Value.Type,
        forKey key: String,
        in userDefaults: UserDefaults,
        failureDescription: String
    ) -> Value? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            DebugLog.error(
                DebugLog.settings,
                "Failed to decode \(failureDescription), clearing stored value and falling back to defaults: \(error.localizedDescription)"
            )
            userDefaults.removeObject(forKey: key)
            return nil
        }
    }

    private enum Keys {
        static let languageOverride = "settings.languageOverride"
        static let hotKeysEnabled = "settings.hotKeysEnabled"
        static let dockGesturesEnabled = "settings.dockGesturesEnabled"
        static let titleBarGesturesEnabled = "settings.titleBarGesturesEnabled"
        static let dockCornerDragSnapEnabled = "settings.dockCornerDragSnapEnabled"
        static let titleBarCornerDragSnapEnabled = "settings.titleBarCornerDragSnapEnabled"
        static let titleBarOverlayProtectionEnabled = "settings.titleBarOverlayProtectionEnabled"
        static let smartPinchExitFullScreenEnabled = "settings.smartPinchExitFullScreenEnabled"
        static let smartBrowserTabCloseEnabled = "settings.smartBrowserTabCloseEnabled"
        static let pinchCloseConfirmationEnabled = "settings.pinchCloseConfirmationEnabled"
        static let closeAndQuitConfirmationEnabled = "settings.closeAndQuitConfirmationEnabled"
        static let experimentalBrowserTabCloseEnabled = "settings.experimentalBrowserTabCloseEnabled"
        static let experimentalDisplayMoveActionsEnabled = "settings.experimentalDisplayMoveActionsEnabled"
        // Deprecated preview-mode persistence keys.
        static let executeGestureOnRelease = "settings.executeGestureOnRelease"
        static let reverseCancelEnabled = "settings.reverseCancelEnabled"
        static let reverseCancelSensitivity = "settings.reverseCancelSensitivity"
        static let swipeSensitivity = "settings.swipeSensitivity"
        static let pinchSensitivity = "settings.pinchSensitivity"
        static let titleBarTriggerHeight = "settings.titleBarTriggerHeight"
        static let titleBarCornerDragHoldDuration = "settings.titleBarCornerDragHoldDuration"
        static let gestureHUDStyle = "settings.gestureHUDStyle"
        static let statusItemIcon = "settings.statusItemIcon"
        static let collapseStatusItemWindowActions = "settings.collapseStatusItemWindowActions"
        static let hasSeenWelcomeGuide = "settings.hasSeenWelcomeGuide"
        static let debugLoggingEnabled = "settings.debugLoggingEnabled"
        static let hotKeyBindings = "settings.hotKeyBindings"
        static let dockGestureBindings = "settings.dockGestureBindings"
        static let titleBarGestureBindings = "settings.titleBarGestureBindings"
    }
}
