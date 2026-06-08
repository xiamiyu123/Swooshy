import Testing
@testable import Swooshy

@MainActor
struct BrowserTabProbeTests {
    @Test
    func supportsMajorBrowsersAndVSCodeEditors() {
        let supportedHosts: [(bundleIdentifier: String?, localizedName: String?)] = [
            ("com.apple.Safari", "Safari"),
            ("com.microsoft.VSCode", "Visual Studio Code"),
            (nil, "Cursor"),
            ("com.google.antigravity", "Antigravity"),
        ]

        for (bundleIdentifier, localizedName) in supportedHosts {
            #expect(
                BrowserTabProbe.supportsTabCloseHost(
                    bundleIdentifier: bundleIdentifier,
                    localizedName: localizedName
                )
            )
        }
    }

    @Test
    func rejectsUnsupportedApps() {
        let unsupportedHosts: [(bundleIdentifier: String?, localizedName: String?)] = [
            ("com.apple.finder", "Finder"),
            (nil, "Preview"),
        ]

        for (bundleIdentifier, localizedName) in unsupportedHosts {
            #expect(
                !BrowserTabProbe.supportsTabCloseHost(
                    bundleIdentifier: bundleIdentifier,
                    localizedName: localizedName
                )
            )
        }
    }

    @Test
    func rejectsPageContentTabsForGenericHosts() {
        let ancestry = [
            tabButton(),
            node(
                role: "AXGroup",
                subrole: "AXTabPanel"
            ),
            node(
                role: "AXGroup",
                subrole: "AXLandmarkMain"
            ),
            node(role: "AXWebArea"),
        ]

        #expect(
            !BrowserTabProbe.acceptsMatchedTabAncestry(
                ancestry,
                hostFamily: .generic
            )
        )
    }

    @Test
    func acceptsSafariStyleTabsForWebKitHosts() {
        let ancestry = [
            tabButton(),
            node(role: "AXGroup"),
        ]

        #expect(
            BrowserTabProbe.acceptsMatchedTabAncestry(
                ancestry,
                hostFamily: .webKit
            )
        )
    }

    @Test
    func acceptsChromiumTabsWithChromeContainers() {
        let ancestry = [
            tabButton(),
            node(role: "AXToolbar"),
        ]

        #expect(
            BrowserTabProbe.acceptsMatchedTabAncestry(
                ancestry,
                hostFamily: .generic
            )
        )
    }

    @Test
    func tabAncestryVerdictDoesNotDependOnTitles() {
        let untitledAncestry = [
            node(
                role: "AXTab",
                title: "",
                matchedTabElement: true
            ),
            node(
                role: "AXToolbar",
                title: ""
            ),
        ]
        let titledAncestry = [
            node(
                role: "AXTab",
                title: "Example",
                matchedTabElement: true
            ),
            node(
                role: "AXToolbar",
                title: "Browser chrome"
            ),
        ]

        #expect(
            BrowserTabProbe.acceptsMatchedTabAncestry(
                untitledAncestry,
                hostFamily: .generic
            ) == BrowserTabProbe.acceptsMatchedTabAncestry(
                titledAncestry,
                hostFamily: .generic
            )
        )
    }

    private func tabButton() -> BrowserTabProbe.TabAncestryNode {
        node(
            role: "AXRadioButton",
            subrole: "AXTabButton",
            matchedTabElement: true
        )
    }

    private func node(
        role: String,
        subrole: String = "",
        title: String = "",
        matchedTabElement: Bool = false
    ) -> BrowserTabProbe.TabAncestryNode {
        BrowserTabProbe.TabAncestryNode(
            role: role,
            subrole: subrole,
            title: title,
            matchedTabElement: matchedTabElement
        )
    }
}
