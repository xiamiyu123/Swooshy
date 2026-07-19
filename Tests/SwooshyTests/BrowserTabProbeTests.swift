import CoreGraphics
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
    func findsChromiumTabFromWindowWhenHitAncestryIsFlattened() {
        let tabStripFrame = CGRect(x: 114, y: 30, width: 494, height: 41)
        let selectedTab = HitNode(
            role: "AXRadioButton",
            subrole: "AXTabButton",
            frame: CGRect(x: 352, y: 30, width: 256, height: 41)
        )
        let tabGroup = HitNode(
            role: "AXTabGroup",
            frame: tabStripFrame,
            children: [selectedTab]
        )
        let flattenedWrappers = (0..<6).reduce(tabGroup) { child, _ in
            HitNode(role: "AXGroup", frame: tabStripFrame, children: [child])
        }
        let window = HitNode(
            role: "AXWindow",
            frame: CGRect(x: 0, y: 30, width: 1_408, height: 770),
            children: [flattenedWrappers]
        )

        #expect(
            BrowserTabProbe.containsTab(
                at: CGPoint(x: 424, y: 50),
                in: window,
                hostFamily: .generic,
                frame: { $0.frame },
                role: { $0.role },
                subrole: { $0.subrole },
                children: { $0.children }
            )
        )
        #expect(
            !BrowserTabProbe.containsTab(
                at: CGPoint(x: 700, y: 50),
                in: window,
                hostFamily: .generic,
                frame: { $0.frame },
                role: { $0.role },
                subrole: { $0.subrole },
                children: { $0.children }
            )
        )
    }

    @Test
    func findsLegacyChromiumGroupInsideTabStrip() {
        let tab = HitNode(
            role: "AXGroup",
            title: "Example",
            supportsPressAction: true,
            frame: CGRect(x: 100, y: 30, width: 200, height: 41)
        )
        let tabGroup = HitNode(
            role: "AXTabGroup",
            frame: CGRect(x: 100, y: 30, width: 400, height: 41),
            children: [tab]
        )

        #expect(
            BrowserTabProbe.containsTab(
                at: CGPoint(x: 150, y: 50),
                in: tabGroup,
                hostFamily: .generic,
                frame: { $0.frame },
                role: { $0.role },
                subrole: { $0.subrole },
                title: { $0.title },
                supportsPressAction: { $0.supportsPressAction },
                children: { $0.children }
            )
        )
    }

    @Test
    func rejectsPressableGroupOutsideTabStrip() {
        let group = HitNode(
            role: "AXGroup",
            title: "Page control",
            supportsPressAction: true,
            frame: CGRect(x: 100, y: 100, width: 200, height: 40)
        )
        let window = HitNode(
            role: "AXWindow",
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            children: [group]
        )

        #expect(
            !BrowserTabProbe.containsTab(
                at: CGPoint(x: 150, y: 120),
                in: window,
                hostFamily: .generic,
                frame: { $0.frame },
                role: { $0.role },
                subrole: { $0.subrole },
                title: { $0.title },
                supportsPressAction: { $0.supportsPressAction },
                children: { $0.children }
            )
        )
    }

    @Test
    func rejectsGroupsWithoutTabSemantics() {
        #expect(
            !BrowserTabProbe.isTabElement(
                role: "AXGroup",
                subrole: ""
            )
        )
    }

    @Test
    func preservesLegacyBrowserTabRoles() {
        #expect(
            BrowserTabProbe.isTabElement(
                role: "AXTab",
                subrole: ""
            )
        )
        #expect(
            BrowserTabProbe.isTabElement(
                role: "AXRadioButton",
                subrole: "AXTabButton"
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

    private struct HitNode {
        let role: String
        var subrole = ""
        var title = ""
        var supportsPressAction = false
        let frame: CGRect?
        var children: [HitNode] = []
    }
}
