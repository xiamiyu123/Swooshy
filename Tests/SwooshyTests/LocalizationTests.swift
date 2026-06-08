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
    func explicitLocaleIdentifierNormalizesUnderscores() {
        #expect(L10n.localization(for: "zh_Hans_CN") == "zh-hans")
        expectStrings(localeIdentifier: "zh_Hans_CN", [
            ("menu.permission.grant", "授予辅助功能权限"),
        ])
    }

    @Test
    func englishStringsResolveFromModuleBundle() {
        expectStrings(localeIdentifier: "en", [
            ("menu.permission.grant", "Grant Accessibility Access"),
            ("menu.window_actions", "Window Actions"),
            ("action.center", "Fill Entire Screen"),
            ("action.quit_application", "Quit Application"),
            ("action.restore_window", "Restore Minimized Window"),
            ("action.exit_full_screen", "Exit Full Screen Only"),
            ("action.cycle_same_app_windows_forward", "Cycle Same-App Windows Forward"),
            ("action.move_to_next_display", "Move to Next Display"),
            ("action.move_to_previous_display", "Move to Previous Display"),
            ("error.no_other_display", "No other display is available for this action."),
            ("settings.status_item_icon.window_grid", "Window grid"),
        ])
    }

    @Test
    func simplifiedChineseStringsResolveFromModuleBundle() {
        expectStrings(localeIdentifier: "zh-Hans", [
            ("menu.permission.grant", "授予辅助功能权限"),
            ("menu.window_actions", "窗口操作"),
            ("action.center", "填充整个屏幕"),
            ("action.close_window", "关闭窗口"),
            ("action.restore_window", "恢复最小化窗口"),
            ("action.exit_full_screen", "仅取消最大化"),
            ("action.cycle_same_app_windows_backward", "向后切换当前应用窗口"),
            ("action.move_to_next_display", "移动到下一台显示器"),
            ("action.move_to_previous_display", "移动到上一台显示器"),
            ("error.no_other_display", "当前没有其他显示器可用于此操作。"),
            ("settings.status_item_icon.window_grid", "窗口网格"),
        ])
    }

    @Test
    func appLanguageTitlesResolveFromModuleBundle() {
        let cases: [(language: AppLanguage, english: String, simplifiedChinese: String)] = [
            (.system, "Follow System", "跟随系统"),
            (.english, "English", "English"),
            (.simplifiedChinese, "Simplified Chinese", "简体中文"),
        ]

        for (language, english, simplifiedChinese) in cases {
            #expect(language.title(localeIdentifier: "en") == english)
            #expect(language.title(localeIdentifier: "zh-Hans") == simplifiedChinese)
        }
    }

    @Test
    func gestureHUDStyleTitlesResolveFromModuleBundle() {
        let cases: [(style: GestureHUDStyle, english: String, simplifiedChinese: String)] = [
            (.classic, "Detailed", "详细"),
            (.elegant, "Elegant", "优雅"),
            (.minimal, "Minimal", "极简"),
        ]

        for (style, english, simplifiedChinese) in cases {
            #expect(style.title(localeIdentifier: "en") == english)
            #expect(style.title(localeIdentifier: "zh-Hans") == simplifiedChinese)
        }
    }

    @Test
    func localizableStringKeysAreUniquePerLocale() throws {
        for relativePath in localeResourcePaths {
            let fileURL = packageRoot.appending(path: relativePath)
            let keys = localizationKeys(
                in: try String(contentsOf: fileURL, encoding: .utf8)
            )
            var seenKeys = Set<String>()
            let duplicateKeys = keys.filter { !seenKeys.insert($0).inserted }

            #expect(duplicateKeys.isEmpty)
        }
    }

    @Test
    func sourceLocalizedStringKeysExistInEveryLocale() throws {
        let sourceKeys = try localizedSourceKeys(
            in: packageRoot.appending(path: "Sources/Swooshy")
        )

        for relativePath in localeResourcePaths {
            let fileURL = packageRoot.appending(path: relativePath)
            let localeKeys = Set(
                localizationKeys(in: try String(contentsOf: fileURL, encoding: .utf8))
            )

            let missingKeys = sourceKeys.subtracting(localeKeys).sorted()
            #expect(missingKeys.isEmpty)
        }
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var localeResourcePaths: [String] {
        [
            "Sources/Swooshy/Resources/en.lproj/Localizable.strings",
            "Sources/Swooshy/Resources/zh-Hans.lproj/Localizable.strings",
        ]
    }

    private func expectStrings(localeIdentifier: String, _ strings: [(key: String, expected: String)]) {
        for (key, expected) in strings {
            #expect(L10n.string(key, localeIdentifier: localeIdentifier) == expected)
        }
    }

    private func localizedSourceKeys(in sourcesURL: URL) throws -> Set<String> {
        let fileManager = FileManager.default
        let regularFileKey = URLResourceKey.isRegularFileKey
        guard let enumerator = fileManager.enumerator(
            at: sourcesURL,
            includingPropertiesForKeys: [regularFileKey]
        ) else {
            throw CocoaError(
                .fileReadUnknown,
                userInfo: [NSFilePathErrorKey: sourcesURL.path]
            )
        }

        let regexes = [
            try NSRegularExpression(pattern: #"(?:localized|L10n\.string)\(\s*"([^"]+)""#),
            try NSRegularExpression(pattern: #"localizationKey\s*=\s*"([^"]+)""#),
            try NSRegularExpression(pattern: #"titleKey:\s*"([^"]+)""#),
        ]
        var keys = Set<String>()

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let values = try fileURL.resourceValues(forKeys: [regularFileKey])
            guard values.isRegularFile == true else { continue }

            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(contents.startIndex ..< contents.endIndex, in: contents)

            for regex in regexes {
                for match in regex.matches(in: contents, range: range) {
                    guard
                        match.numberOfRanges > 1,
                        let keyRange = Range(match.range(at: 1), in: contents)
                    else {
                        continue
                    }

                    let key = String(contents[keyRange])
                    if !key.contains(#"\("#) {
                        keys.insert(key)
                    }
                }
            }
        }

        return keys
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
