import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let permissionManager: AccessibilityPermissionManaging
    private let windowActionRunner: WindowActionRunning
    private let alertPresenter: AlertPresenting
    private let settingsStore: SettingsStore
    private let settingsWindowController: SettingsWindowController
    private let menuContentBuilder = StatusMenuContentBuilder()
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var settingsObserver: NSObjectProtocol?

    init(
        permissionManager: AccessibilityPermissionManaging,
        windowActionRunner: WindowActionRunning,
        alertPresenter: AlertPresenting,
        settingsStore: SettingsStore,
        settingsWindowController: SettingsWindowController
    ) {
        self.permissionManager = permissionManager
        self.windowActionRunner = windowActionRunner
        self.alertPresenter = alertPresenter
        self.settingsStore = settingsStore
        self.settingsWindowController = settingsWindowController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        observeSettings()
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = NSImage(
            systemSymbolName: "rectangle.3.group",
            accessibilityDescription: "Sweeesh"
        )
        button.imagePosition = .imageOnly

        menu.delegate = self
        statusItem.menu = menu
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let permissionGranted = permissionManager.isTrusted(promptIfNeeded: false)
        let entries = menuContentBuilder.makeEntries(
            permissionGranted: permissionGranted,
            preferredLanguages: settingsStore.preferredLanguages
        )

        for entry in entries {
            menu.addItem(menuItem(for: entry))
        }
    }

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: settingsStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildMenu()
            }
        }
    }

    @objc
    private func requestAccessibilityAccess() {
        let granted = permissionManager.isTrusted(promptIfNeeded: true)

        if !granted {
            alertPresenter.show(
                title: settingsStore.localized("alert.permission_required.title"),
                message: settingsStore.localized("alert.permission_required.message")
            )
        }

        rebuildMenu()
    }

    @objc
    private func refreshPermissionState() {
        rebuildMenu()
    }

    @objc
    private func runWindowAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? WindowAction else { return }

        do {
            try windowActionRunner.run(action)
        } catch {
            alertPresenter.show(
                title: settingsStore.localized("alert.window_action_failed.title"),
                message: error.localizedDescription
            )
        }
    }

    @objc
    private func showSettingsWindow() {
        settingsWindowController.show()
    }

    @objc
    private func showAboutPanel() {
        alertPresenter.show(
            title: settingsStore.localized("alert.about.title"),
            message: settingsStore.localized("alert.about.message")
        )
    }

    @objc
    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func menuItem(for entry: StatusMenuEntry) -> NSMenuItem {
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
            item.isEnabled = entry.isEnabled
            return item
        case .refresh:
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(refreshPermissionState),
                keyEquivalent: "r"
            )
            item.target = self
            item.isEnabled = entry.isEnabled
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
            item.isEnabled = entry.isEnabled
            item.keyEquivalentModifierMask = binding.menuModifierFlags
            return item
        case .help:
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(showAboutPanel),
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
            item.isEnabled = entry.isEnabled
            item.keyEquivalentModifierMask = [.command]
            return item
        case .quit:
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(quit),
                keyEquivalent: "q"
            )
            item.target = self
            item.isEnabled = entry.isEnabled
            return item
        }
    }
}
