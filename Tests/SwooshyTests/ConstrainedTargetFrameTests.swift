import CoreGraphics
import Testing
@testable import Swooshy

struct ConstrainedTargetFrameTests {
    private let engine = WindowLayoutEngine()

    private func observation(
        minimumWidth: CGFloat? = nil,
        maximumWidth: CGFloat? = nil,
        minimumHeight: CGFloat? = nil,
        maximumHeight: CGFloat? = nil,
        horizontalAnchor: WindowActionPreview.AxisAnchor,
        verticalAnchor: WindowActionPreview.AxisAnchor
    ) -> WindowActionPreview.Observation {
        WindowActionPreview.Observation(
            sizeBounds: .init(
                minimumWidth: minimumWidth,
                maximumWidth: maximumWidth,
                minimumHeight: minimumHeight,
                maximumHeight: maximumHeight
            ),
            horizontalAnchor: horizontalAnchor,
            verticalAnchor: verticalAnchor
        )
    }

    @Test
    func constrainedTargetFrameReturnsTargetFrameWhenNoObservation() {
        let target = CGRect(x: 0, y: 0, width: 720, height: 900)

        let result = engine.constrainedTargetFrame(
            for: .leftHalf,
            targetFrame: target,
            observation: nil
        )

        #expect(result == target)
    }

    @Test
    func constrainedTargetFrameExpandsLeftHalfFromLeadingEdgeForMinimumWidth() {
        let target = CGRect(x: 0, y: 0, width: 720, height: 900)

        let observation = observation(
            minimumWidth: 860,
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .leadingEdge
        )

        let result = engine.constrainedTargetFrame(
            for: .leftHalf,
            targetFrame: target,
            observation: observation
        )

        #expect(result == CGRect(x: 0, y: 0, width: 860, height: 900))
    }

    @Test
    func constrainedTargetFrameShrinksMaximizeFromCenterForMaximumSize() {
        let target = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let observation = observation(
            maximumWidth: 1200,
            maximumHeight: 800,
            horizontalAnchor: .centered,
            verticalAnchor: .centered
        )

        let result = engine.constrainedTargetFrame(
            for: .maximize,
            targetFrame: target,
            observation: observation
        )

        #expect(result == CGRect(x: 120, y: 50, width: 1200, height: 800))
    }

    @Test
    func constrainedTargetFrameUsesActionVerticalAnchorForStrongMaxHeightInBottomLeftQuarter() {
        let target = CGRect(x: 0, y: 0, width: 704, height: 383)

        let observation = observation(
            maximumWidth: 182,
            maximumHeight: 40,
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .trailingEdge
        )

        let result = engine.constrainedTargetFrame(
            for: .bottomLeftQuarter,
            targetFrame: target,
            observation: observation
        )

        #expect(result.origin.y == 0)
    }

    @Test
    func constrainedTargetFrameKeepsTopRightQuarterFlushWithOuterEdges() {
        let target = CGRect(x: 704, y: 468, width: 704, height: 383)

        let observation = observation(
            maximumWidth: 560,
            minimumHeight: 672,
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .trailingEdge
        )

        let result = engine.constrainedTargetFrame(
            for: .topRightQuarter,
            targetFrame: target,
            observation: observation
        )

        #expect(result == CGRect(x: 848, y: 179, width: 560, height: 672))
    }
}
