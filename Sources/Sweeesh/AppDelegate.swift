import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var globalHotKeyController: GlobalHotKeyController?
    private var settingsWindowController: SettingsWindowController?
    private var dockGestureController: DockGestureController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settingsStore = SettingsStore()
        DebugLog.info(DebugLog.app, "Sweeesh launch sequence started")
        DebugLog.info(DebugLog.app, "Debug log file path: \(DebugLog.logFilePathDescription)")
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

        dockGestureController = DockGestureController(
            windowManager: windowManager,
            alertPresenter: alertPresenter,
            settingsStore: settingsStore
        )

        DebugLog.info(DebugLog.app, "Sweeesh launch sequence completed")
    }
}
