import CoreGraphics

struct WindowActionPreview: Equatable, Sendable {
    enum Style: Equatable, Sendable {
        case area
    }

    enum AxisAnchor: String, Codable, Equatable, Sendable {
        case leadingEdge
        case trailingEdge
        case centered
    }

    struct SizeBounds: Codable, Equatable, Sendable {
        var minimumWidth: CGFloat?
        var maximumWidth: CGFloat?
        var minimumHeight: CGFloat?
        var maximumHeight: CGFloat?

        var hasConstraints: Bool {
            minimumWidth != nil ||
            maximumWidth != nil ||
            minimumHeight != nil ||
            maximumHeight != nil
        }

        func constrainedSize(for targetSize: CGSize) -> CGSize {
            CGSize(
                width: constrainedDimension(
                    targetSize.width,
                    minimum: minimumWidth,
                    maximum: maximumWidth
                ),
                height: constrainedDimension(
                    targetSize.height,
                    minimum: minimumHeight,
                    maximum: maximumHeight
                )
            )
        }

        private func constrainedDimension(
            _ value: CGFloat,
            minimum: CGFloat?,
            maximum: CGFloat?
        ) -> CGFloat {
            var constrainedValue = value
            if let minimum {
                constrainedValue = max(constrainedValue, minimum)
            }
            if let maximum {
                constrainedValue = min(constrainedValue, maximum)
            }
            return constrainedValue
        }
    }

    struct Observation: Codable, Equatable, Sendable {
        var sizeBounds: SizeBounds
        var horizontalAnchor: AxisAnchor?
        var verticalAnchor: AxisAnchor?
    }

    let frame: CGRect
    let style: Style
}

enum DisplayMoveDirection: Equatable, Sendable {
    case next
    case previous
}

/// Maps high-level window actions to target frames and previews, while honoring
/// the size constraints observed from apps that refuse ideal half/quarter sizes.
struct WindowLayoutEngine {
    func targetFrame(
        for action: WindowAction,
        currentWindowFrame: CGRect,
        currentVisibleFrame: CGRect
    ) -> CGRect {
        switch action {
        case .leftHalf:
            return leftHalfFrame(in: currentVisibleFrame)
        case .rightHalf:
            return rightHalfFrame(in: currentVisibleFrame)
        case .topLeftQuarter:
            return topLeftQuarterFrame(in: currentVisibleFrame)
        case .topRightQuarter:
            return topRightQuarterFrame(in: currentVisibleFrame)
        case .bottomLeftQuarter:
            return bottomLeftQuarterFrame(in: currentVisibleFrame)
        case .bottomRightQuarter:
            return bottomRightQuarterFrame(in: currentVisibleFrame)
        case .maximize:
            return currentVisibleFrame.integral
        case .center:
            return currentVisibleFrame.integral
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
            return currentWindowFrame
        }
    }

    func constrainedTargetFrame(
        for action: WindowAction,
        targetFrame: CGRect,
        observation: WindowActionPreview.Observation?
    ) -> CGRect {
        guard let observation, observation.sizeBounds.hasConstraints else {
            return targetFrame
        }

        guard let previewBehavior = action.previewBehavior else {
            return targetFrame
        }

        switch previewBehavior {
        case .area(let defaultHorizontalAnchor, let defaultVerticalAnchor):
            return areaPreviewFrame(
                for: action,
                targetFrame: targetFrame,
                observation: observation,
                defaultHorizontalAnchor: defaultHorizontalAnchor,
                defaultVerticalAnchor: defaultVerticalAnchor
            )
        }
    }

    func preview(
        for action: WindowAction,
        targetFrame: CGRect,
        observation: WindowActionPreview.Observation?
    ) -> WindowActionPreview? {
        guard let previewBehavior = action.previewBehavior else {
            return nil
        }

        switch previewBehavior {
        case .area(let defaultHorizontalAnchor, let defaultVerticalAnchor):
            let frame = areaPreviewFrame(
                for: action,
                targetFrame: targetFrame,
                observation: observation,
                defaultHorizontalAnchor: defaultHorizontalAnchor,
                defaultVerticalAnchor: defaultVerticalAnchor
            )
            return WindowActionPreview(frame: frame, style: .area)
        }
    }

    func screenContainingMost(of windowFrame: CGRect, in screenFrames: [CGRect]) -> CGRect? {
        guard screenFrames.isEmpty == false else {
            return nil
        }

        let midpoint = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        if let midpointScreen = screenFrames.first(where: { $0.contains(midpoint) }) {
            return midpointScreen
        }

        let intersections = screenFrames.map { frame in
            (frame: frame, overlapArea: frame.intersection(windowFrame).area)
        }

        let maxOverlapArea = intersections.map(\.overlapArea).max() ?? 0
        if maxOverlapArea > 0 {
            let overlapTolerance: CGFloat = 1
            let bestCandidates = intersections
                .filter { abs($0.overlapArea - maxOverlapArea) <= overlapTolerance }
                .map(\.frame)

            if bestCandidates.count == 1 {
                return bestCandidates.first
            }

            if let nearestBestCandidate = nearestScreen(to: midpoint, in: bestCandidates) {
                return nearestBestCandidate
            }
        }

        return nearestScreen(to: midpoint, in: screenFrames)
    }

    func resolvedVisibleFrame(
        preferredPoint: CGPoint?,
        currentWindowFrame: CGRect,
        screenFrames: [CGRect]
    ) -> CGRect? {
        // Prefer the screen the pointer came from so a drag or gesture near a
        // display boundary still snaps onto the intended monitor.
        let preferredScreenFrame = preferredPoint.flatMap { preferredPoint in
            screenFrames.first { $0.contains(preferredPoint) }
        }

        return preferredScreenFrame ?? screenContainingMost(
            of: currentWindowFrame,
            in: screenFrames
        )
    }

    func displayMoveTargetFrame(
        direction: DisplayMoveDirection,
        currentWindowFrame: CGRect,
        currentVisibleFrame: CGRect,
        screenFrames: [CGRect]
    ) -> CGRect {
        let orderedScreenFrames = displayTraversalOrder(screenFrames)
        guard
            orderedScreenFrames.count > 1,
            let currentIndex = orderedScreenFrames.firstIndex(of: currentVisibleFrame)
        else {
            return currentWindowFrame.integral
        }

        let targetIndex: Int
        switch direction {
        case .next:
            targetIndex = (currentIndex + 1) % orderedScreenFrames.count
        case .previous:
            targetIndex = (currentIndex + orderedScreenFrames.count - 1) % orderedScreenFrames.count
        }

        let targetVisibleFrame = orderedScreenFrames[targetIndex]
        let relativeCenter = relativeCenter(
            of: currentWindowFrame,
            in: currentVisibleFrame
        )
        let targetSize = CGSize(
            width: min(currentWindowFrame.width, targetVisibleFrame.width),
            height: min(currentWindowFrame.height, targetVisibleFrame.height)
        )
        let targetCenter = CGPoint(
            x: targetVisibleFrame.minX + targetVisibleFrame.width * relativeCenter.x,
            y: targetVisibleFrame.minY + targetVisibleFrame.height * relativeCenter.y
        )
        let targetFrame = CGRect(
            x: targetCenter.x - targetSize.width / 2,
            y: targetCenter.y - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        )

        return clampFrame(targetFrame, to: targetVisibleFrame)
    }

    private func nearestScreen(to point: CGPoint, in screenFrames: [CGRect]) -> CGRect? {
        screenFrames.min { lhs, rhs in
            lhs.center.distance(to: point) < rhs.center.distance(to: point)
        }
    }

    private func displayTraversalOrder(_ screenFrames: [CGRect]) -> [CGRect] {
        screenFrames.sorted { lhs, rhs in
            if abs(lhs.minX - rhs.minX) > 1 {
                return lhs.minX < rhs.minX
            }

            return lhs.minY > rhs.minY
        }
    }

    private func relativeCenter(of windowFrame: CGRect, in visibleFrame: CGRect) -> CGPoint {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        return CGPoint(
            x: ((windowFrame.midX - visibleFrame.minX) / visibleFrame.width).clamped(to: 0 ... 1),
            y: ((windowFrame.midY - visibleFrame.minY) / visibleFrame.height).clamped(to: 0 ... 1)
        )
    }

    private func clampFrame(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        var clamped = frame

        if clamped.width > visibleFrame.width {
            clamped.size.width = visibleFrame.width
        }
        if clamped.height > visibleFrame.height {
            clamped.size.height = visibleFrame.height
        }

        if clamped.minX < visibleFrame.minX {
            clamped.origin.x = visibleFrame.minX
        }
        if clamped.maxX > visibleFrame.maxX {
            clamped.origin.x = visibleFrame.maxX - clamped.width
        }
        if clamped.minY < visibleFrame.minY {
            clamped.origin.y = visibleFrame.minY
        }
        if clamped.maxY > visibleFrame.maxY {
            clamped.origin.y = visibleFrame.maxY - clamped.height
        }

        return clamped.integral
    }

    private func areaPreviewFrame(
        for action: WindowAction,
        targetFrame: CGRect,
        observation: WindowActionPreview.Observation?,
        defaultHorizontalAnchor: WindowActionPreview.AxisAnchor,
        defaultVerticalAnchor: WindowActionPreview.AxisAnchor
    ) -> CGRect {
        let sizeBounds = observation?.sizeBounds
        let resolvedSize: CGSize
        if let sizeBounds {
            resolvedSize = sizeBounds.constrainedSize(for: targetFrame.size)
        } else {
            resolvedSize = targetFrame.size
        }

        var horizontalAnchor = observation?.horizontalAnchor ?? defaultHorizontalAnchor
        var verticalAnchor = observation?.verticalAnchor ?? defaultVerticalAnchor

        if let sizeBounds {
            let constrainedSize = resolvedSize

            // Quarter actions look wrong when a constrained window drifts inward,
            // so keep any dimension that changed pinned to the action's outer edge.
            if action.prefersOuterEdgeAnchoringWhenConstrained {
                if abs(constrainedSize.width - targetFrame.width) > 1 {
                    horizontalAnchor = defaultHorizontalAnchor
                }
                if abs(constrainedSize.height - targetFrame.height) > 1 {
                    verticalAnchor = defaultVerticalAnchor
                }
            }

            // When an app enforces a much smaller maximum size, center anchoring
            // can make the preview appear detached from the intended snap area.
            if sizeBounds.maximumWidth != nil,
               constrainedSize.width <= targetFrame.width,
               horizontalAnchor != defaultHorizontalAnchor {
                let widthRatio = constrainedSize.width / targetFrame.width
                if widthRatio <= 0.5 {
                    horizontalAnchor = defaultHorizontalAnchor
                }
            }

            if sizeBounds.maximumHeight != nil,
               constrainedSize.height <= targetFrame.height,
               verticalAnchor != defaultVerticalAnchor {
                let heightRatio = constrainedSize.height / targetFrame.height
                if heightRatio <= 0.5 {
                    verticalAnchor = defaultVerticalAnchor
                }
            }
        }

        let width = resolvedSize.width
        let height = resolvedSize.height

        let originX = anchoredOrigin(
            min: targetFrame.minX,
            max: targetFrame.maxX,
            targetSize: targetFrame.width,
            resolvedSize: width,
            anchor: horizontalAnchor
        )
        let originY = anchoredOrigin(
            min: targetFrame.minY,
            max: targetFrame.maxY,
            targetSize: targetFrame.height,
            resolvedSize: height,
            anchor: verticalAnchor
        )

        return CGRect(
            x: originX,
            y: originY,
            width: width,
            height: height
        ).integral
    }

    private func anchoredOrigin(
        min: CGFloat,
        max: CGFloat,
        targetSize: CGFloat,
        resolvedSize: CGFloat,
        anchor: WindowActionPreview.AxisAnchor
    ) -> CGFloat {
        switch anchor {
        case .leadingEdge:
            return min
        case .trailingEdge:
            return max - resolvedSize
        case .centered:
            return min - ((resolvedSize - targetSize) / 2)
        }
    }

    private func leftHalfFrame(in visibleFrame: CGRect) -> CGRect {
        let splitX = visibleFrame.minX + floor(visibleFrame.width / 2)
        return CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: splitX - visibleFrame.minX,
            height: visibleFrame.height
        ).integral
    }

    private func rightHalfFrame(in visibleFrame: CGRect) -> CGRect {
        let splitX = visibleFrame.minX + floor(visibleFrame.width / 2)
        return CGRect(
            x: splitX,
            y: visibleFrame.minY,
            width: visibleFrame.maxX - splitX,
            height: visibleFrame.height
        ).integral
    }

    private func topLeftQuarterFrame(in visibleFrame: CGRect) -> CGRect {
        quarterFrame(
            in: visibleFrame,
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .trailingEdge
        )
    }

    private func topRightQuarterFrame(in visibleFrame: CGRect) -> CGRect {
        quarterFrame(
            in: visibleFrame,
            horizontalAnchor: .trailingEdge,
            verticalAnchor: .trailingEdge
        )
    }

    private func bottomLeftQuarterFrame(in visibleFrame: CGRect) -> CGRect {
        quarterFrame(
            in: visibleFrame,
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .leadingEdge
        )
    }

    private func bottomRightQuarterFrame(in visibleFrame: CGRect) -> CGRect {
        quarterFrame(
            in: visibleFrame,
            horizontalAnchor: .trailingEdge,
            verticalAnchor: .leadingEdge
        )
    }

    private func quarterFrame(
        in visibleFrame: CGRect,
        horizontalAnchor: WindowActionPreview.AxisAnchor,
        verticalAnchor: WindowActionPreview.AxisAnchor
    ) -> CGRect {
        let splitX = visibleFrame.minX + floor(visibleFrame.width / 2)
        let splitY = visibleFrame.minY + floor(visibleFrame.height / 2)

        let minX = horizontalAnchor == .leadingEdge ? visibleFrame.minX : splitX
        let maxX = horizontalAnchor == .leadingEdge ? splitX : visibleFrame.maxX
        let minY = verticalAnchor == .leadingEdge ? visibleFrame.minY : splitY
        let maxY = verticalAnchor == .leadingEdge ? splitY : visibleFrame.maxY

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        ).integral
    }
}

private extension WindowAction {
    var prefersOuterEdgeAnchoringWhenConstrained: Bool {
        switch self {
        case .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter:
            return true
        case .leftHalf,
             .rightHalf,
             .maximize,
             .center,
             .minimize,
             .closeWindow,
             .closeTab,
             .quitApplication,
             .cycleSameAppWindowsForward,
             .cycleSameAppWindowsBackward,
             .toggleFullScreen,
             .exitFullScreen,
             .moveToNextDisplay,
             .moveToPreviousDisplay:
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

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
