@MainActor
final class DockingAnimationClock {
    var now = ContinuousClock.now

    func sleep(until deadline: ContinuousClock.Instant) async throws {
        try Task.checkCancellation()
        now = max(now, deadline)
        await Task.yield()
    }
}
