import Testing
@testable import Swooshy

struct WindowConstraintObservationScopeTests {
    @Test
    func storageKeyDiffersAcrossWindowSubroles() {
        let dialogScope = scope(
            subrole: "AXSystemDialog",
            title: nil
        )
        let settingsScope = scope(
            subrole: "AXStandardWindow",
            title: "设置"
        )

        #expect(dialogScope.storageKey != settingsScope.storageKey)
    }

    @Test
    func storageKeyCollapsesTitleWhitespaceAndCase() {
        let lhs = scope(
            subrole: "AXStandardWindow",
            title: "  Settings   Panel "
        )
        let rhs = scope(
            subrole: "AXStandardWindow",
            title: "settings panel"
        )

        #expect(lhs.storageKey == rhs.storageKey)
    }

    private func scope(
        subrole: String?,
        title: String?
    ) -> WindowConstraintObservationScope {
        WindowConstraintObservationScope(
            applicationKey: "com.example.app",
            role: "AXWindow",
            subrole: subrole,
            title: title
        )
    }
}
