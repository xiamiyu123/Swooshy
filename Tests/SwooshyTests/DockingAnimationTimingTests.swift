import CoreGraphics
import Foundation
import Testing
@testable import Swooshy

@MainActor
struct DockingAnimationTimingTests {
    private let original = CGRect(x: 120, y: 150, width: 900, height: 650)
    private let desktop = CGRect(x: 0, y: 83, width: 1408, height: 768)
    private let target = CGRect(x: 704, y: 83, width: 704, height: 384)

    @Test(arguments: [0, 5])
    func shortWritesUseRemainingFrameBudget(milliseconds: Int) async throws {
        let clock = DockingAnimationClock()
        let start = clock.now
        let latency = Duration.milliseconds(milliseconds)
        var writes: [(time: Duration, frame: CGRect)] = []
        var confirmedAt: Duration?
        let session = SmoothDockingSession(
            originalFrame: original, desktopFrame: desktop, baseSizeConstraints: .init(),
            animateFrame: { frame in
                writes.append((start.duration(to: clock.now), frame))
                clock.now += latency
            },
            animationNow: { clock.now },
            animationSleep: { try await clock.sleep(until: $0) },
            applyFrame: { frame in confirmedAt = start.duration(to: clock.now); return frame }
        )
        session.update(action: .bottomRightQuarter)
        #expect(try await session.commit() == target)
        session.finish()
        #expect(writes.count > 2)
        #expect(try #require(writes.last).time <= .milliseconds(240))
        #expect(confirmedAt == .milliseconds(240))
        let first = try #require(writes.first)
        let second = try #require(writes.dropFirst().first)
        #expect(second.time - first.time == .nanoseconds(16_666_667))
        #expect(first.frame.minX > original.minX && first.frame.width < original.width)
        #expect(writes.last?.frame == target)
        #expect(Set(writes.map { NSStringFromRect($0.frame) }).count == writes.count)
    }

    @Test(arguments: [50, 100])
    func slowWriteResumesAtCurrentProgressWithoutReplayingMissedFrames(milliseconds: Int) async throws {
        let clock = DockingAnimationClock()
        let start = clock.now
        let latency = Duration.milliseconds(milliseconds)
        var writes: [(time: Duration, frame: CGRect)] = []
        var confirmedAt: Duration?
        let session = SmoothDockingSession(
            originalFrame: original, desktopFrame: desktop, baseSizeConstraints: .init(),
            animateFrame: { frame in
                writes.append((start.duration(to: clock.now), frame))
                if writes.count == 1 { clock.now += latency }
            },
            animationNow: { clock.now },
            animationSleep: { try await clock.sleep(until: $0) },
            applyFrame: { frame in confirmedAt = start.duration(to: clock.now); return frame }
        )
        session.update(action: .bottomRightQuarter)
        #expect(try await session.commit() == target)
        session.finish()
        let first = try #require(writes.first)
        let resumed = try #require(writes.dropFirst().first)
        #expect(resumed.time == first.time + latency)
        let progress = resumed.time / .milliseconds(240)
        let eased = 1 - pow(1 - progress, 3)
        #expect(abs(resumed.frame.minX - (original.minX + (target.minX - original.minX) * eased)) <= 1)
        #expect(abs(resumed.frame.width - (original.width + (target.width - original.width) * eased)) <= 1)
        #expect(confirmedAt == .milliseconds(240))
        #expect(writes.count < 15)
        #expect(zip(writes, writes.dropFirst()).allSatisfy { $0.time < $1.time })
    }

    @Test
    func lateWakeUsesCurrentTimeInsteadOfScheduledProgress() async throws {
        let clock = DockingAnimationClock()
        let start = clock.now
        var writes: [(time: Duration, frame: CGRect)] = []
        var sleeps = 0
        var confirmedAt: Duration?
        let session = SmoothDockingSession(
            originalFrame: original, desktopFrame: desktop, baseSizeConstraints: .init(),
            animateFrame: { writes.append((start.duration(to: clock.now), $0)) },
            animationNow: { clock.now },
            animationSleep: { deadline in
                try await clock.sleep(until: deadline)
                sleeps += 1
                if sleeps == 1 { clock.now += .milliseconds(50) }
            },
            applyFrame: { frame in confirmedAt = start.duration(to: clock.now); return frame }
        )
        session.update(action: .bottomRightQuarter)
        #expect(try await session.commit() == target)
        session.finish()
        let first = try #require(writes.first)
        #expect(first.time == .nanoseconds(16_666_667) + .milliseconds(50))
        let progress = first.time / .milliseconds(240)
        let eased = 1 - pow(1 - progress, 3)
        #expect(abs(first.frame.minX - (original.minX + (target.minX - original.minX) * eased)) <= 1)
        #expect(confirmedAt == .milliseconds(240))
        #expect(writes.count < 15)
    }

    @Test
    func writeBlockingPastDeadlineGoesStraightToFinalFrame() async throws {
        let clock = DockingAnimationClock()
        let start = clock.now
        var writes: [(time: Duration, frame: CGRect)] = []
        var sleeps = 0
        let session = SmoothDockingSession(
            originalFrame: original, desktopFrame: desktop, baseSizeConstraints: .init(),
            animateFrame: { frame in
                writes.append((start.duration(to: clock.now), frame))
                if writes.count == 1 { clock.now += .milliseconds(300) }
            },
            animationNow: { clock.now },
            animationSleep: { deadline in
                sleeps += 1
                try await clock.sleep(until: deadline)
            },
            applyFrame: { $0 }
        )
        session.update(action: .bottomRightQuarter)
        #expect(try await session.commit() == target)
        session.finish()
        #expect(writes.count == 2)
        #expect(sleeps == 1)
        #expect(writes.last?.frame == target)
        let first = try #require(writes.first)
        #expect(writes.last?.time == first.time + .milliseconds(300))
    }

    @Test(arguments: [25, 50])
    func sustainedSlowWritesNeverAddAnExtraWait(milliseconds: Int) async throws {
        let clock = DockingAnimationClock()
        let start = clock.now
        let latency = Duration.milliseconds(milliseconds)
        var writes: [(time: Duration, frame: CGRect)] = []
        var sleeps = 0
        let session = SmoothDockingSession(
            originalFrame: original, desktopFrame: desktop, baseSizeConstraints: .init(),
            animateFrame: { frame in
                writes.append((start.duration(to: clock.now), frame))
                clock.now += latency
            },
            animationNow: { clock.now },
            animationSleep: { deadline in
                sleeps += 1
                try await clock.sleep(until: deadline)
            },
            applyFrame: { $0 }
        )
        session.update(action: .bottomRightQuarter)
        #expect(try await session.commit() == target)
        session.finish()
        let last = try #require(writes.last)
        #expect(last.frame == target)
        #expect(last.time >= .milliseconds(240))
        #expect(last.time < .milliseconds(240) + latency)
        #expect(sleeps == 1)
        #expect(zip(writes, writes.dropFirst()).allSatisfy { $1.time - $0.time == latency })
    }

    @Test
    func cancellationAfterBlockedWritePreventsFinalWriteAndConfirmation() async throws {
        let clock = DockingAnimationClock()
        var writes = 0
        var confirmations = 0
        var session: SmoothDockingSession!
        session = SmoothDockingSession(
            originalFrame: original, desktopFrame: desktop, baseSizeConstraints: .init(),
            animateFrame: { _ in
                writes += 1
                clock.now += .milliseconds(300)
                session.finish()
            },
            animationNow: { clock.now },
            animationSleep: { try await clock.sleep(until: $0) },
            applyFrame: { confirmations += 1; return $0 }
        )
        session.update(action: .bottomRightQuarter)
        await #expect(throws: CancellationError.self) { try await session.commit() }
        #expect(writes == 1)
        #expect(confirmations == 0)
    }

    @Test(arguments: [120.0, 180.0, 240.0, 320.0, 400.0])
    func selectedDurationKeepsItsDeadlineAfterASlowWrite(milliseconds: Double) async throws {
        let clock = DockingAnimationClock()
        let start = clock.now
        var writes = 0
        var confirmedAt: Duration?
        let session = SmoothDockingSession(
            originalFrame: original, desktopFrame: desktop, baseSizeConstraints: .init(),
            animateFrame: { _ in
                writes += 1
                if writes == 1 { clock.now += .milliseconds(50) }
            },
            animationDuration: { .milliseconds(milliseconds) },
            animationNow: { clock.now },
            animationSleep: { try await clock.sleep(until: $0) },
            applyFrame: { frame in confirmedAt = start.duration(to: clock.now); return frame }
        )
        session.update(action: .bottomRightQuarter)
        #expect(try await session.commit() == target)
        session.finish()
        #expect(confirmedAt == .milliseconds(milliseconds))
        #expect(writes > 2)
    }

    @Test
    func speedChangeAffectsNextTransitionWithoutRestartingCurrentTarget() async throws {
        let defaults = UserDefaults(suiteName: "Swooshy.AnimationTimingTests.\(UUID().uuidString)")!
        let settings = SettingsStore(userDefaults: defaults)
        let clock = DockingAnimationClock()
        let start = clock.now
        var current = original
        var durationReads = 0
        var confirmations: [Duration] = []
        var session: SmoothDockingSession!
        session = SmoothDockingSession(
            originalFrame: original, desktopFrame: desktop, baseSizeConstraints: .init(),
            loadCurrentFrame: { current },
            animateFrame: { current = $0 },
            animationDuration: {
                durationReads += 1
                return .milliseconds(settings.dockingAnimationDurationMilliseconds)
            },
            animationNow: { clock.now },
            animationSleep: { deadline in
                if settings.dockingAnimationDurationMilliseconds == 240 {
                    settings.dockingAnimationDurationMilliseconds = 120
                    session.update(action: .bottomRightQuarter)
                }
                try await clock.sleep(until: deadline)
            },
            applyFrame: { frame in
                confirmations.append(start.duration(to: clock.now))
                current = frame
                return frame
            }
        )
        session.update(action: .bottomRightQuarter)
        #expect(try await session.commit() == target)
        #expect(confirmations == [.milliseconds(240)])
        session.update(action: .topLeftQuarter)
        #expect(try await session.commit() == CGRect(x: 0, y: 467, width: 704, height: 384))
        session.finish()
        #expect(confirmations == [.milliseconds(240), .milliseconds(360)])
        #expect(durationReads == 2)
    }
}
