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
                LaunchOptions.previewHotKeyRegistrationFailureArgument,
                LaunchOptions.previewUpdateAvailableArgument,
            ]
        )

        #expect(options.clearCache)
        #expect(options.resetUserConfiguration)
        #expect(options.previewHotKeyRegistrationFailure)
        #expect(options.previewUpdateAvailable)
    }

    @Test
    func clearCacheRemovesObservedConstraintsButPreservesSettings() {
        let defaults = makeDefaults()
        let settingsStore = SettingsStore(userDefaults: defaults)
        settingsStore.debugLoggingEnabled = true

        recordObservedConstraint(
            in: defaults,
            minimumWidth: 860,
            minimumHeight: 520
        )

        applyLaunchOption(LaunchOptions.clearCacheArgument, to: defaults)

        let reloadedSettings = SettingsStore(userDefaults: defaults)
        let reloadedConstraints = makeConstraintStore(userDefaults: defaults)

        #expect(reloadedSettings.debugLoggingEnabled)
        #expect(reloadedConstraints.observation(for: "com.example.app", action: .leftHalf) == nil)
    }

    @Test
    func resetUserConfigurationClearsSettingsAndObservedConstraints() {
        let defaults = makeDefaults()
        let settingsStore = SettingsStore(userDefaults: defaults)
        settingsStore.debugLoggingEnabled = true
        settingsStore.smartPinchExitFullScreenEnabled = false

        recordObservedConstraint(in: defaults, minimumWidth: 860)

        applyLaunchOption(LaunchOptions.resetUserConfigurationArgument, to: defaults)

        let reloadedSettings = SettingsStore(userDefaults: defaults)
        let reloadedConstraints = makeConstraintStore(userDefaults: defaults)

        #expect(!reloadedSettings.debugLoggingEnabled)
        #expect(reloadedSettings.smartPinchExitFullScreenEnabled)
        #expect(reloadedConstraints.observation(for: "com.example.app", action: .leftHalf) == nil)
    }

    @Test
    func resetUserConfigurationPreservesExperimentalBrowserTabCloseOptIn() {
        let defaults = makeDefaults()
        let settingsStore = SettingsStore(userDefaults: defaults)
        settingsStore.experimentalBrowserTabCloseEnabled = true
        settingsStore.experimentalDisplayMoveActionsEnabled = true
        settingsStore.smartBrowserTabCloseEnabled = true

        applyLaunchOption(LaunchOptions.resetUserConfigurationArgument, to: defaults)

        let reloadedSettings = SettingsStore(userDefaults: defaults)
        #expect(reloadedSettings.experimentalBrowserTabCloseEnabled)
        #expect(reloadedSettings.experimentalDisplayMoveActionsEnabled)
        #expect(!reloadedSettings.smartBrowserTabCloseEnabled)
    }

    private func recordObservedConstraint(
        in defaults: UserDefaults,
        minimumWidth: CGFloat? = nil,
        maximumWidth: CGFloat? = nil,
        minimumHeight: CGFloat? = nil,
        maximumHeight: CGFloat? = nil
    ) {
        let constraintStore = makeConstraintStore(userDefaults: defaults)
        constraintStore.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: minimumWidth,
                maximumWidth: maximumWidth,
                minimumHeight: minimumHeight,
                maximumHeight: maximumHeight
            ),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .leadingEdge,
            action: .leftHalf,
            for: "com.example.app"
        )
        constraintStore.flushPersistedConstraints()
    }

    private func makeConstraintStore(userDefaults: UserDefaults) -> ObservedWindowConstraintStore {
        ObservedWindowConstraintStore(
            userDefaults: userDefaults,
            autosaveInterval: 0
        )
    }

    private func applyLaunchOption(_ argument: String, to defaults: UserDefaults) {
        LaunchOptions(arguments: [argument]).apply(userDefaults: defaults)
    }
}
