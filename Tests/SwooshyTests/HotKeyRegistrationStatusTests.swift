import Carbon.HIToolbox
import Foundation
import Testing
@testable import Swooshy

@MainActor
struct HotKeyRegistrationStatusTests {
    private let displayMoveActions: Set<WindowAction> = [.moveToNextDisplay, .moveToPreviousDisplay]

    @Test
    func recordsFailedRegistrationsAndClearsAfterSuccessfulResync() async {
        let settingsStore = makeSettingsStore()
        let registrationStatusStore = HotKeyRegistrationStatusStore()
        let registrar = FakeHotKeyRegistrar(failingActions: [.maximize])
        let controller = makeController(
            settingsStore: settingsStore,
            registrationStatusStore: registrationStatusStore,
            hotKeyRegistrar: registrar
        )
        defer {
            controller.shutdown()
        }

        let initialFailure = registrationStatusStore.failure(for: .maximize)
        #expect(initialFailure?.binding == settingsStore.hotKeyBinding(for: .maximize))
        #expect(initialFailure?.status == FakeHotKeyRegistrar.failureStatus)

        registrar.failingActions = []
        settingsStore.updateHotKeyKey(.d, for: .maximize)

        await yieldForPendingMainActorWork()

        #expect(registrationStatusStore.failure(for: .maximize) == nil)
        #expect(registrationStatusStore.failures.isEmpty)
    }

    @Test
    func disablingGlobalHotKeysClearsRegistrationFailures() async {
        let settingsStore = makeSettingsStore()
        let registrationStatusStore = HotKeyRegistrationStatusStore()
        let controller = makeController(
            settingsStore: settingsStore,
            registrationStatusStore: registrationStatusStore,
            hotKeyRegistrar: FakeHotKeyRegistrar(failingActions: [.center])
        )
        defer {
            controller.shutdown()
        }

        #expect(registrationStatusStore.failure(for: .center) != nil)

        settingsStore.hotKeysEnabled = false

        await yieldForPendingMainActorWork()

        #expect(registrationStatusStore.failures.isEmpty)
        #expect(!registrationStatusStore.handlerUnavailable)
    }

    @Test
    func rowFactoryAttachesFailuresOnlyToAffectedActions() {
        let settingsStore = makeSettingsStore()
        let registrationStatusStore = HotKeyRegistrationStatusStore()
        let centerBinding = settingsStore.hotKeyBinding(for: .center)
        registrationStatusStore.recordFailure(
            HotKeyRegistrationFailure(
                action: .center,
                binding: centerBinding,
                status: FakeHotKeyRegistrar.failureStatus
            )
        )

        #expect(registrationStatusStore.issueKind(for: .center) == .registrationFailed)
        #expect(registrationStatusStore.issueKind(for: .leftHalf) == nil)

        let rows = HotKeySettingsRowFactory.rows(
            settingsStore: settingsStore,
            registrationStatusStore: registrationStatusStore
        )

        #expect(row(.center, in: rows)?.registrationFailure?.binding == centerBinding)
        #expect(row(.leftHalf, in: rows)?.registrationFailure == nil)
        for action in displayMoveActions {
            #expect(row(action, in: rows) == nil)
        }
    }

    @Test
    func rowFactoryShowsDisplayMoveActionsOnlyWhenExperimentalModeIsEnabled() {
        let settingsStore = makeSettingsStore()
        let registrationStatusStore = HotKeyRegistrationStatusStore()
        let hiddenRows = HotKeySettingsRowFactory.rows(
            settingsStore: settingsStore,
            registrationStatusStore: registrationStatusStore
        )

        for action in displayMoveActions {
            #expect(row(action, in: hiddenRows) == nil)
        }

        settingsStore.experimentalDisplayMoveActionsEnabled = true
        let visibleRows = HotKeySettingsRowFactory.rows(
            settingsStore: settingsStore,
            registrationStatusStore: registrationStatusStore
        )

        for action in displayMoveActions {
            #expect(row(action, in: visibleRows) != nil)
        }
    }

    @Test
    func defaultRegistrationSkipsDisplayMoveHotKeys() {
        let settingsStore = makeSettingsStore()
        let registrar = FakeHotKeyRegistrar()
        let controller = makeController(
            settingsStore: settingsStore,
            hotKeyRegistrar: registrar
        )
        defer {
            controller.shutdown()
        }

        #expect(Set(registrar.registeredActions).isDisjoint(with: displayMoveActions))
        #expect(registrar.registeredActions.contains(.leftHalf))
    }

    @Test
    func enablingDisplayMoveExperimentalModeRegistersDisplayMoveHotKeys() async {
        let settingsStore = makeSettingsStore()
        let registrar = FakeHotKeyRegistrar()
        let controller = makeController(
            settingsStore: settingsStore,
            hotKeyRegistrar: registrar
        )
        defer {
            controller.shutdown()
        }

        registrar.registeredActions.removeAll()
        settingsStore.experimentalDisplayMoveActionsEnabled = true

        await yieldForPendingMainActorWork()

        #expect(Set(registrar.registeredActions).isSuperset(of: displayMoveActions))
    }

    @Test
    func handlerUnavailableMarksEveryActionAsAffected() {
        let registrationStatusStore = HotKeyRegistrationStatusStore()

        #expect(!registrationStatusStore.hasIssue)
        #expect(registrationStatusStore.issueKind(for: .leftHalf) == nil)

        registrationStatusStore.markHandlerUnavailable()

        #expect(registrationStatusStore.hasIssue)
        #expect(registrationStatusStore.issueKind(for: .leftHalf) == .handlerUnavailable)
        #expect(registrationStatusStore.issueKind(for: .quitApplication) == .handlerUnavailable)
    }

    private func makeSettingsStore() -> SettingsStore {
        let suiteName = "Swooshy.HotKeyRegistrationStatusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsStore(userDefaults: defaults)
    }

    private func makeController(
        settingsStore: SettingsStore,
        registrationStatusStore: HotKeyRegistrationStatusStore = HotKeyRegistrationStatusStore(),
        hotKeyRegistrar: FakeHotKeyRegistrar
    ) -> GlobalHotKeyController {
        GlobalHotKeyController(
            windowActionRunner: NoOpWindowActionRunner(),
            alertPresenter: NoOpAlertPresenter(),
            settingsStore: settingsStore,
            registrationStatusStore: registrationStatusStore,
            hotKeyRegistrar: hotKeyRegistrar,
            eventHandling: FakeHotKeyEventHandling()
        )
    }

    private func row(
        _ action: WindowAction,
        in rows: [HotKeyRowModel]
    ) -> HotKeyRowModel? {
        rows.first { $0.action == action }
    }
}

@MainActor
private final class FakeHotKeyRegistrar: HotKeyRegistering {
    static let failureStatus = OSStatus(eventHotKeyExistsErr)

    var failingActions: Set<WindowAction>
    var registeredActions: [WindowAction] = []

    init(failingActions: Set<WindowAction> = []) {
        self.failingActions = failingActions
    }

    func registerHotKey(
        keyCode: UInt32,
        modifiers: UInt32,
        hotKeyID: EventHotKeyID,
        target: EventTargetRef?,
        options: OptionBits,
        hotKeyRef: inout EventHotKeyRef?
    ) -> OSStatus {
        guard let action = WindowAction(rawValue: Int(hotKeyID.id - 1)) else {
            return noErr
        }

        registeredActions.append(action)

        if failingActions.contains(action) {
            return Self.failureStatus
        }

        hotKeyRef = nil
        return noErr
    }

    func unregisterHotKey(_ hotKeyRef: EventHotKeyRef) {}
}

@MainActor
private struct FakeHotKeyEventHandling: HotKeyEventHandling {
    var applicationEventTarget: EventTargetRef? {
        nil
    }

    func installHotKeyPressedHandler(
        _ handler: EventHandlerUPP,
        userData: UnsafeMutableRawPointer,
        eventHandlerRef: inout EventHandlerRef?
    ) -> OSStatus {
        noErr
    }

    func removeEventHandler(_ eventHandlerRef: EventHandlerRef) {}
}

@MainActor
private struct NoOpWindowActionRunner: WindowActionRunning {
    func run(_ action: WindowAction) throws {}
}

@MainActor
private struct NoOpAlertPresenter: AlertPresenting {
    func show(title: String, message: String) {}
}
