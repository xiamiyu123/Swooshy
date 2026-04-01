import Foundation
import Testing
@testable import Swooshy

@MainActor
struct WelcomeWindowControllerTests {
    @Test
    func welcomeContentUsesCurrentLanguageOverride() {
        let suiteName = "Swooshy.WelcomeWindowControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        store.languageOverride = .simplifiedChinese

        let chineseContent = WelcomeGuideContent.make(settingsStore: store)
        #expect(chineseContent.windowTitle == "欢迎")
        #expect(chineseContent.welcomeTitle == "欢迎使用 Swooshy")

        store.languageOverride = .english

        let englishContent = WelcomeGuideContent.make(settingsStore: store)
        #expect(englishContent.windowTitle == "Welcome")
        #expect(englishContent.welcomeTitle == "Welcome to Swooshy")
        #expect(englishContent.pages[1].title == "Dock Gestures: Switch Windows for the Same App")
        #expect(englishContent.pages[6].title == "Title Bar Gestures: Corner Snap Mode")
        #expect(englishContent.pages[6].bullets.count == 3)
        #expect(englishContent.pages[6].bullets[0].contains("0.2 seconds"))
    }

    @Test
    func settingsStoreUsesShortCornerSnapHoldDurationByDefault() {
        let suiteName = "Swooshy.WelcomeWindowControllerTests.Defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)

        #expect(store.titleBarCornerDragHoldDuration == 0.2)
    }
}
