import Foundation
import Observation

extension Notification.Name {
    static let settingsDidChange = Notification.Name("Sweeesh.settingsDidChange")
}

@MainActor
@Observable
final class SettingsStore {
    @ObservationIgnored
    private let userDefaults: UserDefaults

    var languageOverride: AppLanguage {
        didSet {
            guard oldValue != languageOverride else { return }
            userDefaults.set(languageOverride.rawValue, forKey: Keys.languageOverride)
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

    var hotKeyBindings: [HotKeyBinding] {
        didSet {
            guard oldValue != hotKeyBindings else { return }
            persistHotKeyBindings()
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
        if userDefaults.object(forKey: Keys.hotKeysEnabled) == nil {
            self.hotKeysEnabled = true
        } else {
            self.hotKeysEnabled = userDefaults.bool(forKey: Keys.hotKeysEnabled)
        }
        self.hotKeyBindings = Self.decodeHotKeyBindings(from: userDefaults) ?? HotKeyBindings.defaults
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

    private func notifyDidChange() {
        NotificationCenter.default.post(name: .settingsDidChange, object: self)
    }

    private func fallbackBinding(for action: WindowAction) -> HotKeyBinding {
        HotKeyBindings.binding(for: action) ?? HotKeyBinding(
            action: action,
            key: .a,
            modifiers: .commandOptionControl
        )
    }

    private func persistHotKeyBindings() {
        if let data = try? JSONEncoder().encode(hotKeyBindings) {
            userDefaults.set(data, forKey: Keys.hotKeyBindings)
        }
    }

    private static func decodeHotKeyBindings(from userDefaults: UserDefaults) -> [HotKeyBinding]? {
        guard let data = userDefaults.data(forKey: Keys.hotKeyBindings) else { return nil }
        return try? JSONDecoder().decode([HotKeyBinding].self, from: data)
    }

    private enum Keys {
        static let languageOverride = "settings.languageOverride"
        static let hotKeysEnabled = "settings.hotKeysEnabled"
        static let hotKeyBindings = "settings.hotKeyBindings"
    }
}
