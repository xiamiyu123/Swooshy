import CoreGraphics
import Testing
@testable import Swooshy

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
    func leftwardTwoFingerSwipeCyclesHoveredApplicationForward() {
        var recognizer = DockGestureRecognizer()
        let finder = target(
            dockItemName: "Finder",
            processIdentifier: 100,
            bundleIdentifier: "com.apple.finder",
            aliases: ["Finder", "com.apple.finder"]
        )

        _ = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.7, y: 0.5)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.85, y: 0.5)),
                ],
                timestamp: 0
            ),
            hoveredApplication: finder
        )

        #expect(
            recognizer.process(
                frame: TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.5, y: 0.51)),
                        TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.65, y: 0.49)),
                    ],
                    timestamp: 0.1
                ),
                hoveredApplication: finder
            ) == .swipeLeft(application: finder)
        )
    }

    @Test
    func rightwardTwoFingerSwipeCyclesHoveredApplicationBackward() {
        var recognizer = DockGestureRecognizer()
        let arc = target(
            dockItemName: "Arc",
            processIdentifier: 103,
            bundleIdentifier: "company.thebrowser.Browser",
            aliases: ["Arc", "company.thebrowser.Browser"]
        )

        _ = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.2, y: 0.45)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.35, y: 0.45)),
                ],
                timestamp: 0
            ),
            hoveredApplication: arc
        )

        #expect(
            recognizer.process(
                frame: TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.37, y: 0.44)),
                        TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.52, y: 0.46)),
                    ],
                    timestamp: 0.1
                ),
                hoveredApplication: arc
            ) == .swipeRight(application: arc)
        )
    }

    @Test
    func downwardTwoFingerSwipeMinimizesHoveredApplication() {
        var recognizer = DockGestureRecognizer()
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
            ) == .swipeDown(application: finder)
        )
    }

    @Test
    func upwardTwoFingerSwipeRestoresHoveredApplication() {
        var recognizer = DockGestureRecognizer()
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
            ) == .swipeUp(application: ghostty)
        )
    }

    @Test
    func inwardTwoFingerPinchProducesPinchGesture() {
        var recognizer = DockGestureRecognizer()
        let preview = target(
            dockItemName: "Preview",
            processIdentifier: 102,
            bundleIdentifier: "com.apple.Preview",
            aliases: ["Preview", "com.apple.Preview"]
        )

        _ = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.2, y: 0.5)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.8, y: 0.5)),
                ],
                timestamp: 0
            ),
            hoveredApplication: preview
        )

        #expect(
            recognizer.process(
                frame: TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.36, y: 0.5)),
                        TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.64, y: 0.5)),
                    ],
                    timestamp: 0.1
                ),
                hoveredApplication: preview
            ) == .pinchIn(application: preview)
        )
    }

    @Test
    func gestureRequiresHoveredApplicationAtStart() {
        var recognizer = DockGestureRecognizer()

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

    @Test
    func horizontalSwipeRequiresHorizontalBias() {
        var recognizer = DockGestureRecognizer()
        let finder = target(dockItemName: "Finder")

        _ = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.4, y: 0.4)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.6, y: 0.4)),
                ],
                timestamp: 0
            ),
            hoveredApplication: finder
        )

        #expect(
            recognizer.process(
                frame: TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.52, y: 0.55)),
                        TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.72, y: 0.53)),
                    ],
                    timestamp: 0.1
                ),
                hoveredApplication: finder
            ) == nil
        )
    }

    @Test
    func recognizerOnlyRequiresHoveredApplicationBeforeSessionStarts() {
        var recognizer = DockGestureRecognizer()
        let finder = target(dockItemName: "Finder")

        #expect(recognizer.requiresHoveredApplication)

        _ = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.3, y: 0.3)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.5, y: 0.3)),
                ],
                timestamp: 0
            ),
            hoveredApplication: finder
        )

        #expect(recognizer.requiresHoveredApplication == false)

        _ = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.35, y: 0.35)),
                ],
                timestamp: 0.1
            ),
            hoveredApplication: nil
        )

        #expect(recognizer.requiresHoveredApplication)
    }
}
