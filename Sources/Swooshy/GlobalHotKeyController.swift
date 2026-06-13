import AppKit
import Carbon.HIToolbox

@MainActor
protocol HotKeyRegistering {
    func registerHotKey(
        keyCode: UInt32,
        modifiers: UInt32,
        hotKeyID: EventHotKeyID,
        target: EventTargetRef?,
        options: OptionBits,
        hotKeyRef: inout EventHotKeyRef?
    ) -> OSStatus

    func unregisterHotKey(_ hotKeyRef: EventHotKeyRef)
}

@MainActor
struct CarbonHotKeyRegistrar: HotKeyRegistering {
    func registerHotKey(
        keyCode: UInt32,
        modifiers: UInt32,
        hotKeyID: EventHotKeyID,
        target: EventTargetRef?,
        options: OptionBits,
        hotKeyRef: inout EventHotKeyRef?
    ) -> OSStatus {
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            target,
            options,
            &hotKeyRef
        )
    }

    func unregisterHotKey(_ hotKeyRef: EventHotKeyRef) {
        UnregisterEventHotKey(hotKeyRef)
    }
}

@MainActor
protocol HotKeyEventHandling {
    var applicationEventTarget: EventTargetRef? { get }

    func installHotKeyPressedHandler(
        _ handler: EventHandlerUPP,
        userData: UnsafeMutableRawPointer,
        eventHandlerRef: inout EventHandlerRef?
    ) -> OSStatus

    func removeEventHandler(_ eventHandlerRef: EventHandlerRef)
}

@MainActor
struct CarbonHotKeyEventHandler: HotKeyEventHandling {
    var applicationEventTarget: EventTargetRef? {
        GetApplicationEventTarget()
    }

    func installHotKeyPressedHandler(
        _ handler: EventHandlerUPP,
        userData: UnsafeMutableRawPointer,
        eventHandlerRef: inout EventHandlerRef?
    ) -> OSStatus {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        return InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventSpec,
            userData,
            &eventHandlerRef
        )
    }

    func removeEventHandler(_ eventHandlerRef: EventHandlerRef) {
        RemoveEventHandler(eventHandlerRef)
    }
}

@MainActor
final class GlobalHotKeyController {
    private let windowActionRunner: WindowActionRunning
    private let alertPresenter: AlertPresenting
    private let settingsStore: SettingsStore
    private let registrationStatusStore: HotKeyRegistrationStatusStore
    private let hotKeyRegistrar: HotKeyRegistering
    private let eventHandling: HotKeyEventHandling
    private var eventHandlerRef: EventHandlerRef?
    private var eventHandlerInstalled = false
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var hasShownPermissionHint = false
    private var settingsObserver: NSObjectProtocol?

    init(
        windowActionRunner: WindowActionRunning,
        alertPresenter: AlertPresenting,
        settingsStore: SettingsStore,
        registrationStatusStore: HotKeyRegistrationStatusStore = HotKeyRegistrationStatusStore(),
        hotKeyRegistrar: HotKeyRegistering = CarbonHotKeyRegistrar(),
        eventHandling: HotKeyEventHandling = CarbonHotKeyEventHandler()
    ) {
        self.windowActionRunner = windowActionRunner
        self.alertPresenter = alertPresenter
        self.settingsStore = settingsStore
        self.registrationStatusStore = registrationStatusStore
        self.hotKeyRegistrar = hotKeyRegistrar
        self.eventHandling = eventHandling

        installEventHandler()
        syncRegisteredHotKeys()
        observeSettings()
    }

    deinit {
        // deinit is not guaranteed to run on the main thread; assumeIsolated
        // would crash there. AppDelegate calls shutdown() explicitly, so this
        // is only a best-effort fallback when deallocated on the main thread.
        guard Thread.isMainThread else {
            assertionFailure("GlobalHotKeyController deallocated off the main thread without shutdown()")
            return
        }

        MainActor.assumeIsolated {
            shutdown()
        }
    }

    func shutdown() {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }

        unregisterHotKeys()

        if let eventHandlerRef {
            eventHandling.removeEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        eventHandlerInstalled = false
        registrationStatusStore.clear()
    }

    private func installEventHandler() {
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let status = eventHandling.installHotKeyPressedHandler(
            Self.eventHandler,
            userData: selfPointer,
            eventHandlerRef: &eventHandlerRef
        )

        guard status == noErr else {
            eventHandlerRef = nil
            eventHandlerInstalled = false
            registrationStatusStore.markHandlerUnavailable()
            DebugLog.error(DebugLog.hotkeys, "Failed to install global hotkey event handler; status \(status)")
            return
        }

        eventHandlerInstalled = true
    }

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: settingsStore,
            queue: .main
        ) { [weak self] notification in
            let categories = notification.settingsChangeCategories
            MainActor.assumeIsolated {
                guard categories.contains(.hotKeys) else {
                    return
                }

                self?.syncRegisteredHotKeys()
            }
        }
    }

    private func syncRegisteredHotKeys() {
        unregisterHotKeys()
        registrationStatusStore.clear()

        guard settingsStore.hotKeysEnabled else {
            DebugLog.info(DebugLog.hotkeys, "Global hotkeys disabled")
            return
        }

        guard eventHandlerInstalled else {
            registrationStatusStore.markHandlerUnavailable()
            DebugLog.error(DebugLog.hotkeys, "Skipping global hotkey registration because event handler is unavailable")
            return
        }

        DebugLog.info(DebugLog.hotkeys, "Registering global hotkeys")
        registerHotKeys()
    }

    private func registerHotKeys() {
        for action in settingsStore.availableWindowActions {
            let binding = settingsStore.hotKeyBinding(for: action)
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(
                signature: Self.hotKeySignature,
                id: UInt32(action.rawValue + 1)
            )

            let status = hotKeyRegistrar.registerHotKey(
                keyCode: binding.keyCode,
                modifiers: binding.carbonModifiers,
                hotKeyID: hotKeyID,
                target: eventHandling.applicationEventTarget,
                options: 0,
                hotKeyRef: &hotKeyRef
            )
            let actionTitle = action.title(preferredLanguages: settingsStore.preferredLanguages)

            if status == noErr {
                hotKeyRefs.append(hotKeyRef)
                DebugLog.debug(
                    DebugLog.hotkeys,
                    "Registered hotkey for \(actionTitle) as \(binding.modifiers.displayString)\(binding.menuDisplayKey)"
                )
            } else {
                registrationStatusStore.recordFailure(
                    HotKeyRegistrationFailure(
                        action: action,
                        binding: binding,
                        status: status
                    )
                )
                DebugLog.error(
                    DebugLog.hotkeys,
                    "Failed to register hotkey for \(actionTitle) with status \(status)"
                )
            }
        }
    }

    private func unregisterHotKeys() {
        for hotKeyRef in hotKeyRefs {
            if let hotKeyRef {
                hotKeyRegistrar.unregisterHotKey(hotKeyRef)
            }
        }

        hotKeyRefs.removeAll()
    }

    private func handleHotKey(withID identifier: UInt32) {
        guard settingsStore.hotKeysEnabled else { return }
        guard let action = WindowAction(rawValue: Int(identifier - 1)) else { return }
        let actionTitle = action.title(preferredLanguages: settingsStore.preferredLanguages)
        guard settingsStore.isWindowActionAvailable(action) else {
            DebugLog.info(
                DebugLog.hotkeys,
                "Ignoring unavailable hotkey action \(actionTitle)"
            )
            return
        }
        DebugLog.info(DebugLog.hotkeys, "Triggered hotkey for action \(actionTitle)")

        do {
            try windowActionRunner.run(action)
        } catch let error as WindowManagerError {
            handleWindowManagerError(error)
        } catch {
            NSSound.beep()
            DebugLog.error(DebugLog.hotkeys, "Hot key action failed: \(error.localizedDescription)")
        }
    }

    private func handleWindowManagerError(_ error: WindowManagerError) {
        switch error {
        case .accessibilityPermissionMissing:
            guard !hasShownPermissionHint else {
                NSSound.beep()
                return
            }

            hasShownPermissionHint = true
            alertPresenter.show(
                title: settingsStore.localized("alert.permission_required.title"),
                message: settingsStore.localized("alert.permission_required.message")
            )
        default:
            NSSound.beep()
            DebugLog.error(DebugLog.hotkeys, "Hot key action failed: \(error.localizedDescription)")
        }
    }

    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            return status
        }

        guard hotKeyID.signature == GlobalHotKeyController.hotKeySignature else {
            return OSStatus(eventNotHandledErr)
        }

        let controller = Unmanaged<GlobalHotKeyController>
            .fromOpaque(userData)
            .takeUnretainedValue()

        Task { @MainActor in
            controller.handleHotKey(withID: hotKeyID.id)
        }

        return noErr
    }

    private static let hotKeySignature: OSType = 0x53575348 // "SWSH"
}
