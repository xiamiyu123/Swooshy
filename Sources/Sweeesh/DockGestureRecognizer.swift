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

enum DockSwipeEvent: Equatable {
    case minimize(application: DockApplicationTarget)
    case restore(application: DockApplicationTarget)
}

struct DockSwipeGestureRecognizer {
    private struct Session: Equatable {
        let application: DockApplicationTarget
        let startAveragePoint: CGPoint
        var hasTriggered = false
    }

    private let verticalThreshold: CGFloat = 0.09
    private let verticalBiasRatio: CGFloat = 1.35
    private var session: Session?

    mutating func process(
        frame: TrackpadTouchFrame,
        hoveredApplication: DockApplicationTarget?
    ) -> DockSwipeEvent? {
        guard frame.touches.count == 2 else {
            session = nil
            return nil
        }

        let averagePoint = CGPoint(
            x: frame.touches.map(\.position.x).reduce(0, +) / 2,
            y: frame.touches.map(\.position.y).reduce(0, +) / 2
        )

        guard let session else {
            guard let hoveredApplication else {
                return nil
            }

            self.session = Session(
                application: hoveredApplication,
                startAveragePoint: averagePoint
            )
            return nil
        }

        guard session.hasTriggered == false else {
            return nil
        }

        let deltaX = averagePoint.x - session.startAveragePoint.x
        let deltaY = averagePoint.y - session.startAveragePoint.y

        guard abs(deltaY) >= verticalThreshold else {
            return nil
        }

        guard abs(deltaY) >= abs(deltaX) * verticalBiasRatio else {
            return nil
        }

        self.session?.hasTriggered = true

        if deltaY < 0 {
            return .minimize(application: session.application)
        }

        return .restore(application: session.application)
    }
}
