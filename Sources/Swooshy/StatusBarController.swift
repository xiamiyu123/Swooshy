import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let permissionManager: AccessibilityPermissionManaging
    private let windowActionRunner: WindowActionRunning
    private let alertPresenter: AlertPresenting
    private let settingsStore: SettingsStore
    private let settingsWindowController: SettingsWindowController
    private let welcomeWindowController: WelcomeWindowController
    private let menuContentBuilder = StatusMenuContentBuilder()
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var settingsObserver: NSObjectProtocol?
    private var isShuttingDown = false

    init(
        permissionManager: AccessibilityPermissionManaging,
        windowActionRunner: WindowActionRunning,
        alertPresenter: AlertPresenting,
        settingsStore: SettingsStore,
        settingsWindowController: SettingsWindowController,
        welcomeWindowController: WelcomeWindowController
    ) {
        self.permissionManager = permissionManager
        self.windowActionRunner = windowActionRunner
        self.alertPresenter = alertPresenter
        self.settingsStore = settingsStore
        self.settingsWindowController = settingsWindowController
        self.welcomeWindowController = welcomeWindowController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        observeSettings()
        rebuildMenu()
    }

    func shutdown() {
        guard isShuttingDown == false else { return }
        isShuttingDown = true

        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }

        menu.delegate = nil
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            DebugLog.error(DebugLog.app, "Status item button is unavailable; menu icon setup skipped")
            return
        }

        button.imageScaling = .scaleProportionallyDown
        updateStatusItemAppearance(using: button)

        // Prevent AppKit from auto-validating items and overriding manual enabled states.
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
    }

    private func updateStatusItemAppearance(using button: NSStatusBarButton? = nil) {
        guard let button = button ?? statusItem.button else {
            DebugLog.error(DebugLog.app, "Status item button is unavailable; menu icon refresh skipped")
            return
        }

        let accessibilityDescription = settingsStore.localized("menu.app_name")

        if let image = settingsStore.statusItemIcon.makeImage(
            accessibilityDescription: accessibilityDescription
        ) {
            button.image = image
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            DebugLog.error(
                DebugLog.app,
                "Unable to load status item icon \(settingsStore.statusItemIcon.storageValue); falling back to text"
            )
            button.image = nil
            button.title = "S"
            button.imagePosition = .imageLeading
        }

        button.toolTip = accessibilityDescription
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let permissionGranted = permissionManager.isTrusted(promptIfNeeded: false)
        DebugLog.debug(DebugLog.app, "Rebuilding status menu; accessibility granted = \(permissionGranted)")
        let entries = menuContentBuilder.makeEntries(
            permissionGranted: permissionGranted,
            collapseWindowActions: settingsStore.collapseStatusItemWindowActions,
            preferredLanguages: settingsStore.preferredLanguages
        )

        for entry in entries {
            menu.addItem(menuItem(for: entry, permissionGranted: permissionGranted))
        }
    }

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: settingsStore,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateStatusItemAppearance()
                self?.rebuildMenu()
            }
        }
    }

    @objc
    private func requestAccessibilityAccess() {
        DebugLog.info(DebugLog.accessibility, "Permission menu clicked; showing welcome guide")
        welcomeWindowController.show()
    }

    @objc
    private func refreshPermissionState() {
        DebugLog.debug(DebugLog.accessibility, "Refreshing accessibility permission state")
        rebuildMenu()
    }

    @objc
    private func runWindowAction(_ sender: NSMenuItem) {
        guard handleMissingPermissionFallback(for: "window action") == false else { return }
        guard let action = sender.representedObject as? WindowAction else { return }
        DebugLog.info(DebugLog.app, "Menu triggered action \(action.title(preferredLanguages: settingsStore.preferredLanguages))")

        do {
            try windowActionRunner.run(action)
        } catch {
            DebugLog.error(DebugLog.app, "Menu action failed: \(error.localizedDescription)")
            alertPresenter.show(
                title: settingsStore.localized("alert.window_action_failed.title"),
                message: error.localizedDescription
            )
        }
    }

    @objc
    private func showSettingsWindow() {
        guard handleMissingPermissionFallback(for: "settings") == false else { return }
        settingsWindowController.show()
    }

    @objc
    private func showHelpPanel() {
        DebugLog.info(DebugLog.app, "Help menu clicked; showing guide")
        welcomeWindowController.showGuide()
    }

    @objc
    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func handleMissingPermissionFallback(for actionName: String) -> Bool {
        let permissionGranted = permissionManager.isTrusted(promptIfNeeded: false)
        guard permissionGranted == false else {
            return false
        }

        DebugLog.info(
            DebugLog.accessibility,
            "Menu action \(actionName) blocked because accessibility permission is missing; showing welcome guide"
        )
        welcomeWindowController.show()
        rebuildMenu()
        return true
    }

    private func menuItem(for entry: StatusMenuEntry, permissionGranted: Bool) -> NSMenuItem {
        let enforcePermissionLock = permissionGranted == false

        switch entry.kind {
        case .separator:
            return .separator()
        case .title:
            let item = NSMenuItem()
            item.title = entry.title
            item.isEnabled = entry.isEnabled
            return item
        case .permission:
            let item = NSMenuItem(
                title: entry.title,
                action: entry.isEnabled ? #selector(requestAccessibilityAccess) : nil,
                keyEquivalent: ""
            )
            item.target = self
            item.isEnabled = enforcePermissionLock ? true : entry.isEnabled
            return item
        case .refresh:
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(refreshPermissionState),
                keyEquivalent: "r"
            )
            item.target = self
            item.isEnabled = true
            return item
        case .windowAction(let action):
            let binding = settingsStore.hotKeyBinding(for: action)
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(runWindowAction(_:)),
                keyEquivalent: binding.menuKeyEquivalent
            )
            item.target = self
            item.representedObject = action
            item.isEnabled = enforcePermissionLock ? false : entry.isEnabled
            item.keyEquivalentModifierMask = binding.menuModifierFlags
            return item
        case .windowActionGroup:
            let item = NSMenuItem(
                title: entry.title,
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = enforcePermissionLock ? false : entry.isEnabled
            item.submenu = windowActionsSubmenu(permissionGranted: permissionGranted)
            return item
        case .help:
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(showHelpPanel),
                keyEquivalent: ""
            )
            item.target = self
            item.isEnabled = entry.isEnabled
            return item
        case .settings:
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(showSettingsWindow),
                keyEquivalent: ","
            )
            item.target = self
            item.isEnabled = enforcePermissionLock ? false : entry.isEnabled
            item.keyEquivalentModifierMask = [.command]
            return item
        case .quit:
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(quit),
                keyEquivalent: "q"
            )
            item.target = self
            // Allow clicking Quit even without permission
            item.isEnabled = entry.isEnabled
            return item
        }
    }

    private func windowActionsSubmenu(permissionGranted: Bool) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let entries = WindowAction.allCases.map { action in
            StatusMenuEntry(
                kind: .windowAction(action),
                title: action.title(preferredLanguages: settingsStore.preferredLanguages),
                isEnabled: permissionGranted
            )
        }

        for entry in entries {
            submenu.addItem(menuItem(for: entry, permissionGranted: permissionGranted))
        }

        return submenu
    }
}
