import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var globalHotKeyController: GlobalHotKeyController?
    private var settingsWindowController: SettingsWindowController?
    private var welcomeWindowController: WelcomeWindowController?
    private var dockGestureController: DockGestureController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchOptions = LaunchOptions()
        launchOptions.apply()

        let settingsStore = SettingsStore()
        DebugLog.info(DebugLog.app, "Swooshy launch sequence started")
        DebugLog.info(DebugLog.app, "Debug log file path: \(DebugLog.logFilePathDescription)")
        if launchOptions.resetUserConfiguration {
            DebugLog.info(
                DebugLog.app,
                "Launch argument \(LaunchOptions.resetUserConfigurationArgument) detected; user configuration reset"
            )
        }
        if launchOptions.clearCache {
            DebugLog.info(
                DebugLog.app,
                "Launch argument \(LaunchOptions.clearCacheArgument) detected; persisted caches cleared"
            )
        }
        let permissionManager = AccessibilityPermissionManager()
        let hotKeyRegistrationStatusStore = HotKeyRegistrationStatusStore()
        let windowRegistry = WindowRegistry()
        let dockTargetResolver = DockTargetResolver(registry: windowRegistry)
        let windowManager = WindowManager(
            registry: windowRegistry,
            dockTargetResolver: dockTargetResolver
        )
        let layoutEngine = WindowLayoutEngine()
        let windowActionRunner = WindowActionRunner(
            windowManager: windowManager,
            layoutEngine: layoutEngine
        )
        let alertPresenter = AppAlertPresenter()
        let gestureFeedbackPresenter = GestureFeedbackController(settingsStore: settingsStore)
        let dockGestureController = DockGestureController(
            windowManager: windowManager,
            registry: windowRegistry,
            dockTargetResolver: dockTargetResolver,
            layoutEngine: layoutEngine,
            alertPresenter: alertPresenter,
            gestureFeedbackPresenter: gestureFeedbackPresenter,
            settingsStore: settingsStore
        )
        let settingsWindowController = SettingsWindowController(
            settingsStore: settingsStore,
            hotKeyRegistrationStatusStore: hotKeyRegistrationStatusStore,
            onPointerInsideChanged: { [weak dockGestureController] isInside in
                dockGestureController?.setSettingsWindowHoverSuppressed(isInside)
            }
        )
        let welcomeWindowController = WelcomeWindowController(
            settingsStore: settingsStore,
            permissionManager: permissionManager,
            onOpenSettings: { [weak settingsWindowController] in
                settingsWindowController?.show()
            }
        )

        self.settingsWindowController = settingsWindowController
        self.welcomeWindowController = welcomeWindowController

        statusBarController = StatusBarController(
            permissionManager: permissionManager,
            windowActionRunner: windowActionRunner,
            alertPresenter: alertPresenter,
            settingsStore: settingsStore,
            hotKeyRegistrationStatusStore: hotKeyRegistrationStatusStore,
            settingsWindowController: settingsWindowController,
            welcomeWindowController: welcomeWindowController
        )

        globalHotKeyController = GlobalHotKeyController(
            windowActionRunner: windowActionRunner,
            alertPresenter: alertPresenter,
            settingsStore: settingsStore,
            registrationStatusStore: hotKeyRegistrationStatusStore
        )

        self.dockGestureController = dockGestureController

        if launchOptions.previewHotKeyRegistrationFailure {
            let previewAction = WindowAction.center
            hotKeyRegistrationStatusStore.recordFailure(
                HotKeyRegistrationFailure(
                    action: previewAction,
                    binding: settingsStore.hotKeyBinding(for: previewAction),
                    status: OSStatus(eventHotKeyExistsErr)
                )
            )
            settingsWindowController.showShortcuts()
            DebugLog.info(
                DebugLog.app,
                "Launch argument \(LaunchOptions.previewHotKeyRegistrationFailureArgument) detected; previewing hotkey registration failure style"
            )
        } else if settingsStore.consumeWelcomeGuidePresentationFlag() {
            welcomeWindowController.show()
        }

        DebugLog.info(DebugLog.app, "Swooshy launch sequence completed")
    }

    func applicationWillTerminate(_ notification: Notification) {
        dockGestureController?.shutdown()
        globalHotKeyController?.shutdown()
        statusBarController?.shutdown()
        settingsWindowController?.shutdown()
        welcomeWindowController?.shutdown()

        dockGestureController = nil
        globalHotKeyController = nil
        statusBarController = nil
        settingsWindowController = nil
        welcomeWindowController = nil
    }
}
