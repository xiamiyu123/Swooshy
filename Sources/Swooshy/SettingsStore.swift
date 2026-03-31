import Foundation
import Observation

extension Notification.Name {
    static let settingsDidChange = Notification.Name("Swooshy.settingsDidChange")
}

@MainActor
@Observable
final class SettingsStore {
    @ObservationIgnored
    private let userDefaults: UserDefaults
    @ObservationIgnored
    private var notificationDispatchPending = false

    var languageOverride: AppLanguage {
        didSet {
            guard oldValue != languageOverride else { return }
            userDefaults.set(languageOverride.rawValue, forKey: Keys.languageOverride)
            L10n.setPreferredLanguagesOverride(preferredLanguages)
            notifyDidChange()
        }
    }

    var hotKeysEnabled: Bool {
        didSet {
            guard oldValue != hotKeysEnabled else { return }
            userDefaults.set(hotKeysEnabled, forKey: Keys.hotKeysEnabled)
            notifyDidChange()
        }
    }

    var dockGesturesEnabled: Bool {
        didSet {
            guard oldValue != dockGesturesEnabled else { return }
            userDefaults.set(dockGesturesEnabled, forKey: Keys.dockGesturesEnabled)
            DebugLog.info(DebugLog.settings, "Dock gestures enabled set to \(dockGesturesEnabled)")
            notifyDidChange()
        }
    }

    var titleBarGesturesEnabled: Bool {
        didSet {
            guard oldValue != titleBarGesturesEnabled else { return }
            userDefaults.set(titleBarGesturesEnabled, forKey: Keys.titleBarGesturesEnabled)
            DebugLog.info(DebugLog.settings, "Title-bar gestures enabled set to \(titleBarGesturesEnabled)")
            notifyDidChange()
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
            notifyDidChange()
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
            notifyDidChange()
        }
    }

    var executeGestureOnRelease: Bool {
        didSet {
            guard oldValue != executeGestureOnRelease else { return }
            userDefaults.set(executeGestureOnRelease, forKey: Keys.executeGestureOnRelease)
            DebugLog.info(DebugLog.settings, "Execute gesture on release set to \(executeGestureOnRelease)")
            notifyDidChange()
        }
    }

    var reverseCancelEnabled: Bool {
        didSet {
            guard oldValue != reverseCancelEnabled else { return }
            userDefaults.set(reverseCancelEnabled, forKey: Keys.reverseCancelEnabled)
            DebugLog.info(DebugLog.settings, "Reverse cancel enabled set to \(reverseCancelEnabled)")
            notifyDidChange()
        }
    }

    var reverseCancelSensitivity: Double {
        didSet {
            guard oldValue != reverseCancelSensitivity else { return }
            userDefaults.set(reverseCancelSensitivity, forKey: Keys.reverseCancelSensitivity)
            DebugLog.info(DebugLog.settings, "Reverse cancel sensitivity set to \(reverseCancelSensitivity)")
            notifyDidChange()
        }
    }

    var swipeSensitivity: Double {
        didSet {
            guard oldValue != swipeSensitivity else { return }
            userDefaults.set(swipeSensitivity, forKey: Keys.swipeSensitivity)
            DebugLog.info(DebugLog.settings, "Swipe sensitivity set to \(swipeSensitivity)")
            notifyDidChange()
        }
    }

    var pinchSensitivity: Double {
        didSet {
            guard oldValue != pinchSensitivity else { return }
            userDefaults.set(pinchSensitivity, forKey: Keys.pinchSensitivity)
            DebugLog.info(DebugLog.settings, "Pinch sensitivity set to \(pinchSensitivity)")
            notifyDidChange()
        }
    }

    var gestureHUDStyle: GestureHUDStyle {
        didSet {
            guard oldValue != gestureHUDStyle else { return }
            userDefaults.set(gestureHUDStyle.storageValue, forKey: Keys.gestureHUDStyle)
            DebugLog.info(DebugLog.settings, "Gesture HUD style set to \(gestureHUDStyle.storageValue)")
            notifyDidChange()
        }
    }

    var statusItemIcon: StatusItemIcon {
        didSet {
            guard oldValue != statusItemIcon else { return }
            userDefaults.set(statusItemIcon.storageValue, forKey: Keys.statusItemIcon)
            DebugLog.info(DebugLog.settings, "Status item icon set to \(statusItemIcon.storageValue)")
            notifyDidChange()
        }
    }

    var hasSeenWelcomeGuide: Bool {
        didSet {
            guard oldValue != hasSeenWelcomeGuide else { return }
            userDefaults.set(hasSeenWelcomeGuide, forKey: Keys.hasSeenWelcomeGuide)
        }
    }

    #if DEBUG
    var debugLoggingEnabled: Bool {
        didSet {
            guard oldValue != debugLoggingEnabled else { return }
            userDefaults.set(debugLoggingEnabled, forKey: Keys.debugLoggingEnabled)
            DebugLog.info(DebugLog.settings, "Debug logging enabled set to \(debugLoggingEnabled)")
            notifyDidChange()
        }
    }
    #endif

    var hotKeyBindings: [HotKeyBinding] {
        didSet {
            guard oldValue != hotKeyBindings else { return }
            persistHotKeyBindings()
            DebugLog.debug(DebugLog.settings, "Persisted \(hotKeyBindings.count) hot key bindings")
            notifyDidChange()
        }
    }

    var dockGestureBindings: [DockGestureBinding] {
        didSet {
            guard oldValue != dockGestureBindings else { return }
            persistDockGestureBindings()
            DebugLog.debug(DebugLog.settings, "Persisted \(dockGestureBindings.count) Dock gesture bindings")
            notifyDidChange()
        }
    }

    var titleBarGestureBindings: [TitleBarGestureBinding] {
        didSet {
            guard oldValue != titleBarGestureBindings else { return }
            persistTitleBarGestureBindings()
            DebugLog.debug(DebugLog.settings, "Persisted \(titleBarGestureBindings.count) title-bar gesture bindings")
            notifyDidChange()
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
        self.smartPinchExitFullScreenEnabled = Self.boolValue(
            forKey: Keys.smartPinchExitFullScreenEnabled,
            defaultValue: true,
            in: userDefaults
        )
        self.titleBarOverlayProtectionEnabled = Self.boolValue(
            forKey: Keys.titleBarOverlayProtectionEnabled,
            defaultValue: true,
            in: userDefaults
        )
        
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
        self.reverseCancelSensitivity = Self.doubleValue(
            forKey: Keys.reverseCancelSensitivity,
            defaultValue: 0.5,
            in: userDefaults
        )
        self.swipeSensitivity = Self.doubleValue(
            forKey: Keys.swipeSensitivity,
            defaultValue: 0.5,
            in: userDefaults
        )
        self.pinchSensitivity = Self.doubleValue(
            forKey: Keys.pinchSensitivity,
            defaultValue: 0.5,
            in: userDefaults
        )
        self.gestureHUDStyle = GestureHUDStyle(
            storageValue: userDefaults.string(forKey: Keys.gestureHUDStyle)
        )
        self.statusItemIcon = StatusItemIcon(
            storageValue: userDefaults.string(forKey: Keys.statusItemIcon)
        )
        self.hasSeenWelcomeGuide = Self.boolValue(
            forKey: Keys.hasSeenWelcomeGuide,
            defaultValue: false,
            in: userDefaults
        )
        #if DEBUG
        self.debugLoggingEnabled = Self.boolValue(
            forKey: Keys.debugLoggingEnabled,
            defaultValue: false,
            in: userDefaults
        )
        #endif
        self.hotKeyBindings = Self.decodeHotKeyBindings(from: userDefaults) ?? HotKeyBindings.defaults
        self.dockGestureBindings = Self.decodeDockGestureBindings(from: userDefaults) ?? DockGestureBindings.defaults
        self.titleBarGestureBindings = Self.decodeTitleBarGestureBindings(from: userDefaults) ?? TitleBarGestureBindings.defaults

        L10n.setPreferredLanguagesOverride(self.preferredLanguages)
    }

    static func resetPersistedConfiguration(in userDefaults: UserDefaults = .standard) {
        var keysToReset = [
            Keys.languageOverride,
            Keys.hotKeysEnabled,
            Keys.dockGesturesEnabled,
            Keys.titleBarGesturesEnabled,
            Keys.titleBarOverlayProtectionEnabled,
            Keys.executeGestureOnRelease,
            Keys.reverseCancelEnabled,
            Keys.reverseCancelSensitivity,
            Keys.swipeSensitivity,
            Keys.pinchSensitivity,
            Keys.gestureHUDStyle,
            Keys.statusItemIcon,
            Keys.hotKeyBindings,
            Keys.dockGestureBindings,
            Keys.titleBarGestureBindings,
            Keys.hasSeenWelcomeGuide,
        ]

        #if DEBUG
        keysToReset.append(Keys.debugLoggingEnabled)
        #endif

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

        if let currentIndex = newBindings.firstIndex(where: { $0.action == binding.action }) {
            let currentBinding = newBindings[currentIndex]

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
        dockGestureBinding(for: gesture).action
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
        updateDockGestureBinding(
            DockGestureBinding(
                gesture: gesture,
                isEnabled: dockGestureBinding(for: gesture).isEnabled,
                action: action
            )
        )
    }

    func resetDockGestureActionsToDefaults() {
        dockGestureBindings = DockGestureBindings.defaults
    }

    private func updateDockGestureBinding(_ binding: DockGestureBinding) {
        var newBindings = dockGestureBindings

        if let index = newBindings.firstIndex(where: { $0.gesture == binding.gesture }) {
            if newBindings[index] == binding {
                return
            }
            newBindings[index] = binding
        } else {
            newBindings.append(binding)
        }

        dockGestureBindings = newBindings.sorted { lhs, rhs in
            lhs.gesture.rawValue < rhs.gesture.rawValue
        }
    }

    func titleBarGestureBinding(for gesture: DockGestureKind) -> TitleBarGestureBinding? {
        TitleBarGestureBindings.binding(for: gesture, in: titleBarGestureBindings)
    }

    func titleBarGestureAction(for gesture: DockGestureKind) -> WindowAction? {
        titleBarGestureBinding(for: gesture)?.action
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
        updateTitleBarGestureBinding(
            TitleBarGestureBinding(
                gesture: gesture,
                isEnabled: current.isEnabled,
                action: action
            )
        )
    }

    func resetTitleBarGestureActionsToDefaults() {
        titleBarGestureBindings = TitleBarGestureBindings.defaults
    }

    func consumeWelcomeGuidePresentationFlag() -> Bool {
        guard hasSeenWelcomeGuide == false else {
            return false
        }

        hasSeenWelcomeGuide = true
        return true
    }

    private func updateTitleBarGestureBinding(_ binding: TitleBarGestureBinding) {
        var newBindings = titleBarGestureBindings

        if let index = newBindings.firstIndex(where: { $0.gesture == binding.gesture }) {
            if newBindings[index] == binding {
                return
            }
            newBindings[index] = binding
        } else {
            newBindings.append(binding)
        }

        titleBarGestureBindings = newBindings.sorted { lhs, rhs in
            lhs.gesture.rawValue < rhs.gesture.rawValue
        }
    }

    private func notifyDidChange() {
        guard notificationDispatchPending == false else {
            return
        }

        notificationDispatchPending = true
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.notificationDispatchPending = false
            NotificationCenter.default.post(name: .settingsDidChange, object: self)
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
        titleBarOverlayProtectionEnabled = true
        smartPinchExitFullScreenEnabled = true
    }

    private func persistHotKeyBindings() {
        do {
            let data = try JSONEncoder().encode(hotKeyBindings)
            userDefaults.set(data, forKey: Keys.hotKeyBindings)
        } catch {
            DebugLog.error(DebugLog.settings, "Failed to encode hot key bindings: \(error.localizedDescription)")
        }
    }

    private func persistDockGestureBindings() {
        do {
            let data = try JSONEncoder().encode(dockGestureBindings)
            userDefaults.set(data, forKey: Keys.dockGestureBindings)
        } catch {
            DebugLog.error(DebugLog.settings, "Failed to encode Dock gesture bindings: \(error.localizedDescription)")
        }
    }

    private func persistTitleBarGestureBindings() {
        do {
            let data = try JSONEncoder().encode(titleBarGestureBindings)
            userDefaults.set(data, forKey: Keys.titleBarGestureBindings)
        } catch {
            DebugLog.error(DebugLog.settings, "Failed to encode title-bar gesture bindings: \(error.localizedDescription)")
        }
    }

    private static func decodeHotKeyBindings(from userDefaults: UserDefaults) -> [HotKeyBinding]? {
        guard let data = userDefaults.data(forKey: Keys.hotKeyBindings) else { return nil }
        do {
            return try JSONDecoder().decode([HotKeyBinding].self, from: data)
        } catch {
            DebugLog.error(DebugLog.settings, "Failed to decode hot key bindings, falling back to defaults: \(error.localizedDescription)")
            return nil
        }
    }

    private static func decodeDockGestureBindings(from userDefaults: UserDefaults) -> [DockGestureBinding]? {
        guard let data = userDefaults.data(forKey: Keys.dockGestureBindings) else { return nil }
        do {
            return try JSONDecoder().decode([DockGestureBinding].self, from: data)
        } catch {
            DebugLog.error(DebugLog.settings, "Failed to decode Dock gesture bindings, falling back to defaults: \(error.localizedDescription)")
            return nil
        }
    }

    private static func decodeTitleBarGestureBindings(from userDefaults: UserDefaults) -> [TitleBarGestureBinding]? {
        guard let data = userDefaults.data(forKey: Keys.titleBarGestureBindings) else { return nil }
        do {
            return try JSONDecoder().decode([TitleBarGestureBinding].self, from: data)
        } catch {
            DebugLog.error(DebugLog.settings, "Failed to decode title-bar gesture bindings, falling back to defaults: \(error.localizedDescription)")
            return nil
        }
    }

    private enum Keys {
        static let languageOverride = "settings.languageOverride"
        static let hotKeysEnabled = "settings.hotKeysEnabled"
        static let dockGesturesEnabled = "settings.dockGesturesEnabled"
        static let titleBarGesturesEnabled = "settings.titleBarGesturesEnabled"
        static let titleBarOverlayProtectionEnabled = "settings.titleBarOverlayProtectionEnabled"
        static let smartPinchExitFullScreenEnabled = "settings.smartPinchExitFullScreenEnabled"
        static let executeGestureOnRelease = "settings.executeGestureOnRelease"
        static let reverseCancelEnabled = "settings.reverseCancelEnabled"
        static let reverseCancelSensitivity = "settings.reverseCancelSensitivity"
        static let swipeSensitivity = "settings.swipeSensitivity"
        static let pinchSensitivity = "settings.pinchSensitivity"
        static let gestureHUDStyle = "settings.gestureHUDStyle"
        static let statusItemIcon = "settings.statusItemIcon"
        static let hasSeenWelcomeGuide = "settings.hasSeenWelcomeGuide"
        #if DEBUG
        static let debugLoggingEnabled = "settings.debugLoggingEnabled"
        #endif
        static let hotKeyBindings = "settings.hotKeyBindings"
        static let dockGestureBindings = "settings.dockGestureBindings"
        static let titleBarGestureBindings = "settings.titleBarGestureBindings"
    }
}
