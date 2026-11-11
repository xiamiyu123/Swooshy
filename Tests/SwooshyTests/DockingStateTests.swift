import CoreGraphics
import Foundation
import Testing
@testable import Swooshy

@MainActor
struct DockingStateTests {
    private let desktop = CGRect(x: 0, y: 83, width: 1408, height: 768)

    @Test(arguments: [
        (WindowAction.leftHalf, CGPoint(x: 0, y: 179)),
        (.rightHalf, CGPoint(x: 548, y: 179)),
        (.topLeftQuarter, CGPoint(x: 0, y: 179)),
        (.topRightQuarter, CGPoint(x: 548, y: 179)),
        (.bottomLeftQuarter, CGPoint(x: 0, y: 83)),
        (.bottomRightQuarter, CGPoint(x: 548, y: 83)),
        (.maximize, CGPoint(x: 0, y: 179)),
        (.center, CGPoint(x: 0, y: 179))
    ])
    func nonResizableWindowMovesToAnchorWithoutResizingOrChangingCache(
        action: WindowAction, origin: CGPoint
    ) async throws {
        let original = CGRect(x: 301, y: 99, width: 860, height: 672)
        var current = original
        var frames: [CGRect] = []
        var confirmations = 0
        var cacheWrites = 0
        let clock = DockingAnimationClock()
        let session = SmoothDockingSession(
            originalFrame: original, desktopFrame: desktop, baseSizeConstraints: .init(),
            canResize: false,
            observedSizeConstraints: .init(minimumWidth: 1000, maximumHeight: 500),
            loadCurrentFrame: { current },
            animateFrame: { frame in
                guard frame.size == original.size else { throw WindowManagerError.unableToSetFrame }
                current.origin = frame.origin
                frames.append(current)
            },
            animationNow: { clock.now },
            animationSleep: { try await clock.sleep(until: $0) },
            applyFrame: { frame in
                confirmations += 1
                return try await WindowFrameSettler().apply(
                    frame, writePosition: { current.origin = $0 },
                    writeSize: nil,
                    read: { current }, readPresentedFrame: { current }
                )
            },
            recordConstraintObservation: { _, _, _ in cacheWrites += 1 },
            recordAcceptedFrame: { _ in cacheWrites += 1 }
        )
        session.update(action: action)
        #expect(try await session.commit() == CGRect(origin: origin, size: original.size))
        let framesAtArrival = frames
        for _ in 0..<20 { session.update(action: action) }
        _ = try await session.commit()
        #expect(frames == framesAtArrival)
        #expect(confirmations == 1)
        #expect(frames.count > 2)
        #expect(frames.allSatisfy { $0.size == original.size })
        session.restore()
        #expect(try await session.commit() == original)
        session.finish()
        #expect(cacheWrites == 0)
    }

    @Test
    func repeatedTargetKeepsOneProgressiveTransitionAndReleaseReusesIt() async throws {
        let original = CGRect(x: 120, y: 150, width: 900, height: 650)
        var current = original
        var frames: [CGRect] = []
        var confirmations = 0
        var reads = 0
        var accepted = 0
        let clock = DockingAnimationClock()
        var session: SmoothDockingSession!
        session = SmoothDockingSession(
            originalFrame: original, desktopFrame: desktop, baseSizeConstraints: .init(),
            loadCurrentFrame: { reads += 1; return current },
            animateFrame: { frames.append($0); current = $0 },
            animationNow: { clock.now },
            animationSleep: { deadline in
                session.update(action: .bottomRightQuarter)
                try await clock.sleep(until: deadline)
            },
            applyFrame: { confirmations += 1; current = $0; return $0 },
            recordAcceptedFrame: { _ in accepted += 1 }
        )
        session.update(action: .bottomRightQuarter)
        let result = try await session.commit()
        let framesAtArrival = frames
        for _ in 0..<20 { session.update(action: .bottomRightQuarter) }
        #expect(try await session.commit() == result)
        session.finish()
        #expect(frames.count > 2)
        #expect(frames.first != original && frames.first != result)
        #expect(frames.last == result)
        #expect(Set(frames.map(NSStringFromRect)).count == frames.count)
        #expect(frames == framesAtArrival)
        #expect(confirmations == 1)
        #expect(reads == 1)
        #expect(accepted == 1)
    }

    @Test
    func retargetingCancelsOldTransitionBeforeMoreFramesOrConfirmation() async throws {
        let original = CGRect(x: 120, y: 150, width: 900, height: 650)
        var current = original
        var frames: [CGRect] = []
        var confirmations = 0
        var retargeted = false
        var enhancedUI = true
        let clock = DockingAnimationClock()
        let animationControl = WindowFrameAnimationControl(
            readEnabled: { _ in enhancedUI },
            writeEnabled: { _, enabled in enhancedUI = enabled; return .success }
        )
        var session: SmoothDockingSession!
        session = SmoothDockingSession(
            originalFrame: original, desktopFrame: desktop, baseSizeConstraints: .init(),
            loadCurrentFrame: { current },
            animateFrame: {
                #expect(!enhancedUI)
                frames.append($0)
                current = $0
            },
            animationNow: { clock.now },
            animationSleep: { deadline in
                if !retargeted && !frames.isEmpty {
                    retargeted = true
                    session.update(action: .topLeftQuarter)
                }
                try await clock.sleep(until: deadline)
            },
            beginTransition: { try animationControl.begin(for: 42) },
            endTransition: { animationControl.end(for: 42) },
            applyFrame: {
                #expect(!enhancedUI)
                confirmations += 1
                current = $0
                return $0
            }
        )
        session.update(action: .bottomRightQuarter)
        await #expect(throws: CancellationError.self) { try await session.commit() }
        let result = try await session.commit()
        session.finish()
        #expect(result == CGRect(x: 0, y: 467, width: 704, height: 384))
        #expect(confirmations == 1)
        #expect(frames.count > 2)
        #expect(frames.dropFirst().allSatisfy { $0.minX <= frames[0].minX })
        #expect(enhancedUI)
    }

    @Test
    func unchangedTargetAndReleaseReuseOneOperation() async throws {
        var current = CGRect(x: 0, y: 83, width: 820, height: 580)
        var writes: [CGRect] = []
        let session = SmoothDockingSession(
            originalFrame: current, desktopFrame: desktop, baseSizeConstraints: .init(),
            observedSizeConstraints: .init(minimumWidth: 820, minimumHeight: 580),
            applyFrame: { requested in writes.append(requested); current = requested; return current }
        )
        session.update(action: .bottomRightQuarter)
        while writes.isEmpty { await Task.yield() }
        for _ in 0..<20 { session.update(action: .bottomRightQuarter) }
        let result = try await session.commit()
        session.finish()
        #expect(result == CGRect(x: 588, y: 83, width: 820, height: 580))
        #expect(writes == [result])
    }

    @Test
    func cachedMinimumIsNeverRetriedBelowItsLimit() async throws {
        var current = CGRect(x: 588, y: 83, width: 820, height: 580)
        var writes: [CGRect] = []
        let session = SmoothDockingSession(
            originalFrame: current, desktopFrame: desktop, baseSizeConstraints: .init(),
            observedSizeConstraints: .init(minimumWidth: 820, minimumHeight: 580),
            applyFrame: { requested in
                writes.append(requested)
                current = CGRect(origin: requested.origin, size: CGSize(
                    width: max(820, requested.width), height: max(580, requested.height)
                ))
                return current
            }
        )
        session.update(action: .bottomRightQuarter)
        _ = try await session.commit()
        session.finish()
        #expect(writes.allSatisfy { $0.width >= 820 && $0.height >= 580 })
        #expect(current == CGRect(x: 588, y: 83, width: 820, height: 580))
    }
}
