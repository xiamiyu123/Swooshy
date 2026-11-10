import ApplicationServices
import CoreGraphics
import Foundation

/// Keeps the CF handle alive while read-only AX requests run off the UI thread.
private struct DiagnosticAXWindow: @unchecked Sendable {
    let element: AXUIElement
}

/// Read-only observations of an anomalous frame write. All frames use the
/// global, top-left-origin coordinates shared by AX and CGWindowList.
@MainActor
final class WindowFrameDiagnostics {
    typealias Window = WindowFrameSnapshot.Window
    typealias Match = WindowFrameSnapshot.Match

    struct Target {
        let window: AXUIElement
        let ownerPID: pid_t
        let match: Match
        let context: String
    }

    private final class Trace {
        let id = UUID().uuidString
        let target: Target
        var subsequentWriteBatches = 0
        var task: Task<Void, Never>?

        init(target: Target) { self.target = target }
    }

    private let isEnabled: () -> Bool
    private let now: () -> TimeInterval
    private let sleep: (TimeInterval) async throws -> Void
    private let readAXFrame: @MainActor (AXUIElement) async -> CGRect?
    private let loadWindows: () -> [Window]?
    private let log: (String) -> Void
    private var traces: [Trace] = []

    init(
        isEnabled: @escaping () -> Bool = { DebugLog.isEnabled },
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        readAXFrame: @escaping @MainActor (AXUIElement) async -> CGRect? = { window in
            let handle = DiagnosticAXWindow(element: window)
            return await Task.detached(priority: .utility) {
                guard
                    let position = AXAttributeReader.point(kAXPositionAttribute as CFString, from: handle.element),
                    let size = AXAttributeReader.size(kAXSizeAttribute as CFString, from: handle.element)
                else { return nil as CGRect? }
                return CGRect(origin: position, size: size)
            }.value
        },
        loadWindows: @escaping () -> [Window]? = {
            (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]])?
                .compactMap { Window(info: $0) }
        },
        log: @escaping (String) -> Void = { DebugLog.debug(DebugLog.windows, $0) }
    ) {
        self.isEnabled = isEnabled
        self.now = now
        self.sleep = sleep
        self.readAXFrame = readAXFrame
        self.loadWindows = loadWindows
        self.log = log
    }

    func target(
        for window: AXUIElement, preWriteFrame: CGRect?, context: String,
        binding: WindowFrameSnapshot.Binding? = nil
    ) -> Target? {
        guard isEnabled(), let ownerPID = AXAttributeReader.processIdentifier(of: window) else { return nil }
        let windows = loadWindows()
        let axTitle = AXAttributeReader.string(kAXTitleAttribute as CFString, from: window)
        let match = binding?.match ?? Match.resolve(
            windowID: AXAttributeReader.windowIdentifier(of: window),
            ownerPID: ownerPID,
            title: axTitle,
            frame: preWriteFrame,
            windows: windows
        )
        let cgFrame = windows?.first { $0.ownerPID == ownerPID && $0.id == match.windowID }?.frame
        log(
            "Frame diagnostic target [\(context)] ownerPID=\(ownerPID), " +
            "cgWindowID=\(match.windowID.map(String.init) ?? "nil"), match=\(match.method), " +
            "preWriteAX=\(preWriteFrame.map(NSStringFromRect) ?? "unavailable"), " +
            "preWriteCG=\(cgFrame.map(NSStringFromRect) ?? "unavailable")"
        )
        if match.windowID == nil {
            let candidates = windows?.filter { $0.ownerPID == ownerPID }.map {
                "id=\($0.id) title=\(String(reflecting: $0.title)) frame=\(NSStringFromRect($0.frame))"
            }.joined(separator: "; ") ?? "CGUnavailable"
            log("Frame diagnostic unmatched [\(context)] AXTitle=\(String(reflecting: axTitle)), preWriteCandidates=[\(candidates)]")
        }
        return Target(window: window, ownerPID: ownerPID, match: match, context: context)
    }

    func noteWrite(to window: AXUIElement) {
        for trace in traces where AXAttributeReader.sameElement(trace.target.window, window) {
            trace.subsequentWriteBatches += 1
        }
    }

    func observeAfterAttempt(target: Target, requested: CGRect, reason: String) {
        guard isEnabled() else { return }
        if let previous = traces.first(where: { AXAttributeReader.sameElement($0.target.window, target.window) }) {
            previous.task?.cancel()
            log("Frame diagnostic [\(previous.id)] superseded by a newer anomalous attempt for the same window")
            traces.removeAll { $0 === previous }
        }
        let trace = Trace(target: target)
        traces.append(trace)
        let startedAt = now()
        log(
            "Frame diagnostic [\(trace.id) \(target.context)] start: reason=\(reason), " +
            "requestedAX=\(NSStringFromRect(requested)), " +
            "cgWindowID=\(target.match.windowID.map(String.init) ?? "nil"), match=\(target.match.method); " +
            "delaysMs=0,16,50,100,200; normal docking writes continue"
        )
        trace.task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.traces.removeAll { $0 === trace } }
            for delay in [0.0, 0.016, 0.050, 0.100, 0.200] {
                let remaining = startedAt + delay - self.now()
                if remaining > 0 {
                    do { try await self.sleep(remaining) } catch { return }
                }
                guard !Task.isCancelled, self.isEnabled() else { return }
                let sampleStartedAt = self.now()
                let writesBeforeSample = trace.subsequentWriteBatches
                let axFrame = await self.readAXFrame(target.window)
                guard !Task.isCancelled, self.isEnabled() else { return }
                let axReadFinishedAt = self.now()
                let windows = self.loadWindows()?.filter { $0.ownerPID == target.ownerPID }
                let cgDescription: String
                if let windows {
                    if let cgWindow = windows.first(where: { $0.id == target.match.windowID }) {
                        cgDescription = NSStringFromRect(cgWindow.frame)
                    } else if target.match.windowID != nil {
                        cgDescription = "matchedWindowMissing"
                    } else {
                        cgDescription = "unresolved candidates=[\(windows.map { "\($0.id):\(NSStringFromRect($0.frame))" }.joined(separator: ", "))]"
                    }
                } else {
                    cgDescription = "unavailable"
                }
                self.log(
                    "Frame diagnostic [\(trace.id) \(target.context)] sample: " +
                    "scheduledMs=\(Int(delay * 1000)), elapsedMs=\(Self.ms(sampleStartedAt - startedAt)), " +
                    "AX=\(axFrame.map(NSStringFromRect) ?? "unavailable"), CG=\(cgDescription), " +
                    "axReadMs=\(Self.ms(axReadFinishedAt - sampleStartedAt)), " +
                    "cgReadMs=\(Self.ms(self.now() - axReadFinishedAt)), " +
                    "subsequentWriteBatches=\(trace.subsequentWriteBatches), " +
                    "writesDuringSample=\(trace.subsequentWriteBatches - writesBeforeSample)"
                )
            }
        }
    }

    func cancel() {
        for trace in traces { trace.task?.cancel() }
        traces.removeAll()
    }

    private static func ms(_ seconds: TimeInterval) -> String {
        String(format: "%.2f", seconds * 1000)
    }
}
