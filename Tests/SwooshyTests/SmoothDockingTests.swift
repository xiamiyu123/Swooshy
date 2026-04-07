import CoreGraphics
import Testing
@testable import Swooshy

@MainActor
struct SmoothDockingTests {
    private let resolver = SmoothDockingResolver()
    private let desktopFrame = CGRect(x: 0, y: 85, width: 1408, height: 766)

    @Test
    func topLeftQuarterAnchorsConstrainedWindowToDesktopTopLeft() {
        let plan = resolver.plan(
            for: .topLeftQuarter,
            in: desktopFrame,
            sizeConstraints: SmoothDockingSizeConstraints(
                minimumWidth: nil,
                maximumWidth: 560,
                minimumHeight: 672,
                maximumHeight: nil
            )
        )

        #expect(plan.anchor == .topLeading)
        #expect(plan.frame == CGRect(x: 0, y: 179, width: 560, height: 672))
    }

    @Test
    func rightHalfAnchorsConstrainedWindowToDesktopTopRight() {
        let plan = resolver.plan(
            for: .rightHalf,
            in: desktopFrame,
            sizeConstraints: SmoothDockingSizeConstraints(
                minimumWidth: nil,
                maximumWidth: 560,
                minimumHeight: nil,
                maximumHeight: 672
            )
        )

        #expect(plan.anchor == .topTrailing)
        #expect(plan.frame == CGRect(x: 848, y: 179, width: 560, height: 672))
    }

    @Test
    func maximizeAnchorsConstrainedWindowToDesktopTopLeft() {
        let plan = resolver.plan(
            for: .maximize,
            in: desktopFrame,
            sizeConstraints: SmoothDockingSizeConstraints(
                minimumWidth: nil,
                maximumWidth: 1200,
                minimumHeight: nil,
                maximumHeight: 700
            )
        )

        #expect(plan.anchor == .topLeading)
        #expect(plan.frame == CGRect(x: 0, y: 151, width: 1200, height: 700))
    }

    @Test
    func smoothDockingSessionRetargetsAfterDetectingSizeConstraint() async {
        let constrainedSize = CGSize(width: 560, height: 672)
        var currentFrame = CGRect(x: 323, y: 179, width: 560, height: 672)

        let session = SmoothDockingSession(
            originalFrame: currentFrame,
            desktopFrame: desktopFrame,
            baseSizeConstraints: SmoothDockingSizeConstraints(),
            loadCurrentFrame: { currentFrame },
            applyFrame: { requestedFrame in
                if
                    abs(requestedFrame.width - constrainedSize.width) > 0.1 ||
                    abs(requestedFrame.height - constrainedSize.height) > 0.1
                {
                    currentFrame = CGRect(
                        x: requestedFrame.minX,
                        y: requestedFrame.minY,
                        width: constrainedSize.width,
                        height: constrainedSize.height
                    )
                } else {
                    currentFrame = requestedFrame
                }

                return currentFrame
            }
        )

        session.update(action: .topRightQuarter)
        try? await Task.sleep(nanoseconds: 240_000_000)
        _ = try? session.commit()
        session.finish()

        #expect(currentFrame.size == constrainedSize)
        #expect(abs(currentFrame.maxX - desktopFrame.maxX) <= 1)
        #expect(abs(currentFrame.maxY - desktopFrame.maxY) <= 1)
    }
}
