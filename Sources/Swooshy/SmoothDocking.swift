import AppKit
import CoreGraphics

enum SmoothDockingAnchor: Equatable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

struct SmoothDockingSizeConstraints: Equatable, Sendable {
    var minimumWidth: CGFloat?
    var maximumWidth: CGFloat?
    var minimumHeight: CGFloat?
    var maximumHeight: CGFloat?

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
        var width = proposedSize.width
        var height = proposedSize.height

        if let minimumWidth {
            width = max(width, minimumWidth)
        }
        if let maximumWidth {
            width = min(width, maximumWidth)
        }
        if let minimumHeight {
            height = max(height, minimumHeight)
        }
        if let maximumHeight {
            height = min(height, maximumHeight)
        }

        width = min(width, desktopSize.width)
        height = min(height, desktopSize.height)

        return CGSize(width: width, height: height)
    }

    private func normalized() -> Self {
        var normalizedMinimumWidth = minimumWidth
        var normalizedMaximumWidth = maximumWidth
        var normalizedMinimumHeight = minimumHeight
        var normalizedMaximumHeight = maximumHeight

        if
            let minimumWidth = normalizedMinimumWidth,
            let maximumWidth = normalizedMaximumWidth,
            minimumWidth > maximumWidth
        {
            let lockedWidth = max(minimumWidth, maximumWidth)
            normalizedMinimumWidth = lockedWidth
            normalizedMaximumWidth = lockedWidth
        }

        if
            let minimumHeight = normalizedMinimumHeight,
            let maximumHeight = normalizedMaximumHeight,
            minimumHeight > maximumHeight
        {
            let lockedHeight = max(minimumHeight, maximumHeight)
            normalizedMinimumHeight = lockedHeight
            normalizedMaximumHeight = lockedHeight
        }

        return Self(
            minimumWidth: normalizedMinimumWidth,
            maximumWidth: normalizedMaximumWidth,
            minimumHeight: normalizedMinimumHeight,
            maximumHeight: normalizedMaximumHeight
        )
    }

    private func maxNonNil(_ lhs: CGFloat?, _ rhs: CGFloat?) -> CGFloat? {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            return max(lhs, rhs)
        case let (.some(lhs), .none):
            return lhs
        case let (.none, .some(rhs)):
            return rhs
        case (.none, .none):
            return nil
        }
    }

    private func minNonNil(_ lhs: CGFloat?, _ rhs: CGFloat?) -> CGFloat? {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            return min(lhs, rhs)
        case let (.some(lhs), .none):
            return lhs
        case let (.none, .some(rhs)):
            return rhs
        case (.none, .none):
            return nil
        }
    }
}

struct SmoothDockingPlan: Equatable, Sendable {
    let action: WindowAction
    let desktopFrame: CGRect
    let idealFrame: CGRect
    let frame: CGRect
    let anchor: SmoothDockingAnchor
}

struct SmoothDockingResolver {
    func desktopFrame(
        preferredPoint: CGPoint?,
        currentWindowFrame: CGRect,
        screens: [NSScreen]
    ) -> CGRect? {
        let desktopFrames = screens.map(\.visibleFrame).filter { $0.isEmpty == false }
        guard desktopFrames.isEmpty == false else {
            return nil
        }

        if
            let preferredPoint,
            let preferredDesktop = desktopFrames.first(where: { $0.contains(preferredPoint) })
        {
            return preferredDesktop.integral
        }

        let midpoint = CGPoint(x: currentWindowFrame.midX, y: currentWindowFrame.midY)
        if let midpointDesktop = desktopFrames.first(where: { $0.contains(midpoint) }) {
            return midpointDesktop.integral
        }

        let overlaps = desktopFrames.map { frame in
            (frame, frame.intersection(currentWindowFrame).area)
        }
        let maxOverlapArea = overlaps.map(\.1).max() ?? 0
        if maxOverlapArea > 0 {
            let candidates = overlaps
                .filter { abs($0.1 - maxOverlapArea) <= 1 }
                .map(\.0)
            if let bestMatch = nearestFrame(to: midpoint, in: candidates) {
                return bestMatch.integral
            }
        }

        return nearestFrame(to: midpoint, in: desktopFrames)?.integral
    }

    func plan(
        for action: WindowAction,
        in desktopFrame: CGRect,
        sizeConstraints: SmoothDockingSizeConstraints
    ) -> SmoothDockingPlan {
        let normalizedDesktopFrame = desktopFrame.integral
        let idealFrame = idealFrame(for: action, in: normalizedDesktopFrame)
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

    private func idealFrame(for action: WindowAction, in desktopFrame: CGRect) -> CGRect {
        switch action {
        case .leftHalf:
            let splitX = desktopFrame.minX + floor(desktopFrame.width / 2)
            return CGRect(
                x: desktopFrame.minX,
                y: desktopFrame.minY,
                width: splitX - desktopFrame.minX,
                height: desktopFrame.height
            ).integral
        case .rightHalf:
            let splitX = desktopFrame.minX + floor(desktopFrame.width / 2)
            return CGRect(
                x: splitX,
                y: desktopFrame.minY,
                width: desktopFrame.maxX - splitX,
                height: desktopFrame.height
            ).integral
        case .maximize, .center:
            return desktopFrame.integral
        case .topLeftQuarter:
            return quarterFrame(
                in: desktopFrame,
                horizontalAnchor: .topLeading,
                verticalAnchor: .topLeading
            )
        case .topRightQuarter:
            return quarterFrame(
                in: desktopFrame,
                horizontalAnchor: .topTrailing,
                verticalAnchor: .topTrailing
            )
        case .bottomLeftQuarter:
            return quarterFrame(
                in: desktopFrame,
                horizontalAnchor: .bottomLeading,
                verticalAnchor: .bottomLeading
            )
        case .bottomRightQuarter:
            return quarterFrame(
                in: desktopFrame,
                horizontalAnchor: .bottomTrailing,
                verticalAnchor: .bottomTrailing
            )
        case .minimize,
             .closeWindow,
             .closeTab,
             .quitApplication,
             .cycleSameAppWindowsForward,
             .cycleSameAppWindowsBackward,
             .toggleFullScreen,
             .exitFullScreen:
            return desktopFrame.integral
        }
    }

    private func quarterFrame(
        in desktopFrame: CGRect,
        horizontalAnchor: SmoothDockingAnchor,
        verticalAnchor: SmoothDockingAnchor
    ) -> CGRect {
        let splitX = desktopFrame.minX + floor(desktopFrame.width / 2)
        let splitY = desktopFrame.minY + floor(desktopFrame.height / 2)

        let minX = (horizontalAnchor == .topLeading || horizontalAnchor == .bottomLeading)
            ? desktopFrame.minX
            : splitX
        let maxX = (horizontalAnchor == .topLeading || horizontalAnchor == .bottomLeading)
            ? splitX
            : desktopFrame.maxX
        let minY = (verticalAnchor == .bottomLeading || verticalAnchor == .bottomTrailing)
            ? desktopFrame.minY
            : splitY
        let maxY = (verticalAnchor == .bottomLeading || verticalAnchor == .bottomTrailing)
            ? splitY
            : desktopFrame.maxY

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        ).integral
    }

    private func anchor(for action: WindowAction) -> SmoothDockingAnchor {
        switch action {
        case .leftHalf, .maximize, .center:
            return .topLeading
        case .rightHalf:
            return .topTrailing
        case .topLeftQuarter:
            return .topLeading
        case .topRightQuarter:
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
             .exitFullScreen:
            return .topLeading
        }
    }

    private func anchoredFrame(
        in desktopFrame: CGRect,
        size: CGSize,
        anchor: SmoothDockingAnchor
    ) -> CGRect {
        let originX: CGFloat
        switch anchor {
        case .topLeading, .bottomLeading:
            originX = desktopFrame.minX
        case .topTrailing, .bottomTrailing:
            originX = desktopFrame.maxX - size.width
        }

        let originY: CGFloat
        switch anchor {
        case .topLeading, .topTrailing:
            originY = desktopFrame.maxY - size.height
        case .bottomLeading, .bottomTrailing:
            originY = desktopFrame.minY
        }

        return CGRect(
            x: originX,
            y: originY,
            width: size.width,
            height: size.height
        ).integral
    }

    private func nearestFrame(to point: CGPoint, in frames: [CGRect]) -> CGRect? {
        frames.min { lhs, rhs in
            lhs.center.distance(to: point) < rhs.center.distance(to: point)
        }
    }
}

@MainActor
final class SmoothDockingSession {
    private let originalFrame: CGRect
    private let desktopFrame: CGRect
    private let baseSizeConstraints: SmoothDockingSizeConstraints
    private let loadCurrentFrame: () -> CGRect?
    private let applyFrame: (CGRect) throws -> CGRect
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
        animationStepDuration: UInt64 = 12_000_000,
        animationFactor: CGFloat = 0.32,
        snapThreshold: CGFloat = 0.5
    ) {
        self.originalFrame = originalFrame.integral
        self.desktopFrame = desktopFrame.integral
        self.baseSizeConstraints = baseSizeConstraints
        self.loadCurrentFrame = loadCurrentFrame
        self.applyFrame = applyFrame
        self.animationStepDuration = animationStepDuration
        self.animationFactor = animationFactor
        self.snapThreshold = snapThreshold
    }

    deinit {
        animationTask?.cancel()
    }

    func update(action: WindowAction?) {
        currentAction = action
        currentTargetFrame = resolvedTargetFrame(for: action)
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
        guard animationTask == nil else {
            return
        }

        animationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var previousFrame = self.loadCurrentFrame() ?? self.originalFrame

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
        let appliedFrame = try applyFrame(requestedFrame.integral).integral
        adaptiveSizeConstraints.incorporateObservation(
            requestedFrame: requestedFrame.integral,
            appliedFrame: appliedFrame
        )

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
        switch self {
        case .leftHalf,
             .rightHalf,
             .maximize,
             .center,
             .topLeftQuarter,
             .topRightQuarter,
             .bottomLeftQuarter,
             .bottomRightQuarter:
            return true
        case .minimize,
             .closeWindow,
             .closeTab,
             .quitApplication,
             .cycleSameAppWindowsForward,
             .cycleSameAppWindowsBackward,
             .toggleFullScreen,
             .exitFullScreen:
            return false
        }
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }

    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        hypot(point.x - x, point.y - y)
    }
}
