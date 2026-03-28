import CoreGraphics
import Testing
@testable import Sweeesh

struct DockSwipeGestureRecognizerTests {
    @Test
    func downwardTwoFingerSwipeMinimizesHoveredApplication() {
        var recognizer = DockSwipeGestureRecognizer()

        #expect(
            recognizer.process(
                frame: TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.4, y: 0.7)),
                        TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.6, y: 0.7)),
                    ],
                    timestamp: 0
                ),
                hoveredApplicationName: "Finder"
            ) == nil
        )

        #expect(
            recognizer.process(
                frame: TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.42, y: 0.55)),
                        TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.62, y: 0.54)),
                    ],
                    timestamp: 0.1
                ),
                hoveredApplicationName: "Finder"
            ) == .minimize(applicationName: "Finder")
        )
    }

    @Test
    func upwardTwoFingerSwipeRestoresHoveredApplication() {
        var recognizer = DockSwipeGestureRecognizer()

        _ = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.35, y: 0.35)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.55, y: 0.35)),
                ],
                timestamp: 0
            ),
            hoveredApplicationName: "Ghostty"
        )

        #expect(
            recognizer.process(
                frame: TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.36, y: 0.5)),
                        TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.56, y: 0.52)),
                    ],
                    timestamp: 0.1
                ),
                hoveredApplicationName: "Ghostty"
            ) == .restore(applicationName: "Ghostty")
        )
    }

    @Test
    func gestureRequiresHoveredApplicationAtStart() {
        var recognizer = DockSwipeGestureRecognizer()

        #expect(
            recognizer.process(
                frame: TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.4, y: 0.4)),
                        TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.5, y: 0.4)),
                    ],
                    timestamp: 0
                ),
                hoveredApplicationName: nil
            ) == nil
        )
    }
}
