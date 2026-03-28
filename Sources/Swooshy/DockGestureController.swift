import AppKit
import ApplicationServices
import CMultitouchShim
import Foundation

@MainActor
final class DockGestureController {
    private let windowManager: WindowManager
    private let alertPresenter: AlertPresenting
    private let settingsStore: SettingsStore
    private let dockProbe = DockAccessibilityProbe()
    private let monitor = MultitouchInputMonitor()
    private var recognizer = DockGestureRecognizer()
    private var hasShownPermissionHint = false
    private var settingsObserver: NSObjectProtocol?
    private var lastFrameLogAt = Date.distantPast
    private var lastLoggedTouchCount = -1
    private var lastLoggedHover: String?

    init(
        windowManager: WindowManager,
        alertPresenter: AlertPresenting,
        settingsStore: SettingsStore
    ) {
        self.windowManager = windowManager
        self.alertPresenter = alertPresenter
        self.settingsStore = settingsStore

        monitor.onFrame = { [weak self] frame in
            Task { @MainActor in
                self?.handle(frame: frame)
            }
        }

        observeSettings()
        syncMonitoring()
    }

    func shutdown() {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }

        monitor.stop()
    }

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: settingsStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncMonitoring()
            }
        }
    }

    private func syncMonitoring() {
        if settingsStore.dockGesturesEnabled {
            DebugLog.info(DebugLog.dock, "Starting experimental Dock gesture monitoring")
            monitor.startIfAvailable()
        } else {
            DebugLog.info(DebugLog.dock, "Stopping experimental Dock gesture monitoring")
            monitor.stop()
        }
    }

    private func handle(frame: TrackpadTouchFrame) {
        guard settingsStore.dockGesturesEnabled else { return }

        // Keep the hot path cheap: only two-finger input can produce Dock gestures.
        guard frame.touches.count == 2 else {
            _ = recognizer.process(frame: frame, hoveredApplication: nil)
            return
        }

        let needsHoveredApplicationLookup = recognizer.requiresHoveredApplication
        let mouseLocation = needsHoveredApplicationLookup ? NSEvent.mouseLocation : nil
        let hoveredApplication = mouseLocation.flatMap { dockProbe.hoveredApplication(at: $0) }
        if shouldLogFrame(touchCount: frame.touches.count, hoveredApplication: hoveredApplication) {
            let touchSummary = frame.touches
                .map { "#\($0.identifier)=\(NSStringFromPoint($0.position))" }
                .joined(separator: ", ")
            let mouseDescription = mouseLocation.map(NSStringFromPoint) ?? "<skipped>"
            DebugLog.debug(
                DebugLog.dock,
                "Received touch frame with \(frame.touches.count) touches at mouse \(mouseDescription); hovered application = \(hoveredApplication?.logDescription ?? "nil"); touches = [\(touchSummary)]"
            )
        }
        guard let event = recognizer.process(frame: frame, hoveredApplication: hoveredApplication) else {
            return
        }

        do {
            let action = settingsStore.dockGestureAction(for: event.gesture)
            let application = event.application
            DebugLog.info(
                DebugLog.dock,
                "Dock gesture \(event.gesture.rawValue) mapped to \(action.rawValue) for \(application.logDescription)"
            )

            switch action {
            case .minimizeWindow:
                _ = try windowManager.minimizeVisibleWindow(of: application)
            case .restoreWindow:
                _ = try windowManager.restoreMinimizedWindow(of: application)
            case .cycleWindowsForward:
                _ = try windowManager.cycleVisibleWindows(of: application, direction: .forward)
            case .cycleWindowsBackward:
                _ = try windowManager.cycleVisibleWindows(of: application, direction: .backward)
            case .closeWindow:
                _ = try windowManager.closeVisibleWindow(of: application)
            case .quitApplication:
                _ = try windowManager.quitApplication(matching: application)
            }
        } catch let error as WindowManagerError {
            handleWindowManagerError(error)
        } catch {
            NSSound.beep()
            DebugLog.error(DebugLog.dock, "Dock gesture action failed: \(error.localizedDescription)")
        }
    }

    private func shouldLogFrame(touchCount: Int, hoveredApplication: DockApplicationTarget?) -> Bool {
        let hoveredApplicationLogValue = hoveredApplication?.logDescription
        let now = Date()
        let shouldLog = touchCount != lastLoggedTouchCount ||
            hoveredApplicationLogValue != lastLoggedHover ||
            now.timeIntervalSince(lastFrameLogAt) >= 0.25

        if shouldLog {
            lastFrameLogAt = now
            lastLoggedTouchCount = touchCount
            lastLoggedHover = hoveredApplicationLogValue
        }

        return shouldLog
    }

    private func handleWindowManagerError(_ error: WindowManagerError) {
        switch error {
        case .accessibilityPermissionMissing:
            guard hasShownPermissionHint == false else { return }

            hasShownPermissionHint = true
            alertPresenter.show(
                title: settingsStore.localized("alert.permission_required.title"),
                message: settingsStore.localized("alert.permission_required.message")
            )
        default:
            DebugLog.error(DebugLog.dock, "Dock gesture action failed: \(error.localizedDescription)")
        }
    }
}

@MainActor
private final class DockAccessibilityProbe {
    private let cacheTTL: TimeInterval = 0.25
    private let logTTL: TimeInterval = 0.4
    private var cachedCandidates: [DockItemCandidate] = []
    private var cacheExpiresAt = Date.distantPast
    private var lastProbeLogAt = Date.distantPast
    private var lastProbeLogKey = ""

    private struct ApplicationRecord {
        let application: NSRunningApplication
        let aliases: [String]
        let normalizedAliases: [String]
    }

    func hoveredApplication(at appKitPoint: CGPoint) -> DockApplicationTarget? {
        let candidates = dockCandidates()
        var nearestCandidates: [DockItemCandidate] = []

        for candidate in candidates {
            var candidate = candidate
            candidate.distance = distanceFromPoint(appKitPoint, to: candidate.frame)

            if candidate.frame.contains(appKitPoint) {
                logProbeIfNeeded(
                    key: "hit:\(candidate.target.dockItemName):\(candidate.target.processIdentifier):\(NSStringFromPoint(appKitPoint))",
                    message: {
                        "Pointer hit Dock item \(candidate.target.dockItemName) mapped to app \(candidate.target.logDescription) at \(NSStringFromPoint(appKitPoint)); frame = \(NSStringFromRect(candidate.frame)); distance = \(String(format: "%.2f", candidate.distance)); aliases = \(candidate.target.aliases.joined(separator: "|"))"
                    }
                )
                return candidate.target
            }

            insertNearestCandidate(candidate, into: &nearestCandidates)
        }

        let nearestKey = nearestCandidates
            .map {
                "\($0.target.dockItemName):\($0.target.processIdentifier):\(Int($0.distance * 100))"
            }
            .joined(separator: ",")

        logProbeIfNeeded(
            key: "miss:\(nearestKey)",
            message: {
                let nearestSummary = nearestCandidates
                    .map {
                        "\($0.target.dockItemName){app=\($0.target.logDescription), frame=\(NSStringFromRect($0.frame)), distance=\(String(format: "%.2f", $0.distance)), aliases=\($0.target.aliases.joined(separator: "|"))}"
                    }
                    .joined(separator: ", ")
                return "Pointer missed all Dock items at \(NSStringFromPoint(appKitPoint)); evaluated \(candidates.count) candidates; nearest = [\(nearestSummary)]"
            }
        )

        return nil
    }

    private func dockCandidates() -> [DockItemCandidate] {
        let now = Date()
        if now < cacheExpiresAt {
            return cachedCandidates
        }

        guard AXIsProcessTrusted() else { return [] }
        guard let dockProcess = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return []
        }

        let dockElement = AXUIElementCreateApplication(dockProcess.processIdentifier)
        guard let dockList = childElement(
            attribute: kAXChildrenAttribute as CFString,
            from: dockElement
        )?.first else {
            return []
        }

        let geometry = ScreenGeometry(screenFrames: NSScreen.screens.map(\.frame))
        var candidates: [DockItemCandidate] = []
        let applicationRecords = runningApplicationRecords()
        var qualityScoreCache: [pid_t: Int] = [:]

        for item in childElements(attribute: kAXChildrenAttribute as CFString, from: dockList) {
            guard let itemName = stringAttribute(kAXTitleAttribute as CFString, from: item) else {
                continue
            }

            guard let matchedRecord = matchingRunningApplication(
                forDockItemNamed: itemName,
                among: applicationRecords,
                qualityScoreCache: &qualityScoreCache
            ) else {
                continue
            }

            let matchedApplication = matchedRecord.application

            guard
                let axPosition = pointAttribute(kAXPositionAttribute as CFString, from: item),
                let axSize = sizeAttribute(kAXSizeAttribute as CFString, from: item)
            else {
                continue
            }

            let appKitFrame = geometry.appKitFrame(
                fromAXFrame: CGRect(origin: axPosition, size: axSize)
            )
            let target = DockApplicationTarget(
                dockItemName: itemName,
                resolvedApplicationName: matchedApplication.localizedName ?? itemName,
                processIdentifier: matchedApplication.processIdentifier,
                bundleIdentifier: matchedApplication.bundleIdentifier,
                aliases: matchedRecord.aliases
            )
            let candidate = DockItemCandidate(
                target: target,
                frame: appKitFrame,
                distance: 0
            )
            candidates.append(candidate)
        }

        cachedCandidates = candidates
        cacheExpiresAt = now.addingTimeInterval(cacheTTL)
        return candidates
    }

    private func distanceFromPoint(_ point: CGPoint, to frame: CGRect) -> CGFloat {
        if frame.contains(point) {
            return 0
        }

        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return sqrt((dx * dx) + (dy * dy))
    }

    private func matchingRunningApplication(
        forDockItemNamed dockItemName: String,
        among applicationRecords: [ApplicationRecord],
        qualityScoreCache: inout [pid_t: Int]
    ) -> ApplicationRecord? {
        let normalizedDockName = RunningApplicationIdentity.normalizedAlias(dockItemName)
        guard normalizedDockName.isEmpty == false else {
            return nil
        }

        var bestRecord: ApplicationRecord?
        var bestCombinedScore = Int.min

        for record in applicationRecords {
            let aliasScore = appMatchScore(
                forNormalizedDockName: normalizedDockName,
                normalizedAliases: record.normalizedAliases
            )
            guard aliasScore > 0 else {
                continue
            }

            let qualityScore = cachedApplicationQualityScore(
                for: record.application,
                qualityScoreCache: &qualityScoreCache
            )
            let combinedScore = (aliasScore * 1_000) + qualityScore

            if combinedScore > bestCombinedScore {
                bestCombinedScore = combinedScore
                bestRecord = record
                continue
            }

            if
                combinedScore == bestCombinedScore,
                let currentBestRecord = bestRecord,
                // Lower pid usually represents the long-lived primary app process.
                record.application.processIdentifier < currentBestRecord.application.processIdentifier
            {
                bestRecord = record
            }
        }

        return bestRecord
    }

    private func runningApplicationRecords() -> [ApplicationRecord] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            guard application.isTerminated == false else {
                return nil
            }

            let aliases = RunningApplicationIdentity.aliases(for: application)
            let normalizedAliases = Array(
                RunningApplicationIdentity.normalizedAliases(from: aliases)
            )

            return ApplicationRecord(
                application: application,
                aliases: aliases,
                normalizedAliases: normalizedAliases
            )
        }
    }

    private func cachedApplicationQualityScore(
        for application: NSRunningApplication,
        qualityScoreCache: inout [pid_t: Int]
    ) -> Int {
        if let cachedScore = qualityScoreCache[application.processIdentifier] {
            return cachedScore
        }

        let score = applicationQualityScore(for: application)
        qualityScoreCache[application.processIdentifier] = score
        return score
    }

    private func applicationQualityScore(for application: NSRunningApplication) -> Int {
        var score = 0

        switch application.activationPolicy {
        case .regular:
            score += 240
        case .accessory:
            score += 100
        case .prohibited:
            score += 0
        @unknown default:
            score += 0
        }

        if hasAnyWindow(for: application) {
            score += 120
        }

        if application.isHidden == false {
            score += 20
        }

        if RunningApplicationIdentity.isLikelyHelperProcess(application) {
            score -= 220
        }

        return score
    }

    private func hasAnyWindow(for application: NSRunningApplication) -> Bool {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)

        guard error == .success, let windows = value as? [AnyObject] else {
            return false
        }

        return windows.isEmpty == false
    }

    private func logProbeIfNeeded(key: String, message: () -> String) {
        let now = Date()
        guard key != lastProbeLogKey || now.timeIntervalSince(lastProbeLogAt) >= logTTL else {
            return
        }

        lastProbeLogKey = key
        lastProbeLogAt = now
        DebugLog.debug(DebugLog.dock, message())
    }

    private func insertNearestCandidate(
        _ candidate: DockItemCandidate,
        into nearestCandidates: inout [DockItemCandidate]
    ) {
        let insertionIndex = nearestCandidates.firstIndex { candidate.distance < $0.distance } ?? nearestCandidates.endIndex
        nearestCandidates.insert(candidate, at: insertionIndex)

        if nearestCandidates.count > 4 {
            nearestCandidates.removeLast()
        }
    }

    private func appMatchScore(forNormalizedDockName normalizedDockName: String, normalizedAliases: [String]) -> Int {
        var bestScore = 0
        for normalizedAlias in normalizedAliases {
            if normalizedAlias == normalizedDockName {
                bestScore = max(bestScore, 3)
            } else if normalizedAlias.contains(normalizedDockName) || normalizedDockName.contains(normalizedAlias) {
                bestScore = max(bestScore, 2)
            }
        }

        return bestScore
    }

    private func childElements(attribute: CFString, from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard error == .success, let children = value as? [AnyObject] else {
            return []
        }

        let elements: [AXUIElement] = children.compactMap { child -> AXUIElement? in
            guard CFGetTypeID(child) == AXUIElementGetTypeID() else {
                return nil
            }
            return unsafeDowncast(child, to: AXUIElement.self)
        }
        if elements.count != children.count {
            DebugLog.debug(
                DebugLog.accessibility,
                "Dropped \(children.count - elements.count) non-AX children for attribute \(attribute as String)"
            )
        }
        return elements
    }

    private func childElement(attribute: CFString, from element: AXUIElement) -> [AXUIElement]? {
        let children = childElements(attribute: attribute, from: element)
        return children.isEmpty ? nil : children
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else { return nil }
        return value as? String
    }

    private func pointAttribute(_ attribute: CFString, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success, let axValue = value else { return nil }

        guard CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
        let pointValue = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(pointValue) == .cgPoint else { return nil }

        var point = CGPoint.zero
        guard AXValueGetValue(pointValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ attribute: CFString, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success, let axValue = value else { return nil }

        guard CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
        let sizeValue = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(sizeValue) == .cgSize else { return nil }

        var size = CGSize.zero
        guard AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return size
    }

    private struct DockItemCandidate {
        let target: DockApplicationTarget
        let frame: CGRect
        var distance: CGFloat
    }
}

private final class MultitouchInputMonitor {
    var onFrame: ((TrackpadTouchFrame) -> Void)?

    private var isMonitoring = false

    func startIfAvailable() {
        guard isMonitoring == false else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        isMonitoring = SwooshyMTStartMonitoring(multitouchCallback, context)
        if isMonitoring == false {
            DebugLog.error(DebugLog.dock, "MultitouchSupport monitoring unavailable")
        } else {
            DebugLog.info(DebugLog.dock, "MultitouchSupport monitoring active")
        }
    }

    func stop() {
        guard isMonitoring else { return }
        SwooshyMTStopMonitoring()
        isMonitoring = false
        DebugLog.info(DebugLog.dock, "MultitouchSupport monitoring stopped")
    }

    fileprivate func receive(
        fingers: UnsafePointer<SwooshyMTFinger>,
        fingerCount: Int,
        timestamp: Double
    ) {
        guard fingerCount > 0 else {
            onFrame?(
                TrackpadTouchFrame(
                    touches: [],
                    timestamp: timestamp
                )
            )
            return
        }

        let buffer = UnsafeBufferPointer(start: fingers, count: fingerCount)
        let touches = buffer.map {
            TrackpadTouchSample(
                identifier: Int($0.identifier),
                position: CGPoint(
                    x: CGFloat($0.normalized.position.x),
                    y: CGFloat($0.normalized.position.y)
                )
            )
        }

        onFrame?(
            TrackpadTouchFrame(
                touches: touches,
                timestamp: timestamp
            )
        )
    }
}

private func multitouchCallback(
    _ device: Int32,
    _ data: UnsafePointer<SwooshyMTFinger>?,
    _ fingerCount: Int32,
    _ timestamp: Double,
    _ frame: Int32,
    _ context: UnsafeMutableRawPointer?
) {
    guard let data, let context else { return }
    let monitor = Unmanaged<MultitouchInputMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.receive(
        fingers: data,
        fingerCount: Int(fingerCount),
        timestamp: timestamp
    )
}
