import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import Swooshy

@MainActor
struct WindowFrameDiagnosticsTests {
    private typealias Diagnostics = WindowFrameDiagnostics
    private let frame = CGRect(x: -1408, y: 30, width: 704, height: 384)

    @Test
    func parsesCGWindowBoundsAndExcludesNonWindowLayers() throws {
        var info: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: 10),
            kCGWindowOwnerPID as String: NSNumber(value: 42),
            kCGWindowLayer as String: NSNumber(value: 0),
            kCGWindowName as String: "Chrome",
            kCGWindowBounds as String: frame.dictionaryRepresentation,
        ]
        let window = try #require(Diagnostics.Window(info: info))
        #expect(window.id == 10)
        #expect(window.ownerPID == 42)
        #expect(window.frame == frame)
        info[kCGWindowLayer as String] = NSNumber(value: 1)
        #expect(Diagnostics.Window(info: info) == nil)
    }

    @Test
    func matchesUniqueTitleWithinOwningProcess() {
        let match = Diagnostics.Match.resolve(
            windowID: nil, ownerPID: 42, title: "Chrome", frame: nil,
            windows: [
                .init(id: 10, ownerPID: 42, title: "Chrome", frame: frame),
                .init(id: 11, ownerPID: 99, title: "Chrome", frame: frame),
            ]
        )
        #expect(match == .init(windowID: 10, method: "uniqueTitle"))
    }

    @Test
    func matchesUniquePreWriteGeometryWhenTitlesAreUnavailable() {
        let match = Diagnostics.Match.resolve(
            windowID: nil, ownerPID: 42, title: "Chrome", frame: frame,
            windows: [
                .init(id: 10, ownerPID: 42, title: nil, frame: frame),
                .init(id: 11, ownerPID: 42, title: nil, frame: frame.offsetBy(dx: 100, dy: 0)),
                .init(id: 12, ownerPID: 99, title: nil, frame: frame),
            ]
        )
        #expect(match == .init(windowID: 10, method: "uniquePreWriteFrame"))
    }

    @Test
    func matchesChromeCaptionWithoutAXApplicationSuffix() {
        let match = Diagnostics.Match.resolve(
            windowID: nil, ownerPID: 42, title: "新标签页 - Google Chrome", frame: frame,
            windows: [.init(id: 10, ownerPID: 42, title: "新标签页", frame: frame)],
            applicationName: "Google Chrome"
        )
        #expect(match.windowID == 10)
        let duplicate = Diagnostics.Match.resolve(
            windowID: nil, ownerPID: 42, title: "新标签页 - Google Chrome", frame: frame,
            windows: [
                .init(id: 10, ownerPID: 42, title: "新标签页", frame: frame),
                .init(id: 11, ownerPID: 42, title: "新标签页", frame: frame),
            ], applicationName: "Google Chrome"
        )
        #expect(duplicate.windowID == nil)
        let wrongApp = Diagnostics.Match.resolve(
            windowID: nil, ownerPID: 42, title: "新标签页 - Google Chrome", frame: frame,
            windows: [.init(id: 10, ownerPID: 42, title: "新标签页", frame: frame)],
            applicationName: "Other"
        )
        #expect(wrongApp.windowID == nil)
    }

    @Test
    func matchesChromeDecoratedAXTitleOnlyWithUniquePreWriteGeometry() {
        let title = "分支 · 解释栈帧与寄存器保存"
        let axTitle = title + " - 属于未命名群组 - 内存用量高 - 1.2 GB - Google Chrome"
        let windows: [Diagnostics.Window] = [
            .init(id: 7418, ownerPID: 66517, title: title, frame: frame),
            .init(id: 7419, ownerPID: 66517, title: "", frame: frame.offsetBy(dx: 100, dy: 0)),
            .init(id: 7420, ownerPID: 99, title: title, frame: frame),
        ]
        let match = Diagnostics.Match.resolve(
            windowID: nil, ownerPID: 66517, title: axTitle, frame: frame,
            windows: windows, applicationName: "Google Chrome"
        )
        #expect(match == .init(windowID: 7418, method: "uniquePreWriteFrame"))
        let moved = Diagnostics.Match.resolve(
            windowID: nil, ownerPID: 66517, title: axTitle, frame: frame.offsetBy(dx: 50, dy: 0),
            windows: windows, applicationName: "Google Chrome"
        )
        #expect(moved.windowID == nil)
        let ambiguous = Diagnostics.Match.resolve(
            windowID: nil, ownerPID: 66517, title: axTitle, frame: frame,
            windows: windows + [.init(id: 7421, ownerPID: 66517, title: title, frame: frame)],
            applicationName: "Google Chrome"
        )
        #expect(ambiguous.windowID == nil)
    }

    @Test
    func refusesAmbiguousWindowsAndConflictingTitles() {
        let candidates: [Diagnostics.Window] = [
            .init(id: 10, ownerPID: 42, title: "Chrome", frame: frame),
            .init(id: 11, ownerPID: 42, title: "Chrome", frame: frame),
        ]
        let ambiguous = Diagnostics.Match.resolve(
            windowID: nil, ownerPID: 42, title: "Chrome", frame: frame, windows: candidates
        )
        #expect(ambiguous.windowID == nil)
        let conflicting = Diagnostics.Match.resolve(
            windowID: nil, ownerPID: 42, title: "Other", frame: frame, windows: Array(candidates.prefix(1))
        )
        #expect(conflicting.windowID == nil)
    }

    @Test
    func preservesAXIdentifierWhenCGWindowIsTemporarilyMissing() {
        let match = Diagnostics.Match.resolve(
            windowID: 10, ownerPID: 42, title: "Chrome", frame: frame,
            windows: [.init(id: 11, ownerPID: 42, title: "Chrome", frame: frame)]
        )
        #expect(match == .init(windowID: 10, method: "AXWindowID"))
        let unavailable = Diagnostics.Match.resolve(
            windowID: nil, ownerPID: 42, title: "Chrome", frame: frame, windows: nil
        )
        #expect(unavailable == .init(windowID: nil, method: "CGUnavailable"))
    }

    @Test
    func samplesFreshBoundsOnAbsoluteDeadlinesAndMarksSubsequentWrites() async {
        let element = AXUIElementCreateApplication(42)
        let otherElement = AXUIElementCreateApplication(99)
        var time: TimeInterval = 0
        var messages: [String] = []
        var snapshotLoads = 0
        var axReads = 0
        var diagnostics: Diagnostics?
        let sampler = Diagnostics(
            isEnabled: { true }, now: { time },
            sleep: { delay in
                time += delay
                diagnostics?.noteWrite(to: element)
                diagnostics?.noteWrite(to: otherElement)
            },
            readAXFrame: { _ in
                axReads += 1
                time += 0.003
                if axReads == 1 { diagnostics?.noteWrite(to: element) }
                return frame
            },
            loadWindows: {
                snapshotLoads += 1
                if snapshotLoads == 3 { return nil }
                var windows: [Diagnostics.Window] = [
                    .init(id: 11, ownerPID: 42, title: "Chrome", frame: frame),
                ]
                if snapshotLoads < 5 {
                    windows.append(.init(id: 10, ownerPID: 42, title: "Changed title", frame: frame.offsetBy(dx: 20, dy: 0)))
                }
                return windows
            },
            log: { messages.append($0) }
        )
        diagnostics = sampler
        sampler.observeAfterAttempt(
            target: .init(window: element, ownerPID: 42, match: .init(windowID: 10, method: "uniquePreWriteFrame"), context: "test"),
            requested: frame, reason: "AXReadbackMismatch"
        )
        await yieldForPendingMainActorWork()

        let samples = messages.filter { $0.contains("sample:") }
        #expect(samples.count == 5)
        #expect(snapshotLoads == 5)
        #expect(axReads == 5)
        for (sample, milliseconds) in zip(samples, [0, 16, 50, 100, 200]) {
            #expect(sample.contains("scheduledMs=\(milliseconds), elapsedMs=\(milliseconds).00"))
            #expect(sample.contains("AX=\(NSStringFromRect(frame))"))
            #expect(sample.contains("axReadMs=3.00"))
        }
        #expect(samples.first?.contains("subsequentWriteBatches=1, writesDuringSample=1") == true)
        #expect(samples.last?.contains("subsequentWriteBatches=5, writesDuringSample=0") == true)
        #expect(samples.first?.contains("CG=\(NSStringFromRect(frame.offsetBy(dx: 20, dy: 0)))") == true)
        #expect(samples.dropFirst(2).first?.contains("CG=unavailable") == true)
        #expect(samples.last?.contains("CG=matchedWindowMissing") == true)
    }

    @Test
    func cancellationDuringAXReadDoesNotLoadCGOrEmitStaleSample() async throws {
        let element = AXUIElementCreateApplication(42)
        var resumeRead: CheckedContinuation<CGRect?, Never>?
        var cgReads = 0
        var messages: [String] = []
        let diagnostics = Diagnostics(
            isEnabled: { true },
            readAXFrame: { _ in
                await withCheckedContinuation { resumeRead = $0 }
            },
            loadWindows: { cgReads += 1; return [] }, log: { messages.append($0) }
        )
        defer {
            diagnostics.cancel()
            resumeRead?.resume(returning: nil)
        }
        diagnostics.observeAfterAttempt(
            target: .init(window: element, ownerPID: 42, match: .init(windowID: 10, method: "AXWindowID"), context: "test"),
            requested: frame, reason: "AXReadbackMismatch"
        )
        await yieldForPendingMainActorWork()
        let pendingRead = try #require(resumeRead)
        diagnostics.cancel()
        resumeRead = nil
        pendingRead.resume(returning: frame)
        await yieldForPendingMainActorWork()
        #expect(cgReads == 0)
        #expect(!messages.contains { $0.contains("sample:") })
    }

    @Test
    func disablingDiagnosticsOrCancellingPreventsReadback() async {
        let element = AXUIElementCreateApplication(42)
        let target = Diagnostics.Target(
            window: element, ownerPID: 42, match: .init(windowID: 10, method: "AXWindowID"), context: "test"
        )
        var enabled = false
        var axReads = 0
        var cgReads = 0
        let diagnostics = Diagnostics(
            isEnabled: { enabled },
            readAXFrame: { _ in axReads += 1; return frame },
            loadWindows: { cgReads += 1; return [] }, log: { _ in }
        )
        #expect(diagnostics.target(for: element, preWriteFrame: frame, context: "disabled") == nil)
        diagnostics.observeAfterAttempt(target: target, requested: frame, reason: "disabled")
        enabled = true
        diagnostics.observeAfterAttempt(target: target, requested: frame, reason: "cancelled")
        diagnostics.cancel()
        await yieldForPendingMainActorWork()
        #expect(axReads == 0)
        #expect(cgReads == 0)
    }

    @Test
    func newerAnomalyReplacesOnlyTheSameWindowsPendingSamples() async {
        var time: TimeInterval = 0
        var messages: [String] = []
        let diagnostics = Diagnostics(
            isEnabled: { true }, now: { time }, sleep: { time += $0 },
            readAXFrame: { _ in frame }, loadWindows: { [] }, log: { messages.append($0) }
        )
        let target = Diagnostics.Target(
            window: AXUIElementCreateApplication(42), ownerPID: 42,
            match: .init(windowID: nil, method: "unresolved"), context: "first"
        )
        diagnostics.observeAfterAttempt(target: target, requested: frame, reason: "first")
        diagnostics.observeAfterAttempt(target: target, requested: frame, reason: "replacement")
        let otherTarget = Diagnostics.Target(
            window: AXUIElementCreateApplication(99), ownerPID: 99,
            match: .init(windowID: nil, method: "unresolved"), context: "other"
        )
        diagnostics.observeAfterAttempt(target: otherTarget, requested: frame, reason: "other")
        await yieldForPendingMainActorWork()
        #expect(messages.filter { $0.contains("superseded") }.count == 1)
        #expect(messages.filter { $0.contains("sample:") }.count == 10)
        #expect(messages.contains { $0.contains("CG=unresolved candidates=[]") })
    }
}
