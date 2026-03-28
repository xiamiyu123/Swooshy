import Testing
@testable import Sweeesh

struct LocalizationTests {
    @Test
    func preferredLanguagesResolveToSimplifiedChineseLocalization() {
        #expect(
            L10n.localization(
                for: nil,
                preferredLanguages: ["zh-Hans-CN"]
            ) == "zh-hans"
        )
    }

    @Test
    func englishStringsResolveFromModuleBundle() {
        #expect(L10n.string("menu.permission.grant", localeIdentifier: "en") == "Grant Accessibility Access")
        #expect(L10n.string("action.center", localeIdentifier: "en") == "Center Large Window")
        #expect(L10n.string("action.quit_application", localeIdentifier: "en") == "Quit Application")
    }

    @Test
    func simplifiedChineseStringsResolveFromModuleBundle() {
        #expect(L10n.string("menu.permission.grant", localeIdentifier: "zh-Hans") == "授予辅助功能权限")
        #expect(L10n.string("action.center", localeIdentifier: "zh-Hans") == "居中放大窗口")
        #expect(L10n.string("action.close_window", localeIdentifier: "zh-Hans") == "关闭窗口")
    }
}
