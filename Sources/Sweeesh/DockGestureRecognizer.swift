import CoreGraphics
import Foundation

struct TrackpadTouchSample: Equatable {
    let identifier: Int
    let position: CGPoint
}

struct TrackpadTouchFrame: Equatable {
    let touches: [TrackpadTouchSample]
    let timestamp: TimeInterval
}

struct DockApplicationTarget: Equatable {
    let dockItemName: String
    let resolvedApplicationName: String
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let aliases: [String]

    var logDescription: String {
        if let bundleIdentifier, bundleIdentifier.isEmpty == false {
            return "\(resolvedApplicationName) [\(bundleIdentifier)]"
        }

        return resolvedApplicationName
    }
}

enum DockGestureEvent: Equatable {
    case swipeDown(application: DockApplicationTarget)
    case swipeUp(application: DockApplicationTarget)
    case pinchIn(application: DockApplicationTarget)

    var gesture: DockGestureKind {
        switch self {
        case .swipeDown:
            return .swipeDown
        case .swipeUp:
            return .swipeUp
        case .pinchIn:
            return .pinchIn
        }
    }

    var application: DockApplicationTarget {
        switch self {
        case .swipeDown(let application), .swipeUp(let application), .pinchIn(let application):
            return application
        }
    }
}

struct DockGestureRecognizer {
    private struct Session: Equatable {
        let application: DockApplicationTarget
        let startAveragePoint: CGPoint
        let startFingerDistance: CGFloat
        var hasTriggered = false
    }

    private let verticalThreshold: CGFloat = 0.09
    private let verticalBiasRatio: CGFloat = 1.35
    private let pinchThreshold: CGFloat = 0.08
    private let pinchBiasRatio: CGFloat = 1.15
    private var session: Session?

    mutating func process(
        frame: TrackpadTouchFrame,
        hoveredApplication: DockApplicationTarget?
    ) -> DockGestureEvent? {
        guard frame.touches.count == 2 else {
            session = nil
            return nil
        }

        let averagePoint = averagePoint(for: frame.touches)
        let currentFingerDistance = fingerDistance(for: frame.touches)

        guard let session else {
            guard let hoveredApplication else {
                return nil
            }

            self.session = Session(
                application: hoveredApplication,
                startAveragePoint: averagePoint,
                startFingerDistance: currentFingerDistance
            )
            return nil
        }

        guard session.hasTriggered == false else {
            return nil
        }

        let deltaX = averagePoint.x - session.startAveragePoint.x
        let deltaY = averagePoint.y - session.startAveragePoint.y
        let translationMagnitude = hypot(deltaX, deltaY)
        let fingerDistanceDelta = currentFingerDistance - session.startFingerDistance

        if
            fingerDistanceDelta <= -pinchThreshold,
            abs(fingerDistanceDelta) >= translationMagnitude * pinchBiasRatio
        {
            self.session?.hasTriggered = true
            return .pinchIn(application: session.application)
        }

        guard abs(deltaY) >= verticalThreshold else {
            return nil
        }

        guard abs(deltaY) >= abs(deltaX) * verticalBiasRatio else {
            return nil
        }

        self.session?.hasTriggered = true

        if deltaY < 0 {
            return .swipeDown(application: session.application)
        }

        return .swipeUp(application: session.application)
    }

    private func averagePoint(for touches: [TrackpadTouchSample]) -> CGPoint {
        guard let firstTouch = touches.first else {
            return .zero
        }

        if touches.count == 2 {
            let secondTouch = touches[1]
            return CGPoint(
                x: (firstTouch.position.x + secondTouch.position.x) / 2,
                y: (firstTouch.position.y + secondTouch.position.y) / 2
            )
        }

        var totalX = firstTouch.position.x
        var totalY = firstTouch.position.y

        for touch in touches.dropFirst() {
            totalX += touch.position.x
            totalY += touch.position.y
        }

        return CGPoint(
            x: totalX / CGFloat(touches.count),
            y: totalY / CGFloat(touches.count)
        )
    }

    private func fingerDistance(for touches: [TrackpadTouchSample]) -> CGFloat {
        guard touches.count == 2 else {
            return 0
        }

        let first = touches[0].position
        let second = touches[1].position
        let dx = second.x - first.x
        let dy = second.y - first.y
        return hypot(dx, dy)
    }
}

typealias DockSwipeGestureRecognizer = DockGestureRecognizer
typealias DockSwipeEvent = DockGestureEvent
