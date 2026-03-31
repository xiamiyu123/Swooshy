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
    case swipeLeft(application: DockApplicationTarget)
    case swipeRight(application: DockApplicationTarget)
    case swipeDown(application: DockApplicationTarget)
    case swipeUp(application: DockApplicationTarget)
    case pinchIn(application: DockApplicationTarget)

    var gesture: DockGestureKind {
        switch self {
        case .swipeLeft:
            return .swipeLeft
        case .swipeRight:
            return .swipeRight
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
        case .swipeLeft(let application),
             .swipeRight(let application),
             .swipeDown(let application),
             .swipeUp(let application),
             .pinchIn(let application):
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

    var translationThreshold: CGFloat = 0.09
    private let directionalBiasRatio: CGFloat = 1.35
    var pinchThreshold: CGFloat = 0.08
    private let pinchBiasRatio: CGFloat = 1.15
    private var session: Session?

    var requiresHoveredApplication: Bool {
        session == nil
    }

    mutating func process(
        frame: TrackpadTouchFrame,
        hoveredApplication: DockApplicationTarget?
    ) -> DockGestureEvent? {
        guard frame.touches.count == 2 else {
            session = nil
            return nil
        }

        let firstTouchPoint = frame.touches[0].position
        let secondTouchPoint = frame.touches[1].position
        let averagePoint = midpoint(firstTouchPoint, secondTouchPoint)
        let currentFingerDistance = distance(firstTouchPoint, secondTouchPoint)

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

        if
            abs(deltaY) >= translationThreshold,
            abs(deltaY) >= abs(deltaX) * directionalBiasRatio
        {
            self.session?.hasTriggered = true

            if deltaY < 0 {
                return .swipeDown(application: session.application)
            }

            return .swipeUp(application: session.application)
        }

        guard abs(deltaX) >= translationThreshold else {
            return nil
        }

        guard abs(deltaX) >= abs(deltaY) * directionalBiasRatio else {
            return nil
        }

        self.session?.hasTriggered = true

        if deltaX < 0 {
            return .swipeLeft(application: session.application)
        }

        return .swipeRight(application: session.application)
    }

    private func midpoint(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
        CGPoint(
            x: (first.x + second.x) / 2,
            y: (first.y + second.y) / 2
        )
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        let dx = second.x - first.x
        let dy = second.y - first.y
        return hypot(dx, dy)
    }
}

typealias DockSwipeGestureRecognizer = DockGestureRecognizer
typealias DockSwipeEvent = DockGestureEvent
