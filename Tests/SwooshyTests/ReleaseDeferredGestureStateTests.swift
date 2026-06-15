import CoreGraphics
import Foundation
import Testing
@testable import Swooshy

struct ReleaseDeferredGestureStateTests {
    @Test
    func stagedActionCanBeTakenOnce() {
        let target = makeTarget()
        var state = ReleaseDeferredGestureState()

        state.stageDockAction(
            .minimizeWindow,
            application: target,
            gesture: .swipeLeft,
            touches: touches(at: CGPoint(x: 0.8, y: 0.5))
        )

        #expect(state.hasAction)
        #expect(state.hasGestureAnchor)
        #expect(state.actionKind == .dock)

        guard let pending = state.takeAction() else {
            Issue.record("Expected staged action")
            return
        }
        #expect(pending.gesture == .swipeLeft)
        if case .dock(let action, let application) = pending.action {
            #expect(action == .minimizeWindow)
            #expect(application == target)
        } else {
            Issue.record("Expected staged dock action")
        }

        #expect(!state.hasAction)
        #expect(!state.hasGestureAnchor)
        #expect(state.takeAction() == nil)
    }

    @Test
    func clearRemovesActionAndGestureAnchor() {
        let target = makeTarget()
        var state = ReleaseDeferredGestureState()

        state.stageTitleBarAction(
            .quitApplication,
            event: .pinchIn(application: target),
            anchorPoint: CGPoint(x: 20, y: 40),
            replacesWithTabClose: false,
            touches: [
                TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.3, y: 0.5)),
                TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.7, y: 0.5)),
            ]
        )

        state.clear()

        #expect(!state.hasAction)
        #expect(!state.hasGestureAnchor)
        #expect(state.actionKind == nil)
        #expect(state.takeAction() == nil)
    }

    @Test
    func swipeReverseMovementCancelsAfterHighWaterMarkRetreat() {
        let target = makeTarget()
        var state = ReleaseDeferredGestureState()

        state.stageDockAction(
            .minimizeWindow,
            application: target,
            gesture: .swipeLeft,
            touches: touches(at: CGPoint(x: 0.8, y: 0.5))
        )

        #expect(state.reverseCancellationGesture(
            for: frame(touches: touches(at: CGPoint(x: 0.65, y: 0.5))),
            threshold: 0.04
        ) == nil)
        #expect(state.reverseCancellationGesture(
            for: frame(touches: touches(at: CGPoint(x: 0.75, y: 0.5))),
            threshold: 0.04
        ) == .swipeLeft)
    }

    @Test
    func pinchReverseMovementCancelsAfterDistanceRetreat() {
        let target = makeTarget()
        var state = ReleaseDeferredGestureState()

        state.stageDockAction(
            .closeWindow,
            application: target,
            gesture: .pinchOut,
            touches: [
                TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.4, y: 0.5)),
                TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.6, y: 0.5)),
            ]
        )

        #expect(state.reverseCancellationGesture(
            for: frame(touches: [
                TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.25, y: 0.5)),
                TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.75, y: 0.5)),
            ]),
            threshold: 0.04
        ) == nil)
        #expect(state.reverseCancellationGesture(
            for: frame(touches: [
                TrackpadTouchSample(identifier: 1, position: CGPoint(x: 0.325, y: 0.5)),
                TrackpadTouchSample(identifier: 2, position: CGPoint(x: 0.675, y: 0.5)),
            ]),
            threshold: 0.04
        ) == .pinchOut)
    }

    private func makeTarget() -> InteractionTarget {
        let appIdentity = AppIdentity(
            bundleURL: URL(fileURLWithPath: "/Applications/Canvas.app"),
            bundleIdentifier: "com.example.Canvas",
            processIdentifier: 42,
            localizedName: "Canvas"
        )!
        return .application(appIdentity, source: .dockAppItem(DockItemHandle()))
    }

    private func touches(at midpoint: CGPoint) -> [TrackpadTouchSample] {
        [
            TrackpadTouchSample(
                identifier: 1,
                position: CGPoint(x: midpoint.x, y: midpoint.y - 0.05)
            ),
            TrackpadTouchSample(
                identifier: 2,
                position: CGPoint(x: midpoint.x, y: midpoint.y + 0.05)
            ),
        ]
    }

    private func frame(touches: [TrackpadTouchSample]) -> TrackpadTouchFrame {
        TrackpadTouchFrame(touches: touches, timestamp: 1)
    }
}
