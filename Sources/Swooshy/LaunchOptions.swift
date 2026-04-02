import Foundation

struct LaunchOptions: Equatable {
    static let resetUserConfigurationArgument = "--reset-user-config"
    static let clearCacheArgument = "--clear-cache"

    let resetUserConfiguration: Bool
    let clearCache: Bool

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.resetUserConfiguration = arguments.contains(Self.resetUserConfigurationArgument)
        self.clearCache = arguments.contains(Self.clearCacheArgument)
    }

    @MainActor
    func apply(userDefaults: UserDefaults = .standard) {
        if resetUserConfiguration {
            SettingsStore.resetPersistedConfiguration(in: userDefaults)
        }

        if clearCache || resetUserConfiguration {
            ObservedWindowConstraintStore.resetPersistedConstraints(in: userDefaults)
        }
    }
}
