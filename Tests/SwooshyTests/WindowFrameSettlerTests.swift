import CoreGraphics
import Testing
@testable import Swooshy

@MainActor
struct WindowFrameSettlerTests {
    @Test
    func moveOnlyWindowWaitsForPresentationWithoutASizeSetter() async throws {
        let window = DeferredNativeWindow(frame: CGRect(x: 301, y: 110, width: 860, height: 672))
        let target = CGRect(x: 548, y: 126, width: 860, height: 672)
        let actual = try await WindowFrameSettler(
            now: { window.time }, sleep: { window.time += $0 }
        ).apply(
            target, writePosition: { window.move(to: $0) }, writeSize: nil,
            read: { window.logical },
            readPresentedFrame: {
                if let pending = window.pending, window.time + 0.0001 >= pending.at {
                    window.presented = pending.frame
                    window.pending = nil
                }
                return window.presented
            }
        )
        #expect(actual == target)
        #expect(window.presented == target)
        #expect(window.writes.map(\.attribute) == ["position"])
        #expect(window.time >= 0.1)
    }

    @Test
    func expansionWaitsForPresentedPositionBeforeResizing() async throws {
        // Chrome reported the new AX origin while its visible window was still
        // at the old origin; resizing there clipped 1408 down to 712 points.
        let window = DeferredNativeWindow(frame: CGRect(x: 696, y: 401, width: 712, height: 395))
        let target = CGRect(x: 0, y: 30, width: 1408, height: 768)
        let actual = try await window.apply(target)
        #expect(actual == target)
        #expect(window.presented == target)
        #expect(window.writes.map(\.attribute) == ["position", "size"])
        #expect(window.writes[1].time >= 0.1)
    }

    @Test
    func shrinkingConfirmsSizeBeforeMovingToBottomRight() async throws {
        let window = DeferredNativeWindow(frame: CGRect(x: 0, y: 30, width: 1408, height: 768))
        let target = CGRect(x: 704, y: 414, width: 704, height: 384)
        #expect(try await window.apply(target) == target)
        #expect(window.writes.map(\.attribute) == ["size", "position"])
        #expect(window.writes[1].time >= 0.1)
    }

    @Test
    func jointBottomRightTransitionMovesAndShrinksTogetherAndReleaseReusesIt() async throws {
        let desktop = CGRect(x: 0, y: 83, width: 1408, height: 768)
        let window = DeferredNativeWindow(frame: CGRect(x: 0, y: 30, width: 1408, height: 768))
        let caption = "分支 · 解释栈帧与寄存器保存"
        let match = WindowFrameSnapshot.Match.resolve(
            windowID: nil, ownerPID: 66517,
            title: caption + " - 属于未命名群组 - 内存用量高 - 1.2 GB - Google Chrome",
            frame: window.logical,
            windows: [.init(id: 7418, ownerPID: 66517, title: caption, frame: window.presented)],
            applicationName: "Google Chrome"
        )
        #expect(match.windowID == 7418)
        let animationControl = WindowFrameAnimationControl(
            readEnabled: { _ in window.enhancedUI },
            writeEnabled: { _, enabled in window.enhancedUI = enabled; return .success }
        )
        var frames: [CGRect] = []
        var observations = 0
        let clock = DockingAnimationClock()
        let session = SmoothDockingSession(
            originalFrame: desktop, desktopFrame: desktop, baseSizeConstraints: .init(),
            loadCurrentFrame: { desktop },
            animateFrame: { target in
                #expect(!window.enhancedUI)
                let axTarget = CGRect(x: target.minX, y: 881 - target.maxY, width: target.width, height: target.height)
                window.resize(to: axTarget.size)
                window.move(to: axTarget.origin)
                frames.append(window.presented)
            },
            animationNow: { clock.now },
            animationSleep: { try await clock.sleep(until: $0) },
            beginTransition: { try animationControl.begin(for: 66517) },
            endTransition: { animationControl.end(for: 66517) },
            applyFrame: { target in
                let axTarget = CGRect(x: target.minX, y: 881 - target.maxY, width: target.width, height: target.height)
                let actual = try await window.apply(axTarget)
                return CGRect(x: actual.minX, y: 881 - actual.maxY, width: actual.width, height: actual.height)
            },
            recordConstraintObservation: { _, _, _ in observations += 1 }
        )
        session.update(action: .bottomRightQuarter)
        for _ in 0..<20 { session.update(action: .bottomRightQuarter) }
        #expect(try await session.commit() == CGRect(x: 704, y: 83, width: 704, height: 384))
        let writesAtArrival = window.writes.count
        _ = try await session.commit()
        session.finish()
        let first = try #require(frames.first)
        #expect(first.minX > 0 && first.minY > 30)
        #expect(first.width < desktop.width && first.height < desktop.height)
        #expect(frames.count > 2)
        #expect(frames.allSatisfy { abs($0.maxX - 1408) <= 1 && abs($0.maxY - 798) <= 1 })
        #expect(window.writes.count == writesAtArrival)
        #expect(window.presented == CGRect(x: 704, y: 414, width: 704, height: 384))
        #expect(window.enhancedUI)
        #expect(observations == 0)
    }

    @Test
    func matchingFrameDoesNotWrite() async throws {
        let frame = CGRect(x: 704, y: 414, width: 704, height: 384)
        let window = DeferredNativeWindow(frame: frame)
        #expect(try await window.apply(frame) == frame)
        #expect(window.writes.isEmpty)
    }

    @Test
    func matchingAXFrameStillWaitsForPendingPresentation() async throws {
        let target = CGRect(x: 0, y: 30, width: 1408, height: 768)
        let window = DeferredNativeWindow(frame: CGRect(x: 696, y: 401, width: 712, height: 395))
        window.logical = target
        window.pending = (0.1, target)
        #expect(try await window.apply(target) == target)
        #expect(window.presented == target)
        #expect(window.time >= 0.1)
        #expect(window.writes.isEmpty)
    }

    @Test
    func stableSizeClampRequiresTwoSizeRequests() async throws {
        var time = 0.0
        var current = CGRect(x: 0, y: 30, width: 800, height: 700)
        var sizes = 0
        var positions = 0
        let target = CGRect(x: 0, y: 30, width: 704, height: 384)
        let actual = try await WindowFrameSettler(now: { time }, sleep: { time += $0 }).apply(
            target,
            writePosition: { current.origin = $0; positions += 1 },
            writeSize: { _ in current.size = CGSize(width: 820, height: 580); sizes += 1 },
            read: { current }
        )
        #expect(actual.size == CGSize(width: 820, height: 580))
        #expect(sizes == 2)
        #expect(positions == 0)
        #expect(time >= 0.4)
    }

    @Test
    func changingSizeResultsAreNotCachedAsConstraints() async {
        var time = 0.0
        var current = CGRect(x: 0, y: 30, width: 712, height: 395)
        var sizes = 0
        await #expect(throws: WindowManagerError.self) {
            try await WindowFrameSettler(now: { time }, sleep: { time += $0 }).apply(
                CGRect(x: 0, y: 30, width: 1408, height: 768),
                writePosition: { current.origin = $0 },
                writeSize: { _ in sizes += 1; current.size = CGSize(width: 712, height: 395 + sizes * 6) },
                read: { current }
            )
        }
        #expect(sizes == 2)
    }

    @Test
    func missingPinnedWindowDoesNotFallBackToAnotherWindowOrResize() async {
        var time = 0.0
        var current = CGRect(x: 704, y: 30, width: 704, height: 384)
        var sizes = 0
        await #expect(throws: WindowManagerError.self) {
            try await WindowFrameSettler(now: { time }, sleep: { time += $0 }).apply(
                CGRect(x: 0, y: 30, width: 1408, height: 768),
                writePosition: { current.origin = $0 }, writeSize: { _ in sizes += 1 },
                read: { current }, readPresentedFrame: { nil }
            )
        }
        #expect(sizes == 0)
        #expect(time == 0.5)
    }

    @Test
    func onePointSizeDifferenceIsAcceptedWithoutAnotherSizeWrite() async throws {
        let window = DeferredNativeWindow(frame: CGRect(x: 0, y: 30, width: 1408, height: 767))
        let actual = try await window.apply(CGRect(x: 0, y: 30, width: 1408, height: 768))
        #expect(actual.height == 767)
        #expect(window.writes.isEmpty)
    }

    @Test
    func cancellationDuringMovePreventsResize() async {
        var moved = false
        var sizes = 0
        var frame = CGRect(x: 704, y: 30, width: 704, height: 384)
        let task = Task { @MainActor in
            try await WindowFrameSettler().apply(
                CGRect(x: 0, y: 30, width: 1408, height: 768),
                writePosition: { frame.origin = $0; moved = true }, writeSize: { _ in sizes += 1 },
                read: { frame }, readPresentedFrame: { nil }
            )
        }
        while !moved { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(sizes == 0)
    }

    @Test
    func unavailableAXFrameFailsWithoutWriting() async {
        var writes = 0
        await #expect(throws: WindowManagerError.self) {
            try await WindowFrameSettler().apply(
                .zero, writePosition: { _ in writes += 1 }, writeSize: { _ in writes += 1 }, read: { nil }
            )
        }
        #expect(writes == 0)
    }
}

@MainActor
private final class DeferredNativeWindow {
    var enhancedUI = true
    var time = 0.0
    var logical: CGRect
    var presented: CGRect
    var pending: (at: Double, frame: CGRect)?
    var writes: [(attribute: String, time: Double)] = []

    init(frame: CGRect) { logical = frame; presented = frame }

    func move(to point: CGPoint) {
        writes.append(("position", time))
        logical = CGRect(origin: point, size: presented.size)
        if enhancedUI { pending = (time + 0.1, logical) }
        else { presented = logical; pending = nil }
    }

    func resize(to size: CGSize) {
        writes.append(("size", time))
        logical = CGRect(origin: presented.origin, size: CGSize(
            width: min(size.width, 1408 - presented.minX),
            height: min(size.height, 798 - presented.minY)
        ))
        if enhancedUI { pending = (time + 0.1, logical) }
        else { presented = logical; pending = nil }
    }

    func apply(_ target: CGRect) async throws -> CGRect {
        try await WindowFrameSettler(now: { self.time }, sleep: { self.time += $0 }).apply(
            target,
            writePosition: { self.move(to: $0) },
            writeSize: { self.resize(to: $0) },
            read: { self.logical },
            readPresentedFrame: {
                if let pending = self.pending, self.time + 0.0001 >= pending.at {
                    self.presented = pending.frame
                    self.pending = nil
                }
                return self.presented
            }
        )
    }
}
