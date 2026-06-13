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

    private var manager: IOHIDManager?

    deinit {
        // deinit is not guaranteed to run on the main thread; assumeIsolated
        // would crash there. The restart coordinator calls stop() explicitly,
        // so this is only a best-effort fallback on the main thread.
        guard Thread.isMainThread else {
            assertionFailure("HIDMultitouchDeviceObserver deallocated off the main thread without stop()")
            return
        }

        MainActor.assumeIsolated {
            stop()
        }
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

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceConfigurationChanged, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceConfigurationChanged, context)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )

        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else {
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

        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
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

        let observer = Unmanaged<HIDMultitouchDeviceObserver>
            .fromOpaque(context)
            .takeUnretainedValue()
        Task { @MainActor [weak observer] in
            observer?.notifyDeviceConfigurationChanged()
        }
    }
}
