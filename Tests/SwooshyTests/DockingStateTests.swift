import CoreGraphics
import Foundation
import Testing
@testable import Swooshy

@MainActor
struct DockingStateTests {
    private let desktop = CGRect(x: 0, y: 83, width: 1408, height: 768)

    @Test
    func repeatedTargetKeepsOneProgressiveTransitionAndReleaseReusesIt() async throws {
        let original = CGRect(x: 120, y: 150, width: 900, height: 650)
        var current = original
        var frames: [CGRect] = []
        var confirmations = 0
        var reads = 0
        var accepted = 0
        var session: SmoothDockingSession!
        session = SmoothDockingSession(
            originalFrame: original, desktopFrame: desktop, baseSizeConstraints: .init(),
            loadCurrentFrame: { reads += 1; return current },
            animateFrame: { frames.append($0); current = $0 },
            animationSleep: {
                session.update(action: .bottomRightQuarter)
                await Task.yield()
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
        var session: SmoothDockingSession!
        session = SmoothDockingSession(
            originalFrame: original, desktopFrame: desktop, baseSizeConstraints: .init(),
            loadCurrentFrame: { current },
            animateFrame: { frames.append($0); current = $0 },
            animationSleep: {
                if !retargeted {
                    retargeted = true
                    session.update(action: .topLeftQuarter)
                }
                await Task.yield()
            },
            applyFrame: { confirmations += 1; current = $0; return $0 }
        )
        session.update(action: .bottomRightQuarter)
        await #expect(throws: CancellationError.self) { try await session.commit() }
        let result = try await session.commit()
        session.finish()
        #expect(result == CGRect(x: 0, y: 467, width: 704, height: 384))
        #expect(confirmations == 1)
        #expect(frames.count > 2)
        #expect(frames.dropFirst().allSatisfy { $0.minX <= frames[0].minX })
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
