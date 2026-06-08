import Testing
@testable import Swooshy

struct StatusMenuContentBuilderTests {
    private let builder = StatusMenuContentBuilder()

    @Test
    func menuUsesSimplifiedChineseForChinesePreferredLanguages() {
        let entries = menuEntries(
            permissionGranted: false,
            preferredLanguages: ["zh-Hans-CN"]
        )

        let localizedTitles: [(StatusMenuEntry.Kind, String)] = [
            (.title, "Swooshy"),
            (.permission, "授予辅助功能权限"),
            (.refresh, "刷新权限状态"),
            (.windowAction(.leftHalf), "贴靠到左半屏"),
            (.windowAction(.cycleSameAppWindowsForward), "向前切换当前应用窗口"),
            (.windowAction(.cycleSameAppWindowsBackward), "向后切换当前应用窗口"),
            (.windowAction(.toggleFullScreen), "最大化全屏"),
            (.settings, "设置…"),
            (.help, "使用说明"),
            (.quit, "退出 Swooshy"),
        ]

        for (kind, title) in localizedTitles {
            #expect(entry(kind, in: entries)?.title == title)
        }
    }

    @Test
    func menuUsesReadyStateWhenPermissionGranted() {
        let entries = menuEntries(permissionGranted: true)

        #expect(entry(.permission, in: entries)?.title == "Accessibility Access Ready")
        #expect(entry(.permission, in: entries)?.isEnabled == false)
        #expect(entry(.windowAction(.leftHalf), in: entries)?.isEnabled == true)
        #expect(entry(.windowAction(.cycleSameAppWindowsForward), in: entries)?.isEnabled == true)
        #expect(entry(.windowAction(.cycleSameAppWindowsBackward), in: entries)?.isEnabled == true)
    }

    @Test
    func menuCanCollapseWindowActionsIntoSingleEntry() {
        let entries = menuEntries(
            permissionGranted: true,
            collapseWindowActions: true,
            preferredLanguages: ["zh-Hans-CN"]
        )

        #expect(entry(.windowActionGroup, in: entries)?.title == "窗口操作")
        #expect(entry(.windowAction(.leftHalf), in: entries) == nil)
        #expect(entry(.windowAction(.toggleFullScreen), in: entries) == nil)
    }

    @Test
    func menuUsesProvidedWindowActions() {
        let entries = menuEntries(
            permissionGranted: true,
            windowActions: [.leftHalf, .center]
        )

        #expect(entry(.windowAction(.leftHalf), in: entries) != nil)
        #expect(entry(.windowAction(.center), in: entries) != nil)
        #expect(entry(.windowAction(.moveToNextDisplay), in: entries) == nil)
        #expect(entry(.windowAction(.moveToPreviousDisplay), in: entries) == nil)
    }

    @Test
    func collapsedWindowActionIssueUsesProvidedWindowActionsOnly() {
        let entries = menuEntries(
            permissionGranted: true,
            collapseWindowActions: true,
            windowActions: [.leftHalf],
            hotKeyIssueForAction: { action in
                action == .moveToNextDisplay ? .registrationFailed : nil
            }
        )

        #expect(entry(.windowActionGroup, in: entries)?.hotKeyIssue == nil)
    }

    @Test
    func windowActionEntriesCarryHotKeyRegistrationIssues() {
        let entries = menuEntries(
            permissionGranted: true,
            hotKeyIssueForAction: { action in
                action == .center ? .registrationFailed : nil
            }
        )

        #expect(entry(.windowAction(.center), in: entries)?.hotKeyIssue == .registrationFailed)
        #expect(entry(.windowAction(.leftHalf), in: entries)?.hotKeyIssue == nil)
    }

    @Test
    func collapsedWindowActionGroupCarriesHotKeyRegistrationIssue() {
        let entries = menuEntries(
            permissionGranted: true,
            collapseWindowActions: true,
            hotKeyIssueForAction: { action in
                action == .maximize ? .handlerUnavailable : nil
            }
        )

        #expect(entry(.windowActionGroup, in: entries)?.hotKeyIssue == .handlerUnavailable)
    }

    @Test
    func permissionAndRefreshEntriesAreEnabledWhenPermissionMissing() {
        let entries = menuEntries(permissionGranted: false)

        let enabledEntries = entries.filter(\.isEnabled)
        #expect(enabledEntries.map(\.kind) == [
            .permission,
            .refresh,
            .settings,
            .help,
            .quit,
        ])
    }

    @Test
    func quitEntryRemainsEnabledWhenPermissionMissing() {
        let entries = menuEntries(permissionGranted: false)

        #expect(entry(.quit, in: entries)?.isEnabled == true)
    }

    @Test
    func settingsEntryRemainsEnabledWhenPermissionMissing() {
        let entries = menuEntries(permissionGranted: false)

        #expect(entry(.settings, in: entries)?.isEnabled == true)
        #expect(entry(.windowAction(.leftHalf), in: entries)?.isEnabled == false)
    }

    @Test
    func menuFallsBackToEnglishForUnsupportedPreferredLanguages() {
        let entries = menuEntries(
            permissionGranted: false,
            preferredLanguages: ["fr-FR"]
        )

        #expect(entry(.permission, in: entries)?.title == "Grant Accessibility Access")
        #expect(entry(.settings, in: entries)?.title == "Settings…")
        #expect(entry(.help, in: entries)?.title == "How This Works")
    }

    private func menuEntries(
        permissionGranted: Bool,
        collapseWindowActions: Bool = false,
        windowActions: [WindowAction] = WindowAction.allCases,
        preferredLanguages: [String] = ["en-US"],
        hotKeyIssueForAction: (WindowAction) -> HotKeyRegistrationIssueKind? = { _ in nil }
    ) -> [StatusMenuEntry] {
        builder.makeEntries(
            permissionGranted: permissionGranted,
            collapseWindowActions: collapseWindowActions,
            windowActions: windowActions,
            preferredLanguages: preferredLanguages,
            hotKeyIssueForAction: hotKeyIssueForAction
        )
    }

    private func entry(
        _ kind: StatusMenuEntry.Kind,
        in entries: [StatusMenuEntry]
    ) -> StatusMenuEntry? {
        entries.first { $0.kind == kind }
    }
}
