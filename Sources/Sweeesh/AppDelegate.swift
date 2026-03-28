import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var globalHotKeyController: GlobalHotKeyController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settingsStore = SettingsStore()
        let permissionManager = AccessibilityPermissionManager()
        let windowManager = WindowManager()
        let layoutEngine = WindowLayoutEngine()
        let windowActionRunner = WindowActionRunner(
            windowManager: windowManager,
            layoutEngine: layoutEngine
        )
        let alertPresenter = AppAlertPresenter()
        let settingsWindowController = SettingsWindowController(settingsStore: settingsStore)

        self.settingsWindowController = settingsWindowController

        statusBarController = StatusBarController(
            permissionManager: permissionManager,
            windowActionRunner: windowActionRunner,
            alertPresenter: alertPresenter,
            settingsStore: settingsStore,
            settingsWindowController: settingsWindowController
        )

        globalHotKeyController = GlobalHotKeyController(
            windowActionRunner: windowActionRunner,
            alertPresenter: alertPresenter,
            settingsStore: settingsStore
        )
    }
}
