import CoreGraphics
import CMultitouchShim
import Foundation
import Testing
@testable import Swooshy

struct DockSwipeGestureRecognizerTests {
    private final class DeferredDrainScheduler {
        private var operations: [@MainActor () -> Void] = []

        var scheduledCount: Int {
            operations.count
        }

        func schedule(_ operation: @escaping @MainActor () -> Void) {
            operations.append(operation)
        }

        func runAll() {
            while operations.isEmpty == false {
                let operation = operations.removeFirst()
                MainActor.assumeIsolated {
                    operation()
                }
            }
        }
    }

    private func expect(_ point: CGPoint, approximatelyEquals expected: CGPoint) {
        #expect(abs(point.x - expected.x) < 0.0001)
        #expect(abs(point.y - expected.y) < 0.0001)
    }

    private func target(
        dockItemName: String,
        resolvedApplicationName: String? = nil,
        processIdentifier: pid_t = 42,
        bundleIdentifier: String? = nil,
        aliases: [String] = []
    ) -> InteractionTarget {
        let appIdentity = AppIdentity(
            bundleURL: URL(fileURLWithPath: "/Applications/\((resolvedApplicationName ?? dockItemName)).app"),
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            localizedName: resolvedApplicationName ?? dockItemName
        )!
        _ = aliases
        return .application(appIdentity, source: .dockAppItem(DockItemHandle()))
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

    @Test
    func predictedEventMatchesSwipeWithoutMutatingRecognizerState() {
        var recognizer = DockGestureRecognizer()
        let finder = target(dockItemName: "Finder")
        let startFrame = TrackpadTouchFrame(
            touches: [
                TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.3, y: 0.3)),
                TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.5, y: 0.3)),
            ],
            timestamp: 0
        )
        let swipeFrame = TrackpadTouchFrame(
            touches: [
                TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.45, y: 0.31)),
                TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.65, y: 0.3)),
            ],
            timestamp: 0.1
        )

        _ = recognizer.process(frame: startFrame, hoveredApplication: finder)

        #expect(
            recognizer.predictedEvent(
                frame: swipeFrame,
                hoveredApplication: nil
            ) == .swipeRight(application: finder)
        )
        #expect(
            recognizer.process(
                frame: swipeFrame,
                hoveredApplication: nil
            ) == .swipeRight(application: finder)
        )
    }

    @Test
    func predictedEventReturnsNilWhenGestureWouldNotTrigger() {
        var recognizer = DockGestureRecognizer()
        let finder = target(dockItemName: "Finder")

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

        #expect(
            recognizer.predictedEvent(
                frame: TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.32, y: 0.31)),
                        TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.52, y: 0.31)),
                    ],
                    timestamp: 0.1
                ),
                hoveredApplication: nil
            ) == nil
        )
    }

    @Test
    func titleBarCornerDragRecognizerActivatesAfterLongPressBeforeMovement() {
        var recognizer = TitleBarCornerDragRecognizer()
        let finder = target(dockItemName: "Finder")

        #expect(
            recognizer.process(
                frame: TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.4, y: 0.4)),
                        TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.55, y: 0.4)),
                    ],
                    timestamp: 0
                ),
                hoveredApplication: finder
            ) == nil
        )

        let event = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.402, y: 0.4)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.552, y: 0.402)),
                ],
                timestamp: 1.6
            ),
            hoveredApplication: finder
        )

        guard case .began(let application, let startAveragePoint, let currentAveragePoint) = event else {
            Issue.record("Expected corner drag recognizer to begin after the hold threshold")
            return
        }
        #expect(application == finder)
        expect(startAveragePoint, approximatelyEquals: CGPoint(x: 0.475, y: 0.4))
        expect(currentAveragePoint, approximatelyEquals: CGPoint(x: 0.477, y: 0.401))

        #expect(recognizer.isActive)
    }

    @Test
    func titleBarCornerDragRecognizerOnlyRequiresHoveredApplicationBeforeSessionStarts() {
        var recognizer = TitleBarCornerDragRecognizer()
        let finder = target(dockItemName: "Finder")

        #expect(recognizer.requiresHoveredApplication)

        _ = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.4, y: 0.4)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.55, y: 0.4)),
                ],
                timestamp: 0
            ),
            hoveredApplication: finder
        )

        #expect(recognizer.requiresHoveredApplication == false)

        _ = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [],
                timestamp: 0.2
            ),
            hoveredApplication: nil
        )

        #expect(recognizer.requiresHoveredApplication)
    }

    @Test
    func titleBarCornerDragRecognizerActivatesOnFirstDragFrameAfterHoldThreshold() {
        var recognizer = TitleBarCornerDragRecognizer()
        let finder = target(dockItemName: "Finder")

        _ = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.4, y: 0.4)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.55, y: 0.4)),
                ],
                timestamp: 0
            ),
            hoveredApplication: finder
        )

        let event = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.47, y: 0.41)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.62, y: 0.41)),
                ],
                timestamp: 1.55
            ),
            hoveredApplication: finder
        )

        guard case .began(let application, let startAveragePoint, let currentAveragePoint) = event else {
            Issue.record("Expected the first post-hold drag frame to activate corner drag mode")
            return
        }
        #expect(application == finder)
        expect(startAveragePoint, approximatelyEquals: CGPoint(x: 0.475, y: 0.4))
        expect(currentAveragePoint, approximatelyEquals: CGPoint(x: 0.545, y: 0.41))
    }

    @Test
    func titleBarCornerDragRecognizerResetsHoldWhenFingersMoveTooSoon() {
        var recognizer = TitleBarCornerDragRecognizer()
        let finder = target(dockItemName: "Finder")

        _ = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.4, y: 0.4)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.55, y: 0.4)),
                ],
                timestamp: 0
            ),
            hoveredApplication: finder
        )

        #expect(
            recognizer.process(
                frame: TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.46, y: 0.4)),
                        TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.61, y: 0.4)),
                    ],
                    timestamp: 0.1
                ),
                hoveredApplication: finder
            ) == nil
        )

        #expect(
            recognizer.process(
                frame: TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.462, y: 0.4)),
                        TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.612, y: 0.401)),
                    ],
                    timestamp: 1.7
                ),
                hoveredApplication: finder
            ) == .began(
                application: finder,
                startAveragePoint: CGPoint(x: 0.535, y: 0.4),
                currentAveragePoint: CGPoint(x: 0.537, y: 0.4005)
            )
        )
    }

    @Test
    func titleBarCornerDragRecognizerReportsChangedTouchTranslationWhileActive() {
        var recognizer = TitleBarCornerDragRecognizer()
        let finder = target(dockItemName: "Finder")

        _ = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.4, y: 0.4)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.55, y: 0.4)),
                ],
                timestamp: 0
            ),
            hoveredApplication: finder
        )
        _ = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.402, y: 0.4)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.552, y: 0.402)),
                ],
                timestamp: 1.6
            ),
            hoveredApplication: finder
        )

        let event = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.34, y: 0.48)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.49, y: 0.5)),
                ],
                timestamp: 1.7
            ),
            hoveredApplication: finder
        )

        guard case .changed(let application, let startAveragePoint, let currentAveragePoint) = event else {
            Issue.record("Expected active corner drag recognizer to report changed touch positions")
            return
        }
        #expect(application == finder)
        expect(startAveragePoint, approximatelyEquals: CGPoint(x: 0.475, y: 0.4))
        expect(currentAveragePoint, approximatelyEquals: CGPoint(x: 0.415, y: 0.49))
    }

    @Test
    func cornerDragActionUsesDiagonalTouchTranslation() {
        #expect(
            cornerDragAction(
                forTouchTranslation: CGPoint(x: -0.09, y: 0.08),
                threshold: 0.06
            ) == .topLeftQuarter
        )
        #expect(
            cornerDragAction(
                forTouchTranslation: CGPoint(x: 0.1, y: 0.09),
                threshold: 0.06
            ) == .topRightQuarter
        )
        #expect(
            cornerDragAction(
                forTouchTranslation: CGPoint(x: -0.08, y: -0.1),
                threshold: 0.06
            ) == .bottomLeftQuarter
        )
        #expect(
            cornerDragAction(
                forTouchTranslation: CGPoint(x: 0.09, y: -0.08),
                threshold: 0.06
            ) == .bottomRightQuarter
        )
        #expect(
            cornerDragAction(
                forTouchTranslation: CGPoint(x: 0.12, y: 0.02),
                threshold: 0.06
            ) == nil
        )
    }

    @Test
    func cornerDragTransitionUsesCurrentCornerAsReference() {
        #expect(
            cornerDragTransitionAction(
                from: .topRightQuarter,
                forTouchTranslation: CGPoint(x: 0.01, y: -0.09),
                threshold: 0.06
            ) == .bottomRightQuarter
        )
        #expect(
            cornerDragTransitionAction(
                from: .bottomRightQuarter,
                forTouchTranslation: CGPoint(x: -0.08, y: 0.02),
                threshold: 0.06
            ) == .bottomLeftQuarter
        )
        #expect(
            cornerDragTransitionAction(
                from: .bottomLeftQuarter,
                forTouchTranslation: CGPoint(x: 0.02, y: 0.1),
                threshold: 0.06
            ) == .topLeftQuarter
        )
        #expect(
            cornerDragTransitionAction(
                from: .topLeftQuarter,
                forTouchTranslation: CGPoint(x: 0.03, y: 0.01),
                threshold: 0.06
            ) == .topLeftQuarter
        )
    }

    @Test
    func titleBarCornerDragRecognizerEndsWhenTouchesLift() {
        var recognizer = TitleBarCornerDragRecognizer()
        let finder = target(dockItemName: "Finder")

        _ = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.4, y: 0.4)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.55, y: 0.4)),
                ],
                timestamp: 0
            ),
            hoveredApplication: finder
        )
        _ = recognizer.process(
            frame: TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.4, y: 0.4)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.55, y: 0.4)),
                ],
                timestamp: 1.6
            ),
            hoveredApplication: finder
        )

        #expect(
            recognizer.process(
                frame: TrackpadTouchFrame(
                    touches: [],
                    timestamp: 1.7
                ),
                hoveredApplication: nil
            ) == .ended(application: finder)
        )
        #expect(recognizer.isActive == false)
    }

    @Test
    func twoFingerTouchSequenceTrackerFlagsFreshContactsWithoutLiftFrames() {
        var tracker = TwoFingerTouchSequenceTracker()

        #expect(
            tracker.consume(
                TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.4, y: 0.4)),
                        TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.6, y: 0.4)),
                    ],
                    timestamp: 0
                )
            ) == .none
        )

        #expect(
            tracker.consume(
                TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 7, position: CGPoint(x: 0.45, y: 0.45)),
                        TrackpadTouchSample(identifier: 8, position: CGPoint(x: 0.65, y: 0.45)),
                    ],
                    timestamp: 0.2
                )
            ) == .restarted(previousIdentifiers: [1, 2], currentIdentifiers: [7, 8])
        )
    }

    @Test
    func twoFingerTouchSequenceTrackerFlagsWhenOneFingerChangesWithoutLift() {
        var tracker = TwoFingerTouchSequenceTracker()

        #expect(
            tracker.consume(
                TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.4, y: 0.4)),
                        TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.6, y: 0.4)),
                    ],
                    timestamp: 0
                )
            ) == .none
        )

        #expect(
            tracker.consume(
                TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.45, y: 0.45)),
                        TrackpadTouchSample(identifier: 8, position: CGPoint(x: 0.65, y: 0.45)),
                    ],
                    timestamp: 0.2
                )
            ) == .restarted(previousIdentifiers: [1, 2], currentIdentifiers: [1, 8])
        )
    }

    @Test
    func twoFingerTouchSequenceTrackerResetsAfterExplicitLift() {
        var tracker = TwoFingerTouchSequenceTracker()

        _ = tracker.consume(
            TrackpadTouchFrame(
                touches: [
                    TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.4, y: 0.4)),
                    TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.6, y: 0.4)),
                ],
                timestamp: 0
            )
        )

        #expect(
            tracker.consume(
                TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.42, y: 0.42)),
                    ],
                    timestamp: 0.1
                )
            ) == .none
        )

        #expect(
            tracker.consume(
                TrackpadTouchFrame(
                    touches: [
                        TrackpadTouchSample(identifier: 7, position: CGPoint(x: 0.45, y: 0.45)),
                        TrackpadTouchSample(identifier: 8, position: CGPoint(x: 0.65, y: 0.45)),
                    ],
                    timestamp: 0.2
                )
            ) == .none
        )
    }

    @Test
    func pendingReleaseGestureCancelsWhenAThirdFingerInterrupts() {
        #expect(
            gestureSessionTouchInterruption(
                touchCount: 3,
                previousTouchCount: 2,
                hasPendingReleaseAction: true,
                hasActiveCornerDrag: false
            ) == .invalidAdditionalTouch
        )
    }

    @Test
    func activeCornerDragCancelsWhenAThirdFingerInterrupts() {
        #expect(
            gestureSessionTouchInterruption(
                touchCount: 3,
                previousTouchCount: 2,
                hasPendingReleaseAction: false,
                hasActiveCornerDrag: true
            ) == .invalidAdditionalTouch
        )
    }

    @Test
    func gestureHoverLookupRequiredWhileEitherRecognizerStillNeedsHoverCapture() {
        #expect(
            gestureHoverLookupRequired(
                gesturesEnabled: true,
                standardRecognizerRequiresHoveredApplication: true,
                cornerDragEnabled: true,
                cornerDragRecognizerRequiresHoveredApplication: false,
                hasActiveCornerDragApplication: false
            )
        )
        #expect(
            gestureHoverLookupRequired(
                gesturesEnabled: true,
                standardRecognizerRequiresHoveredApplication: false,
                cornerDragEnabled: true,
                cornerDragRecognizerRequiresHoveredApplication: true,
                hasActiveCornerDragApplication: false
            )
        )
        #expect(
            gestureHoverLookupRequired(
                gesturesEnabled: true,
                standardRecognizerRequiresHoveredApplication: false,
                cornerDragEnabled: true,
                cornerDragRecognizerRequiresHoveredApplication: false,
                hasActiveCornerDragApplication: false
            ) == false
        )
    }

    @Test
    func gestureHoverLookupSkipsWorkWhenCornerDragSessionIsAlreadyActive() {
        #expect(
            gestureHoverLookupRequired(
                gesturesEnabled: true,
                standardRecognizerRequiresHoveredApplication: true,
                cornerDragEnabled: true,
                cornerDragRecognizerRequiresHoveredApplication: true,
                hasActiveCornerDragApplication: true
            ) == false
        )
        #expect(
            gestureHoverLookupRequired(
                gesturesEnabled: false,
                standardRecognizerRequiresHoveredApplication: true,
                cornerDragEnabled: true,
                cornerDragRecognizerRequiresHoveredApplication: true,
                hasActiveCornerDragApplication: false
            ) == false
        )
    }

    @Test
    func twoFingerReleaseStillExecutesOnLift() {
        #expect(
            gestureSessionTouchInterruption(
                touchCount: 1,
                previousTouchCount: 2,
                hasPendingReleaseAction: true,
                hasActiveCornerDrag: false
            ) == .release
        )
    }

    @MainActor
    @Test
    func multitouchMonitorDeliversZeroTouchFramesWhenCallbackPayloadIsNil() {
        let scheduler = DeferredDrainScheduler()
        let monitor = MultitouchInputMonitor(scheduleDrain: { operation in
            scheduler.schedule(operation)
        })
        var deliveredFrames: [TrackpadTouchFrame] = []
        monitor.onFrame = { deliveredFrames.append($0) }

        monitor.receiveCallbackPayload(
            fingers: nil,
            fingerCount: 0,
            timestamp: 1.25
        )
        monitor.receiveCallbackPayload(
            fingers: nil,
            fingerCount: 0,
            timestamp: 1.5
        )

        scheduler.runAll()

        #expect(deliveredFrames.count == 1)
        #expect(deliveredFrames.first?.touches == [])
        #expect(deliveredFrames.first?.timestamp == 1.25)
    }

    @MainActor
    @Test
    func multitouchMonitorCoalescesBurstCallbacksIntoOneScheduledDrain() {
        let scheduler = DeferredDrainScheduler()
        let monitor = MultitouchInputMonitor(scheduleDrain: { operation in
            scheduler.schedule(operation)
        })
        var deliveredFrames: [TrackpadTouchFrame] = []
        monitor.onFrame = { deliveredFrames.append($0) }

        withUnsafeTemporaryAllocation(of: SwooshyMTFinger.self, capacity: 2) { buffer in
            buffer.initialize(repeating: SwooshyMTFinger())
            buffer[0].identifier = 1
            buffer[1].identifier = 2

            buffer[0].normalized.position = SwooshyMTPoint(x: 0.20, y: 0.30)
            buffer[1].normalized.position = SwooshyMTPoint(x: 0.40, y: 0.50)
            monitor.receiveCallbackPayload(
                fingers: buffer.baseAddress,
                fingerCount: 2,
                timestamp: 1.0
            )

            buffer[0].normalized.position = SwooshyMTPoint(x: 0.60, y: 0.70)
            buffer[1].normalized.position = SwooshyMTPoint(x: 0.80, y: 0.90)
            monitor.receiveCallbackPayload(
                fingers: buffer.baseAddress,
                fingerCount: 2,
                timestamp: 2.0
            )
        }

        #expect(scheduler.scheduledCount == 1)
        #expect(deliveredFrames.isEmpty)

        scheduler.runAll()

        #expect(deliveredFrames.count == 1)
        #expect(deliveredFrames.first?.timestamp == 2.0)
        #expect(deliveredFrames.first?.touches.count == 2)
        expect(deliveredFrames.first?.touches[0].position ?? .zero, approximatelyEquals: CGPoint(x: 0.60, y: 0.70))
        expect(deliveredFrames.first?.touches[1].position ?? .zero, approximatelyEquals: CGPoint(x: 0.80, y: 0.90))
    }

    @MainActor
    @Test
    func multitouchMonitorPreservesReleaseTransitionBeforeImmediateRetrigger() {
        let scheduler = DeferredDrainScheduler()
        let monitor = MultitouchInputMonitor(scheduleDrain: { operation in
            scheduler.schedule(operation)
        })
        var deliveredFrames: [TrackpadTouchFrame] = []
        monitor.onFrame = { deliveredFrames.append($0) }

        withUnsafeTemporaryAllocation(of: SwooshyMTFinger.self, capacity: 2) { buffer in
            buffer.initialize(repeating: SwooshyMTFinger())
            buffer[0].identifier = 1
            buffer[1].identifier = 2

            buffer[0].normalized.position = SwooshyMTPoint(x: 0.20, y: 0.30)
            buffer[1].normalized.position = SwooshyMTPoint(x: 0.40, y: 0.50)
            monitor.receiveCallbackPayload(
                fingers: buffer.baseAddress,
                fingerCount: 2,
                timestamp: 1.0
            )

            monitor.receiveCallbackPayload(
                fingers: nil,
                fingerCount: 0,
                timestamp: 1.1
            )

            buffer[0].identifier = 7
            buffer[1].identifier = 8
            buffer[0].normalized.position = SwooshyMTPoint(x: 0.60, y: 0.70)
            buffer[1].normalized.position = SwooshyMTPoint(x: 0.80, y: 0.90)
            monitor.receiveCallbackPayload(
                fingers: buffer.baseAddress,
                fingerCount: 2,
                timestamp: 1.2
            )
        }

        scheduler.runAll()

        #expect(deliveredFrames.count == 3)
        #expect(deliveredFrames.map(\.touches.count) == [2, 0, 2])
        #expect(deliveredFrames.map(\.timestamp) == [1.0, 1.1, 1.2])
    }

    @MainActor
    @Test
    func multitouchMonitorDropsPendingFramesAfterStop() {
        let scheduler = DeferredDrainScheduler()
        let monitor = MultitouchInputMonitor(scheduleDrain: { operation in
            scheduler.schedule(operation)
        })
        var deliveredFrames: [TrackpadTouchFrame] = []
        monitor.onFrame = { deliveredFrames.append($0) }

        withUnsafeTemporaryAllocation(of: SwooshyMTFinger.self, capacity: 2) { buffer in
            buffer.initialize(repeating: SwooshyMTFinger())
            buffer[0].identifier = 1
            buffer[1].identifier = 2
            buffer[0].normalized.position = SwooshyMTPoint(x: 0.15, y: 0.25)
            buffer[1].normalized.position = SwooshyMTPoint(x: 0.35, y: 0.45)

            monitor.receiveCallbackPayload(
                fingers: buffer.baseAddress,
                fingerCount: 2,
                timestamp: 3.0
            )
        }

        #expect(scheduler.scheduledCount == 1)

        monitor.stop()
        scheduler.runAll()

        #expect(deliveredFrames.isEmpty)
    }
}
