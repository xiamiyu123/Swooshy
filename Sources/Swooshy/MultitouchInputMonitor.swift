import CMultitouchShim
import CoreGraphics
import Foundation

protocol MultitouchMonitoring: AnyObject {
    var onFrame: ((TrackpadTouchFrame) -> Void)? { get set }
    var isMonitoringActive: Bool { get }

    func startIfAvailable()
    func stop()
}

final class MultitouchInputMonitor: MultitouchMonitoring, @unchecked Sendable {
    // `onFrame` and `isMonitoring` are guarded by `stateLock` because the C
    // multitouch callback runs on a private MultitouchSupport thread and the
    // rest of the API is driven from `@MainActor`.
    var onFrame: ((TrackpadTouchFrame) -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return onFrameHandler
        }
        set {
            stateLock.lock()
            onFrameHandler = newValue
            stateLock.unlock()
        }
    }

    private let frameDeliveryCoalescer = FrameDeliveryCoalescer()
    private let scheduleDrain: (@escaping @MainActor () -> Void) -> Void
    private let startMonitoring: (UnsafeMutableRawPointer) -> Bool
    private let stopMonitoring: () -> Void
    private let stateLock = NSLock()
    private var isMonitoring = false
    private var onFrameHandler: ((TrackpadTouchFrame) -> Void)?

    init(
        scheduleDrain: @escaping (@escaping @MainActor () -> Void) -> Void = { operation in
            Task { @MainActor in
                operation()
            }
        },
        startMonitoring: @escaping (UnsafeMutableRawPointer) -> Bool = { context in
            SwooshyMTStartMonitoring(multitouchCallback, context)
        },
        stopMonitoring: @escaping () -> Void = {
            SwooshyMTStopMonitoring()
        }
    ) {
        self.scheduleDrain = scheduleDrain
        self.startMonitoring = startMonitoring
        self.stopMonitoring = stopMonitoring
    }

    deinit {
        if !Thread.isMainThread {
            assertionFailure("MultitouchInputMonitor deallocated off the main thread without stop()")
        }
        if isMonitoringActive {
            stop()
        }
    }

    var isMonitoringActive: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isMonitoring
    }

    func startIfAvailable() {
        stateLock.lock()
        guard !isMonitoring else {
            stateLock.unlock()
            return
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let didStart = startMonitoring(context)
        isMonitoring = didStart
        frameDeliveryCoalescer.reset()
        if !didStart {
            stopMonitoring()
        }
        stateLock.unlock()

        if didStart {
            DebugLog.info(DebugLog.dock, "MultitouchSupport monitoring active")
        } else {
            DebugLog.error(DebugLog.dock, "MultitouchSupport monitoring unavailable")
        }
    }

    func stop() {
        stateLock.lock()
        let wasMonitoring = isMonitoring
        isMonitoring = false
        // Reset the coalescer so any drain scheduled before this point becomes a
        // no-op (it finds an empty queue). The frame handler is intentionally
        // left intact: `stop()` is reused by restart paths (workspace wake,
        // device change, watchdog recovery) that immediately call
        // `startIfAvailable()` again, and clearing the handler here would leave
        // monitoring "active" but silently dropping every frame until the next
        // process launch. The handler's lifetime is owned by the controller,
        // which nils it in `shutdown()` before the final `stop()`.
        frameDeliveryCoalescer.reset()
        if wasMonitoring {
            stopMonitoring()
        }
        stateLock.unlock()

        DebugLog.info(DebugLog.dock, "MultitouchSupport monitoring stopped")
    }

    func receiveCallbackPayload(
        fingers: UnsafePointer<SwooshyMTFinger>?,
        fingerCount: Int,
        timestamp: Double
    ) {
        guard fingerCount > 0 else {
            deliverZeroTouchFrame(timestamp: timestamp)
            return
        }

        guard let fingers else {
            DebugLog.error(
                DebugLog.dock,
                "Multitouch callback dropped a non-zero finger payload because the finger buffer was nil"
            )
            return
        }

        receive(
            fingers: fingers,
            fingerCount: fingerCount,
            timestamp: timestamp
        )
    }

    fileprivate func receive(
        fingers: UnsafePointer<SwooshyMTFinger>,
        fingerCount: Int,
        timestamp: Double
    ) {
        let buffer = UnsafeBufferPointer(start: fingers, count: fingerCount)
        let touches = buffer.map {
            TrackpadTouchSample(
                identifier: Int($0.identifier),
                position: CGPoint(
                    x: CGFloat($0.normalized.position.x),
                    y: CGFloat($0.normalized.position.y)
                )
            )
        }

        enqueueForDelivery(
            TrackpadTouchFrame(
                touches: touches,
                timestamp: timestamp
            )
        )
    }

    private func deliverZeroTouchFrame(timestamp: Double) {
        enqueueForDelivery(
            TrackpadTouchFrame(
                touches: [],
                timestamp: timestamp
            )
        )
    }

    private func enqueueForDelivery(_ frame: TrackpadTouchFrame) {
        guard frameDeliveryCoalescer.enqueue(frame) == .scheduleDrain else {
            return
        }

        scheduleDrain { [weak self] in
            self?.drainPendingFrames()
        }
    }

    @MainActor
    private func drainPendingFrames() {
        // Snapshot the handler and monitoring flag under the lock. Gating on
        // `isMonitoring` means an in-flight callback that lands after `stop()`
        // (the C callback runs on a private MultitouchSupport thread) drains to
        // nothing, while a restart (`stop()` → `startIfAvailable()`) restores
        // delivery without the controller having to re-assign `onFrame`. The
        // handler snapshot also guards against the controller niling `onFrame`
        // during `shutdown()` mid-drain.
        stateLock.lock()
        let handler = isMonitoring ? onFrameHandler : nil
        stateLock.unlock()

        while let frame = frameDeliveryCoalescer.nextFrameForDrain() {
            handler?(frame)
        }
    }
}

private final class FrameDeliveryCoalescer {
    enum EnqueueResult {
        case ignored
        case queued
        case scheduleDrain
    }

    private let lock = NSLock()
    private var queuedFrames: [TrackpadTouchFrame] = []
    private var drainScheduled = false
    private var lastQueuedFingerCount = -1

    func enqueue(_ frame: TrackpadTouchFrame) -> EnqueueResult {
        lock.lock()
        defer { lock.unlock() }

        if frame.touches.isEmpty, lastQueuedFingerCount == 0 {
            return .ignored
        }

        lastQueuedFingerCount = frame.touches.count
        if
            let lastIndex = queuedFrames.indices.last,
            sameCoalescingBucket(lhs: queuedFrames[lastIndex], rhs: frame)
        {
            queuedFrames[lastIndex] = frame
        } else {
            queuedFrames.append(frame)
        }

        guard !drainScheduled else {
            return .queued
        }

        drainScheduled = true
        return .scheduleDrain
    }

    func nextFrameForDrain() -> TrackpadTouchFrame? {
        lock.lock()
        defer { lock.unlock() }

        if !queuedFrames.isEmpty {
            return queuedFrames.removeFirst()
        }

        drainScheduled = false
        return nil
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        queuedFrames = []
        drainScheduled = false
        lastQueuedFingerCount = -1
    }

    private func sameCoalescingBucket(
        lhs: TrackpadTouchFrame,
        rhs: TrackpadTouchFrame
    ) -> Bool {
        coalescingBucket(for: lhs) == coalescingBucket(for: rhs)
    }

    private func coalescingBucket(for frame: TrackpadTouchFrame) -> Int {
        frame.touches.count
    }
}

private func multitouchCallback(
    _ device: Int32,
    _ data: UnsafePointer<SwooshyMTFinger>?,
    _ fingerCount: Int32,
    _ timestamp: Double,
    _ frame: Int32,
    _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let monitor = Unmanaged<MultitouchInputMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.receiveCallbackPayload(
        fingers: data,
        fingerCount: Int(fingerCount),
        timestamp: timestamp
    )
}
