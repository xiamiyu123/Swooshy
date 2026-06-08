import Foundation
import Testing
@testable import Swooshy

struct AppIdentityTests {
    @Test
    func fallsBackToCanonicalBundleNameWhenLocalizedNameIsMissing() {
        let identity = AppIdentity(
            bundleURL: URL(fileURLWithPath: "/Applications/Example.app/Contents/MacOS/Example"),
            bundleIdentifier: "com.example.Example",
            processIdentifier: 42,
            localizedName: nil
        )

        #expect(identity?.bundleURL.path == "/Applications/Example.app")
        #expect(identity?.localizedName == "Example")
    }

    @Test
    func fallsBackToBundleNameWhenLocalizedNameIsEmpty() {
        let identity = AppIdentity(
            bundleURL: URL(fileURLWithPath: "/Applications/Preview.app"),
            bundleIdentifier: "com.apple.Preview",
            processIdentifier: 42,
            localizedName: ""
        )

        #expect(identity?.localizedName == "Preview")
    }

    @Test
    func preservesNonEmptyLocalizedName() {
        let identity = AppIdentity(
            bundleURL: URL(fileURLWithPath: "/Applications/Calendar.app"),
            bundleIdentifier: "com.apple.iCal",
            processIdentifier: 42,
            localizedName: "Calendar"
        )

        #expect(identity?.localizedName == "Calendar")
    }
}
