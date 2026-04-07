import CoreGraphics
import Testing
@testable import Swooshy

struct ConstrainedTargetFrameTests {
    private let engine = WindowLayoutEngine()

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

        let observation = WindowActionPreview.Observation(
            sizeBounds: .init(
                minimumWidth: 860,
                maximumWidth: nil,
                minimumHeight: nil,
                maximumHeight: nil
            ),
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

        let observation = WindowActionPreview.Observation(
            sizeBounds: .init(
                minimumWidth: nil,
                maximumWidth: 1200,
                minimumHeight: nil,
                maximumHeight: 800
            ),
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

        let observation = WindowActionPreview.Observation(
            sizeBounds: .init(
                minimumWidth: nil,
                maximumWidth: 182,
                minimumHeight: nil,
                maximumHeight: 40
            ),
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

        let observation = WindowActionPreview.Observation(
            sizeBounds: .init(
                minimumWidth: nil,
                maximumWidth: 560,
                minimumHeight: 672,
                maximumHeight: nil
            ),
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
