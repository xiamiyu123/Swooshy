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
}
