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

private func midpoint(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
    CGPoint(
        x: (first.x + second.x) / 2,
        y: (first.y + second.y) / 2
    )
}

private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
    hypot(second.x - first.x, second.y - first.y)
}

enum DockGestureEvent: Equatable {
    case swipeLeft(application: InteractionTarget)
    case swipeRight(application: InteractionTarget)
    case swipeDown(application: InteractionTarget)
    case swipeUp(application: InteractionTarget)
    case pinchIn(application: InteractionTarget)
    case pinchOut(application: InteractionTarget)

    var gesture: DockGestureKind {
        switch self {
        case .swipeLeft:
            .swipeLeft
        case .swipeRight:
            .swipeRight
        case .swipeDown:
            .swipeDown
        case .swipeUp:
            .swipeUp
        case .pinchIn:
            .pinchIn
        case .pinchOut:
            .pinchOut
        }
    }

    var application: InteractionTarget {
        switch self {
        case .swipeLeft(let application),
             .swipeRight(let application),
             .swipeDown(let application),
             .swipeUp(let application),
             .pinchIn(let application),
             .pinchOut(let application):
            application
        }
    }
}

/// Recognizes two-finger Dock gestures from raw touch frames and locks the
/// gesture to the app that was hovered when the session began.
struct DockGestureRecognizer {
    private struct Session: Equatable {
        let application: InteractionTarget
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
        hoveredApplication: InteractionTarget?
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

            // Capture the hovered app once so sliding across Dock icons mid-gesture
            // does not retarget the action to a different application.
            self.session = Session(
                application: hoveredApplication,
                startAveragePoint: averagePoint,
                startFingerDistance: currentFingerDistance
            )
            return nil
        }

        guard !session.hasTriggered else {
            return nil
        }

        let deltaX = averagePoint.x - session.startAveragePoint.x
        let deltaY = averagePoint.y - session.startAveragePoint.y
        let translationMagnitude = hypot(deltaX, deltaY)
        let fingerDistanceDelta = currentFingerDistance - session.startFingerDistance

        if
            abs(fingerDistanceDelta) >= pinchThreshold,
            abs(fingerDistanceDelta) >= translationMagnitude * pinchBiasRatio
        {
            if fingerDistanceDelta > 0 {
                return trigger(.pinchOut(application: session.application))
            }
            return trigger(.pinchIn(application: session.application))
        }

        if
            abs(deltaY) >= translationThreshold,
            abs(deltaY) >= abs(deltaX) * directionalBiasRatio
        {
            if deltaY < 0 {
                return trigger(.swipeDown(application: session.application))
            }

            return trigger(.swipeUp(application: session.application))
        }

        guard
            abs(deltaX) >= translationThreshold,
            abs(deltaX) >= abs(deltaY) * directionalBiasRatio
        else {
            return nil
        }

        if deltaX < 0 {
            return trigger(.swipeLeft(application: session.application))
        }

        return trigger(.swipeRight(application: session.application))
    }

    func predictedEvent(
        frame: TrackpadTouchFrame,
        hoveredApplication: InteractionTarget?
    ) -> DockGestureEvent? {
        var recognizer = self
        return recognizer.process(
            frame: frame,
            hoveredApplication: hoveredApplication
        )
    }

    mutating func reset() {
        session = nil
    }

    private mutating func trigger(_ event: DockGestureEvent) -> DockGestureEvent {
        session?.hasTriggered = true
        return event
    }
}

typealias DockSwipeGestureRecognizer = DockGestureRecognizer
typealias DockSwipeEvent = DockGestureEvent

enum TitleBarCornerDragEvent: Equatable {
    case began(
        application: InteractionTarget,
        startAveragePoint: CGPoint,
        currentAveragePoint: CGPoint
    )
    case changed(
        application: InteractionTarget,
        startAveragePoint: CGPoint,
        currentAveragePoint: CGPoint
    )
    case ended(application: InteractionTarget)
}

struct TitleBarCornerDragRecognizer {
    private struct Session: Equatable {
        let application: InteractionTarget
        let startAveragePoint: CGPoint
        let startTimestamp: TimeInterval
        var isActive = false
    }

    // Default used when constructing this recognizer directly (notably in unit
    // tests, whose frame timestamps assume the 1.5s threshold). Production
    // recognizers are always reconfigured from
    // SettingsStore.titleBarCornerDragHoldDuration (default 0.2s) before use
    // via makeConfiguredCornerDragRecognizer/refreshRecognizerConfiguration.
    var holdDurationThreshold: TimeInterval = 1.5
    var stationaryDistanceThreshold: CGFloat = 0.025
    private var session: Session?

    var isActive: Bool {
        session?.isActive ?? false
    }

    var requiresHoveredApplication: Bool {
        session == nil
    }

    mutating func process(
        frame: TrackpadTouchFrame,
        hoveredApplication: InteractionTarget?
    ) -> TitleBarCornerDragEvent? {
        guard frame.touches.count == 2 else {
            defer { session = nil }
            guard let session, session.isActive else {
                return nil
            }

            return .ended(application: session.application)
        }

        let averagePoint = midpoint(frame.touches[0].position, frame.touches[1].position)

        guard var session else {
            guard let hoveredApplication else {
                return nil
            }

            self.session = Session(
                application: hoveredApplication,
                startAveragePoint: averagePoint,
                startTimestamp: frame.timestamp
            )
            return nil
        }

        if session.isActive {
            return .changed(
                application: session.application,
                startAveragePoint: session.startAveragePoint,
                currentAveragePoint: averagePoint
            )
        }

        if frame.timestamp - session.startTimestamp >= holdDurationThreshold {
            session.isActive = true
            self.session = session
            return .began(
                application: session.application,
                startAveragePoint: session.startAveragePoint,
                currentAveragePoint: averagePoint
            )
        }

        let driftDistance = distance(averagePoint, session.startAveragePoint)
        if driftDistance > stationaryDistanceThreshold {
            // Rearm from the new resting point so a user can reposition their fingers
            // and still trigger the hold without lifting both touches first.
            guard let hoveredApplication else {
                self.session = nil
                return nil
            }

            self.session = Session(
                application: hoveredApplication,
                startAveragePoint: averagePoint,
                startTimestamp: frame.timestamp
            )
            return nil
        }
        return nil
    }

    mutating func reset() {
        session = nil
    }
}
