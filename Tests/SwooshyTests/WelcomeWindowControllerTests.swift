import Combine
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
        let store = makeSettingsStore()
        store.languageOverride = .simplifiedChinese

        let chineseContent = WelcomeGuideContent.make(settingsStore: store)
        #expect(chineseContent.windowTitle == "欢迎")
        #expect(chineseContent.welcomeTitle == "欢迎使用 Swooshy")

        store.languageOverride = .english

        let englishContent = WelcomeGuideContent.make(settingsStore: store)
        let dockSwitchPage = englishContent.pages[1]
        let titleBarHorizontalPage = englishContent.pages[5]
        let cornerSnapPage = englishContent.pages[6]
        let shortcutsPage = englishContent.pages[8]
        let experimentalPage = englishContent.pages[10]

        #expect(englishContent.windowTitle == "Welcome")
        #expect(englishContent.welcomeTitle == "Welcome to Swooshy")
        #expect(dockSwitchPage.title == "Dock Gestures: Switch Windows for the Same App")
        #expect(titleBarHorizontalPage.bullets.count == 3)
        #expect(titleBarHorizontalPage.bullets[2].contains("real window"))
        #expect(cornerSnapPage.title == "Title Bar Gestures: Corner Snap Mode")
        #expect(cornerSnapPage.bullets.count == 3)
        #expect(cornerSnapPage.message.contains("title bar or Dock"))
        #expect(cornerSnapPage.bullets[0].contains("0.2 seconds"))
        #expect(cornerSnapPage.visual == .cornerSnapGesturePreview)
        #expect(shortcutsPage.bullets.count == 7)
        #expect(shortcutsPage.bullets[5].contains("Experimental display moves"))
        #expect(experimentalPage.bullets.count == 4)
        #expect(experimentalPage.bullets[3].contains("Display move actions"))
    }

    @Test
    func settingsStoreUsesShortCornerSnapHoldDurationByDefault() {
        let store = makeSettingsStore()

        #expect(store.titleBarCornerDragHoldDuration == 0.2)
    }

    @Test
    func welcomeGuideOnlyShowsPermissionStatusOnWelcomePage() {
        let store = makeSettingsStore()
        let content = WelcomeGuideContent.make(settingsStore: store)

        let pagesShowingPermission = content.pages
            .filter { $0.showsPermissionStatus }
            .map(\.id)

        #expect(pagesShowingPermission == [0])
    }

    @Test
    func welcomeGuideHUDStyleOptionUsesSettingsStore() {
        let store = makeSettingsStore()
        let viewModel = makeViewModel(settingsStore: store)

        viewModel.gestureHUDStyle = .minimal

        #expect(store.gestureHUDStyle == .minimal)
        #expect(viewModel.gestureHUDStyle == .minimal)
    }

    @Test
    func welcomeGuideHUDPreviewItemsFollowSelectedStyleAndGestureActions() {
        let store = makeSettingsStore()
        let viewModel = makeViewModel(settingsStore: store)

        viewModel.gestureHUDStyle = .classic

        let items = viewModel.gesturePreviewItems

        #expect(items.map(\.style) == [.classic, .classic])
        #expect(items.map(\.gesture) == [.pinchIn, .swipeUp])
        #expect(items.map(\.actionTitle) == [
            DockGestureAction.quitApplication.title(preferredLanguages: store.preferredLanguages),
            DockGestureAction.restoreWindow.title(preferredLanguages: store.preferredLanguages),
        ])
    }

    @Test
    func welcomeGuideExperimentalOptionsUseSameGateAsSettings() {
        let store = makeSettingsStore()
        let viewModel = makeViewModel(settingsStore: store)

        #expect(!viewModel.experimentalBrowserTabCloseEnabled)
        #expect(!viewModel.experimentalDisplayMoveActionsEnabled)
        #expect(!viewModel.smartBrowserTabCloseEnabled)

        viewModel.experimentalBrowserTabCloseEnabled = true
        viewModel.experimentalDisplayMoveActionsEnabled = true
        viewModel.smartBrowserTabCloseEnabled = true

        #expect(store.experimentalBrowserTabCloseEnabled)
        #expect(store.experimentalDisplayMoveActionsEnabled)
        #expect(store.smartBrowserTabCloseEnabled)

        viewModel.experimentalBrowserTabCloseEnabled = false

        #expect(!viewModel.experimentalBrowserTabCloseEnabled)
        #expect(!viewModel.smartBrowserTabCloseEnabled)
    }

    @Test
    func settingsBackedWelcomeGuideOptionsPublishViewChanges() {
        let store = makeSettingsStore()
        let viewModel = makeViewModel(settingsStore: store)
        var notificationCount = 0
        let cancellable = viewModel.objectWillChange.sink {
            notificationCount += 1
        }
        defer {
            cancellable.cancel()
        }

        viewModel.experimentalBrowserTabCloseEnabled = true
        viewModel.smartBrowserTabCloseEnabled = true
        viewModel.experimentalBrowserTabCloseEnabled = false

        #expect(notificationCount == 3)
        #expect(!viewModel.experimentalBrowserTabCloseEnabled)
        #expect(!viewModel.smartBrowserTabCloseEnabled)
    }

    @Test
    func welcomeGuideCanOpenSettingsBeforePermissionIsGranted() {
        let store = makeSettingsStore()
        let viewModel = makeViewModel(
            settingsStore: store,
            permissionManager: PermissionManagerStub(isTrustedValue: false)
        )

        #expect(!viewModel.permissionGranted)
        #expect(viewModel.canOpenSettings)
    }

    private func makeSettingsStore() -> SettingsStore {
        SettingsStore(userDefaults: makeDefaults())
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "Swooshy.WelcomeWindowControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeViewModel(
        settingsStore: SettingsStore,
        permissionManager: PermissionManagerStub = PermissionManagerStub()
    ) -> WelcomeGuideViewModel {
        WelcomeGuideViewModel(
            settingsStore: settingsStore,
            permissionManager: permissionManager,
            onOpenSettings: {},
            onDismiss: {}
        )
    }
}
