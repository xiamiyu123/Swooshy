import Testing
@testable import Sweeesh

struct StatusMenuContentBuilderTests {
    private let builder = StatusMenuContentBuilder()

    @Test
    func menuUsesSimplifiedChineseForChinesePreferredLanguages() {
        let entries = builder.makeEntries(
            permissionGranted: false,
            preferredLanguages: ["zh-Hans-CN"]
        )

        #expect(entries[0].title == "Sweeesh")
        #expect(entries[1].title == "授予辅助功能权限")
        #expect(entries[2].title == "刷新权限状态")
        #expect(entries[4].title == "贴靠到左半屏")
        #expect(entries[11].title == "切换同应用窗口")
        #expect(entries[13].title == "设置…")
        #expect(entries[15].title == "使用说明")
        #expect(entries[16].title == "退出 Sweeesh")
    }

    @Test
    func menuUsesReadyStateWhenPermissionGranted() {
        let entries = builder.makeEntries(
            permissionGranted: true,
            preferredLanguages: ["en-US"]
        )

        #expect(entries[1].title == "Accessibility Access Ready")
        #expect(entries[1].isEnabled == false)
        #expect(entries[4].isEnabled == true)
        #expect(entries[11].isEnabled == true)
    }

    @Test
    func menuFallsBackToEnglishForUnsupportedPreferredLanguages() {
        let entries = builder.makeEntries(
            permissionGranted: false,
            preferredLanguages: ["fr-FR"]
        )

        #expect(entries[1].title == "Grant Accessibility Access")
        #expect(entries[13].title == "Settings…")
        #expect(entries[15].title == "How This Works")
    }
}
