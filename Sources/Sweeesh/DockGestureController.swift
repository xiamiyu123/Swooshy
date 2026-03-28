import AppKit
import ApplicationServices
import CMultitouchShim
import Dispatch
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
            self?.handle(frame: frame)
        }

        observeSettings()
        syncMonitoring()
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

        let mouseLocation = NSEvent.mouseLocation
        let hoveredApplication = dockProbe.hoveredApplication(at: mouseLocation)
        if shouldLogFrame(touchCount: frame.touches.count, hoveredApplication: hoveredApplication) {
            let touchSummary = frame.touches
                .map { "#\($0.identifier)=\(NSStringFromPoint($0.position))" }
                .joined(separator: ", ")
            DebugLog.debug(
                DebugLog.dock,
                "Received touch frame with \(frame.touches.count) touches at mouse \(NSStringFromPoint(mouseLocation)); hovered application = \(hoveredApplication?.logDescription ?? "nil"); touches = [\(touchSummary)]"
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
    private let cacheTTL: TimeInterval = 0.75
    private let logTTL: TimeInterval = 0.4
    private let probeMargin: CGFloat = 24
    private var cachedCandidates: [DockItemCandidate] = []
    private var cachedDockBounds: CGRect = .null
    private var cacheExpiresAt = Date.distantPast
    private var lastProbeLogAt = Date.distantPast
    private var lastProbeLogKey = ""
    private var lastResolvedPoint: CGPoint?
    private var lastResolvedTarget: DockApplicationTarget?
    private var lastResolvedCandidateFrame: CGRect?
    private var invalidationObservers: [NSObjectProtocol] = []

    init() {
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        invalidationObservers = [
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.invalidateCache()
                }
            },
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.invalidateCache()
                }
            },
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didHideApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.invalidateCache()
                }
            },
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didUnhideApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.invalidateCache()
                }
            },
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.invalidateCache()
                }
            },
        ]
    }

    func hoveredApplication(at appKitPoint: CGPoint) -> DockApplicationTarget? {
        if lastResolvedPoint == appKitPoint {
            return lastResolvedTarget
        }

        if let lastResolvedCandidateFrame, lastResolvedCandidateFrame.contains(appKitPoint) {
            lastResolvedPoint = appKitPoint
            return lastResolvedTarget
        }

        let now = Date()
        if
            cachedDockBounds.isNull == false,
            now < cacheExpiresAt,
            expandedDockBounds().contains(appKitPoint) == false
        {
            cacheResolvedTarget(nil, frame: nil, for: appKitPoint)
            return nil
        }

        let candidates = dockCandidates()
        guard candidates.isEmpty == false else {
            cacheResolvedTarget(nil, frame: nil, for: appKitPoint)
            return nil
        }

        guard expandedDockBounds().contains(appKitPoint) else {
            cacheResolvedTarget(nil, frame: nil, for: appKitPoint)
            return nil
        }

        var nearestCandidates: [DockItemCandidate] = []
        let shouldCollectNearestCandidates = DebugLog.isEnabled

        for candidate in candidates {
            var candidate = candidate

            if candidate.frame.contains(appKitPoint) {
                logProbeIfNeeded(
                    key: "hit:\(candidate.target.dockItemName):\(candidate.target.processIdentifier):\(NSStringFromRect(candidate.frame))",
                    message: "Pointer hit Dock item \(candidate.target.dockItemName) mapped to app \(candidate.target.logDescription) at \(NSStringFromPoint(appKitPoint)); frame = \(NSStringFromRect(candidate.frame)); aliases = \(candidate.target.aliases.joined(separator: "|"))"
                )
                cacheResolvedTarget(candidate.target, frame: candidate.frame, for: appKitPoint)
                return candidate.target
            }

            guard shouldCollectNearestCandidates else { continue }

            candidate.distance = distanceFromPoint(appKitPoint, to: candidate.frame)
            insertNearestCandidate(candidate, into: &nearestCandidates)
        }

        if shouldCollectNearestCandidates {
            let nearestSummary = nearestCandidates
                .map {
                    "\($0.target.dockItemName){app=\($0.target.logDescription), frame=\(NSStringFromRect($0.frame)), distance=\(String(format: "%.2f", $0.distance)), aliases=\($0.target.aliases.joined(separator: "|"))}"
                }
                .joined(separator: ", ")

            logProbeIfNeeded(
                key: "miss:\(NSStringFromRect(cachedDockBounds))",
                message: "Pointer missed all Dock items at \(NSStringFromPoint(appKitPoint)); evaluated \(candidates.count) candidates; nearest = [\(nearestSummary)]"
            )
        }

        cacheResolvedTarget(nil, frame: nil, for: appKitPoint)
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
        var qualityScoreCache: [pid_t: Int] = [:]
        var aliasCache: [pid_t: [String]] = [:]
        var dockBounds: CGRect = .null

        for item in childElements(attribute: kAXChildrenAttribute as CFString, from: dockList) {
            guard let itemName = stringAttribute(kAXTitleAttribute as CFString, from: item) else {
                continue
            }

            guard let matchedApplication = matchingRunningApplication(
                forDockItemNamed: itemName,
                qualityScoreCache: &qualityScoreCache,
                aliasCache: &aliasCache
            ) else {
                continue
            }

            guard
                let axPosition = pointAttribute(kAXPositionAttribute as CFString, from: item),
                let axSize = sizeAttribute(kAXSizeAttribute as CFString, from: item)
            else {
                continue
            }

            let appKitFrame = geometry.appKitFrame(
                fromAXFrame: CGRect(origin: axPosition, size: axSize)
            )
            let aliases = cachedApplicationAliases(for: matchedApplication, aliasCache: &aliasCache)
            let target = DockApplicationTarget(
                dockItemName: itemName,
                resolvedApplicationName: matchedApplication.localizedName ?? itemName,
                processIdentifier: matchedApplication.processIdentifier,
                bundleIdentifier: matchedApplication.bundleIdentifier,
                aliases: aliases
            )
            let candidate = DockItemCandidate(
                target: target,
                frame: appKitFrame,
                distance: 0
            )
            candidates.append(candidate)
            dockBounds = dockBounds.union(appKitFrame)
        }

        cachedCandidates = candidates
        cachedDockBounds = dockBounds
        cacheExpiresAt = now.addingTimeInterval(cacheTTL)
        return candidates
    }

    private func expandedDockBounds() -> CGRect {
        cachedDockBounds.insetBy(dx: -probeMargin, dy: -probeMargin)
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
        qualityScoreCache: inout [pid_t: Int],
        aliasCache: inout [pid_t: [String]]
    ) -> NSRunningApplication? {
        let scoredMatches = NSWorkspace.shared.runningApplications.compactMap { application -> (NSRunningApplication, Int, Int)? in
            let aliasScore = appMatchScore(
                forDockItemNamed: dockItemName,
                aliases: cachedApplicationAliases(for: application, aliasCache: &aliasCache)
            )
            guard aliasScore > 0 else {
                return nil
            }

            let qualityScore = cachedApplicationQualityScore(
                for: application,
                qualityScoreCache: &qualityScoreCache
            )
            return (application, aliasScore, qualityScore)
        }

        return scoredMatches.max {
            let lhsCombinedScore = ($0.1 * 1_000) + $0.2
            let rhsCombinedScore = ($1.1 * 1_000) + $1.2

            if lhsCombinedScore == rhsCombinedScore {
                // Lower pid usually represents the long-lived primary app process.
                return $0.0.processIdentifier > $1.0.processIdentifier
            }

            return lhsCombinedScore < rhsCombinedScore
        }?.0
    }

    private func cachedApplicationAliases(
        for application: NSRunningApplication,
        aliasCache: inout [pid_t: [String]]
    ) -> [String] {
        if let aliases = aliasCache[application.processIdentifier] {
            return aliases
        }

        let aliases = applicationAliases(for: application)
        aliasCache[application.processIdentifier] = aliases
        return aliases
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

        if isLikelyHelperProcess(application) {
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

    private func isLikelyHelperProcess(_ application: NSRunningApplication) -> Bool {
        let localizedName = (application.localizedName ?? "").lowercased()
        let bundleIdentifier = (application.bundleIdentifier ?? "").lowercased()
        let bundlePath = (application.bundleURL?.path ?? "").lowercased()

        if localizedName.contains("helper") || localizedName.contains("notification service") {
            return true
        }

        if bundleIdentifier.contains(".framework.") || bundleIdentifier.contains(".helper") {
            return true
        }

        if bundlePath.contains("/frameworks/") || bundlePath.contains("/helpers/") || bundlePath.contains(".appex/") {
            return true
        }

        return false
    }

    private func logProbeIfNeeded(key: String, message: @autoclosure () -> String) {
        let now = Date()
        guard key != lastProbeLogKey || now.timeIntervalSince(lastProbeLogAt) >= logTTL else {
            return
        }

        lastProbeLogKey = key
        lastProbeLogAt = now
        DebugLog.debug(DebugLog.dock, message())
    }

    private func cacheResolvedTarget(
        _ target: DockApplicationTarget?,
        frame: CGRect?,
        for point: CGPoint
    ) {
        lastResolvedPoint = point
        lastResolvedTarget = target
        lastResolvedCandidateFrame = frame
    }

    private func invalidateCache() {
        cachedCandidates = []
        cachedDockBounds = .null
        cacheExpiresAt = .distantPast
        lastResolvedPoint = nil
        lastResolvedTarget = nil
        lastResolvedCandidateFrame = nil
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

    private func applicationAliases(for application: NSRunningApplication) -> [String] {
        var aliases: Set<String> = []

        if let localizedName = application.localizedName, localizedName.isEmpty == false {
            aliases.insert(localizedName)
        }

        if let bundleIdentifier = application.bundleIdentifier, bundleIdentifier.isEmpty == false {
            aliases.insert(bundleIdentifier)
        }

        if let bundleURL = application.bundleURL {
            aliases.insert(bundleURL.deletingPathExtension().lastPathComponent)

            if
                let bundle = Bundle(url: bundleURL),
                let info = bundle.infoDictionary
            {
                let keys = [
                    "CFBundleDisplayName",
                    "CFBundleName",
                    "CFBundleExecutable",
                ]

                for key in keys {
                    if let value = info[key] as? String, value.isEmpty == false {
                        aliases.insert(value)
                    }
                }
            }
        }

        return Array(aliases)
    }

    private func appMatchScore(forDockItemNamed dockItemName: String, aliases: [String]) -> Int {
        let normalizedDockName = normalizedAlias(dockItemName)
        guard normalizedDockName.isEmpty == false else {
            return 0
        }

        var bestScore = 0
        for alias in aliases {
            let normalizedAlias = normalizedAlias(alias)
            guard normalizedAlias.isEmpty == false else {
                continue
            }

            if normalizedAlias == normalizedDockName {
                bestScore = max(bestScore, 3)
            } else if normalizedAlias.contains(normalizedDockName) || normalizedDockName.contains(normalizedAlias) {
                bestScore = max(bestScore, 2)
            }
        }

        return bestScore
    }

    private func normalizedAlias(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private func childElements(attribute: CFString, from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard error == .success, let children = value as? [AnyObject] else {
            return []
        }

        return children.map { unsafeDowncast($0, to: AXUIElement.self) }
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

private final class MultitouchInputMonitor: @unchecked Sendable {
    var onFrame: ((TrackpadTouchFrame) -> Void)?

    private var isMonitoring = false
    private let deliveryStateQueue = DispatchQueue(label: "Sweeesh.MultitouchInputMonitor.delivery")
    private var latestFrame: TrackpadTouchFrame?
    private var isFrameDeliveryScheduled = false

    func startIfAvailable() {
        guard isMonitoring == false else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        isMonitoring = SweeeshMTStartMonitoring(multitouchCallback, context)
        if isMonitoring == false {
            DebugLog.error(DebugLog.dock, "MultitouchSupport monitoring unavailable")
        } else {
            DebugLog.info(DebugLog.dock, "MultitouchSupport monitoring active")
        }
    }

    func stop() {
        guard isMonitoring else { return }
        SweeeshMTStopMonitoring()
        isMonitoring = false
        deliveryStateQueue.sync {
            latestFrame = nil
            isFrameDeliveryScheduled = false
        }
        DebugLog.info(DebugLog.dock, "MultitouchSupport monitoring stopped")
    }

    fileprivate func receive(
        fingers: UnsafePointer<SweeeshMTFinger>,
        fingerCount: Int,
        timestamp: Double
    ) {
        let frame: TrackpadTouchFrame

        guard fingerCount > 0 else {
            frame = TrackpadTouchFrame(
                touches: [],
                timestamp: timestamp
            )
            enqueue(frame: frame)
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

        frame = TrackpadTouchFrame(
            touches: touches,
            timestamp: timestamp
        )
        enqueue(frame: frame)
    }

    private func enqueue(frame: TrackpadTouchFrame) {
        deliveryStateQueue.async { [weak self] in
            guard let self else { return }

            self.latestFrame = frame
            guard self.isFrameDeliveryScheduled == false else { return }

            self.isFrameDeliveryScheduled = true
            self.scheduleMainDelivery()
        }
    }

    private func deliverPendingFrameOnMain() {
        let frame = deliveryStateQueue.sync { () -> TrackpadTouchFrame? in
            let frame = latestFrame
            latestFrame = nil
            isFrameDeliveryScheduled = false
            return frame
        }

        guard let frame else { return }
        onFrame?(frame)

        deliveryStateQueue.async { [weak self] in
            guard let self, self.latestFrame != nil, self.isFrameDeliveryScheduled == false else { return }

            self.isFrameDeliveryScheduled = true
            self.scheduleMainDelivery()
        }
    }

    private func scheduleMainDelivery() {
        let monitorPointer = Unmanaged.passRetained(self).toOpaque()
        DispatchQueue.main.async {
            let monitor = Unmanaged<MultitouchInputMonitor>.fromOpaque(monitorPointer).takeRetainedValue()
            monitor.deliverPendingFrameOnMain()
        }
    }
}

private func multitouchCallback(
    _ device: Int32,
    _ data: UnsafePointer<SweeeshMTFinger>?,
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
