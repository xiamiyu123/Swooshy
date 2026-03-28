import CoreGraphics
import Testing
@testable import Sweeesh

struct WindowLayoutEngineTests {
    private let engine = WindowLayoutEngine()
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test
    func leftHalfUsesLeftSideOfVisibleFrame() {
        let frame = engine.targetFrame(
            for: .leftHalf,
            currentWindowFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            currentVisibleFrame: visibleFrame
        )

        #expect(frame == CGRect(x: 0, y: 0, width: 720, height: 900))
    }

    @Test
    func rightHalfUsesRightSideOfVisibleFrame() {
        let frame = engine.targetFrame(
            for: .rightHalf,
            currentWindowFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            currentVisibleFrame: visibleFrame
        )

        #expect(frame == CGRect(x: 720, y: 0, width: 720, height: 900))
    }

    @Test
    func maximizeUsesEntireVisibleFrame() {
        let frame = engine.targetFrame(
            for: .maximize,
            currentWindowFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            currentVisibleFrame: visibleFrame
        )

        #expect(frame == visibleFrame)
    }

    @Test
    func centerUsesEightyPercentFillRatio() {
        let frame = engine.targetFrame(
            for: .center,
            currentWindowFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            currentVisibleFrame: visibleFrame
        )

        #expect(frame == CGRect(x: 144, y: 90, width: 1152, height: 720))
    }

    @Test
    func nonLayoutActionsPreserveCurrentFrame() {
        let currentWindowFrame = CGRect(x: 100, y: 100, width: 800, height: 600)

        for action in [WindowAction.minimize, .closeWindow, .quitApplication, .cycleSameAppWindows] {
            let frame = engine.targetFrame(
                for: action,
                currentWindowFrame: currentWindowFrame,
                currentVisibleFrame: visibleFrame
            )

            #expect(frame == currentWindowFrame)
        }
    }
}
