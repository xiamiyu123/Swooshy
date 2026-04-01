import Testing
@testable import Swooshy

@MainActor
struct BrowserTabProbeTests {
    @Test
    func supportsMajorBrowsersAndVSCodeEditors() {
        #expect(
            BrowserTabProbe.supportsTabCloseHost(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari"
            )
        )
        #expect(
            BrowserTabProbe.supportsTabCloseHost(
                bundleIdentifier: "com.microsoft.VSCode",
                localizedName: "Visual Studio Code"
            )
        )
        #expect(
            BrowserTabProbe.supportsTabCloseHost(
                bundleIdentifier: nil,
                localizedName: "Cursor"
            )
        )
        #expect(
            BrowserTabProbe.supportsTabCloseHost(
                bundleIdentifier: "com.google.antigravity",
                localizedName: "Antigravity"
            )
        )
    }

    @Test
    func rejectsUnsupportedApps() {
        #expect(
            BrowserTabProbe.supportsTabCloseHost(
                bundleIdentifier: "com.apple.finder",
                localizedName: "Finder"
            ) == false
        )
        #expect(
            BrowserTabProbe.supportsTabCloseHost(
                bundleIdentifier: nil,
                localizedName: "Preview"
            ) == false
        )
    }
}
