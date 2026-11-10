import ApplicationServices
import Testing
@testable import Swooshy

@MainActor
struct WindowFrameAnimationControlTests {
    @Test
    func overlappingWindowsRestoreTheApplicationOnlyAfterBothFinish() throws {
        var enabled = true
        var reads = 0
        var writes: [Bool] = []
        let control = WindowFrameAnimationControl(
            readEnabled: { _ in reads += 1; return enabled },
            writeEnabled: { _, value in writes.append(value); enabled = value; return .success }
        )
        try control.begin(for: 42)
        try control.begin(for: 42)
        #expect(!enabled)
        control.end(for: 42)
        #expect(!enabled)
        #expect(writes == [false])
        control.end(for: 42)
        #expect(enabled)
        #expect(reads == 1)
        #expect(writes == [false, true])
    }

    @Test(arguments: [false, nil] as [Bool?])
    func disabledOrUnsupportedAttributeIsLeftUntouched(original: Bool?) throws {
        var writes = 0
        let control = WindowFrameAnimationControl(
            readEnabled: { _ in original },
            writeEnabled: { _, _ in writes += 1; return .success }
        )
        try control.begin(for: 42)
        control.end(for: 42)
        #expect(writes == 0)
    }

    @Test
    func failedSuppressionStopsBeforeAnyFrameWrites() async {
        var frameWrites = 0
        var flagWrites: [Bool] = []
        let control = WindowFrameAnimationControl(
            readEnabled: { _ in true },
            writeEnabled: { _, value in flagWrites.append(value); return .cannotComplete }
        )
        let session = SmoothDockingSession(
            originalFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            desktopFrame: CGRect(x: 0, y: 83, width: 1408, height: 768),
            baseSizeConstraints: .init(),
            animateFrame: { _ in frameWrites += 1 },
            animationSleep: {},
            beginTransition: { try control.begin(for: 42) },
            endTransition: { control.end(for: 42) },
            applyFrame: { frameWrites += 1; return $0 }
        )
        session.update(action: .bottomRightQuarter)
        await #expect(throws: WindowManagerError.self) { try await session.commit() }
        session.finish()
        #expect(frameWrites == 0)
        #expect(flagWrites == [false])
    }

    @Test
    func confirmationFailureRestoresTheOriginalState() async {
        var enabled = true
        let control = WindowFrameAnimationControl(
            readEnabled: { _ in enabled },
            writeEnabled: { _, value in enabled = value; return .success }
        )
        let session = SmoothDockingSession(
            originalFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            desktopFrame: CGRect(x: 0, y: 83, width: 1408, height: 768),
            baseSizeConstraints: .init(),
            beginTransition: { try control.begin(for: 42) },
            endTransition: { control.end(for: 42) },
            applyFrame: { _ in
                #expect(!enabled)
                throw WindowManagerError.unableToSetFrame
            }
        )
        session.update(action: .maximize)
        await #expect(throws: WindowManagerError.self) { try await session.commit() }
        session.finish()
        #expect(enabled)
    }

    @Test
    func cancellationRestoresTheOriginalState() async {
        var enabled = true
        var confirming = false
        let control = WindowFrameAnimationControl(
            readEnabled: { _ in enabled },
            writeEnabled: { _, value in enabled = value; return .success }
        )
        let session = SmoothDockingSession(
            originalFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            desktopFrame: CGRect(x: 0, y: 83, width: 1408, height: 768),
            baseSizeConstraints: .init(),
            beginTransition: { try control.begin(for: 42) },
            endTransition: { control.end(for: 42) },
            applyFrame: { frame in
                #expect(!enabled)
                confirming = true
                try await Task.sleep(for: .seconds(10))
                return frame
            }
        )
        session.update(action: .maximize)
        let commit = Task { try await session.commit() }
        while !confirming { await Task.yield() }
        session.finish()
        await #expect(throws: CancellationError.self) { try await commit.value }
        #expect(enabled)
    }

    @Test
    func shutdownRestoresEachActiveApplicationOnce() throws {
        var writes: [(pid_t, Bool)] = []
        let control = WindowFrameAnimationControl(
            readEnabled: { _ in true },
            writeEnabled: { pid, value in writes.append((pid, value)); return .success }
        )
        try control.begin(for: 42)
        try control.begin(for: 42)
        try control.begin(for: 99)
        control.shutdown()
        control.end(for: 42)
        control.end(for: 42)
        control.end(for: 99)
        #expect(writes.filter { $0.1 }.map(\.0).sorted() == [42, 99])
    }
}
