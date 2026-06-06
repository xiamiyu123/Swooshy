import Foundation
import Testing
@testable import Swooshy

@MainActor
struct WelcomeWindowControllerTests {
    private struct PermissionManagerStub: AccessibilityPermissionManaging {
        var isTrustedValue = true

        func isTrusted(promptIfNeeded: Bool) -> Bool {
            isTrustedValue
        }
    }

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
        #expect(englishContent.pages[5].bullets.count == 3)
        #expect(englishContent.pages[5].bullets[2].contains("real window"))
        #expect(englishContent.pages[6].title == "Title Bar Gestures: Corner Snap Mode")
        #expect(englishContent.pages[6].bullets.count == 3)
        #expect(englishContent.pages[6].message.contains("title bar or Dock"))
        #expect(englishContent.pages[6].bullets[0].contains("0.2 seconds"))
        #expect(englishContent.pages[8].bullets.count == 7)
        #expect(englishContent.pages[8].bullets[5].contains("Experimental display moves"))
        #expect(englishContent.pages[9].bullets.count == 5)
        #expect(englishContent.pages[9].bullets[4].contains("Display move actions"))
    }

    @Test
    func settingsStoreUsesShortCornerSnapHoldDurationByDefault() {
        let suiteName = "Swooshy.WelcomeWindowControllerTests.Defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)

        #expect(store.titleBarCornerDragHoldDuration == 0.2)
    }

    @Test
    func welcomeGuideExperimentalOptionsUseSameGateAsSettings() {
        let suiteName = "Swooshy.WelcomeWindowControllerTests.Experimental.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        let viewModel = WelcomeGuideViewModel(
            settingsStore: store,
            permissionManager: PermissionManagerStub(),
            onOpenSettings: {},
            onDismiss: {}
        )

        #expect(viewModel.experimentalBrowserTabCloseEnabled == false)
        #expect(viewModel.experimentalDisplayMoveActionsEnabled == false)
        #expect(viewModel.smartBrowserTabCloseEnabled == false)

        viewModel.experimentalBrowserTabCloseEnabled = true
        viewModel.experimentalDisplayMoveActionsEnabled = true
        viewModel.smartBrowserTabCloseEnabled = true

        #expect(store.experimentalBrowserTabCloseEnabled == true)
        #expect(store.experimentalDisplayMoveActionsEnabled == true)
        #expect(store.smartBrowserTabCloseEnabled == true)

        viewModel.experimentalBrowserTabCloseEnabled = false

        #expect(viewModel.experimentalBrowserTabCloseEnabled == false)
        #expect(viewModel.smartBrowserTabCloseEnabled == false)
    }

    @Test
    func welcomeGuideCanOpenSettingsBeforePermissionIsGranted() {
        let suiteName = "Swooshy.WelcomeWindowControllerTests.Permission.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        let viewModel = WelcomeGuideViewModel(
            settingsStore: store,
            permissionManager: PermissionManagerStub(isTrustedValue: false),
            onOpenSettings: {},
            onDismiss: {}
        )

        #expect(viewModel.permissionGranted == false)
        #expect(viewModel.canOpenSettings == true)
    }
}
