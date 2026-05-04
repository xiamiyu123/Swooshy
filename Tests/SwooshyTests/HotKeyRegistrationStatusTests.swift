import Carbon.HIToolbox
import Foundation
import Testing
@testable import Swooshy

@MainActor
struct HotKeyRegistrationStatusTests {
    @Test
    func recordsFailedRegistrationsAndClearsAfterSuccessfulResync() async {
        let suiteName = "Swooshy.HotKeyRegistrationStatusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settingsStore = SettingsStore(userDefaults: defaults)
        let registrationStatusStore = HotKeyRegistrationStatusStore()
        let registrar = FakeHotKeyRegistrar(failingActions: [.maximize])
        let controller = GlobalHotKeyController(
            windowActionRunner: NoOpWindowActionRunner(),
            alertPresenter: NoOpAlertPresenter(),
            settingsStore: settingsStore,
            registrationStatusStore: registrationStatusStore,
            hotKeyRegistrar: registrar,
            eventHandling: FakeHotKeyEventHandling()
        )
        defer {
            controller.shutdown()
        }

        let initialFailure = registrationStatusStore.failure(for: .maximize)
        #expect(initialFailure?.binding == settingsStore.hotKeyBinding(for: .maximize))
        #expect(initialFailure?.status == FakeHotKeyRegistrar.failureStatus)

        registrar.failingActions = []
        settingsStore.updateHotKeyKey(.d, for: .maximize)

        for _ in 0 ..< 3 {
            await Task.yield()
        }

        #expect(registrationStatusStore.failure(for: .maximize) == nil)
        #expect(registrationStatusStore.failures.isEmpty)
    }

    @Test
    func disablingGlobalHotKeysClearsRegistrationFailures() async {
        let suiteName = "Swooshy.HotKeyRegistrationStatusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settingsStore = SettingsStore(userDefaults: defaults)
        let registrationStatusStore = HotKeyRegistrationStatusStore()
        let controller = GlobalHotKeyController(
            windowActionRunner: NoOpWindowActionRunner(),
            alertPresenter: NoOpAlertPresenter(),
            settingsStore: settingsStore,
            registrationStatusStore: registrationStatusStore,
            hotKeyRegistrar: FakeHotKeyRegistrar(failingActions: [.center]),
            eventHandling: FakeHotKeyEventHandling()
        )
        defer {
            controller.shutdown()
        }

        #expect(registrationStatusStore.failure(for: .center) != nil)

        settingsStore.hotKeysEnabled = false

        for _ in 0 ..< 3 {
            await Task.yield()
        }

        #expect(registrationStatusStore.failures.isEmpty)
        #expect(registrationStatusStore.handlerUnavailable == false)
    }

    @Test
    func rowFactoryAttachesFailuresOnlyToAffectedActions() {
        let suiteName = "Swooshy.HotKeyRegistrationStatusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settingsStore = SettingsStore(userDefaults: defaults)
        let registrationStatusStore = HotKeyRegistrationStatusStore()
        let centerBinding = settingsStore.hotKeyBinding(for: .center)
        registrationStatusStore.recordFailure(
            HotKeyRegistrationFailure(
                action: .center,
                binding: centerBinding,
                status: FakeHotKeyRegistrar.failureStatus
            )
        )

        let rows = HotKeySettingsRowFactory.rows(
            settingsStore: settingsStore,
            registrationStatusStore: registrationStatusStore
        )

        #expect(rows.first { $0.action == .center }?.registrationFailure?.binding == centerBinding)
        #expect(rows.first { $0.action == .leftHalf }?.registrationFailure == nil)
    }

    @Test
    func handlerUnavailableMarksEveryActionAsAffected() {
        let registrationStatusStore = HotKeyRegistrationStatusStore()

        #expect(registrationStatusStore.hasIssue == false)
        #expect(registrationStatusStore.issueKind(for: .leftHalf) == nil)

        registrationStatusStore.markHandlerUnavailable()

        #expect(registrationStatusStore.hasIssue)
        #expect(registrationStatusStore.issueKind(for: .leftHalf) == .handlerUnavailable)
        #expect(registrationStatusStore.issueKind(for: .quitApplication) == .handlerUnavailable)
    }
}

@MainActor
private final class FakeHotKeyRegistrar: HotKeyRegistering {
    static let failureStatus = OSStatus(eventHotKeyExistsErr)

    var failingActions: Set<WindowAction>

    init(failingActions: Set<WindowAction>) {
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
