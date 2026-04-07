import Testing
@testable import Swooshy

struct WindowConstraintObservationScopeTests {
    @Test
    func storageKeyDiffersAcrossWindowSubroles() {
        let dialogScope = WindowConstraintObservationScope(
            applicationKey: "com.example.app",
            role: "AXWindow",
            subrole: "AXSystemDialog",
            title: nil
        )
        let settingsScope = WindowConstraintObservationScope(
            applicationKey: "com.example.app",
            role: "AXWindow",
            subrole: "AXStandardWindow",
            title: "设置"
        )

        #expect(dialogScope.storageKey != settingsScope.storageKey)
    }

    @Test
    func storageKeyCollapsesTitleWhitespaceAndCase() {
        let lhs = WindowConstraintObservationScope(
            applicationKey: "com.example.app",
            role: "AXWindow",
            subrole: "AXStandardWindow",
            title: "  Settings   Panel "
        )
        let rhs = WindowConstraintObservationScope(
            applicationKey: "com.example.app",
            role: "AXWindow",
            subrole: "AXStandardWindow",
            title: "settings panel"
        )

        #expect(lhs.storageKey == rhs.storageKey)
    }
}
