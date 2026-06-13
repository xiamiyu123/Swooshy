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
    private let originalFrame: CGRect
    private let desktopFrame: CGRect
    private let baseSizeConstraints: SmoothDockingSizeConstraints
    private let loadCurrentFrame: () -> CGRect?
    private let applyFrame: (CGRect) throws -> CGRect
    private let recordConstraintObservation: @MainActor (WindowAction, CGRect, CGRect) -> Void
    private let animationStepDuration: UInt64
    private let animationFactor: CGFloat
    private let snapThreshold: CGFloat
    private let resolver = SmoothDockingResolver()

    private var adaptiveSizeConstraints = SmoothDockingSizeConstraints()
    private var currentAction: WindowAction?
    private var currentTargetFrame: CGRect?
    private var animationTask: Task<Void, Never>?

    init(
        originalFrame: CGRect,
        desktopFrame: CGRect,
        baseSizeConstraints: SmoothDockingSizeConstraints,
        loadCurrentFrame: @escaping () -> CGRect?,
        applyFrame: @escaping (CGRect) throws -> CGRect,
        recordConstraintObservation: @escaping @MainActor (WindowAction, CGRect, CGRect) -> Void = { _, _, _ in },
        animationStepDuration: UInt64 = 16_000_000,
        animationFactor: CGFloat = 0.32,
        snapThreshold: CGFloat = 0.5
    ) {
        self.originalFrame = originalFrame.integral
        self.desktopFrame = desktopFrame.integral
        self.baseSizeConstraints = baseSizeConstraints
        self.loadCurrentFrame = loadCurrentFrame
        self.applyFrame = applyFrame
        self.recordConstraintObservation = recordConstraintObservation
        self.animationStepDuration = animationStepDuration
        self.animationFactor = animationFactor
        self.snapThreshold = snapThreshold
    }

    deinit {
        animationTask?.cancel()
    }

    func update(action: WindowAction?) {
        let nextTargetFrame = resolvedTargetFrame(for: action)
        let targetChanged = currentAction != action || currentTargetFrame != nextTargetFrame
        currentAction = action
        currentTargetFrame = nextTargetFrame

        guard targetChanged else {
            return
        }

        startAnimationLoopIfNeeded()
    }

    func restore() {
        update(action: nil)
    }

    func commit() throws -> CGRect {
        animationTask?.cancel()
        animationTask = nil

        guard let targetFrame = currentTargetFrame else {
            return originalFrame
        }

        let appliedFrame = try settle(at: targetFrame, maxIterations: 4)
        currentTargetFrame = appliedFrame.integral
        return appliedFrame
    }

    func finish() {
        animationTask?.cancel()
        animationTask = nil
        currentTargetFrame = nil
        currentAction = nil
    }

    private func startAnimationLoopIfNeeded() {
        guard animationTask == nil, let targetFrame = currentTargetFrame else {
            return
        }

        let currentFrame = loadCurrentFrame() ?? originalFrame
        guard !framesAreClose(currentFrame, targetFrame, tolerance: snapThreshold) else {
            return
        }

        animationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var previousFrame = currentFrame

            while !Task.isCancelled {
                guard let targetFrame = self.currentTargetFrame else {
                    break
                }

                let currentFrame = self.loadCurrentFrame() ?? previousFrame
                if self.framesAreClose(currentFrame, targetFrame, tolerance: self.snapThreshold) {
                    if currentFrame.integral != targetFrame {
                        do {
                            previousFrame = try self.applyAndObserve(targetFrame)
                        } catch {
                            DebugLog.debug(
                                DebugLog.windows,
                                "Smooth docking snap failed: \(error.localizedDescription)"
                            )
                        }
                    }
                    break
                }

                // Move part of the remaining distance each tick so the preview stays
                // responsive even when the target keeps shifting after new observations.
                let interpolatedFrame = CGRect(
                    x: currentFrame.minX + (targetFrame.minX - currentFrame.minX) * self.animationFactor,
                    y: currentFrame.minY + (targetFrame.minY - currentFrame.minY) * self.animationFactor,
                    width: currentFrame.width + (targetFrame.width - currentFrame.width) * self.animationFactor,
                    height: currentFrame.height + (targetFrame.height - currentFrame.height) * self.animationFactor
                ).integral

                do {
                    previousFrame = try self.applyAndObserve(interpolatedFrame)
                } catch {
                    DebugLog.debug(
                        DebugLog.windows,
                        "Smooth docking move failed: \(error.localizedDescription)"
                    )
                    break
                }

                try? await Task.sleep(nanoseconds: self.animationStepDuration)
            }

            self.animationTask = nil
        }
    }

    private func applyAndObserve(_ requestedFrame: CGRect) throws -> CGRect {
        let normalizedRequestedFrame = requestedFrame.integral
        let appliedFrame = try applyFrame(normalizedRequestedFrame).integral
        let previousAdaptiveSizeConstraints = adaptiveSizeConstraints
        adaptiveSizeConstraints.incorporateObservation(
            requestedFrame: normalizedRequestedFrame,
            appliedFrame: appliedFrame
        )
        if
            let currentAction,
            adaptiveSizeConstraints != previousAdaptiveSizeConstraints
        {
            recordConstraintObservation(currentAction, normalizedRequestedFrame, appliedFrame)
        }

        // Retarget immediately after each write so later steps chase the frame
        // the app can actually honor instead of the original ideal geometry.
        let recalculatedTarget = resolvedTargetFrame(for: currentAction)
        if recalculatedTarget != currentTargetFrame {
            DebugLog.debug(
                DebugLog.windows,
                "Adjusted smooth docking target from \(currentTargetFrame.map(NSStringFromRect) ?? "nil") to \(NSStringFromRect(recalculatedTarget))"
            )
            currentTargetFrame = recalculatedTarget
        }

        return appliedFrame
    }

    private func settle(
        at targetFrame: CGRect,
        maxIterations: Int
    ) throws -> CGRect {
        var latestFrame = loadCurrentFrame() ?? originalFrame
        var requestedFrame = targetFrame.integral

        // A few synchronous retries help after the user releases the gesture,
        // when some apps only expose their final size constraints one write later.
        for _ in 0..<maxIterations {
            latestFrame = try applyAndObserve(requestedFrame)
            let correctedTargetFrame = currentTargetFrame ?? requestedFrame
            if framesAreClose(latestFrame, correctedTargetFrame, tolerance: 1) {
                return correctedTargetFrame
            }

            requestedFrame = correctedTargetFrame.integral
        }

        latestFrame = try applyAndObserve(requestedFrame)
        return latestFrame.integral
    }

    private func resolvedTargetFrame(for action: WindowAction?) -> CGRect {
        guard let action else {
            return originalFrame.integral
        }

        let plan = resolver.plan(
            for: action,
            in: desktopFrame,
            sizeConstraints: baseSizeConstraints.merged(with: adaptiveSizeConstraints)
        )
        return plan.frame.integral
    }

    private func framesAreClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance &&
            abs(lhs.minY - rhs.minY) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }
}

extension WindowAction {
    var supportsSmoothDocking: Bool {
        supportsSnapPreview
    }
}
