import CoreGraphics
import Foundation

/// Writes each AX attribute only after the preceding change has settled.
@MainActor
struct WindowFrameSettler {
    private enum Component {
        case position, size, frame

        func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
            switch self {
            case .position:
                abs(lhs.minX - rhs.minX) <= 1 && abs(lhs.minY - rhs.minY) <= 1
            case .size:
                abs(lhs.width - rhs.width) <= 1 && abs(lhs.height - rhs.height) <= 1
            case .frame:
                Self.position.matches(lhs, rhs) && Self.size.matches(lhs, rhs)
            }
        }
    }

    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var sleep: (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }

    func apply(
        _ target: CGRect,
        writePosition: (CGPoint) throws -> Void,
        writeSize: ((CGSize) throws -> Void)?,
        read: () -> CGRect?,
        readPresentedFrame: (() -> CGRect?)? = nil
    ) async throws -> CGRect {
        try Task.checkCancellation()
        guard var actual = read() else { throw WindowManagerError.unableToSetFrame }
        let expanding = target.width > actual.width + 1 || target.height > actual.height + 1
        if expanding, !Component.position.matches(actual, target) {
            try writePosition(target.origin)
            actual = try await observe(target, component: .position, read: read, presented: readPresentedFrame)
        }

        if !Component.size.matches(actual, target) {
            guard let writeSize else { throw WindowManagerError.unableToSetFrame }
            var candidate: CGRect?
            var confirmed = false
            for _ in 0..<2 {
                try Task.checkCancellation()
                try writeSize(target.size)
                actual = try await observe(target, component: .size, read: read, presented: readPresentedFrame)
                if Component.size.matches(actual, target) { confirmed = true; break }
                if let candidate, Component.size.matches(actual, candidate) { confirmed = true; break }
                candidate = actual
            }
            guard confirmed else { throw WindowManagerError.unableToSetFrame }
            // The caller re-anchors a confirmed constrained size once.
            if !Component.size.matches(actual, target) { return actual }
        }
        if !Component.position.matches(actual, target) {
            try Task.checkCancellation()
            try writePosition(target.origin)
            actual = try await observe(target, component: .position, read: read, presented: readPresentedFrame)
        }
        return try await observe(target, component: .frame, read: read, presented: readPresentedFrame)
    }

    private func observe(
        _ target: CGRect, component: Component,
        read: () -> CGRect?, presented: (() -> CGRect?)?
    ) async throws -> CGRect {
        let startedAt = now()
        var previous: CGRect?
        for offset in [0.0, 0.016, 0.05, 0.1, 0.2, 0.35, 0.5] {
            if offset > 0, now() > startedAt + 0.5 { break }
            let delay = startedAt + offset - now()
            if delay > 0 { try await sleep(delay) }
            try Task.checkCancellation()
            guard let actual = read() else { previous = nil; continue }
            let stable = previous.map { component.matches($0, actual) } ?? false
            let agrees: Bool
            if let presented {
                agrees = presented().map { component.matches($0, actual) } ?? false
            } else {
                agrees = stable && offset > 0
            }
            if agrees, component.matches(actual, target) { return actual }
            if component == .size, offset >= 0.2, stable, agrees {
                DebugLog.debug(
                    DebugLog.windows,
                    "AX size confirmation: requested=\(NSStringFromSize(target.size)), stable=\(NSStringFromSize(actual.size))"
                )
                return actual
            }
            previous = actual
        }
        throw WindowManagerError.unableToSetFrame
    }
}
