import CoreGraphics
import Foundation
import Testing
@testable import Swooshy

private func descriptor(_ windowID: CGWindowID?, _ frame: CGRect) -> WindowOrderDescriptor {
    WindowOrderDescriptor(windowID: windowID, frame: frame)
}

private func descriptor(
    _ windowID: CGWindowID?,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat = 600,
    height: CGFloat = 400
) -> WindowOrderDescriptor {
    descriptor(
        windowID,
        CGRect(x: x, y: y, width: width, height: height)
    )
}

struct WindowOrderingTests {
    private struct TestWindow: Equatable {
        let id: String
        let descriptor: WindowOrderDescriptor
    }

    private let ordering = WindowOrdering()

    private func window(
        _ id: String,
        windowID: CGWindowID?,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat = 600,
        height: CGFloat = 400
    ) -> TestWindow {
        TestWindow(
            id: id,
            descriptor: descriptor(windowID, x: x, y: y, width: width, height: height)
        )
    }

    @Test
    func appliesFrontToBackOrderFromMatchedDescriptors() {
        let windows = [
            window("B", windowID: 2, x: 100, y: 100),
            window("C", windowID: 3, x: 200, y: 200),
            window("A", windowID: 1, x: 0, y: 0),
        ]

        let ordered = ordering.frontToBack(
            windows,
            descriptor: \.descriptor,
            using: [
                descriptor(1, x: 0, y: 0),
                descriptor(2, x: 100, y: 100),
                descriptor(3, x: 200, y: 200),
            ]
        )

        #expect(ordered.map(\.id) == ["A", "B", "C"])
    }

    @Test
    func appendsUnmatchedWindowsAfterMatchedOnes() {
        let windows = [
            window("A", windowID: 1, x: 0, y: 0),
            window("B", windowID: 2, x: 100, y: 100),
            window("C", windowID: 3, x: 200, y: 200),
        ]

        let ordered = ordering.frontToBack(
            windows,
            descriptor: \.descriptor,
            using: [
                descriptor(2, x: 100, y: 100),
            ]
        )

        #expect(ordered.map(\.id) == ["B", "A", "C"])
    }

    @Test
    func usesWindowIdentifiersToDisambiguateWindowsWithSameFrame() {
        let sharedFrame = CGRect(x: 40, y: 80, width: 900, height: 700)
        let windows = [
            TestWindow(id: "report", descriptor: descriptor(90, sharedFrame)),
            TestWindow(id: "notes", descriptor: descriptor(91, sharedFrame)),
        ]

        let ordered = ordering.frontToBack(
            windows,
            descriptor: \.descriptor,
            using: [
                descriptor(91, sharedFrame),
                descriptor(90, sharedFrame),
            ]
        )

        #expect(ordered.map(\.id) == ["notes", "report"])
    }

    @Test
    func keepsInputOrderWhenMatchesTie() {
        let sharedFrame = CGRect(x: 40, y: 80, width: 900, height: 700)
        let windows = [
            TestWindow(id: "report", descriptor: descriptor(nil, sharedFrame)),
            TestWindow(id: "notes", descriptor: descriptor(nil, sharedFrame)),
        ]

        let ordered = ordering.frontToBack(
            windows,
            descriptor: \.descriptor,
            using: [
                descriptor(nil, sharedFrame),
            ]
        )

        #expect(ordered.map(\.id) == ["report", "notes"])
    }

    @Test
    func toleratesSmallFrameDifferencesBetweenAxAndCgSnapshots() {
        let windows = [
            window("editor", windowID: 10, x: 120, y: 88, width: 1438, height: 877),
            window("preview", windowID: 11, x: 180, y: 140, width: 960, height: 720),
        ]

        let ordered = ordering.frontToBack(
            windows,
            descriptor: \.descriptor,
            using: [
                descriptor(11, x: 182, y: 141, width: 958, height: 718),
                descriptor(10, x: 121, y: 90, width: 1440, height: 880),
            ]
        )

        #expect(ordered.map(\.id) == ["preview", "editor"])
    }
}

@MainActor
struct WindowCycleSessionStoreTests {
    private let processIdentifier: pid_t = 42

    private struct TestCycleWindow {
        let id: String
        let descriptor: WindowOrderDescriptor
    }

    private func makeStore() -> WindowCycleSessionStore<TestCycleWindow> {
        WindowCycleSessionStore(areEqual: { $0.id == $1.id })
    }

    private func cycleWindow(_ id: String, windowID: CGWindowID, x: CGFloat, y: CGFloat) -> TestCycleWindow {
        TestCycleWindow(
            id: id,
            descriptor: descriptor(windowID, x: x, y: y, width: 500, height: 400)
        )
    }

    @Test
    func forwardCyclingWalksAcrossAllWindowsInsteadOfBouncing() {
        let store = makeStore()
        let a = cycleWindow("a", windowID: 1, x: 0, y: 0)
        let b = cycleWindow("b", windowID: 2, x: 40, y: 40)
        let c = cycleWindow("c", windowID: 3, x: 80, y: 80)

        let firstTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [a, b, c],
            currentWindow: a,
            direction: .forward,
            now: time(0)
        )
        let secondTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [b, a, c],
            currentWindow: b,
            direction: .forward,
            now: time(1)
        )
        let thirdTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [c, b, a],
            currentWindow: c,
            direction: .forward,
            now: time(2)
        )

        #expect(firstTarget?.id == "b")
        #expect(secondTarget?.id == "c")
        #expect(thirdTarget?.id == "a")
    }

    @Test
    func backwardCyclingRemainsSymmetric() {
        let store = makeStore()
        let a = cycleWindow("a", windowID: 1, x: 0, y: 0)
        let b = cycleWindow("b", windowID: 2, x: 40, y: 40)
        let c = cycleWindow("c", windowID: 3, x: 80, y: 80)

        let firstTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [a, b, c],
            currentWindow: a,
            direction: .backward,
            now: time(0)
        )
        let secondTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [c, a, b],
            currentWindow: c,
            direction: .backward,
            now: time(1)
        )

        #expect(firstTarget?.id == "c")
        #expect(secondTarget?.id == "b")
    }

    @Test
    func manualWindowChangeResetsCycleSequence() {
        let store = makeStore()
        let a = cycleWindow("a", windowID: 1, x: 0, y: 0)
        let b = cycleWindow("b", windowID: 2, x: 40, y: 40)
        let c = cycleWindow("c", windowID: 3, x: 80, y: 80)

        _ = store.nextTarget(
            for: processIdentifier,
            liveOrder: [a, b, c],
            currentWindow: a,
            direction: .forward,
            now: time(0)
        )

        let resetTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [c, b, a],
            currentWindow: c,
            direction: .forward,
            now: time(1)
        )

        #expect(resetTarget?.id == "b")
    }

    @Test
    func continuesCyclingWhenDifferentWindowsShareTheSameDescriptor() {
        let store = makeStore()
        let sharedDescriptor = descriptor(nil, CGRect(x: 0, y: 30, width: 1408, height: 766))
        let a = TestCycleWindow(id: "a", descriptor: sharedDescriptor)
        let b = TestCycleWindow(id: "b", descriptor: sharedDescriptor)
        let c = TestCycleWindow(id: "c", descriptor: sharedDescriptor)

        let firstTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [a, b, c],
            currentWindow: a,
            direction: .forward,
            now: time(0)
        )
        let secondTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [b, a, c],
            currentWindow: b,
            direction: .forward,
            now: time(1)
        )
        let thirdTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [c, b, a],
            currentWindow: c,
            direction: .forward,
            now: time(2)
        )

        #expect(firstTarget?.id == "b")
        #expect(secondTarget?.id == "c")
        #expect(thirdTarget?.id == "a")
    }

    private func time(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }
}
