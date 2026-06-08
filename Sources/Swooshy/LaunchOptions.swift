import Foundation

struct LaunchOptions: Equatable {
    static let resetUserConfigurationArgument = "--reset-user-config"
    static let clearCacheArgument = "--clear-cache"
    static let previewHotKeyRegistrationFailureArgument = "--preview-hotkey-registration-failure"

    let resetUserConfiguration: Bool
    let clearCache: Bool
    let previewHotKeyRegistrationFailure: Bool

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let argumentSet = Set(arguments)

        self.resetUserConfiguration = argumentSet.contains(Self.resetUserConfigurationArgument)
        self.clearCache = argumentSet.contains(Self.clearCacheArgument)
        self.previewHotKeyRegistrationFailure = argumentSet.contains(
            Self.previewHotKeyRegistrationFailureArgument
        )
    }

    @MainActor
    func apply(userDefaults: UserDefaults = .standard) {
        let clearObservedConstraints = clearCache || resetUserConfiguration

        if resetUserConfiguration {
            SettingsStore.resetPersistedConfiguration(in: userDefaults)
        }

        if clearObservedConstraints {
            ObservedWindowConstraintStore.resetPersistedConstraints(in: userDefaults)
        }
    }
}
