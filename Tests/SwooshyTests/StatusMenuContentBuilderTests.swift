import Testing
@testable import Swooshy

struct StatusMenuContentBuilderTests {
    private let builder = StatusMenuContentBuilder()

    @Test
    func menuUsesSimplifiedChineseForChinesePreferredLanguages() {
        let entries = builder.makeEntries(
            permissionGranted: false,
            preferredLanguages: ["zh-Hans-CN"]
        )

        #expect(entries.first(where: { $0.kind == .title })?.title == "Swooshy")
        #expect(entries.first(where: { $0.kind == .permission })?.title == "授予辅助功能权限")
        #expect(entries.first(where: { $0.kind == .refresh })?.title == "刷新权限状态")
        #expect(entries.first(where: { $0.kind == .windowAction(.leftHalf) })?.title == "贴靠到左半屏")
        #expect(entries.first(where: { $0.kind == .windowAction(.cycleSameAppWindowsForward) })?.title == "向前切换当前应用窗口")
        #expect(entries.first(where: { $0.kind == .windowAction(.cycleSameAppWindowsBackward) })?.title == "向后切换当前应用窗口")
        #expect(entries.first(where: { $0.kind == .windowAction(.toggleFullScreen) })?.title == "最大化全屏")
        #expect(entries.first(where: { $0.kind == .settings })?.title == "设置…")
        #expect(entries.first(where: { $0.kind == .help })?.title == "使用说明")
        #expect(entries.first(where: { $0.kind == .quit })?.title == "退出 Swooshy")
    }

    @Test
    func menuUsesReadyStateWhenPermissionGranted() {
        let entries = builder.makeEntries(
            permissionGranted: true,
            preferredLanguages: ["en-US"]
        )

        #expect(entries.first(where: { $0.kind == .permission })?.title == "Accessibility Access Ready")
        #expect(entries.first(where: { $0.kind == .permission })?.isEnabled == false)
        #expect(entries.first(where: { $0.kind == .windowAction(.leftHalf) })?.isEnabled == true)
        #expect(entries.first(where: { $0.kind == .windowAction(.cycleSameAppWindowsForward) })?.isEnabled == true)
        #expect(entries.first(where: { $0.kind == .windowAction(.cycleSameAppWindowsBackward) })?.isEnabled == true)
    }

    @Test
    func menuCanCollapseWindowActionsIntoSingleEntry() {
        let entries = builder.makeEntries(
            permissionGranted: true,
            collapseWindowActions: true,
            preferredLanguages: ["zh-Hans-CN"]
        )

        #expect(entries.contains { $0.kind == .windowActionGroup && $0.title == "窗口操作" })
        #expect(entries.contains { $0.kind == .windowAction(.leftHalf) } == false)
        #expect(entries.contains { $0.kind == .windowAction(.toggleFullScreen) } == false)
    }

    @Test
    func permissionAndRefreshEntriesAreEnabledWhenPermissionMissing() {
        let entries = builder.makeEntries(
            permissionGranted: false,
            preferredLanguages: ["en-US"]
        )

        let enabledEntries = entries.filter(\.isEnabled)
        #expect(enabledEntries.count == 3)
        #expect(enabledEntries.contains { $0.kind == .permission })
        #expect(enabledEntries.contains { $0.kind == .refresh })
        #expect(enabledEntries.contains { $0.kind == .help })
    }

    @Test
    func menuFallsBackToEnglishForUnsupportedPreferredLanguages() {
        let entries = builder.makeEntries(
            permissionGranted: false,
            preferredLanguages: ["fr-FR"]
        )

        #expect(entries.first(where: { $0.kind == .permission })?.title == "Grant Accessibility Access")
        #expect(entries.first(where: { $0.kind == .settings })?.title == "Settings…")
        #expect(entries.first(where: { $0.kind == .help })?.title == "How This Works")
    }
}
