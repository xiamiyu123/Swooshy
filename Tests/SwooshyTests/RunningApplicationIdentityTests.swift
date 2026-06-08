import Testing
@testable import Swooshy

struct RunningApplicationIdentityTests {
    private let frameworkHelperPath = "/Applications/Example.app/Contents/Frameworks/Example Helper.app"
    private let bundledHelperPath = "/Applications/Example.app/Contents/Helpers/Example Helper.app"
    private let appExtensionPath = "/Applications/Example.app/Contents/PlugIns/Example.appex/Contents/MacOS/Example"

    @Test
    func likelyHelperProcessMatchesHelperNamesBundleIdentifiersAndPaths() {
        let helperProcesses: [(localizedName: String?, bundleIdentifier: String?, bundlePath: String?)] = [
            ("Calendar Helper", "com.example.app", "/Applications/Example.app"),
            ("Example", "com.example.app.helper", "/Applications/Example.app"),
            ("Example", "com.example.framework.runner", "/Applications/Example.app"),
            ("Example", "com.example.app", frameworkHelperPath),
            ("Example", "com.example.app", bundledHelperPath),
            ("Example", "com.example.app", appExtensionPath),
            ("Notification Service", nil, nil),
        ]

        for (localizedName, bundleIdentifier, bundlePath) in helperProcesses {
            #expect(isLikelyHelperProcess(
                localizedName: localizedName,
                bundleIdentifier: bundleIdentifier,
                bundlePath: bundlePath
            ))
        }
    }

    @Test
    func likelyHelperProcessLeavesMainApplicationsAlone() {
        #expect(!isLikelyHelperProcess(
            localizedName: "Calendar",
            bundleIdentifier: "com.apple.iCal",
            bundlePath: "/Applications/Calendar.app"
        ))
    }

    private func isLikelyHelperProcess(
        localizedName: String? = "Example",
        bundleIdentifier: String? = "com.example.app",
        bundlePath: String? = "/Applications/Example.app"
    ) -> Bool {
        RunningApplicationIdentity.isLikelyHelperProcess(
            localizedName: localizedName,
            bundleIdentifier: bundleIdentifier,
            bundlePath: bundlePath
        )
    }
}
