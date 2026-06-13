import Testing
@testable import Swooshy

@MainActor
private final class RefreshDebouncerProbe {
    var count = 0

    func record(_ value: Int = 1) {
        count += value
    }
}

@MainActor
private func waitForDebouncerToDrain<Key: Hashable & Sendable>(
    _ debouncer: RefreshDebouncer<Key>
) async throws {
    for _ in 0..<200 {
        if debouncer.scheduledCount == 0 {
            return
        }

        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

@MainActor
struct RefreshDebouncerTests {
    @Test
    func coalescesRequestsForSameKey() async throws {
        let debouncer = RefreshDebouncer<String>(delayNanoseconds: 1_000_000)
        let probe = RefreshDebouncerProbe()

        debouncer.schedule(key: "application") {
            probe.record()
        }
        debouncer.schedule(key: "application") {
            probe.record(100)
        }

        #expect(debouncer.scheduledCount == 1)

        try await waitForDebouncerToDrain(debouncer)

        #expect(probe.count == 1)
        #expect(debouncer.scheduledCount == 0)
    }

    @Test
    func runsIndependentKeysSeparately() async throws {
        let debouncer = RefreshDebouncer<String>(delayNanoseconds: 1_000_000)
        let probe = RefreshDebouncerProbe()

        debouncer.schedule(key: "application") {
            probe.record()
        }
        debouncer.schedule(key: "workspace") {
            probe.record(10)
        }

        #expect(debouncer.scheduledCount == 2)

        try await waitForDebouncerToDrain(debouncer)

        #expect(probe.count == 11)
        #expect(debouncer.scheduledCount == 0)
    }

    @Test
    func cancelPreventsScheduledAction() async throws {
        let debouncer = RefreshDebouncer<String>(delayNanoseconds: 1_000_000)
        let probe = RefreshDebouncerProbe()

        debouncer.schedule(key: "application") {
            probe.record()
        }
        debouncer.cancel(key: "application")

        #expect(debouncer.scheduledCount == 0)

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(probe.count == 0)
    }
}
