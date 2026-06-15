import Foundation
import IOKit.hid

@MainActor
protocol MultitouchDeviceObserving: AnyObject {
    var onDeviceConfigurationChanged: (@MainActor () -> Void)? { get set }

    func start()
    func stop()
}

@MainActor
final class MultitouchDeviceRestartCoordinator {
    private let observer: MultitouchDeviceObserving
    private var pendingRestartTask: Task<Void, Never>?
    private var shouldRestart: (@MainActor () -> Bool)?
    private var restart: (@MainActor () -> Void)?

    init(observer: MultitouchDeviceObserving) {
        self.observer = observer
    }

    func start(
        shouldRestart: @escaping @MainActor () -> Bool,
        restart: @escaping @MainActor () -> Void
    ) {
        self.shouldRestart = shouldRestart
        self.restart = restart
        observer.onDeviceConfigurationChanged = { [weak self] in
            self?.scheduleRestartIfNeeded()
        }
        observer.start()
    }

    func stop() {
        pendingRestartTask?.cancel()
        pendingRestartTask = nil
        shouldRestart = nil
        restart = nil
        observer.onDeviceConfigurationChanged = nil
        observer.stop()
    }

    private func scheduleRestartIfNeeded() {
        guard pendingRestartTask == nil else {
            return
        }

        pendingRestartTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else {
                return
            }

            self.pendingRestartTask = nil
            guard self.shouldRestart?() == true else {
                return
            }

            self.restart?()
        }
    }
}

@MainActor
final class HIDMultitouchDeviceObserver: MultitouchDeviceObserving {
    var onDeviceConfigurationChanged: (@MainActor () -> Void)?

    // Wrapped in a Sendable box so a nonisolated `deinit` can read the handle.
    // The handle itself is only ever touched from the main run-loop (start/stop
    // are @MainActor, and the manager was scheduled onto the main run loop), so
    // the unchecked conformance is safe: access is effectively serialized.
    private var managerBox = HIDManagerBox()
    private let callbackContext = HIDObserverCallbackContext()

    private var manager: IOHIDManager? {
        get { managerBox.value }
        set { managerBox.value = newValue }
    }

    deinit {
        // deinit is not guaranteed to run on the main thread. The restart
        // coordinator calls stop() explicitly during normal teardown, so this
        // is a best-effort fallback to avoid leaking the IOHIDManager if an
        // instance is somehow released without that explicit stop.
        guard let manager = managerBox.value else { return }
        let callbackContext = callbackContext
        callbackContext.invalidate()

        if Thread.isMainThread {
            Self.tearDownManager(manager)
        } else {
            // Release builds must not silently leak: hop to the main run loop
            // (where the manager was scheduled) and tear it down there. In
            // debug, flag the unexpected off-main dealloc loudly.
            assertionFailure("HIDMultitouchDeviceObserver deallocated off the main thread without stop()")
            DispatchQueue.main.async {
                Self.tearDownManager(manager)
                withExtendedLifetime(callbackContext) {}
            }
        }
    }

    // nonisolated so it is callable from `deinit` (which is not main-actor
    // isolated). It touches only the C IOKit handle, no instance state.
    private nonisolated static func tearDownManager(_ manager: IOHIDManager) {
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func start() {
        guard manager == nil else {
            return
        }

        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        IOHIDManagerSetDeviceMatchingMultiple(manager, Self.matchingDictionaries as CFArray)

        callbackContext.activate(observer: self)
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(callbackContext).toOpaque())
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceConfigurationChanged, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceConfigurationChanged, context)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )

        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else {
            callbackContext.invalidate()
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.defaultMode.rawValue
            )
            DebugLog.error(DebugLog.dock, "Failed to observe multitouch HID devices; status \(status)")
            return
        }

        self.manager = manager
        DebugLog.info(DebugLog.dock, "Observing multitouch HID device changes")
    }

    func stop() {
        guard let manager else {
            return
        }

        callbackContext.invalidate()
        Self.tearDownManager(manager)
        self.manager = nil
        DebugLog.info(DebugLog.dock, "Stopped observing multitouch HID device changes")
    }

    private func notifyDeviceConfigurationChanged() {
        DebugLog.info(DebugLog.dock, "Multitouch HID device configuration changed")
        onDeviceConfigurationChanged?()
    }

    private static let matchingDictionaries: [[String: Int]] = [
        [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_Digitizer,
            kIOHIDDeviceUsageKey as String: kHIDUsage_Dig_TouchPad,
        ],
    ]

    private static let deviceConfigurationChanged: IOHIDDeviceCallback = { context, result, _, _ in
        guard result == kIOReturnSuccess, let context else {
            return
        }

        let callbackContext = Unmanaged<HIDObserverCallbackContext>
            .fromOpaque(context)
            .takeUnretainedValue()
        Task { @MainActor in
            callbackContext.observerIfValid()?.notifyDeviceConfigurationChanged()
        }
    }
}

// Sendable box around an IOHIDManager so it can be read from a nonisolated
// `deinit`. The contained handle is only mutated from @MainActor (start/stop)
// and torn down on the main run loop, so unchecked Sendability is safe here.
private final class HIDManagerBox: @unchecked Sendable {
    private var stored: IOHIDManager?

    var value: IOHIDManager? {
        get { stored }
        set { stored = newValue }
    }
}

private final class HIDObserverCallbackContext: @unchecked Sendable {
    private let lock = NSLock()
    private weak var observer: HIDMultitouchDeviceObserver?
    private var isValid = true

    func activate(observer: HIDMultitouchDeviceObserver) {
        lock.lock()
        self.observer = observer
        isValid = true
        lock.unlock()
    }

    func invalidate() {
        lock.lock()
        isValid = false
        observer = nil
        lock.unlock()
    }

    func observerIfValid() -> HIDMultitouchDeviceObserver? {
        lock.lock()
        defer { lock.unlock() }
        return isValid ? observer : nil
    }
}
