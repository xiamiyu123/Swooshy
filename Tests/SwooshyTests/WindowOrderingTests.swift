import CoreGraphics
import Foundation
import Testing
@testable import Swooshy

struct WindowOrderingTests {
    private struct TestWindow: Equatable {
        let id: String
        let descriptor: WindowOrderDescriptor
    }

    private let ordering = WindowOrdering()

    private func descriptor(_ windowID: CGWindowID?, _ frame: CGRect) -> WindowOrderDescriptor {
        WindowOrderDescriptor(windowID: windowID, frame: frame)
    }

    @Test
    func appliesFrontToBackOrderFromMatchedDescriptors() {
        let windows = [
            TestWindow(id: "B", descriptor: descriptor(2, CGRect(x: 100, y: 100, width: 600, height: 400))),
            TestWindow(id: "C", descriptor: descriptor(3, CGRect(x: 200, y: 200, width: 600, height: 400))),
            TestWindow(id: "A", descriptor: descriptor(1, CGRect(x: 0, y: 0, width: 600, height: 400))),
        ]

        let ordered = ordering.frontToBack(
            windows,
            descriptor: \.descriptor,
            using: [
                descriptor(1, CGRect(x: 0, y: 0, width: 600, height: 400)),
                descriptor(2, CGRect(x: 100, y: 100, width: 600, height: 400)),
                descriptor(3, CGRect(x: 200, y: 200, width: 600, height: 400)),
            ]
        )

        #expect(ordered.map(\.id) == ["A", "B", "C"])
    }

    @Test
    func appendsUnmatchedWindowsAfterMatchedOnes() {
        let windows = [
            TestWindow(id: "A", descriptor: descriptor(1, CGRect(x: 0, y: 0, width: 600, height: 400))),
            TestWindow(id: "B", descriptor: descriptor(2, CGRect(x: 100, y: 100, width: 600, height: 400))),
            TestWindow(id: "C", descriptor: descriptor(3, CGRect(x: 200, y: 200, width: 600, height: 400))),
        ]

        let ordered = ordering.frontToBack(
            windows,
            descriptor: \.descriptor,
            using: [
                descriptor(2, CGRect(x: 100, y: 100, width: 600, height: 400)),
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
    func toleratesSmallFrameDifferencesBetweenAxAndCgSnapshots() {
        let windows = [
            TestWindow(id: "editor", descriptor: descriptor(10, CGRect(x: 120, y: 88, width: 1438, height: 877))),
            TestWindow(id: "preview", descriptor: descriptor(11, CGRect(x: 180, y: 140, width: 960, height: 720))),
        ]

        let ordered = ordering.frontToBack(
            windows,
            descriptor: \.descriptor,
            using: [
                descriptor(11, CGRect(x: 182, y: 141, width: 958, height: 718)),
                descriptor(10, CGRect(x: 121, y: 90, width: 1440, height: 880)),
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

    private func descriptor(_ windowID: CGWindowID?, _ frame: CGRect) -> WindowOrderDescriptor {
        WindowOrderDescriptor(windowID: windowID, frame: frame)
    }

    @Test
    func forwardCyclingWalksAcrossAllWindowsInsteadOfBouncing() {
        let store = WindowCycleSessionStore<TestCycleWindow>(areEqual: { $0.id == $1.id })
        let a = TestCycleWindow(id: "a", descriptor: descriptor(1, CGRect(x: 0, y: 0, width: 500, height: 400)))
        let b = TestCycleWindow(id: "b", descriptor: descriptor(2, CGRect(x: 40, y: 40, width: 500, height: 400)))
        let c = TestCycleWindow(id: "c", descriptor: descriptor(3, CGRect(x: 80, y: 80, width: 500, height: 400)))

        let firstTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [a, b, c],
            currentWindow: a,
            direction: .forward,
            now: Date(timeIntervalSinceReferenceDate: 0)
        )
        let secondTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [b, a, c],
            currentWindow: b,
            direction: .forward,
            now: Date(timeIntervalSinceReferenceDate: 1)
        )
        let thirdTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [c, b, a],
            currentWindow: c,
            direction: .forward,
            now: Date(timeIntervalSinceReferenceDate: 2)
        )

        #expect(firstTarget?.id == "b")
        #expect(secondTarget?.id == "c")
        #expect(thirdTarget?.id == "a")
    }

    @Test
    func backwardCyclingRemainsSymmetric() {
        let store = WindowCycleSessionStore<TestCycleWindow>(areEqual: { $0.id == $1.id })
        let a = TestCycleWindow(id: "a", descriptor: descriptor(1, CGRect(x: 0, y: 0, width: 500, height: 400)))
        let b = TestCycleWindow(id: "b", descriptor: descriptor(2, CGRect(x: 40, y: 40, width: 500, height: 400)))
        let c = TestCycleWindow(id: "c", descriptor: descriptor(3, CGRect(x: 80, y: 80, width: 500, height: 400)))

        let firstTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [a, b, c],
            currentWindow: a,
            direction: .backward,
            now: Date(timeIntervalSinceReferenceDate: 0)
        )
        let secondTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [c, a, b],
            currentWindow: c,
            direction: .backward,
            now: Date(timeIntervalSinceReferenceDate: 1)
        )

        #expect(firstTarget?.id == "c")
        #expect(secondTarget?.id == "b")
    }

    @Test
    func manualWindowChangeResetsCycleSequence() {
        let store = WindowCycleSessionStore<TestCycleWindow>(areEqual: { $0.id == $1.id })
        let a = TestCycleWindow(id: "a", descriptor: descriptor(1, CGRect(x: 0, y: 0, width: 500, height: 400)))
        let b = TestCycleWindow(id: "b", descriptor: descriptor(2, CGRect(x: 40, y: 40, width: 500, height: 400)))
        let c = TestCycleWindow(id: "c", descriptor: descriptor(3, CGRect(x: 80, y: 80, width: 500, height: 400)))

        _ = store.nextTarget(
            for: processIdentifier,
            liveOrder: [a, b, c],
            currentWindow: a,
            direction: .forward,
            now: Date(timeIntervalSinceReferenceDate: 0)
        )

        let resetTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [c, b, a],
            currentWindow: c,
            direction: .forward,
            now: Date(timeIntervalSinceReferenceDate: 1)
        )

        #expect(resetTarget?.id == "b")
    }

    @Test
    func continuesCyclingWhenDifferentWindowsShareTheSameDescriptor() {
        let store = WindowCycleSessionStore<TestCycleWindow>(areEqual: { $0.id == $1.id })
        let sharedDescriptor = descriptor(nil, CGRect(x: 0, y: 30, width: 1408, height: 766))
        let a = TestCycleWindow(id: "a", descriptor: sharedDescriptor)
        let b = TestCycleWindow(id: "b", descriptor: sharedDescriptor)
        let c = TestCycleWindow(id: "c", descriptor: sharedDescriptor)

        let firstTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [a, b, c],
            currentWindow: a,
            direction: .forward,
            now: Date(timeIntervalSinceReferenceDate: 0)
        )
        let secondTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [b, a, c],
            currentWindow: b,
            direction: .forward,
            now: Date(timeIntervalSinceReferenceDate: 1)
        )
        let thirdTarget = store.nextTarget(
            for: processIdentifier,
            liveOrder: [c, b, a],
            currentWindow: c,
            direction: .forward,
            now: Date(timeIntervalSinceReferenceDate: 2)
        )

        #expect(firstTarget?.id == "b")
        #expect(secondTarget?.id == "c")
        #expect(thirdTarget?.id == "a")
    }
}
