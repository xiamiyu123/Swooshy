import AppKit
import ApplicationServices
import CMultitouchShim
import Foundation

@MainActor
final class DockGestureController {
    private let windowManager: WindowManager
    private let layoutEngine: WindowLayoutEngine
    private let alertPresenter: AlertPresenting
    private let gestureFeedbackPresenter: GestureFeedbackPresenting
    private let settingsStore: SettingsStore
    private let dockProbe = DockAccessibilityProbe()
    private let titleBarProbe = TitleBarAccessibilityProbe()
    private let monitor = MultitouchInputMonitor()
    private var dockRecognizer = DockGestureRecognizer()
    private var titleBarRecognizer = DockGestureRecognizer()
    private var hasShownPermissionHint = false
    private var settingsObserver: NSObjectProtocol?
#if DEBUG
    private var lastFrameLogAt = Date.distantPast
    private var lastLoggedTouchCount = -1
    private var lastLoggedHover: String?
#endif
    private var pendingTouchFrame: TrackpadTouchFrame?
    private var isProcessingTouchFrame = false
    private var monitoringState: MonitoringState?
    private var isShuttingDown = false
    private let restoreHUDLeadDelay: UInt64 = 16_000_000

    private var pendingReleaseAction: PendingReleaseAction?
    private var escMonitor: Any?
    private var lastTouchCount: Int = 0
    private var pendingReleaseGestureKind: DockGestureKind?
    private var pendingReleaseHighWaterMark: CGFloat?
    private var pendingReleasePinchHighWaterMark: CGFloat?

    private enum PendingReleaseAction {
        case dock(action: DockGestureAction, application: DockApplicationTarget)
        case titleBar(
            action: WindowAction,
            event: DockGestureEvent,
            anchorPoint: CGPoint,
            replacesWithTabClose: Bool
        )
    }

    private struct MonitoringState: Equatable {
        let dockGesturesEnabled: Bool
        let titleBarGesturesEnabled: Bool
    }

    init(
        windowManager: WindowManager,
        layoutEngine: WindowLayoutEngine,
        alertPresenter: AlertPresenting,
        gestureFeedbackPresenter: GestureFeedbackPresenting,
        settingsStore: SettingsStore
    ) {
        self.windowManager = windowManager
        self.layoutEngine = layoutEngine
        self.alertPresenter = alertPresenter
        self.gestureFeedbackPresenter = gestureFeedbackPresenter
        self.settingsStore = settingsStore

        monitor.onFrame = { [weak self] frame in
            self?.enqueue(frame: frame)
        }

        observeSettings()
        syncMonitoring()
    }

    func shutdown() {
        guard isShuttingDown == false else { return }
        isShuttingDown = true

        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }

        pendingTouchFrame = nil
        isProcessingTouchFrame = false
        monitoringState = nil
        dockRecognizer = makeConfiguredRecognizer()
        titleBarRecognizer = makeConfiguredRecognizer()
        dockProbe.clearCache()
        titleBarProbe.clearCache()
        monitor.onFrame = nil
        monitor.stop()
        cancelPendingReleaseAction()
    }

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: settingsStore,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dockProbe.clearCache()
                self?.titleBarProbe.clearCache()
                self?.syncMonitoring()
            }
        }
    }

    private func syncMonitoring() {
        guard isShuttingDown == false else {
            return
        }

        let state = MonitoringState(
            dockGesturesEnabled: settingsStore.dockGesturesEnabled,
            titleBarGesturesEnabled: settingsStore.titleBarGesturesEnabled
        )
        guard state != monitoringState else { return }

        monitoringState = state
        dockRecognizer = makeConfiguredRecognizer()
        titleBarRecognizer = makeConfiguredRecognizer()
        dockProbe.clearCache()
        titleBarProbe.clearCache()
        pendingTouchFrame = nil
        isProcessingTouchFrame = false
        cancelPendingReleaseAction()

        if state.dockGesturesEnabled || state.titleBarGesturesEnabled {
            DebugLog.info(DebugLog.dock, "Starting trackpad gesture monitoring")
            monitor.startIfAvailable()
        } else {
            DebugLog.info(DebugLog.dock, "Stopping trackpad gesture monitoring")
            monitor.stop()
        }
    }

    nonisolated private func enqueue(frame: TrackpadTouchFrame) {
        Task { @MainActor [weak self] in
            guard let self, self.isShuttingDown == false else { return }
            self.schedule(frame: frame)
        }
    }

    private func schedule(frame: TrackpadTouchFrame) {
        guard isShuttingDown == false else { return }

        pendingTouchFrame = frame
        guard isProcessingTouchFrame == false else { return }

        isProcessingTouchFrame = true
        drainPendingFrames()
    }

    private func drainPendingFrames() {
        defer {
            isProcessingTouchFrame = false
        }

        while let nextFrame = pendingTouchFrame {
            pendingTouchFrame = nil
            handle(frame: nextFrame)
        }
    }

    private func handle(frame: TrackpadTouchFrame) {
        guard isShuttingDown == false else { return }

        let dockGesturesEnabled = settingsStore.dockGesturesEnabled
        let titleBarGesturesEnabled = settingsStore.titleBarGesturesEnabled
        guard dockGesturesEnabled || titleBarGesturesEnabled else { return }

        let touchCount = frame.touches.count
        let previousTouchCount = lastTouchCount
        lastTouchCount = touchCount

        // Execute pending action on finger release (touch count drops to 0).
        if touchCount == 0, previousTouchCount > 0, pendingReleaseAction != nil {
            executePendingReleaseAction()
            // Still let recognizers see the zero-touch frame.
        }

        // Keep the hot path cheap: only two-finger input can produce these gestures.
        guard frame.touches.count == 2 else {
            if dockGesturesEnabled {
                _ = dockRecognizer.process(frame: frame, hoveredApplication: nil)
            }
            if titleBarGesturesEnabled {
                _ = titleBarRecognizer.process(frame: frame, hoveredApplication: nil)
            }
            return
        }

        // Check for reverse swipe cancellation while fingers are still down.
        if pendingReleaseAction != nil {
            checkReverseCancellation(frame: frame)
            if pendingReleaseAction == nil {
                return
            }
        }

        let needsDockLookup = dockGesturesEnabled && dockRecognizer.requiresHoveredApplication
        let needsTitleBarLookup = titleBarGesturesEnabled && titleBarRecognizer.requiresHoveredApplication
        let mouseLocation = (needsDockLookup || needsTitleBarLookup) ? NSEvent.mouseLocation : nil
        let hoveredDockApplication = needsDockLookup ? mouseLocation.flatMap {
            dockProbe.hoveredApplication(
                at: $0,
                requireFrontmostOwnership: settingsStore.titleBarOverlayProtectionEnabled
            )
        } : nil
        let hoveredTitleBarApplication = needsTitleBarLookup && hoveredDockApplication == nil
            ? mouseLocation.flatMap {
                titleBarProbe.hoveredApplication(
                    at: $0,
                    requireFrontmostOwnership: settingsStore.titleBarOverlayProtectionEnabled,
                    allowFullScreen: settingsStore.smartPinchExitFullScreenEnabled,
                    allowBrowserTabFallback: settingsStore.smartBrowserTabCloseEnabled
                )
            }
            : nil

#if DEBUG
        if shouldLogFrame(
            touchCount: frame.touches.count,
            dockHoveredApplication: hoveredDockApplication,
            titleBarHoveredApplication: hoveredTitleBarApplication
        ) {
            let touchSummary = frame.touches
                .map { "#\($0.identifier)=\(NSStringFromPoint($0.position))" }
                .joined(separator: ", ")
            let mouseDescription = mouseLocation.map(NSStringFromPoint) ?? "<skipped>"
            DebugLog.debug(
                DebugLog.dock,
                "Received touch frame with \(frame.touches.count) touches at mouse \(mouseDescription); dock hover = \(hoveredDockApplication?.logDescription ?? "nil"); title-bar hover = \(hoveredTitleBarApplication?.logDescription ?? "nil"); touches = [\(touchSummary)]"
            )
        }
#endif

        if dockGesturesEnabled, let dockEvent = dockRecognizer.process(frame: frame, hoveredApplication: hoveredDockApplication) {
            let anchorPoint = mouseLocation ?? NSEvent.mouseLocation
            handleDockGestureEvent(dockEvent, anchorPoint: anchorPoint, touches: frame.touches)
            return
        }

        guard titleBarGesturesEnabled, let titleBarEvent = titleBarRecognizer.process(frame: frame, hoveredApplication: hoveredTitleBarApplication) else {
            return
        }

        let anchorPoint = mouseLocation ?? NSEvent.mouseLocation
        handleTitleBarGestureEvent(titleBarEvent, anchorPoint: anchorPoint, touches: frame.touches)
    }

    private func handleDockGestureEvent(_ event: DockGestureEvent, anchorPoint: CGPoint, touches: [TrackpadTouchSample]) {
        guard settingsStore.dockGestureIsEnabled(for: event.gesture) else {
            DebugLog.debug(DebugLog.dock, "Ignoring disabled Dock gesture \(event.gesture.rawValue)")
            return
        }
        let action = settingsStore.dockGestureAction(for: event.gesture)
        let application = event.application
        let persistent = settingsStore.executeGestureOnRelease
        gestureFeedbackPresenter.show(
            gesture: event.gesture,
            gestureTitle: event.gesture.title(preferredLanguages: settingsStore.preferredLanguages),
            actionTitle: action.title(preferredLanguages: settingsStore.preferredLanguages),
            anchor: anchorPoint,
            persistent: persistent
        )
        DebugLog.info(
            DebugLog.dock,
            "Dock gesture \(event.gesture.rawValue) mapped to \(action.rawValue) for \(application.logDescription)"
        )

        if persistent {
            pendingReleaseAction = .dock(action: action, application: application)
            storeTouchAnchor(gesture: event.gesture, touches: touches)
            installEscMonitor()
            DebugLog.info(DebugLog.dock, "Deferred dock action \(action.rawValue) until finger release")
        } else {
            scheduleDockGestureAction(action, for: application)
        }
    }

    private func scheduleDockGestureAction(_ action: DockGestureAction, for application: DockApplicationTarget) {
        Task { @MainActor [weak self] in
            guard let self, self.isShuttingDown == false else { return }

            await Task.yield()

            // Give AppKit one frame to present HUD before heavier restore AX work.
            if action == .restoreWindow {
                try? await Task.sleep(nanoseconds: self.restoreHUDLeadDelay)
                guard self.isShuttingDown == false else { return }
            }

            self.performDockGestureAction(action, for: application)
        }
    }

    private func performDockGestureAction(_ action: DockGestureAction, for application: DockApplicationTarget) {
        do {
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
            case .closeTab:
                guard BrowserTabProbe.simulateMiddleClickAtMouseLocation() else {
                    throw WindowManagerError.unableToPerformAction
                }
            case .quitApplication:
                _ = try windowManager.quitApplication(matching: application)
            case .toggleFullScreenWindow:
                _ = try windowManager.toggleFullScreenWindow(of: application)
            }
        } catch let error as WindowManagerError {
            handleWindowManagerError(error)
        } catch {
            NSSound.beep()
            DebugLog.error(DebugLog.dock, "Dock gesture action failed: \(error.localizedDescription)")
        }
    }

    private func handleTitleBarGestureEvent(_ event: DockGestureEvent, anchorPoint: CGPoint, touches: [TrackpadTouchSample]) {
        guard
            let frontmostApplication = NSWorkspace.shared.frontmostApplication,
            frontmostApplication.processIdentifier == event.application.processIdentifier
        else {
            DebugLog.debug(
                DebugLog.dock,
                "Ignoring title-bar gesture \(event.gesture.rawValue) because frontmost app changed"
            )
            return
        }

        guard let action = titleBarAction(for: event.gesture) else {
            DebugLog.debug(DebugLog.dock, "Ignoring unsupported title-bar gesture \(event.gesture.rawValue)")
            return
        }

        guard settingsStore.titleBarGestureIsEnabled(for: event.gesture) else {
            DebugLog.debug(DebugLog.dock, "Ignoring disabled title-bar gesture \(event.gesture.rawValue)")
            return
        }

        let window = try? windowManager.focusedWindowElement(in: AXUIElementCreateApplication(frontmostApplication.processIdentifier))
        let isInFullScreen = window.map { windowManager.isFullScreen($0) } ?? false

        // Whitelist: In Full Screen, ONLY Pinch In is allowed (for smart exit).
        if isInFullScreen {
            guard settingsStore.smartPinchExitFullScreenEnabled, event.gesture == .pinchIn else {
                DebugLog.debug(DebugLog.dock, "Ignoring title-bar gesture \(event.gesture.rawValue) in Full Screen because it is not Pinch In")
                return
            }
        }

        let replacesWithTabClose = shouldReplaceWithBrowserTabClose(
            action: action,
            event: event,
            anchorPoint: anchorPoint,
            isInFullScreen: isInFullScreen
        )

        var actionTitle = action.title(preferredLanguages: settingsStore.preferredLanguages)
        if replacesWithTabClose {
            actionTitle = L10n.string(
                "action.close_tab",
                preferredLanguages: settingsStore.preferredLanguages
            )
        }
        if isInFullScreen, event.gesture == .pinchIn {
            actionTitle = L10n.string(
                "action.exit_full_screen",
                preferredLanguages: settingsStore.preferredLanguages
            )
        }

        let persistent = settingsStore.executeGestureOnRelease
        gestureFeedbackPresenter.show(
            gesture: event.gesture,
            gestureTitle: event.gesture.title(preferredLanguages: settingsStore.preferredLanguages),
            actionTitle: actionTitle,
            anchor: anchorPoint,
            persistent: persistent
        )
        DebugLog.info(
            DebugLog.dock,
            "Title-bar gesture \(event.gesture.rawValue) mapped to \(actionTitle) for \(event.application.logDescription)"
        )

        if persistent {
            pendingReleaseAction = .titleBar(
                action: action,
                event: event,
                anchorPoint: anchorPoint,
                replacesWithTabClose: replacesWithTabClose
            )
            storeTouchAnchor(gesture: event.gesture, touches: touches)
            installEscMonitor()
            DebugLog.info(DebugLog.dock, "Deferred title-bar action \(String(describing: action)) until finger release")
        } else {
            executeTitleBarAction(
                action,
                event: event,
                anchorPoint: anchorPoint,
                replacesWithTabClose: replacesWithTabClose
            )
        }
    }

    private func executeTitleBarAction(
        _ action: WindowAction,
        event: DockGestureEvent,
        anchorPoint: CGPoint,
        replacesWithTabClose: Bool = false
    ) {
        do {
            if settingsStore.smartPinchExitFullScreenEnabled, event.gesture == .pinchIn {
                let app = try windowManager.runningApplication(matching: event.application)
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                if let window = try? windowManager.focusedWindowElement(in: appElement),
                   windowManager.isFullScreen(window) {
                    try windowManager.setFullScreen(false, for: window)
                    DebugLog.info(DebugLog.dock, "Smart intercept: pinched in on full screen window, forced exit.")
                    return
                }
            }

            if replacesWithTabClose {
                if BrowserTabProbe.simulateMiddleClick(at: anchorPoint) {
                    DebugLog.info(
                        DebugLog.dock,
                        "Smart browser tab close replaced \(String(describing: action)) for \(event.application.logDescription)"
                    )
                    return
                }

                DebugLog.error(
                    DebugLog.dock,
                    "Smart browser tab close simulation failed; falling back to \(String(describing: action)) for \(event.application.logDescription)"
                )
            }

            try windowManager.perform(
                action,
                layoutEngine: layoutEngine,
                preferredAppKitPoint: anchorPoint
            )
        } catch let error as WindowManagerError {
            handleWindowManagerError(error)
        } catch {
            NSSound.beep()
            DebugLog.error(DebugLog.dock, "Title-bar gesture action failed: \(error.localizedDescription)")
        }
    }

    private func titleBarAction(for gesture: DockGestureKind) -> WindowAction? {
        settingsStore.titleBarGestureAction(for: gesture)
    }

    private func shouldReplaceWithBrowserTabClose(
        action: WindowAction,
        event: DockGestureEvent,
        anchorPoint: CGPoint,
        isInFullScreen: Bool
    ) -> Bool {
        guard settingsStore.smartBrowserTabCloseEnabled else {
            DebugLog.debug(DebugLog.dock, "Smart browser tab close disabled; skip replacement")
            return false
        }

        guard isInFullScreen == false else {
            DebugLog.debug(DebugLog.dock, "Smart browser tab close skipped in full screen")
            return false
        }

        guard action == .closeWindow || action == .quitApplication else {
            DebugLog.debug(DebugLog.dock, "Smart browser tab close skipped for non-close action \(String(describing: action))")
            return false
        }

        let isBrowserTab = BrowserTabProbe.isBrowserTab(
            at: anchorPoint,
            processIdentifier: event.application.processIdentifier
        )

        DebugLog.debug(
            DebugLog.dock,
            "Smart browser tab probe for \(event.application.logDescription) at \(NSStringFromPoint(anchorPoint)) => \(isBrowserTab)"
        )
        return isBrowserTab
    }

    // MARK: - Execute on Release

    private func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return } // 53 = Esc
            Task { @MainActor [weak self] in
                self?.cancelPendingReleaseAction()
            }
        }
        DebugLog.debug(DebugLog.dock, "Installed global Esc monitor for pending gesture")
    }

    private func removeEscMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
            DebugLog.debug(DebugLog.dock, "Removed global Esc monitor")
        }
    }

    private func cancelPendingReleaseAction() {
        guard pendingReleaseAction != nil else {
            removeEscMonitor()
            return
        }
        DebugLog.info(DebugLog.dock, "Cancelled pending gesture action")
        pendingReleaseAction = nil
        clearTouchAnchor()
        removeEscMonitor()
        gestureFeedbackPresenter.dismiss()
    }

    private func executePendingReleaseAction() {
        guard let action = pendingReleaseAction else { return }
        pendingReleaseAction = nil
        clearTouchAnchor()
        removeEscMonitor()
        gestureFeedbackPresenter.scheduleDismiss()

        switch action {
        case .dock(let dockAction, let application):
            DebugLog.info(DebugLog.dock, "Executing deferred dock action \(dockAction.rawValue) on finger release")
            scheduleDockGestureAction(dockAction, for: application)
        case .titleBar(let windowAction, let event, let anchorPoint, let replacesWithTabClose):
            DebugLog.info(DebugLog.dock, "Executing deferred title-bar action \(String(describing: windowAction)) on finger release")
            executeTitleBarAction(
                windowAction,
                event: event,
                anchorPoint: anchorPoint,
                replacesWithTabClose: replacesWithTabClose
            )
        }
    }

    private func storeTouchAnchor(gesture: DockGestureKind, touches: [TrackpadTouchSample]) {
        pendingReleaseGestureKind = gesture
        guard touches.count >= 2 else {
            pendingReleaseHighWaterMark = nil
            pendingReleasePinchHighWaterMark = nil
            return
        }
        let p0 = touches[0].position
        let p1 = touches[1].position
        let avg = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        // Initialize the high water mark with the gesture-direction component at trigger time.
        pendingReleaseHighWaterMark = gestureDirectionComponent(for: gesture, point: avg)
        pendingReleasePinchHighWaterMark = hypot(p1.x - p0.x, p1.y - p0.y)
    }

    private func clearTouchAnchor() {
        pendingReleaseGestureKind = nil
        pendingReleaseHighWaterMark = nil
        pendingReleasePinchHighWaterMark = nil
    }

    /// Returns the scalar component along the gesture direction.
    /// For swipe gestures this is the signed position along the swipe axis,
    /// oriented so that "further into the gesture" is a larger value.
    private func gestureDirectionComponent(for gesture: DockGestureKind, point: CGPoint) -> CGFloat {
        switch gesture {
        case .swipeLeft:  return -point.x  // moving left = decreasing x → negate so further = larger
        case .swipeRight: return  point.x
        case .swipeUp:    return  point.y  // trackpad y increases upward
        case .swipeDown:  return -point.y
        case .pinchIn, .pinchOut: return 0 // handled separately via finger distance
        }
    }

    private func computeReverseCancelThreshold() -> CGFloat {
        let sensitivity = settingsStore.reverseCancelSensitivity
        // sensitivity 0.0 → threshold 0.06 (hard to cancel), 1.0 → threshold 0.005 (easy to cancel)
        let minThreshold: CGFloat = 0.005
        let maxThreshold: CGFloat = 0.06
        return CGFloat(maxThreshold - sensitivity * (maxThreshold - minThreshold))
    }

    private func checkReverseCancellation(frame: TrackpadTouchFrame) {
        guard settingsStore.reverseCancelEnabled else { return }
        guard
            let gestureKind = pendingReleaseGestureKind,
            let highWater = pendingReleaseHighWaterMark,
            frame.touches.count == 2
        else { return }

        let p0 = frame.touches[0].position
        let p1 = frame.touches[1].position
        let avg = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        let threshold = computeReverseCancelThreshold()

        var shouldCancel = false

        if gestureKind == .pinchIn {
            // For pinch in: track the minimum finger distance (most pinched) as high water mark.
            let currentDist = hypot(p1.x - p0.x, p1.y - p0.y)
            let pinchHighWater = pendingReleasePinchHighWaterMark ?? currentDist
            if currentDist < pinchHighWater {
                pendingReleasePinchHighWaterMark = currentDist
            }
            let retreat = currentDist - (pendingReleasePinchHighWaterMark ?? currentDist)
            shouldCancel = retreat > threshold
        } else if gestureKind == .pinchOut {
            // For pinch out: track the maximum finger distance (most spread) as high water mark.
            let currentDist = hypot(p1.x - p0.x, p1.y - p0.y)
            let pinchHighWater = pendingReleasePinchHighWaterMark ?? currentDist
            if currentDist > pinchHighWater {
                pendingReleasePinchHighWaterMark = currentDist
            }
            let retreat = (pendingReleasePinchHighWaterMark ?? currentDist) - currentDist
            shouldCancel = retreat > threshold
        } else {
            // For swipe gestures: track the furthest progress along gesture direction.
            let current = gestureDirectionComponent(for: gestureKind, point: avg)
            if current > highWater {
                pendingReleaseHighWaterMark = current
            }
            let retreat = (pendingReleaseHighWaterMark ?? current) - current
            shouldCancel = retreat > threshold
        }

        if shouldCancel {
            DebugLog.info(DebugLog.dock, "Reverse movement detected for \(gestureKind.rawValue), cancelling pending action")
            cancelPendingReleaseAction()
        }
    }

    private func makeConfiguredRecognizer() -> DockGestureRecognizer {
        var recognizer = DockGestureRecognizer()
        // sensitivity 0.0 → threshold 0.16 (hard), 1.0 → threshold 0.04 (easy)
        let swipeSens = settingsStore.swipeSensitivity
        recognizer.translationThreshold = CGFloat(0.16 - swipeSens * (0.16 - 0.04))
        // sensitivity 0.0 → threshold 0.14 (hard), 1.0 → threshold 0.03 (easy)
        let pinchSens = settingsStore.pinchSensitivity
        recognizer.pinchThreshold = CGFloat(0.14 - pinchSens * (0.14 - 0.03))
        return recognizer
    }

#if DEBUG
    private func shouldLogFrame(
        touchCount: Int,
        dockHoveredApplication: DockApplicationTarget?,
        titleBarHoveredApplication: DockApplicationTarget?
    ) -> Bool {
        let hoveredApplicationLogValue = "dock=\(dockHoveredApplication?.logDescription ?? "nil")|title=\(titleBarHoveredApplication?.logDescription ?? "nil")"
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
#endif

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

struct DockHoverCandidate: Equatable {
    let target: DockApplicationTarget
    let frame: CGRect
}

struct DockHoverSnapshot: Equatable {
    let candidates: [DockHoverCandidate]
    let bounds: CGRect

    init(candidates: [DockHoverCandidate]) {
        self.candidates = candidates
        self.bounds = candidates.reduce(into: CGRect.null) { partialResult, candidate in
            partialResult = partialResult.union(candidate.frame)
        }
    }

    func hoveredCandidate(at point: CGPoint) -> DockHoverCandidate? {
        candidates.first { $0.frame.contains(point) }
    }

    func containsApproximateDockRegion(_ point: CGPoint) -> Bool {
        guard bounds.isNull == false, bounds.isEmpty == false else {
            return false
        }

        return bounds.contains(point)
    }
}

@MainActor
private final class TitleBarAccessibilityProbe {
    private let cacheTTL: TimeInterval = 0.2
    private let logTTL: TimeInterval = 0.4
    private let minimumTitleBarHeight: CGFloat = 24
    private let maximumTitleBarHeight: CGFloat = 56
    private var cachedHitRegion: CachedHitRegion?
    private var lastProbeLogAt = Date.distantPast
    private var lastProbeLogKey = ""

    private struct CachedHitRegion {
        let application: DockApplicationTarget
        let frame: CGRect
        let expiresAt: Date
    }

    func clearCache() {
        cachedHitRegion = nil
        lastProbeLogAt = .distantPast
        lastProbeLogKey = ""
    }

    func hoveredApplication(
        at appKitPoint: CGPoint,
        requireFrontmostOwnership: Bool,
        allowFullScreen: Bool = false,
        allowBrowserTabFallback: Bool = false
    ) -> DockApplicationTarget? {
        let now = Date()

        if let cachedHitRegion, now < cachedHitRegion.expiresAt {
            if
                cachedHitRegion.frame.contains(appKitPoint),
                pointBelongsToFrontmostApplication(
                    appKitPoint,
                    processIdentifier: cachedHitRegion.application.processIdentifier,
                    required: requireFrontmostOwnership
                )
            {
                logProbeIfNeeded(
                    key: "hit-cache:\(cachedHitRegion.application.processIdentifier):\(Int(appKitPoint.x)):\(Int(appKitPoint.y))",
                    message: {
                        "Pointer hit cached title-bar region for \(cachedHitRegion.application.logDescription) at \(NSStringFromPoint(appKitPoint)); frame = \(NSStringFromRect(cachedHitRegion.frame))"
                    }
                )
                return cachedHitRegion.application
            }

            guard allowBrowserTabFallback else {
                return nil
            }
        }

        guard AXIsProcessTrusted() else {
            cachedHitRegion = nil
            return nil
        }

        guard
            let frontmostApplication = NSWorkspace.shared.frontmostApplication,
            frontmostApplication.isTerminated == false
        else {
            cachedHitRegion = nil
            return nil
        }

        let appElement = AXUIElementCreateApplication(frontmostApplication.processIdentifier)
        guard
            let window = focusedOrMainWindow(in: appElement),
            let appKitWindowFrame = appKitFrame(of: window)
        else {
            cachedHitRegion = nil
            return nil
        }

        let windowIsFullScreen = isFullScreen(window)
        if windowIsFullScreen, !allowFullScreen {
            cachedHitRegion = nil
            return nil
        }

        let titleBarFrame = titleBarFrame(for: appKitWindowFrame)
        guard titleBarFrame.isEmpty == false else {
            cachedHitRegion = nil
            return nil
        }

        let aliases = RunningApplicationIdentity.aliases(for: frontmostApplication)
        let fallbackName = frontmostApplication.bundleIdentifier ?? "Application"
        let resolvedName = frontmostApplication.localizedName ?? aliases.first ?? fallbackName
        let target = DockApplicationTarget(
            dockItemName: resolvedName,
            resolvedApplicationName: resolvedName,
            processIdentifier: frontmostApplication.processIdentifier,
            bundleIdentifier: frontmostApplication.bundleIdentifier,
            aliases: aliases
        )

        cachedHitRegion = CachedHitRegion(
            application: target,
            frame: titleBarFrame,
            expiresAt: now.addingTimeInterval(cacheTTL)
        )

        if
            titleBarFrame.contains(appKitPoint),
            pointBelongsToFrontmostApplication(
                appKitPoint,
                processIdentifier: target.processIdentifier,
                required: requireFrontmostOwnership
            )
        {
            logProbeIfNeeded(
                key: "hit:\(target.processIdentifier):\(Int(titleBarFrame.minX)):\(Int(titleBarFrame.minY)):\(Int(titleBarFrame.width)):\(Int(titleBarFrame.height))",
                message: {
                    "Pointer hit title-bar region for \(target.logDescription) at \(NSStringFromPoint(appKitPoint)); frame = \(NSStringFromRect(titleBarFrame))"
                }
            )
            return target
        }

        if
            allowBrowserTabFallback,
            windowIsFullScreen == false,
            pointBelongsToFrontmostApplication(
                appKitPoint,
                processIdentifier: target.processIdentifier,
                required: requireFrontmostOwnership
            ),
            BrowserTabProbe.isBrowserTab(
                at: appKitPoint,
                processIdentifier: target.processIdentifier
            )
        {
            logProbeIfNeeded(
                key: "hit-browser-tab:\(target.processIdentifier):\(Int(appKitPoint.x)):\(Int(appKitPoint.y))",
                message: {
                    "Pointer hit browser-tab fallback region for \(target.logDescription) at \(NSStringFromPoint(appKitPoint))"
                }
            )
            return target
        }

        logProbeIfNeeded(
            key: "miss:\(target.processIdentifier):\(Int(titleBarFrame.minX)):\(Int(titleBarFrame.minY)):\(Int(titleBarFrame.width)):\(Int(titleBarFrame.height))",
            message: {
                "Pointer missed title-bar region for \(target.logDescription) at \(NSStringFromPoint(appKitPoint)); frame = \(NSStringFromRect(titleBarFrame))"
            }
        )
        return nil
    }

    private func focusedOrMainWindow(in appElement: AXUIElement) -> AXUIElement? {
        if let focusedWindow = AXAttributeReader.element(kAXFocusedWindowAttribute as CFString, from: appElement) {
            return focusedWindow
        }

        return AXAttributeReader.element(kAXMainWindowAttribute as CFString, from: appElement)
    }

    private func appKitFrame(of window: AXUIElement) -> CGRect? {
        guard
            let axPosition = AXAttributeReader.point(kAXPositionAttribute as CFString, from: window),
            let axSize = AXAttributeReader.size(kAXSizeAttribute as CFString, from: window)
        else {
            return nil
        }

        let geometry = ScreenGeometry(screenFrames: NSScreen.screens.map(\.frame))
        let appKitFrame = geometry.appKitFrame(
            fromAXFrame: CGRect(origin: axPosition, size: axSize)
        )

        guard appKitFrame.width >= 120, appKitFrame.height >= 80 else {
            return nil
        }

        return appKitFrame
    }

    private func titleBarFrame(for windowFrame: CGRect) -> CGRect {
        let estimatedHeight = floor(windowFrame.height * 0.12)
        let height = min(maximumTitleBarHeight, max(minimumTitleBarHeight, estimatedHeight))

        return CGRect(
            x: windowFrame.minX,
            y: windowFrame.maxY - height,
            width: windowFrame.width,
            height: height
        ).integral
    }

    private func pointBelongsToFrontmostApplication(
        _ appKitPoint: CGPoint,
        processIdentifier: pid_t,
        required: Bool
    ) -> Bool {
        guard required else {
            return true
        }

        guard let hitProcessIdentifier = axHitProcessIdentifier(at: appKitPoint) else {
            return true
        }

        return hitProcessIdentifier == processIdentifier
    }

    private func isFullScreen(_ window: AXUIElement) -> Bool {
        AXAttributeReader.bool("AXFullScreen" as CFString, from: window) ?? false
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
}

private func axHitProcessIdentifier(at appKitPoint: CGPoint) -> pid_t? {
    let geometry = ScreenGeometry(screenFrames: NSScreen.screens.map(\.frame))
    let axPoint = geometry.axPoint(fromAppKitPoint: appKitPoint)
    let systemWideElement = AXUIElementCreateSystemWide()
    var hitElement: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(
        systemWideElement,
        Float(axPoint.x),
        Float(axPoint.y),
        &hitElement
    )

    guard result == .success, let hitElement else {
        return nil
    }

    var hitProcessIdentifier: pid_t = 0
    let pidResult = AXUIElementGetPid(hitElement, &hitProcessIdentifier)
    guard pidResult == .success else {
        return nil
    }

    return hitProcessIdentifier
}

@MainActor
private final class DockAccessibilityProbe {
    private let candidateCacheTTL: TimeInterval = 0.25
    private let regionCacheTTL: TimeInterval = 1.0
    private let logTTL: TimeInterval = 0.4
    private var cachedSnapshot: CachedSnapshot?
    private var cachedHoverHit: CachedHoverHit?
#if DEBUG
    private var lastProbeLogAt = Date.distantPast
    private var lastProbeLogKey = ""
#endif

    private struct CachedSnapshot {
        let snapshot: DockHoverSnapshot
        let candidateExpiresAt: Date
        let regionExpiresAt: Date
    }

    private struct CachedHoverHit {
        let target: DockApplicationTarget
        let frame: CGRect
        let expiresAt: Date
    }

    private struct ApplicationRecord {
        let application: NSRunningApplication
        let aliases: [String]
        let normalizedAliases: [String]
    }

    func clearCache() {
        cachedSnapshot = nil
        cachedHoverHit = nil
#if DEBUG
        lastProbeLogAt = .distantPast
        lastProbeLogKey = ""
#endif
    }

    func hoveredApplication(
        at appKitPoint: CGPoint,
        requireFrontmostOwnership: Bool
    ) -> DockApplicationTarget? {
        let now = Date()

        if
            let cachedHoverHit,
            now < cachedHoverHit.expiresAt,
            cachedHoverHit.frame.contains(appKitPoint),
            pointBelongsToDock(at: appKitPoint, required: requireFrontmostOwnership)
        {
            logProbeIfNeeded(
                key: "hit-cache:\(cachedHoverHit.target.dockItemName):\(cachedHoverHit.target.processIdentifier):\(Int(appKitPoint.x)):\(Int(appKitPoint.y))",
                message: {
                    "Pointer hit cached Dock item \(cachedHoverHit.target.dockItemName) mapped to app \(cachedHoverHit.target.logDescription) at \(NSStringFromPoint(appKitPoint)); frame = \(NSStringFromRect(cachedHoverHit.frame)); aliases = \(cachedHoverHit.target.aliases.joined(separator: "|"))"
                }
            )
            return cachedHoverHit.target
        }

        let snapshot = dockSnapshot(containing: appKitPoint, at: now)
        guard snapshot.containsApproximateDockRegion(appKitPoint) else {
            cachedHoverHit = nil
            return nil
        }

        guard let hoveredCandidate = snapshot.hoveredCandidate(at: appKitPoint) else {
            cachedHoverHit = nil
            logMissIfNeeded(at: appKitPoint, snapshot: snapshot)
            return nil
        }

        cachedHoverHit = CachedHoverHit(
            target: hoveredCandidate.target,
            frame: hoveredCandidate.frame,
            expiresAt: now.addingTimeInterval(candidateCacheTTL)
        )
        guard pointBelongsToDock(at: appKitPoint, required: requireFrontmostOwnership) else {
            return nil
        }
        logProbeIfNeeded(
            key: "hit:\(hoveredCandidate.target.dockItemName):\(hoveredCandidate.target.processIdentifier):\(Int(appKitPoint.x)):\(Int(appKitPoint.y))",
            message: {
                "Pointer hit Dock item \(hoveredCandidate.target.dockItemName) mapped to app \(hoveredCandidate.target.logDescription) at \(NSStringFromPoint(appKitPoint)); frame = \(NSStringFromRect(hoveredCandidate.frame)); aliases = \(hoveredCandidate.target.aliases.joined(separator: "|"))"
            }
        )
        return hoveredCandidate.target
    }

    private func pointBelongsToDock(at appKitPoint: CGPoint, required: Bool) -> Bool {
        guard required else {
            return true
        }

        guard
            let dockProcess = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.dock"
            ).first
        else {
            return true
        }

        guard let hitProcessIdentifier = axHitProcessIdentifier(at: appKitPoint) else {
            return true
        }

        return hitProcessIdentifier == dockProcess.processIdentifier
    }

    private func dockSnapshot(containing appKitPoint: CGPoint, at now: Date) -> DockHoverSnapshot {
        if let cachedSnapshot {
            if now < cachedSnapshot.candidateExpiresAt {
                return cachedSnapshot.snapshot
            }

            if
                now < cachedSnapshot.regionExpiresAt,
                cachedSnapshot.snapshot.containsApproximateDockRegion(appKitPoint) == false
            {
                return cachedSnapshot.snapshot
            }
        }

        let snapshot = rebuildDockSnapshot()
        cachedSnapshot = CachedSnapshot(
            snapshot: snapshot,
            candidateExpiresAt: now.addingTimeInterval(candidateCacheTTL),
            regionExpiresAt: now.addingTimeInterval(regionCacheTTL)
        )
        return snapshot
    }

    private func rebuildDockSnapshot() -> DockHoverSnapshot {
        guard AXIsProcessTrusted() else { return DockHoverSnapshot(candidates: []) }
        guard let dockProcess = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return DockHoverSnapshot(candidates: [])
        }

        let dockElement = AXUIElementCreateApplication(dockProcess.processIdentifier)
        guard let dockList = childElement(
            attribute: kAXChildrenAttribute as CFString,
            from: dockElement
        )?.first else {
            return DockHoverSnapshot(candidates: [])
        }

        let geometry = ScreenGeometry(screenFrames: NSScreen.screens.map(\.frame))
        var candidates: [DockHoverCandidate] = []
        let applicationRecords = runningApplicationRecords()
        var qualityScoreCache: [pid_t: Int] = [:]

        for item in childElements(attribute: kAXChildrenAttribute as CFString, from: dockList) {
            guard let itemName = AXAttributeReader.string(kAXTitleAttribute as CFString, from: item) else {
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
                let axPosition = AXAttributeReader.point(kAXPositionAttribute as CFString, from: item),
                let axSize = AXAttributeReader.size(kAXSizeAttribute as CFString, from: item)
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
            let candidate = DockHoverCandidate(
                target: target,
                frame: appKitFrame
            )
            candidates.append(candidate)
        }

        return DockHoverSnapshot(candidates: candidates)
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
        return AXAttributeReader.elements(kAXWindowsAttribute as CFString, from: appElement).isEmpty == false
    }

    private func logProbeIfNeeded(key: String, message: () -> String) {
#if DEBUG
        let now = Date()
        guard key != lastProbeLogKey || now.timeIntervalSince(lastProbeLogAt) >= logTTL else {
            return
        }

        lastProbeLogKey = key
        lastProbeLogAt = now
        DebugLog.debug(DebugLog.dock, message())
#endif
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

    private func logMissIfNeeded(at appKitPoint: CGPoint, snapshot: DockHoverSnapshot) {
#if DEBUG
        var nearestCandidates: [(candidate: DockHoverCandidate, distance: CGFloat)] = []

        for candidate in snapshot.candidates {
            let distance = distanceFromPoint(appKitPoint, to: candidate.frame)
            let insertionIndex = nearestCandidates.firstIndex { distance < $0.distance } ?? nearestCandidates.endIndex
            nearestCandidates.insert((candidate, distance), at: insertionIndex)

            if nearestCandidates.count > 4 {
                nearestCandidates.removeLast()
            }
        }

        let nearestKey = nearestCandidates
            .map {
                "\($0.candidate.target.dockItemName):\($0.candidate.target.processIdentifier):\(Int($0.distance * 100))"
            }
            .joined(separator: ",")

        logProbeIfNeeded(
            key: "miss:\(nearestKey)",
            message: {
                let nearestSummary = nearestCandidates
                    .map {
                        "\($0.candidate.target.dockItemName){app=\($0.candidate.target.logDescription), frame=\(NSStringFromRect($0.candidate.frame)), distance=\(String(format: "%.2f", $0.distance)), aliases=\($0.candidate.target.aliases.joined(separator: "|"))}"
                    }
                    .joined(separator: ", ")
                return "Pointer missed all Dock items at \(NSStringFromPoint(appKitPoint)); evaluated \(snapshot.candidates.count) candidates; nearest = [\(nearestSummary)]"
            }
        )
#endif
    }

    private func distanceFromPoint(_ point: CGPoint, to frame: CGRect) -> CGFloat {
        if frame.contains(point) {
            return 0
        }

        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return sqrt((dx * dx) + (dy * dy))
    }
}

private final class MultitouchInputMonitor {
    var onFrame: ((TrackpadTouchFrame) -> Void)?

    private var isMonitoring = false
    private var lastDeliveredFingerCount = -1

    func startIfAvailable() {
        guard isMonitoring == false else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        isMonitoring = SwooshyMTStartMonitoring(multitouchCallback, context)
        lastDeliveredFingerCount = -1
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
        lastDeliveredFingerCount = -1
        DebugLog.info(DebugLog.dock, "MultitouchSupport monitoring stopped")
    }

    fileprivate func receive(
        fingers: UnsafePointer<SwooshyMTFinger>,
        fingerCount: Int,
        timestamp: Double
    ) {
        guard fingerCount > 0 else {
            guard lastDeliveredFingerCount != 0 else { return }
            lastDeliveredFingerCount = 0
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

        lastDeliveredFingerCount = fingerCount
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
