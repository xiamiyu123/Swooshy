import AppKit
import CoreGraphics

enum SmoothDockingAnchor: Equatable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

/// Tracks the minimum and maximum size bounds learned from previous frame writes.
/// Some apps silently clamp AX writes, so the session uses those observations to
/// converge on a frame the app will actually accept.
struct SmoothDockingSizeConstraints: Equatable, Sendable {
    var minimumWidth: CGFloat?
    var maximumWidth: CGFloat?
    var minimumHeight: CGFloat?
    var maximumHeight: CGFloat?

    init(
        minimumWidth: CGFloat? = nil,
        maximumWidth: CGFloat? = nil,
        minimumHeight: CGFloat? = nil,
        maximumHeight: CGFloat? = nil
    ) {
        self.minimumWidth = minimumWidth
        self.maximumWidth = maximumWidth
        self.minimumHeight = minimumHeight
        self.maximumHeight = maximumHeight
    }

    init(sizeBounds: WindowActionPreview.SizeBounds) {
        self.init(
            minimumWidth: sizeBounds.minimumWidth,
            maximumWidth: sizeBounds.maximumWidth,
            minimumHeight: sizeBounds.minimumHeight,
            maximumHeight: sizeBounds.maximumHeight
        )
    }

    func merged(with other: Self) -> Self {
        Self(
            minimumWidth: maxNonNil(minimumWidth, other.minimumWidth),
            maximumWidth: minNonNil(maximumWidth, other.maximumWidth),
            minimumHeight: maxNonNil(minimumHeight, other.minimumHeight),
            maximumHeight: minNonNil(maximumHeight, other.maximumHeight)
        ).normalized()
    }

    mutating func incorporateObservation(
        requestedFrame: CGRect,
        appliedFrame: CGRect,
        tolerance: CGFloat = 0.5
    ) {
        // If the app made the frame larger than requested, we learned a minimum.
        // If it made the frame smaller, we learned a maximum.
        if appliedFrame.width > requestedFrame.width + tolerance {
            minimumWidth = maxNonNil(minimumWidth, appliedFrame.width)
        } else if appliedFrame.width < requestedFrame.width - tolerance {
            maximumWidth = minNonNil(maximumWidth, appliedFrame.width)
        }

        if appliedFrame.height > requestedFrame.height + tolerance {
            minimumHeight = maxNonNil(minimumHeight, appliedFrame.height)
        } else if appliedFrame.height < requestedFrame.height - tolerance {
            maximumHeight = minNonNil(maximumHeight, appliedFrame.height)
        }

        self = normalized()
    }

    func resolvedSize(
        for proposedSize: CGSize,
        within desktopSize: CGSize
    ) -> CGSize {
        CGSize(
            width: resolvedDimension(
                proposedSize.width,
                minimum: minimumWidth,
                maximum: maximumWidth,
                desktopMaximum: desktopSize.width
            ),
            height: resolvedDimension(
                proposedSize.height,
                minimum: minimumHeight,
                maximum: maximumHeight,
                desktopMaximum: desktopSize.height
            )
        )
    }

    private func resolvedDimension(
        _ proposed: CGFloat,
        minimum: CGFloat?,
        maximum: CGFloat?,
        desktopMaximum: CGFloat
    ) -> CGFloat {
        var resolved = proposed
        if let minimum {
            resolved = max(resolved, minimum)
        }
        if let maximum {
            resolved = min(resolved, maximum)
        }
        return min(resolved, desktopMaximum)
    }

    private func normalized() -> Self {
        let widthBounds = normalizedBounds(minimum: minimumWidth, maximum: maximumWidth)
        let heightBounds = normalizedBounds(minimum: minimumHeight, maximum: maximumHeight)

        return Self(
            minimumWidth: widthBounds.minimum,
            maximumWidth: widthBounds.maximum,
            minimumHeight: heightBounds.minimum,
            maximumHeight: heightBounds.maximum
        )
    }

    private func normalizedBounds(
        minimum: CGFloat?,
        maximum: CGFloat?
    ) -> (minimum: CGFloat?, maximum: CGFloat?) {
        guard
            let minimum,
            let maximum,
            minimum > maximum
        else {
            return (minimum, maximum)
        }

        let lockedValue = max(minimum, maximum)
        return (lockedValue, lockedValue)
    }

    private func maxNonNil(_ lhs: CGFloat?, _ rhs: CGFloat?) -> CGFloat? {
        mergeNonNil(lhs, rhs, combine: max)
    }

    private func minNonNil(_ lhs: CGFloat?, _ rhs: CGFloat?) -> CGFloat? {
        mergeNonNil(lhs, rhs, combine: min)
    }

    private func mergeNonNil(
        _ lhs: CGFloat?,
        _ rhs: CGFloat?,
        combine: (CGFloat, CGFloat) -> CGFloat
    ) -> CGFloat? {
        if let lhs, let rhs {
            return combine(lhs, rhs)
        }

        return lhs ?? rhs
    }
}

struct SmoothDockingPlan: Equatable, Sendable {
    let action: WindowAction
    let desktopFrame: CGRect
    let idealFrame: CGRect
    let frame: CGRect
    let anchor: SmoothDockingAnchor
}

/// Resolves the ideal desktop region for a snap action before app-specific size
/// constraints are applied.
struct SmoothDockingResolver {
    private let layoutEngine = WindowLayoutEngine()

    func desktopFrame(
        preferredPoint: CGPoint?,
        currentWindowFrame: CGRect,
        screens: [NSScreen]
    ) -> CGRect? {
        let desktopFrames = screens.map(\.visibleFrame).filter { !$0.isEmpty }
        guard !desktopFrames.isEmpty else {
            return nil
        }

        return layoutEngine.resolvedVisibleFrame(
            preferredPoint: preferredPoint,
            currentWindowFrame: currentWindowFrame,
            screenFrames: desktopFrames
        )?.integral
    }

    func plan(
        for action: WindowAction,
        in desktopFrame: CGRect,
        sizeConstraints: SmoothDockingSizeConstraints
    ) -> SmoothDockingPlan {
        let normalizedDesktopFrame = desktopFrame.integral
        let idealFrame = layoutEngine.targetFrame(
            for: action,
            currentWindowFrame: normalizedDesktopFrame,
            currentVisibleFrame: normalizedDesktopFrame
        )
        let resolvedSize = sizeConstraints.resolvedSize(
            for: idealFrame.size,
            within: normalizedDesktopFrame.size
        )
        let anchor = anchor(for: action)
        let resolvedFrame = anchoredFrame(
            in: normalizedDesktopFrame,
            size: resolvedSize,
            anchor: anchor
        )

        return SmoothDockingPlan(
            action: action,
            desktopFrame: normalizedDesktopFrame,
            idealFrame: idealFrame,
            frame: resolvedFrame,
            anchor: anchor
        )
    }

    private func anchor(for action: WindowAction) -> SmoothDockingAnchor {
        switch action {
        case .leftHalf, .topLeftQuarter, .maximize, .center:
            return .topLeading
        case .rightHalf, .topRightQuarter:
            return .topTrailing
        case .bottomLeftQuarter:
            return .bottomLeading
        case .bottomRightQuarter:
            return .bottomTrailing
        case .minimize,
             .closeWindow,
             .closeTab,
             .quitApplication,
             .cycleSameAppWindowsForward,
             .cycleSameAppWindowsBackward,
             .toggleFullScreen,
             .exitFullScreen,
             .moveToNextDisplay,
             .moveToPreviousDisplay:
            return .topLeading
        }
    }

    private func anchoredFrame(
        in desktopFrame: CGRect,
        size: CGSize,
        anchor: SmoothDockingAnchor
    ) -> CGRect {
        let originX = anchor.isLeading ? desktopFrame.minX : desktopFrame.maxX - size.width
        let originY = anchor.isBottom ? desktopFrame.minY : desktopFrame.maxY - size.height

        return CGRect(
            x: originX,
            y: originY,
            width: size.width,
            height: size.height
        ).integral
    }

}

private extension SmoothDockingAnchor {
    var isLeading: Bool {
        self == .topLeading || self == .bottomLeading
    }

    var isBottom: Bool {
        self == .bottomLeading || self == .bottomTrailing
    }
}

@MainActor
final class SmoothDockingSession {
    private struct Result {
        let requested: CGRect
        let applied: CGRect
    }

    private let diagnosticContext: String
    private let originalFrame: CGRect
    private let desktopFrame: CGRect
    private let baseSizeConstraints: SmoothDockingSizeConstraints
    private let observedSizeConstraints: SmoothDockingSizeConstraints
    private let loadCurrentFrame: () -> CGRect?
    private let animateFrame: ((CGRect) throws -> Void)?
    private let animationSleep: () async throws -> Void
    private let applyFrame: (CGRect) async throws -> CGRect
    private let recordConstraintObservation: @MainActor (WindowAction, CGRect, CGRect) -> Void
    private let recordAcceptedFrame: @MainActor (CGRect) -> Void
    private let resolver = SmoothDockingResolver()
    private var adaptiveSizeConstraints = SmoothDockingSizeConstraints()
    private var currentAction: WindowAction?
    private var operation: Task<Result, Error>?
    private var generation: UInt64 = 0
    private var committedGeneration: UInt64?
    private(set) var isFinished = false

    init(
        originalFrame: CGRect,
        desktopFrame: CGRect,
        baseSizeConstraints: SmoothDockingSizeConstraints,
        observedSizeConstraints: SmoothDockingSizeConstraints = .init(),
        loadCurrentFrame: @escaping () -> CGRect? = { nil },
        animateFrame: ((CGRect) throws -> Void)? = nil,
        animationSleep: @escaping () async throws -> Void = { try await Task.sleep(for: .milliseconds(16)) },
        applyFrame: @escaping (CGRect) async throws -> CGRect,
        recordConstraintObservation: @escaping @MainActor (WindowAction, CGRect, CGRect) -> Void = { _, _, _ in },
        recordAcceptedFrame: @escaping @MainActor (CGRect) -> Void = { _ in },
        diagnosticContext: String = UUID().uuidString
    ) {
        self.diagnosticContext = diagnosticContext
        self.originalFrame = originalFrame.integral
        self.desktopFrame = desktopFrame.integral
        self.baseSizeConstraints = baseSizeConstraints
        self.observedSizeConstraints = observedSizeConstraints
        self.loadCurrentFrame = loadCurrentFrame
        self.animateFrame = animateFrame
        self.animationSleep = animationSleep
        self.applyFrame = applyFrame
        self.recordConstraintObservation = recordConstraintObservation
        self.recordAcceptedFrame = recordAcceptedFrame
    }

    deinit { operation?.cancel() }

    func update(action: WindowAction?) {
        guard !isFinished, operation == nil || action != currentAction else { return }
        operation?.cancel()
        generation &+= 1
        let generation = generation
        currentAction = action
        let bounds = baseSizeConstraints.merged(with: observedSizeConstraints)
        let requested = target(for: action, constraints: bounds)
        let resolved = target(for: action, constraints: bounds.merged(with: adaptiveSizeConstraints))
        let frames = animateFrame == nil ? [] : transitionFrames(
            from: loadCurrentFrame() ?? originalFrame, to: resolved
        )
        DebugLog.debug(
            DebugLog.windows,
            "Docking [\(diagnosticContext)] target: action=\(String(describing: action)), requested=\(NSStringFromRect(requested)), resolved=\(NSStringFromRect(resolved))"
        )
        operation = Task { @MainActor in
            do {
                if let animateFrame = self.animateFrame {
                    for frame in frames {
                        try Task.checkCancellation()
                        try animateFrame(frame)
                        try await self.animationSleep()
                    }
                }
                let applied = try await self.settle(at: resolved, action: action, constraints: bounds)
                try Task.checkCancellation()
                guard self.generation == generation else { throw CancellationError() }
                self.adaptiveSizeConstraints.incorporateObservation(
                    requestedFrame: requested, appliedFrame: applied, tolerance: 1
                )
                DebugLog.debug(
                    DebugLog.windows,
                    "Docking [\(self.diagnosticContext)] settled: requested=\(NSStringFromRect(resolved)), applied=\(NSStringFromRect(applied))"
                )
                return Result(requested: requested, applied: applied)
            } catch {
                if !(error is CancellationError) {
                    DebugLog.debug(DebugLog.windows, "Docking [\(self.diagnosticContext)] failed: \(error.localizedDescription)")
                }
                throw error
            }
        }
    }

    func restore() { update(action: nil) }

    func commit() async throws -> CGRect {
        guard !isFinished else { throw CancellationError() }
        guard let operation else { return originalFrame }
        let generation = generation
        let result = try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
        try Task.checkCancellation()
        guard !isFinished, self.generation == generation else { throw CancellationError() }
        if committedGeneration != generation {
            recordAcceptedFrame(result.applied)
            if let currentAction,
               abs(result.requested.width - result.applied.width) > 1 ||
               abs(result.requested.height - result.applied.height) > 1 {
                recordConstraintObservation(currentAction, result.requested, result.applied)
            }
            committedGeneration = generation
        }
        return result.applied
    }

    func finish() {
        operation?.cancel()
        operation = nil
        generation &+= 1
        isFinished = true
    }

    private func settle(
        at frame: CGRect, action: WindowAction?, constraints: SmoothDockingSizeConstraints
    ) async throws -> CGRect {
        var requested = frame
        var confirmedBounds = constraints.merged(with: adaptiveSizeConstraints)
        for _ in 0..<3 {
            try Task.checkCancellation()
            let applied = try await applyFrame(requested).integral
            try Task.checkCancellation()
            if framesAreClose(applied, requested) { return applied }
            guard let action else { throw WindowManagerError.unableToSetFrame }
            confirmedBounds.incorporateObservation(requestedFrame: requested, appliedFrame: applied, tolerance: 1)
            requested = target(for: action, constraints: confirmedBounds)
        }
        throw WindowManagerError.unableToSetFrame
    }

    private func target(for action: WindowAction?, constraints: SmoothDockingSizeConstraints) -> CGRect {
        guard let action else { return originalFrame }
        return resolver.plan(for: action, in: desktopFrame, sizeConstraints: constraints).frame
    }

    private func transitionFrames(from start: CGRect, to target: CGRect) -> [CGRect] {
        guard !framesAreClose(start, target) else { return [] }
        var previous = start.integral
        // Build one finite transition per target; intermediate writes never
        // resolve the layout again or teach size constraints.
        return (1...15).compactMap { step in
            let progress = CGFloat(step) / 15
            let eased = 1 - pow(1 - progress, 3)
            let frame = CGRect(
                x: (start.minX + (target.minX - start.minX) * eased).rounded(),
                y: (start.minY + (target.minY - start.minY) * eased).rounded(),
                width: (start.width + (target.width - start.width) * eased).rounded(),
                height: (start.height + (target.height - start.height) * eased).rounded()
            )
            guard frame != previous else { return nil }
            previous = frame
            return frame
        }
    }

    private func framesAreClose(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 1 && abs(lhs.minY - rhs.minY) <= 1 &&
            abs(lhs.width - rhs.width) <= 1 && abs(lhs.height - rhs.height) <= 1
    }
}

extension WindowAction {
    var supportsSmoothDocking: Bool {
        supportsSnapPreview
    }
}
