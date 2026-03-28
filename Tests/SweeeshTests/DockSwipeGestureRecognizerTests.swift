import CoreGraphics
import Testing
@testable import Sweeesh

struct DockSwipeGestureRecognizerTests {
    private func target(
        dockItemName: String,
        resolvedApplicationName: String? = nil,
        processIdentifier: pid_t = 42,
        bundleIdentifier: String? = nil,
        aliases: [String] = []
    ) -> DockApplicationTarget {
        DockApplicationTarget(
            dockItemName: dockItemName,
            resolvedApplicationName: resolvedApplicationName ?? dockItemName,
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier,
            aliases: aliases
        )
    }

    @Test
    func downwardTwoFingerSwipeMinimizesHoveredApplication() {
        var recognizer = DockSwipeGestureRecognizer()
        let finder = target(
            dockItemName: "Finder",
            processIdentifier: 100,
            bundleIdentifier: "com.apple.finder",
            aliases: ["Finder", "com.apple.finder"]
        )

        #expect(
            recognizer.process(
                frame: TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.4, y: 0.7)),
                        TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.6, y: 0.7)),
                    ],
                    timestamp: 0
                ),
                hoveredApplication: finder
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
                hoveredApplication: finder
            ) == .minimize(application: finder)
        )
    }

    @Test
    func upwardTwoFingerSwipeRestoresHoveredApplication() {
        var recognizer = DockSwipeGestureRecognizer()
        let ghostty = target(
            dockItemName: "Ghostty",
            processIdentifier: 101,
            bundleIdentifier: "com.mitchellh.ghostty",
            aliases: ["Ghostty", "com.mitchellh.ghostty"]
        )

        _ = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.35, y: 0.35)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.55, y: 0.35)),
                ],
                timestamp: 0
            ),
            hoveredApplication: ghostty
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
                hoveredApplication: ghostty
            ) == .restore(application: ghostty)
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
                hoveredApplication: nil
            ) == nil
        )
    }
}
