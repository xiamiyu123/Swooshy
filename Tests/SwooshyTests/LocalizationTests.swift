import Foundation
import Testing
@testable import Swooshy

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
        #expect(L10n.string("menu.window_actions", localeIdentifier: "en") == "Window Actions")
        #expect(L10n.string("action.center", localeIdentifier: "en") == "Fill Entire Screen")
        #expect(L10n.string("action.quit_application", localeIdentifier: "en") == "Quit Application")
        #expect(L10n.string("action.restore_window", localeIdentifier: "en") == "Restore Minimized Window")
        #expect(L10n.string("action.exit_full_screen", localeIdentifier: "en") == "Exit Full Screen Only")
        #expect(L10n.string("action.cycle_same_app_windows_forward", localeIdentifier: "en") == "Cycle Same-App Windows Forward")
        #expect(L10n.string("action.move_to_next_display", localeIdentifier: "en") == "Move to Next Display")
        #expect(L10n.string("action.move_to_previous_display", localeIdentifier: "en") == "Move to Previous Display")
        #expect(L10n.string("settings.status_item_icon.window_grid", localeIdentifier: "en") == "Window grid")
    }

    @Test
    func simplifiedChineseStringsResolveFromModuleBundle() {
        #expect(L10n.string("menu.permission.grant", localeIdentifier: "zh-Hans") == "授予辅助功能权限")
        #expect(L10n.string("menu.window_actions", localeIdentifier: "zh-Hans") == "窗口操作")
        #expect(L10n.string("action.center", localeIdentifier: "zh-Hans") == "填充整个屏幕")
        #expect(L10n.string("action.close_window", localeIdentifier: "zh-Hans") == "关闭窗口")
        #expect(L10n.string("action.restore_window", localeIdentifier: "zh-Hans") == "恢复最小化窗口")
        #expect(L10n.string("action.exit_full_screen", localeIdentifier: "zh-Hans") == "仅取消最大化")
        #expect(L10n.string("action.cycle_same_app_windows_backward", localeIdentifier: "zh-Hans") == "向后切换当前应用窗口")
        #expect(L10n.string("action.move_to_next_display", localeIdentifier: "zh-Hans") == "移动到下一台显示器")
        #expect(L10n.string("action.move_to_previous_display", localeIdentifier: "zh-Hans") == "移动到上一台显示器")
        #expect(L10n.string("settings.status_item_icon.window_grid", localeIdentifier: "zh-Hans") == "窗口网格")
    }

    @Test
    func localizableStringKeysAreUniquePerLocale() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "Sources/Swooshy/Resources/en.lproj/Localizable.strings",
            "Sources/Swooshy/Resources/zh-Hans.lproj/Localizable.strings",
        ]

        for relativePath in relativePaths {
            let fileURL = packageRoot.appending(path: relativePath)
            let keys = localizationKeys(
                in: try String(contentsOf: fileURL, encoding: .utf8)
            )
            var seenKeys = Set<String>()
            var duplicateKeys: [String] = []

            for key in keys where seenKeys.insert(key).inserted == false {
                duplicateKeys.append(key)
            }

            #expect(duplicateKeys.isEmpty)
        }
    }

    private func localizationKeys(in contents: String) -> [String] {
        contents.split(separator: "\n").compactMap { line in
            let trimmedLine = String(line).trimmingCharacters(in: .whitespaces)
            guard trimmedLine.hasPrefix("\"") else {
                return nil
            }

            let keyStart = trimmedLine.index(after: trimmedLine.startIndex)
            guard let keyEnd = trimmedLine[keyStart...].firstIndex(of: "\"") else {
                return nil
            }

            return String(trimmedLine[keyStart ..< keyEnd])
        }
    }
}
