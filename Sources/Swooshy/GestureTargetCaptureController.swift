import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class GestureTargetCaptureController {
    @ObservationIgnored
    private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored
    var onStateChanged: (() -> Void)?

    private(set) var isCapturing = false
    var capturedApplication: GestureExcludedApplication?
    var didTimeout = false
    var didMiss = false

    func start(timeout: Duration = .seconds(10)) {
        timeoutTask?.cancel()
        capturedApplication = nil
        didTimeout = false
        didMiss = false
        isCapturing = true
        onStateChanged?()

        timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }

            guard let self, self.isCapturing else { return }
            self.isCapturing = false
            self.didTimeout = true
            self.onStateChanged?()
        }
    }

    func cancel() {
        guard isCapturing else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        isCapturing = false
        onStateChanged?()
    }

    func complete(with application: GestureExcludedApplication) {
        guard isCapturing else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        capturedApplication = application
        isCapturing = false
        onStateChanged?()
    }

    func miss() {
        guard isCapturing else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        didMiss = true
        isCapturing = false
        onStateChanged?()
    }

    func clearResult() {
        capturedApplication = nil
        didTimeout = false
        didMiss = false
    }
}

struct GestureTargetCaptureRecognizer {
    var pinchThreshold: CGFloat = 0.08
    private var startFingerDistance: CGFloat?
    private var hasTriggered = false

    mutating func process(frame: TrackpadTouchFrame) -> DockGestureKind? {
        guard frame.touches.count == 2 else {
            reset()
            return nil
        }

        let fingerDistance = distance(frame.touches[0].position, frame.touches[1].position)

        guard let startFingerDistance else {
            self.startFingerDistance = fingerDistance
            return nil
        }

        guard !hasTriggered else {
            return nil
        }

        let delta = fingerDistance - startFingerDistance
        guard abs(delta) >= pinchThreshold else {
            return nil
        }

        hasTriggered = true
        return delta > 0 ? .pinchOut : .pinchIn
    }

    mutating func reset() {
        startFingerDistance = nil
        hasTriggered = false
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(second.x - first.x, second.y - first.y)
    }
}
