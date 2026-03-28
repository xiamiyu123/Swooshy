import Foundation
import Testing
@testable import Sweeesh

@MainActor
struct SettingsStoreTests {
    @Test
    func persistsLanguageAndHotKeyPreferences() {
        let suiteName = "Sweeesh.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        store.languageOverride = .simplifiedChinese
        store.hotKeysEnabled = false

        let reloadedStore = SettingsStore(userDefaults: defaults)

        #expect(reloadedStore.languageOverride == .simplifiedChinese)
        #expect(reloadedStore.hotKeysEnabled == false)
    }

    @Test
    func persistsCustomHotKeyBinding() {
        let suiteName = "Sweeesh.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        store.updateHotKeyKey(.w, for: .maximize)
        store.updateHotKeyModifiers(.commandShift, for: .maximize)

        let reloadedStore = SettingsStore(userDefaults: defaults)
        let binding = reloadedStore.hotKeyBinding(for: .maximize)

        #expect(binding.key == .w)
        #expect(binding.modifiers == .commandShift)
    }

    @Test
    func swapsConflictingBindingsToKeepShortcutsUnique() {
        let suiteName = "Sweeesh.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        let originalLeft = store.hotKeyBinding(for: .leftHalf)
        let originalCenter = store.hotKeyBinding(for: .center)

        store.updateHotKeyBinding(
            HotKeyBinding(
                action: .center,
                key: originalLeft.key,
                modifiers: originalLeft.modifiers
            )
        )

        #expect(store.hotKeyBinding(for: .center).key == originalLeft.key)
        #expect(store.hotKeyBinding(for: .leftHalf).key == originalCenter.key)
    }

    @Test
    func systemLanguageUsesCurrentPreferredLanguages() {
        let suiteName = "Sweeesh.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        #expect(store.preferredLanguages.isEmpty == false)
    }
}
