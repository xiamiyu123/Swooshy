import Foundation
import Testing
@testable import Swooshy

@MainActor
struct LaunchOptionsTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "Swooshy.LaunchOptionsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test
    func parsesSupportedLaunchArguments() {
        let options = LaunchOptions(
            arguments: [
                "/Applications/Swooshy.app/Contents/MacOS/Swooshy",
                LaunchOptions.clearCacheArgument,
                LaunchOptions.resetUserConfigurationArgument,
            ]
        )

        #expect(options.clearCache == true)
        #expect(options.resetUserConfiguration == true)
    }

    @Test
    func clearCacheRemovesObservedConstraintsButPreservesSettings() {
        let defaults = makeDefaults()
        let settingsStore = SettingsStore(userDefaults: defaults)
        settingsStore.debugLoggingEnabled = true

        let constraintStore = ObservedWindowConstraintStore(
            userDefaults: defaults,
            autosaveInterval: 0
        )
        constraintStore.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: 860,
                maximumWidth: nil,
                minimumHeight: 520,
                maximumHeight: nil
            ),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .leadingEdge,
            action: .leftHalf,
            for: "com.example.app"
        )
        constraintStore.flushPersistedConstraints()

        LaunchOptions(arguments: [LaunchOptions.clearCacheArgument]).apply(userDefaults: defaults)

        let reloadedSettings = SettingsStore(userDefaults: defaults)
        let reloadedConstraints = ObservedWindowConstraintStore(
            userDefaults: defaults,
            autosaveInterval: 0
        )

        #expect(reloadedSettings.debugLoggingEnabled == true)
        #expect(reloadedConstraints.observation(for: "com.example.app", action: .leftHalf) == nil)
    }

    @Test
    func resetUserConfigurationClearsSettingsAndObservedConstraints() {
        let defaults = makeDefaults()
        let settingsStore = SettingsStore(userDefaults: defaults)
        settingsStore.debugLoggingEnabled = true

        let constraintStore = ObservedWindowConstraintStore(
            userDefaults: defaults,
            autosaveInterval: 0
        )
        constraintStore.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: 860,
                maximumWidth: nil,
                minimumHeight: nil,
                maximumHeight: nil
            ),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .leadingEdge,
            action: .leftHalf,
            for: "com.example.app"
        )
        constraintStore.flushPersistedConstraints()

        LaunchOptions(arguments: [LaunchOptions.resetUserConfigurationArgument]).apply(userDefaults: defaults)

        let reloadedSettings = SettingsStore(userDefaults: defaults)
        let reloadedConstraints = ObservedWindowConstraintStore(
            userDefaults: defaults,
            autosaveInterval: 0
        )

        #expect(reloadedSettings.debugLoggingEnabled == false)
        #expect(reloadedConstraints.observation(for: "com.example.app", action: .leftHalf) == nil)
    }
}
