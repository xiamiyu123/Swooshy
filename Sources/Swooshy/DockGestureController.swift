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
    private var dockCornerDragRecognizer = TitleBarCornerDragRecognizer()
    private var titleBarRecognizer = DockGestureRecognizer()
    private var titleBarCornerDragRecognizer = TitleBarCornerDragRecognizer()
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
    private let gestureStateTimeout: TimeInterval = 30
    private var gestureStateWatchdog: Timer?
    private var gestureStateWatchdogState: GestureStateSnapshot?

    private var touchSequenceTracker = TwoFingerTouchSequenceTracker()
    private var pendingReleaseAction: PendingReleaseAction?
    private var escMonitor: Any?
    private var lastTouchCount: Int = 0
    private var pendingReleaseGestureKind: DockGestureKind?
    private var pendingReleaseHighWaterMark: CGFloat?
    private var pendingReleasePinchHighWaterMark: CGFloat?
    private var titleBarSessionHoverSource: TitleBarHoverSource?
    private var activeCornerDragApplication: DockApplicationTarget?
    private var activeCornerDragSource: CornerDragSource?
    private var activeCornerDragAction: WindowAction?
    private var activeCornerDragAnchorPoint: CGPoint?
    private var activeCornerDragTouchOrigin: CGPoint?
    private var activeCornerDragTouchReferencePoint: CGPoint?
    private var smoothDockingSession: SmoothDockingSession?
    private let cornerDragTranslationThreshold: CGFloat = 0.06

    private enum PendingReleaseAction {
        case dock(action: DockGestureAction, application: DockApplicationTarget)
        case titleBar(
            action: WindowAction,
            event: DockGestureEvent,
            anchorPoint: CGPoint,
            replacesWithTabClose: Bool
        )
        case cornerDrag(
            action: WindowAction,
            application: DockApplicationTarget,
            anchorPoint: CGPoint,
            source: CornerDragSource
        )
    }

    private struct MonitoringState: Equatable {
        let dockCornerDragEnabled: Bool
        let titleBarCornerDragEnabled: Bool
        let dockGesturesEnabled: Bool
        let titleBarGesturesEnabled: Bool
    }

    private enum CornerDragSource: Equatable {
        case dock
        case titleBar

        var logLabel: String {
            switch self {
            case .dock:
                return "dock"
            case .titleBar:
                return "title-bar"
            }
        }
    }

    private struct GestureStateSnapshot: Equatable {
        enum PendingActionKind: Equatable {
            case dock
            case titleBar
            case cornerDrag
        }

        let pendingActionKind: PendingActionKind?
        let pendingGestureKind: DockGestureKind?
        let dockRecognizerCaptured: Bool
        let titleBarRecognizerCaptured: Bool
        let dockCornerDragActive: Bool
        let titleBarCornerDragActive: Bool
        let activeCornerDragProcessIdentifier: pid_t?
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
        invalidateGestureStateWatchdog()

        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }

        pendingTouchFrame = nil
        isProcessingTouchFrame = false
        monitoringState = nil
        touchSequenceTracker.reset()
        dockRecognizer = makeConfiguredRecognizer()
        dockCornerDragRecognizer = makeConfiguredCornerDragRecognizer()
        titleBarRecognizer = makeConfiguredRecognizer()
        titleBarCornerDragRecognizer = makeConfiguredCornerDragRecognizer()
        titleBarSessionHoverSource = nil
        activeCornerDragApplication = nil
        activeCornerDragSource = nil
        activeCornerDragAction = nil
        activeCornerDragAnchorPoint = nil
        activeCornerDragTouchOrigin = nil
        activeCornerDragTouchReferencePoint = nil
        endSmoothDockingSession(restore: true)
        dockProbe.clearCache()
        titleBarProbe.clearCache()
        windowManager.shutdown()
        monitor.onFrame = nil
        monitor.stop()
        cancelPendingReleaseAction()
    }

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: settingsStore,
            queue: .main
        ) { [weak self] notification in
            let categories = notification.settingsChangeCategories
            MainActor.assumeIsolated {
                guard categories.intersection([.gestureMonitoring, .advancedGestureBehavior]).isEmpty == false else {
                    return
                }

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
            dockCornerDragEnabled: settingsStore.dockCornerDragSnapEnabled,
            titleBarCornerDragEnabled: settingsStore.titleBarCornerDragSnapEnabled,
            dockGesturesEnabled: settingsStore.dockGesturesEnabled,
            titleBarGesturesEnabled: settingsStore.titleBarGesturesEnabled
        )
        guard state != monitoringState else { return }

        monitoringState = state
        DebugLog.info(
            DebugLog.dock,
            "Syncing gesture monitoring; dockGesturesEnabled=\(state.dockGesturesEnabled), titleBarGesturesEnabled=\(state.titleBarGesturesEnabled), dockCornerDragEnabled=\(state.dockCornerDragEnabled), titleBarCornerDragEnabled=\(state.titleBarCornerDragEnabled)"
        )
        touchSequenceTracker.reset()
        dockRecognizer = makeConfiguredRecognizer()
        dockCornerDragRecognizer = makeConfiguredCornerDragRecognizer()
        titleBarRecognizer = makeConfiguredRecognizer()
        titleBarCornerDragRecognizer = makeConfiguredCornerDragRecognizer()
        titleBarSessionHoverSource = nil
        activeCornerDragApplication = nil
        activeCornerDragSource = nil
        activeCornerDragAction = nil
        activeCornerDragAnchorPoint = nil
        activeCornerDragTouchOrigin = nil
        activeCornerDragTouchReferencePoint = nil
        endSmoothDockingSession(restore: true)
        dockProbe.clearCache()
        titleBarProbe.clearCache()
        pendingTouchFrame = nil
        isProcessingTouchFrame = false
        cancelPendingReleaseAction()

        setTrackpadMonitoringEnabled(state.dockGesturesEnabled || state.titleBarGesturesEnabled)

        syncGestureStateWatchdog()
    }

    private func setTrackpadMonitoringEnabled(_ isEnabled: Bool) {
        if isEnabled {
            DebugLog.info(DebugLog.dock, "Starting trackpad gesture monitoring")
            monitor.startIfAvailable()
        } else {
            DebugLog.info(DebugLog.dock, "Stopping trackpad gesture monitoring")
            monitor.stop()
        }
    }

    private func restartTrackpadMonitoringIfNeeded() {
        guard let monitoringState else {
            return
        }

        guard monitoringState.dockGesturesEnabled || monitoringState.titleBarGesturesEnabled else {
            return
        }

        DebugLog.info(DebugLog.dock, "Restarting trackpad gesture monitoring after watchdog recovery")
        monitor.stop()
        monitor.startIfAvailable()
        DebugLog.info(DebugLog.dock, "Trackpad gesture monitoring restart requested after watchdog recovery")
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
        defer {
            syncGestureStateWatchdog()
        }

        let dockGesturesEnabled = settingsStore.dockGesturesEnabled
        let titleBarGesturesEnabled = settingsStore.titleBarGesturesEnabled
        let dockCornerDragEnabled = dockGesturesEnabled && settingsStore.dockCornerDragSnapEnabled
        let titleBarCornerDragEnabled = titleBarGesturesEnabled && settingsStore.titleBarCornerDragSnapEnabled
        guard dockGesturesEnabled || titleBarGesturesEnabled else { return }

        let touchCount = frame.touches.count
        let previousTouchCount = lastTouchCount
        lastTouchCount = touchCount

        refreshRecognizerConfiguration()

        if case .restarted(let previousIdentifiers, let currentIdentifiers) = touchSequenceTracker.consume(frame) {
            if hasActiveGestureState {
                DebugLog.info(
                    DebugLog.dock,
                    "Detected fresh two-finger contact \(currentIdentifiers) replacing \(previousIdentifiers) without an intervening lift; resetting stale gesture state"
                )
                resetGestureStateForNewTouchSequence()
            }
        }

        if let interruption = gestureSessionTouchInterruption(
            touchCount: touchCount,
            previousTouchCount: previousTouchCount,
            hasPendingReleaseAction: pendingReleaseAction != nil,
            hasActiveCornerDrag: activeCornerDragApplication != nil
        ) {
            if dockCornerDragRecognizer.isActive || titleBarCornerDragRecognizer.isActive {
                if pendingReleaseAction == nil {
                    endSmoothDockingSession(restore: true)
                }
                resetCornerDragSession(dismissFeedback: pendingReleaseAction == nil)
            }
            if pendingReleaseAction != nil {
                switch interruption {
                case .release:
                    executePendingReleaseAction()
                case .invalidAdditionalTouch:
                    DebugLog.info(
                        DebugLog.dock,
                        "Detected \(touchCount)-finger interruption while waiting for a two-finger release; cancelling pending gesture state"
                    )
                    cancelPendingReleaseAction()
                }
            }
            // Still let recognizers see the zero-touch frame.
        }

        // Keep the hot path cheap: only two-finger input can produce these gestures.
        guard frame.touches.count == 2 else {
            if dockGesturesEnabled {
                _ = dockRecognizer.process(frame: frame, hoveredApplication: nil)
                _ = dockCornerDragRecognizer.process(frame: frame, hoveredApplication: nil)
            }
            if titleBarGesturesEnabled {
                _ = titleBarRecognizer.process(frame: frame, hoveredApplication: nil)
                titleBarSessionHoverSource = nil
                _ = titleBarCornerDragRecognizer.process(frame: frame, hoveredApplication: nil)
            }
            return
        }

        // Check for reverse swipe cancellation while fingers are still down.
        if pendingReleaseGestureKind != nil {
            checkReverseCancellation(frame: frame)
            if pendingReleaseAction == nil {
                return
            }
            return
        }

        let cornerDragSessionActive = activeCornerDragApplication != nil ||
            (dockCornerDragEnabled && dockCornerDragRecognizer.isActive) ||
            (titleBarCornerDragEnabled && titleBarCornerDragRecognizer.isActive)
        let needsDockLookup = dockGesturesEnabled &&
            dockRecognizer.requiresHoveredApplication &&
            cornerDragSessionActive == false
        let needsTitleBarLookup = titleBarGesturesEnabled &&
            cornerDragSessionActive == false &&
            (titleBarRecognizer.requiresHoveredApplication || titleBarCornerDragRecognizer.isActive == false)
        let mouseLocation = (needsDockLookup || needsTitleBarLookup) ? NSEvent.mouseLocation : nil
        let hoveredDockApplication = needsDockLookup ? mouseLocation.flatMap {
            dockProbe.hoveredApplication(
                at: $0,
                requireFrontmostOwnership: settingsStore.titleBarOverlayProtectionEnabled
            )
        } : nil
        let hoveredTitleBarTarget: TitleBarHoverTarget?
        if needsTitleBarLookup && hoveredDockApplication == nil, let mouseLocation {
        #if DEBUG
            if settingsStore.debugLoggingEnabled {
                let start = CFAbsoluteTimeGetCurrent()
                hoveredTitleBarTarget = titleBarProbe.hoveredTarget(
                    at: mouseLocation,
                    requireFrontmostOwnership: settingsStore.titleBarOverlayProtectionEnabled,
                    titleBarHeight: CGFloat(settingsStore.titleBarTriggerHeight),
                    allowFullScreen: settingsStore.smartPinchExitFullScreenEnabled,
                    allowBrowserTabFallback: settingsStore.smartBrowserTabCloseEnabled
                )
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
                DebugLog.debug(
                    DebugLog.dock,
                    String(format: "titleBarProbe.hoveredTarget took %.1f ms", elapsedMs)
                )
            } else {
                hoveredTitleBarTarget = titleBarProbe.hoveredTarget(
                    at: mouseLocation,
                    requireFrontmostOwnership: settingsStore.titleBarOverlayProtectionEnabled,
                    titleBarHeight: CGFloat(settingsStore.titleBarTriggerHeight),
                    allowFullScreen: settingsStore.smartPinchExitFullScreenEnabled,
                    allowBrowserTabFallback: settingsStore.smartBrowserTabCloseEnabled
                )
            }
        #else
            hoveredTitleBarTarget = titleBarProbe.hoveredTarget(
                at: mouseLocation,
                requireFrontmostOwnership: settingsStore.titleBarOverlayProtectionEnabled,
                titleBarHeight: CGFloat(settingsStore.titleBarTriggerHeight),
                allowFullScreen: settingsStore.smartPinchExitFullScreenEnabled,
                allowBrowserTabFallback: settingsStore.smartBrowserTabCloseEnabled
            )
        #endif
        } else {
            hoveredTitleBarTarget = nil
        }

#if DEBUG
        if shouldLogFrame(
            touchCount: frame.touches.count,
            dockHoveredApplication: hoveredDockApplication,
            titleBarHoveredApplication: hoveredTitleBarTarget
        ) {
            let touchSummary = frame.touches
                .map { "#\($0.identifier)=\(NSStringFromPoint($0.position))" }
                .joined(separator: ", ")
            let mouseDescription = mouseLocation.map(NSStringFromPoint) ?? "<skipped>"
            DebugLog.debug(
                DebugLog.dock,
                "Received touch frame with \(frame.touches.count) touches at mouse \(mouseDescription); dock hover = \(hoveredDockApplication?.logDescription ?? "nil"); title-bar hover = \(hoveredTitleBarTarget?.logDescription ?? "nil"); state = \(gestureStateDebugDescription()); touches = [\(touchSummary)]"
            )
        }
#endif

        if dockCornerDragEnabled {
            let dockCornerDragEvent = dockCornerDragRecognizer.process(
                frame: frame,
                hoveredApplication: hoveredDockApplication
            )
            if handleCornerDragEvent(
                dockCornerDragEvent,
                frame: frame,
                hoveredApplication: hoveredDockApplication,
                anchorPoint: mouseLocation ?? NSEvent.mouseLocation,
                source: .dock
            ) {
                return
            }
        }

        if titleBarCornerDragEnabled {
            let cornerDragEvent = titleBarCornerDragRecognizer.process(
                frame: frame,
                hoveredApplication: hoveredTitleBarTarget?.source == .titleBar
                    ? hoveredTitleBarTarget?.application
                    : nil
            )
            if handleCornerDragEvent(
                cornerDragEvent,
                frame: frame,
                hoveredApplication: hoveredTitleBarTarget?.source == .titleBar
                    ? hoveredTitleBarTarget?.application
                    : nil,
                anchorPoint: mouseLocation ?? NSEvent.mouseLocation,
                source: .titleBar
            ) {
                return
            }
        }

        if dockGesturesEnabled, let dockEvent = dockRecognizer.process(frame: frame, hoveredApplication: hoveredDockApplication) {
            let anchorPoint = mouseLocation ?? NSEvent.mouseLocation
            handleDockGestureEvent(dockEvent, anchorPoint: anchorPoint, touches: frame.touches)
            return
        }

        if titleBarRecognizer.requiresHoveredApplication {
            titleBarSessionHoverSource = hoveredTitleBarTarget?.source
        }

        guard titleBarGesturesEnabled, let titleBarEvent = titleBarRecognizer.process(frame: frame, hoveredApplication: hoveredTitleBarTarget?.application) else {
            return
        }

        let anchorPoint = mouseLocation ?? NSEvent.mouseLocation
        handleTitleBarGestureEvent(
            titleBarEvent,
            hoverSource: titleBarSessionHoverSource ?? hoveredTitleBarTarget?.source ?? .titleBar,
            anchorPoint: anchorPoint,
            touches: frame.touches
        )
    }

    private func handleCornerDragEvent(
        _ event: TitleBarCornerDragEvent?,
        frame: TrackpadTouchFrame,
        hoveredApplication: DockApplicationTarget?,
        anchorPoint: CGPoint,
        source: CornerDragSource
    ) -> Bool {
        switch event {
        case .began(let application, let startAveragePoint, let currentAveragePoint):
            guard standardGestureWouldTrigger(
                beforeCornerDragFrom: source,
                frame: frame,
                hoveredApplication: hoveredApplication ?? application
            ) == false else {
                resetCornerDragRecognizer(for: source)
                DebugLog.debug(
                    DebugLog.dock,
                    "Suppressed \(source.logLabel) corner drag entry because a standard gesture matched first"
                )
                return false
            }
            if source == .dock {
                dockRecognizer.reset()
            } else {
                titleBarRecognizer.reset()
                titleBarSessionHoverSource = nil
            }
            pendingReleaseAction = nil
            clearTouchAnchor()
            endSmoothDockingSession(restore: false)
            gestureFeedbackPresenter.dismiss()
            activeCornerDragApplication = application
            activeCornerDragSource = source
            activeCornerDragAction = nil
            activeCornerDragAnchorPoint = anchorPoint
            activeCornerDragTouchOrigin = startAveragePoint
            activeCornerDragTouchReferencePoint = startAveragePoint
            installEscMonitor()
            updateCornerDragFeedback(
                currentTouchPoint: currentAveragePoint,
                forcePresentation: true
            )
            DebugLog.info(DebugLog.dock, "Entered \(source.logLabel) corner drag mode for \(application.logDescription)")
            return true
        case .changed(_, _, let currentAveragePoint):
            updateCornerDragFeedback(currentTouchPoint: currentAveragePoint)
            return true
        case .ended:
            return activeCornerDragApplication != nil
        case .none:
            let recognizerIsActive = source == .dock
                ? dockCornerDragRecognizer.isActive
                : titleBarCornerDragRecognizer.isActive
            if recognizerIsActive {
                if hoveredApplication == nil, activeCornerDragApplication == nil {
                    return false
                }
                return true
            }
            return false
        }
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
            persistent: persistent,
            preview: nil
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
                _ = try windowManager.closeWindow(of: application, preferredAppKitPoint: nil)
            case .closeTab:
                guard BrowserTabProbe.simulateMiddleClickAtMouseLocation() else {
                    throw WindowManagerError.unableToPerformAction
                }
            case .quitApplication:
                _ = try windowManager.quitApplication(matching: application)
            case .toggleFullScreenWindow:
                _ = try windowManager.toggleFullScreenWindow(of: application)
            case .exitFullScreenWindow:
                _ = try windowManager.exitFullScreenWindow(of: application)
            }
        } catch let error as WindowManagerError {
            handleWindowManagerError(error)
        } catch {
            NSSound.beep()
            DebugLog.error(DebugLog.dock, "Dock gesture action failed: \(error.localizedDescription)")
        }
    }

    private func handleTitleBarGestureEvent(
        _ event: DockGestureEvent,
        hoverSource: TitleBarHoverSource,
        anchorPoint: CGPoint,
        touches: [TrackpadTouchSample]
    ) {
        guard let action = titleBarAction(for: event.gesture) else {
            DebugLog.debug(DebugLog.dock, "Ignoring unsupported title-bar gesture \(event.gesture.rawValue)")
            return
        }

        guard settingsStore.titleBarGestureIsEnabled(for: event.gesture) else {
            DebugLog.debug(DebugLog.dock, "Ignoring disabled title-bar gesture \(event.gesture.rawValue)")
            return
        }

        guard hoverSource.allowsGestureAction(action) else {
            DebugLog.debug(
                DebugLog.dock,
                "Ignoring title-bar gesture \(event.gesture.rawValue) from browser-tab fallback because \(String(describing: action)) is not close/quit"
            )
            return
        }

        let fullScreenWindow = try? windowManager.preferredFullScreenWindow(
            matching: event.application,
            preferredAppKitPoint: anchorPoint
        )
        let isInFullScreen = fullScreenWindow != nil

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
            hoverSource: hoverSource,
            anchorPoint: anchorPoint,
            isInFullScreen: isInFullScreen
        )

        var actionTitle = action.title(preferredLanguages: settingsStore.preferredLanguages)
        if replacesWithTabClose {
            actionTitle = L10n.string(
                "action.close_tab",
                preferredLanguages: settingsStore.preferredLanguages
            )
        } else if isInFullScreen, event.gesture == .pinchIn {
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
            persistent: persistent,
            preview: nil
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
            if action.supportsSmoothDocking {
                startOrUpdateSmoothDockingSession(
                    for: action,
                    application: event.application,
                    anchorPoint: anchorPoint
                )
            } else {
                endSmoothDockingSession(restore: true)
            }
            storeTouchAnchor(gesture: event.gesture, touches: touches)
            installEscMonitor()
            DebugLog.info(DebugLog.dock, "Deferred title-bar action \(String(describing: action)) until finger release")
        } else {
            endSmoothDockingSession(restore: true)
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

            if settingsStore.smartPinchExitFullScreenEnabled, event.gesture == .pinchIn,
               let window = try windowManager.preferredFullScreenWindow(
                    matching: event.application,
                    preferredAppKitPoint: anchorPoint
               )
            {
                try windowManager.setFullScreen(false, for: window)
                DebugLog.info(DebugLog.dock, "Smart intercept: pinched in on full screen window, forced exit.")
                return
            }

            try windowManager.perform(
                action,
                on: event.application,
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

    private func updateCornerDragFeedback(
        currentTouchPoint: CGPoint,
        forcePresentation: Bool = false
    ) {
        guard
            let application = activeCornerDragApplication,
            let source = activeCornerDragSource,
            let anchorPoint = activeCornerDragAnchorPoint,
            let touchOrigin = activeCornerDragTouchReferencePoint ?? activeCornerDragTouchOrigin
        else {
            return
        }

        let translation = CGPoint(
            x: currentTouchPoint.x - touchOrigin.x,
            y: currentTouchPoint.y - touchOrigin.y
        )
        let previousAction = activeCornerDragAction
        let nextAction: WindowAction?

        if let previousAction {
            nextAction = cornerDragTransitionAction(
                from: previousAction,
                forTouchTranslation: translation,
                threshold: cornerDragTranslationThreshold
            )
        } else {
            nextAction = cornerDragAction(
                forTouchTranslation: translation,
                threshold: cornerDragTranslationThreshold
            )
        }

        activeCornerDragAction = nextAction

        if let nextAction, nextAction != previousAction {
            activeCornerDragTouchReferencePoint = currentTouchPoint
        } else if previousAction == nil, nextAction == nil {
            activeCornerDragTouchReferencePoint = activeCornerDragTouchOrigin
        }

        if let nextAction {
            pendingReleaseAction = .cornerDrag(
                action: nextAction,
                application: application,
                anchorPoint: anchorPoint,
                source: source
            )
        } else if case .cornerDrag = pendingReleaseAction {
            pendingReleaseAction = nil
        }

        guard forcePresentation || nextAction != previousAction else {
            return
        }

        let actionTitle = nextAction?.title(preferredLanguages: settingsStore.preferredLanguages)
            ?? settingsStore.localized("gesture.corner_drag.waiting")

        DebugLog.debug(
            DebugLog.dock,
            "Corner drag translation \(NSStringFromPoint(translation)) mapped to \(String(describing: nextAction)) for \(application.logDescription)"
        )

        gestureFeedbackPresenter.show(
            glyph: cornerDragGlyph(for: nextAction),
            gestureTitle: settingsStore.localized("gesture.corner_drag.title"),
            actionTitle: actionTitle,
            anchor: anchorPoint,
            persistent: true,
            preview: nil
        )

        if let nextAction {
            startOrUpdateSmoothDockingSession(
                for: nextAction,
                application: application,
                anchorPoint: anchorPoint
            )
        } else {
            restoreSmoothDockingSessionIfNeeded()
        }
    }

    private func resetCornerDragSession(
        dismissFeedback: Bool,
        rebuildRecognizers: Bool = false
    ) {
        if rebuildRecognizers {
            DebugLog.info(DebugLog.dock, "Rebuilding corner drag recognizers for stale gesture recovery")
            dockCornerDragRecognizer = makeConfiguredCornerDragRecognizer()
            titleBarCornerDragRecognizer = makeConfiguredCornerDragRecognizer()
        } else {
            dockCornerDragRecognizer.reset()
            titleBarCornerDragRecognizer.reset()
        }
        activeCornerDragApplication = nil
        activeCornerDragSource = nil
        activeCornerDragAction = nil
        activeCornerDragAnchorPoint = nil
        activeCornerDragTouchOrigin = nil
        activeCornerDragTouchReferencePoint = nil
        if dismissFeedback {
            gestureFeedbackPresenter.dismiss()
            removeEscMonitor()
        }
    }

    private var hasActiveGestureState: Bool {
        pendingReleaseAction != nil ||
            pendingReleaseGestureKind != nil ||
            dockRecognizer.requiresHoveredApplication == false ||
            titleBarRecognizer.requiresHoveredApplication == false ||
            activeCornerDragApplication != nil ||
            dockCornerDragRecognizer.isActive ||
            titleBarCornerDragRecognizer.isActive
    }

    private func resetStandardRecognizers(rebuildRecognizers: Bool = false) {
        if rebuildRecognizers {
            DebugLog.info(DebugLog.dock, "Rebuilding standard gesture recognizers for stale gesture recovery")
            dockRecognizer = makeConfiguredRecognizer()
            titleBarRecognizer = makeConfiguredRecognizer()
        } else {
            dockRecognizer.reset()
            titleBarRecognizer.reset()
        }
        titleBarSessionHoverSource = nil
    }

    private func resetCornerDragRecognizer(for source: CornerDragSource) {
        switch source {
        case .dock:
            dockCornerDragRecognizer.reset()
        case .titleBar:
            titleBarCornerDragRecognizer.reset()
        }
    }

    private func standardGestureWouldTrigger(
        beforeCornerDragFrom source: CornerDragSource,
        frame: TrackpadTouchFrame,
        hoveredApplication: DockApplicationTarget?
    ) -> Bool {
        switch source {
        case .dock:
            return dockRecognizer.predictedEvent(
                frame: frame,
                hoveredApplication: hoveredApplication
            ) != nil
        case .titleBar:
            return titleBarRecognizer.predictedEvent(
                frame: frame,
                hoveredApplication: hoveredApplication
            ) != nil
        }
    }

    private func resetGestureStateForNewTouchSequence(rebuildRecognizers: Bool = false) {
        if rebuildRecognizers {
            DebugLog.info(DebugLog.dock, "Resetting gesture state by rebuilding recognizers for watchdog recovery")
        }
        pendingReleaseAction = nil
        clearTouchAnchor()
        resetStandardRecognizers(rebuildRecognizers: rebuildRecognizers)
        endSmoothDockingSession(restore: true)
        resetCornerDragSession(
            dismissFeedback: false,
            rebuildRecognizers: rebuildRecognizers
        )
        removeEscMonitor()
        gestureFeedbackPresenter.dismiss()
        syncGestureStateWatchdog()
    }

    private func gestureStateSnapshot() -> GestureStateSnapshot? {
        guard hasActiveGestureState else {
            return nil
        }

        let pendingActionKind: GestureStateSnapshot.PendingActionKind?
        switch pendingReleaseAction {
        case .dock:
            pendingActionKind = .dock
        case .titleBar:
            pendingActionKind = .titleBar
        case .cornerDrag:
            pendingActionKind = .cornerDrag
        case .none:
            pendingActionKind = nil
        }

        return GestureStateSnapshot(
            pendingActionKind: pendingActionKind,
            pendingGestureKind: pendingReleaseGestureKind,
            dockRecognizerCaptured: dockRecognizer.requiresHoveredApplication == false,
            titleBarRecognizerCaptured: titleBarRecognizer.requiresHoveredApplication == false,
            dockCornerDragActive: dockCornerDragRecognizer.isActive,
            titleBarCornerDragActive: titleBarCornerDragRecognizer.isActive,
            activeCornerDragProcessIdentifier: activeCornerDragApplication?.processIdentifier
        )
    }

    private func syncGestureStateWatchdog() {
        let nextState = gestureStateSnapshot()
        guard nextState != gestureStateWatchdogState else {
            return
        }

        invalidateGestureStateWatchdog()
        gestureStateWatchdogState = nextState

        guard let nextState else {
            DebugLog.debug(DebugLog.dock, "Disarming gesture state watchdog; no active gesture state remains")
            return
        }

        DebugLog.debug(DebugLog.dock, "Arming gesture state watchdog for active gesture state")
        let timer = Timer.scheduledTimer(withTimeInterval: gestureStateTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleGestureStateWatchdogFired(expectedState: nextState)
            }
        }
        timer.tolerance = min(1, gestureStateTimeout * 0.1)
        gestureStateWatchdog = timer
    }

    private func invalidateGestureStateWatchdog() {
        gestureStateWatchdog?.invalidate()
        gestureStateWatchdog = nil
    }

    private func handleGestureStateWatchdogFired(expectedState: GestureStateSnapshot) {
        guard isShuttingDown == false else { return }
        guard gestureStateWatchdogState == expectedState else { return }

        #if DEBUG
        let stateDescription = gestureStateDebugDescription()
        #else
        let stateDescription = "watchdog_active"
        #endif
        DebugLog.error(
            DebugLog.dock,
            "Gesture state watchdog reset stale gesture state after \(Int(gestureStateTimeout))s; state = \(stateDescription)"
        )
        DebugLog.info(DebugLog.dock, "Clearing pending touch frame and rebuilding recognizers after watchdog timeout")
        pendingTouchFrame = nil
        isProcessingTouchFrame = false
        lastTouchCount = 0
        touchSequenceTracker.reset()
        dockProbe.clearCache()
        titleBarProbe.clearCache()
        resetGestureStateForNewTouchSequence(rebuildRecognizers: true)
        restartTrackpadMonitoringIfNeeded()
    }

    private func cornerDragGlyph(for action: WindowAction?) -> GestureHUDGlyph {
        switch action {
        case .topLeftQuarter:
            return .diagonal(.topLeft)
        case .topRightQuarter:
            return .diagonal(.topRight)
        case .bottomLeftQuarter:
            return .diagonal(.bottomLeft)
        case .bottomRightQuarter:
            return .diagonal(.bottomRight)
        default:
            return .cornerMode
        }
    }

    private func shouldReplaceWithBrowserTabClose(
        action: WindowAction,
        event: DockGestureEvent,
        hoverSource: TitleBarHoverSource,
        anchorPoint: CGPoint,
        isInFullScreen: Bool
    ) -> Bool {
        guard settingsStore.smartBrowserTabCloseEnabled else {
            DebugLog.debug(DebugLog.dock, "Smart browser tab close disabled; skip replacement")
            return false
        }

        guard action == .closeWindow || action == .quitApplication else {
            DebugLog.debug(DebugLog.dock, "Smart browser tab close skipped for non-close action \(String(describing: action))")
            return false
        }

        if hoverSource == .browserTabFallback {
            DebugLog.debug(DebugLog.dock, "Smart browser tab close accepted from browser-tab fallback")
            return true
        }

        let isBrowserTab = BrowserTabProbe.isBrowserTab(
            at: anchorPoint,
            processIdentifier: event.application.processIdentifier
        )

        DebugLog.debug(
            DebugLog.dock,
            "Smart browser tab probe for \(event.application.logDescription) at \(NSStringFromPoint(anchorPoint)) => \(isBrowserTab)"
        )

        if isInFullScreen && isBrowserTab == false {
            DebugLog.debug(DebugLog.dock, "Smart browser tab close skipped in full screen outside browser tab")
        }

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
        guard pendingReleaseAction != nil || activeCornerDragApplication != nil else {
            endSmoothDockingSession(restore: true)
            removeEscMonitor()
            return
        }
        DebugLog.info(DebugLog.dock, "Cancelled pending gesture action")
        resetGestureStateForNewTouchSequence()
    }

    private func executePendingReleaseAction() {
        guard let action = pendingReleaseAction else { return }
        pendingReleaseAction = nil
        clearTouchAnchor()
        removeEscMonitor()
        gestureFeedbackPresenter.scheduleDismiss()

        switch action {
        case .dock(let dockAction, let application):
            endSmoothDockingSession(restore: false)
            DebugLog.info(DebugLog.dock, "Executing deferred dock action \(dockAction.rawValue) on finger release")
            scheduleDockGestureAction(dockAction, for: application)
        case .titleBar(let windowAction, let event, let anchorPoint, let replacesWithTabClose):
            DebugLog.info(DebugLog.dock, "Executing deferred title-bar action \(String(describing: windowAction)) on finger release")
            if commitSmoothDockingSessionIfNeeded(for: windowAction) == false {
                executeTitleBarAction(
                    windowAction,
                    event: event,
                    anchorPoint: anchorPoint,
                    replacesWithTabClose: replacesWithTabClose
                )
            }
        case .cornerDrag(let windowAction, let application, let anchorPoint, let source):
            DebugLog.info(DebugLog.dock, "Executing deferred corner drag action \(String(describing: windowAction)) on finger release")
            if commitSmoothDockingSessionIfNeeded(for: windowAction) == false {
                executeCornerDragAction(
                    windowAction,
                    application: application,
                    anchorPoint: anchorPoint,
                    source: source
                )
            }
        }

        resetStandardRecognizers()
    }

    private func executeCornerDragAction(
        _ action: WindowAction,
        application: DockApplicationTarget,
        anchorPoint: CGPoint,
        source: CornerDragSource
    ) {
        do {
            switch source {
            case .dock:
                try windowManager.perform(
                    action,
                    on: application,
                    layoutEngine: layoutEngine,
                    preferredAppKitPoint: anchorPoint
                )
            case .titleBar:
                try windowManager.perform(
                    action,
                    on: application,
                    layoutEngine: layoutEngine,
                    preferredAppKitPoint: anchorPoint
                )
            }
        } catch let error as WindowManagerError {
            handleWindowManagerError(error)
        } catch {
            NSSound.beep()
            DebugLog.error(DebugLog.dock, "Corner drag action failed: \(error.localizedDescription)")
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

    private func startOrUpdateSmoothDockingSession(
        for action: WindowAction,
        application: DockApplicationTarget,
        anchorPoint: CGPoint
    ) {
        guard action.supportsSmoothDocking else {
            endSmoothDockingSession(restore: true)
            return
        }

        if smoothDockingSession == nil {
            do {
                smoothDockingSession = try windowManager.beginSmoothDockingSession(
                    on: application,
                    preferredAppKitPoint: anchorPoint
                )
            } catch let error as WindowManagerError {
                handleWindowManagerError(error)
                smoothDockingSession = nil
                return
            } catch {
                DebugLog.debug(DebugLog.dock, "Unable to begin smooth docking session: \(error.localizedDescription)")
                smoothDockingSession = nil
                return
            }
        }

        smoothDockingSession?.update(action: action)
    }

    private func restoreSmoothDockingSessionIfNeeded() {
        smoothDockingSession?.restore()
    }

    private func commitSmoothDockingSessionIfNeeded(for action: WindowAction) -> Bool {
        guard action.supportsSmoothDocking, let smoothDockingSession else {
            endSmoothDockingSession(restore: false)
            return false
        }

        do {
            _ = try smoothDockingSession.commit()
            smoothDockingSession.finish()
            self.smoothDockingSession = nil
            return true
        } catch let error as WindowManagerError {
            handleWindowManagerError(error)
        } catch {
            NSSound.beep()
            DebugLog.error(DebugLog.dock, "Smooth docking commit failed: \(error.localizedDescription)")
        }

        smoothDockingSession.finish()
        self.smoothDockingSession = nil
        return false
    }

    private func endSmoothDockingSession(restore: Bool) {
        guard let smoothDockingSession else {
            return
        }

        if restore {
            smoothDockingSession.restore()
            let session = smoothDockingSession
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 160_000_000)
                guard let self, self.smoothDockingSession === session else {
                    return
                }

                session.finish()
                self.smoothDockingSession = nil
            }
            return
        }

        smoothDockingSession.finish()
        self.smoothDockingSession = nil
    }

    private func makeConfiguredRecognizer() -> DockGestureRecognizer {
        var recognizer = DockGestureRecognizer()
        configure(&recognizer)
        return recognizer
    }

    private func makeConfiguredCornerDragRecognizer() -> TitleBarCornerDragRecognizer {
        var recognizer = TitleBarCornerDragRecognizer()
        recognizer.holdDurationThreshold = settingsStore.titleBarCornerDragHoldDuration
        return recognizer
    }

    private func refreshRecognizerConfiguration() {
        configure(&dockRecognizer)
        dockCornerDragRecognizer.holdDurationThreshold = settingsStore.titleBarCornerDragHoldDuration
        configure(&titleBarRecognizer)
        titleBarCornerDragRecognizer.holdDurationThreshold = settingsStore.titleBarCornerDragHoldDuration
    }

    private func configure(_ recognizer: inout DockGestureRecognizer) {
        // sensitivity 0.0 → threshold 0.16 (hard), 1.0 → threshold 0.04 (easy)
        let swipeSens = settingsStore.swipeSensitivity
        recognizer.translationThreshold = CGFloat(0.16 - swipeSens * (0.16 - 0.04))
        // sensitivity 0.0 → threshold 0.14 (hard), 1.0 → threshold 0.03 (easy)
        let pinchSens = settingsStore.pinchSensitivity
        recognizer.pinchThreshold = CGFloat(0.14 - pinchSens * (0.14 - 0.03))
    }

#if DEBUG
    private func gestureStateDebugDescription() -> String {
        let pendingActionDescription: String
        switch pendingReleaseAction {
        case .dock:
            pendingActionDescription = "dock"
        case .titleBar:
            pendingActionDescription = "titleBar"
        case .cornerDrag:
            pendingActionDescription = "cornerDrag"
        case .none:
            pendingActionDescription = "none"
        }

        return "pendingAction=\(pendingActionDescription), pendingGesture=\(pendingReleaseGestureKind?.rawValue ?? "nil"), dockSession=\(dockRecognizer.requiresHoveredApplication ? "idle" : "captured"), titleSession=\(titleBarRecognizer.requiresHoveredApplication ? "idle" : "captured"), dockCornerActive=\(dockCornerDragRecognizer.isActive), titleCornerActive=\(titleBarCornerDragRecognizer.isActive), activeCornerApp=\(activeCornerDragApplication?.logDescription ?? "nil")"
    }

    private func shouldLogFrame(
        touchCount: Int,
        dockHoveredApplication: DockApplicationTarget?,
        titleBarHoveredApplication: TitleBarHoverTarget?
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

enum TwoFingerTouchSequenceTransition: Equatable {
    case none
    case restarted(previousIdentifiers: [Int], currentIdentifiers: [Int])
}

struct TwoFingerTouchSequenceTracker {
    private var previousIdentifiers: [Int] = []

    mutating func consume(_ frame: TrackpadTouchFrame) -> TwoFingerTouchSequenceTransition {
        let currentIdentifiers = sortedTwoFingerIdentifiers(in: frame)
        defer {
            previousIdentifiers = currentIdentifiers
        }

        guard previousIdentifiers.count == 2, currentIdentifiers.count == 2 else {
            return .none
        }

        if previousIdentifiers != currentIdentifiers {
            return .restarted(
                previousIdentifiers: previousIdentifiers,
                currentIdentifiers: currentIdentifiers
            )
        }

        return .none
    }

    mutating func reset() {
        previousIdentifiers = []
    }

    private func sortedTwoFingerIdentifiers(in frame: TrackpadTouchFrame) -> [Int] {
        guard frame.touches.count == 2 else {
            return []
        }

        return frame.touches.map(\.identifier).sorted()
    }
}

enum GestureSessionTouchInterruption: Equatable {
    case release
    case invalidAdditionalTouch
}

func gestureSessionTouchInterruption(
    touchCount: Int,
    previousTouchCount: Int,
    hasPendingReleaseAction: Bool,
    hasActiveCornerDrag: Bool
) -> GestureSessionTouchInterruption? {
    if touchCount < 2, previousTouchCount == 2 {
        return .release
    }

    guard touchCount > 2 else {
        return nil
    }

    if hasPendingReleaseAction || hasActiveCornerDrag {
        return .invalidAdditionalTouch
    }

    return nil
}

func cornerDragAction(
    forTouchTranslation translation: CGPoint,
    threshold: CGFloat
) -> WindowAction? {
    guard abs(translation.x) >= threshold, abs(translation.y) >= threshold else {
        return nil
    }

    if translation.x < 0, translation.y > 0 {
        return .topLeftQuarter
    }
    if translation.x > 0, translation.y > 0 {
        return .topRightQuarter
    }
    if translation.x < 0, translation.y < 0 {
        return .bottomLeftQuarter
    }
    if translation.x > 0, translation.y < 0 {
        return .bottomRightQuarter
    }

    return nil
}

func cornerDragTransitionAction(
    from currentAction: WindowAction,
    forTouchTranslation translation: CGPoint,
    threshold: CGFloat
) -> WindowAction {
    guard abs(translation.x) >= threshold || abs(translation.y) >= threshold else {
        return currentAction
    }

    let horizontalDominates = abs(translation.x) >= abs(translation.y)

    if horizontalDominates {
        if translation.x > 0 {
            switch currentAction {
            case .topLeftQuarter:
                return .topRightQuarter
            case .bottomLeftQuarter:
                return .bottomRightQuarter
            default:
                return currentAction
            }
        } else {
            switch currentAction {
            case .topRightQuarter:
                return .topLeftQuarter
            case .bottomRightQuarter:
                return .bottomLeftQuarter
            default:
                return currentAction
            }
        }
    }

    if translation.y > 0 {
        switch currentAction {
        case .bottomLeftQuarter:
            return .topLeftQuarter
        case .bottomRightQuarter:
            return .topRightQuarter
        default:
            return currentAction
        }
    }

    switch currentAction {
    case .topLeftQuarter:
        return .bottomLeftQuarter
    case .topRightQuarter:
        return .bottomRightQuarter
    default:
        return currentAction
    }
}

enum TitleBarHoverSource: Equatable {
    case titleBar
    case browserTabFallback

    func allowsGestureAction(_ action: WindowAction) -> Bool {
        switch self {
        case .titleBar:
            return true
        case .browserTabFallback:
            return action == .closeWindow || action == .quitApplication
        }
    }
}

struct TitleBarHoverTarget: Equatable {
    let application: DockApplicationTarget
    let source: TitleBarHoverSource

    var logDescription: String {
        switch source {
        case .titleBar:
            return application.logDescription
        case .browserTabFallback:
            return "\(application.logDescription) via browser-tab fallback"
        }
    }
}
@MainActor
private final class TitleBarAccessibilityProbe {
    private let cacheTTL: TimeInterval = 0.2
    private let logTTL: TimeInterval = 0.4
    private var cachedHitRegion: CachedHitRegion?
    private var lastProbeLogAt = Date.distantPast
    private var lastProbeLogKey = ""

    private struct CachedHitRegion {
        let application: DockApplicationTarget
        let frame: CGRect
        let expiresAt: Date
        let isFullScreen: Bool
    }

    private struct HoveredWindowTarget {
        let application: DockApplicationTarget
        let window: AXUIElement
    }

    private var preheatTask: Task<Void, Never>?

    func clearCache() {
        preheatTask?.cancel()
        preheatTask = nil
        cachedHitRegion = nil
        lastProbeLogAt = .distantPast
        lastProbeLogKey = ""
    }

    func hoveredTarget(
        at appKitPoint: CGPoint,
        requireFrontmostOwnership: Bool,
        titleBarHeight: CGFloat,
        allowFullScreen: Bool = false,
        allowBrowserTabFallback: Bool = false
    ) -> TitleBarHoverTarget? {
        let now = Date()

        if let cachedHitRegion, now < cachedHitRegion.expiresAt {
            // 快过期时异步预热（距离过期还有 ≤0.15 秒）
            if now >= cachedHitRegion.expiresAt.addingTimeInterval(-0.15) {
                startPreheatIfNeeded(
                    titleBarHeight: titleBarHeight,
                    allowFullScreen: allowFullScreen
                )
            }

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
                return TitleBarHoverTarget(
                    application: cachedHitRegion.application,
                    source: .titleBar
                )
            }

            guard allowBrowserTabFallback else {
                return nil
            }
        }

        // 缓存过期 → 同步重建
        preheatTask?.cancel()
        preheatTask = nil

        guard AXIsProcessTrusted() else {
            cachedHitRegion = nil
            return nil
        }

        guard let hoveredTarget = hoveredWindowTarget(at: appKitPoint) else {
            cachedHitRegion = nil
            return nil
        }

        let window = hoveredTarget.window
        guard let appKitWindowFrame = appKitFrame(of: window) else {
            cachedHitRegion = nil
            return nil
        }

        let windowIsFullScreen = isFullScreen(window)
        if windowIsFullScreen, !allowFullScreen {
            cachedHitRegion = nil
            return nil
        }

        let titleBarFrame = titleBarFrame(for: appKitWindowFrame, titleBarHeight: titleBarHeight)
        guard titleBarFrame.isEmpty == false else {
            cachedHitRegion = nil
            return nil
        }

        let target = hoveredTarget.application

        cachedHitRegion = CachedHitRegion(
            application: target,
            frame: titleBarFrame,
            expiresAt: now.addingTimeInterval(cacheTTL),
            isFullScreen: windowIsFullScreen
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
            return TitleBarHoverTarget(application: target, source: .titleBar)
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
            return TitleBarHoverTarget(application: target, source: .browserTabFallback)
        }

        logProbeIfNeeded(
            key: "miss:\(target.processIdentifier):\(Int(titleBarFrame.minX)):\(Int(titleBarFrame.minY)):\(Int(titleBarFrame.width)):\(Int(titleBarFrame.height))",
            message: {
                "Pointer missed title-bar region for \(target.logDescription) at \(NSStringFromPoint(appKitPoint)); frame = \(NSStringFromRect(titleBarFrame))"
            }
        )
        return nil
    }

    private func startPreheatIfNeeded(titleBarHeight: CGFloat, allowFullScreen: Bool) {
        guard preheatTask == nil else {
        #if DEBUG
            DebugLog.debug(DebugLog.windows, "TitleBar preheat skipped: task already running")
        #endif
            return
        }

        preheatTask = Task { @MainActor [weak self] in
            guard let self else { return }
        #if DEBUG
            let start = Date()
            DebugLog.debug(DebugLog.windows, "TitleBar preheat started")
            defer {
                let elapsed = Date().timeIntervalSince(start)
                let elapsedText = String(format: "%.3f", elapsed)
                DebugLog.debug(
                    DebugLog.windows,
                    "TitleBar preheat finished in \(elapsedText)s; hasCache = \(self.cachedHitRegion != nil)"
                )
            }
        #endif

            let mouseLocation = NSEvent.mouseLocation

            guard AXIsProcessTrusted() else {
                self.cachedHitRegion = nil
                self.preheatTask = nil
                return
            }

            guard let hoveredTarget = self.hoveredWindowTarget(at: mouseLocation) else {
                self.cachedHitRegion = nil
                self.preheatTask = nil
                return
            }

            let window = hoveredTarget.window
            guard let appKitWindowFrame = self.appKitFrame(of: window) else {
                self.cachedHitRegion = nil
                self.preheatTask = nil
                return
            }

            let windowIsFullScreen = self.isFullScreen(window)
            if windowIsFullScreen, !allowFullScreen {
                self.cachedHitRegion = nil
                self.preheatTask = nil
                return
            }

            let titleBarFrame = self.titleBarFrame(for: appKitWindowFrame, titleBarHeight: titleBarHeight)
            guard titleBarFrame.isEmpty == false else {
                self.cachedHitRegion = nil
                self.preheatTask = nil
                return
            }

            let now = Date()
            self.cachedHitRegion = CachedHitRegion(
                application: hoveredTarget.application,
                frame: titleBarFrame,
                expiresAt: now.addingTimeInterval(self.cacheTTL),
                isFullScreen: windowIsFullScreen
            )

            self.preheatTask = nil
        }
    }

    private func hoveredWindowTarget(at appKitPoint: CGPoint) -> HoveredWindowTarget? {
        guard let hitElement = AXAttributeReader.hitElement(at: appKitPoint) else {
            return nil
        }

        guard let hitProcessIdentifier = AXAttributeReader.processIdentifier(of: hitElement) else {
            return nil
        }

        guard
            let application = NSRunningApplication(processIdentifier: hitProcessIdentifier),
            application.isTerminated == false
        else {
            return nil
        }

        let aliases = RunningApplicationIdentity.aliases(for: application)
        let fallbackName = application.bundleIdentifier ?? "Application"
        let resolvedName = application.localizedName ?? aliases.first ?? fallbackName
        let target = DockApplicationTarget(
            dockItemName: resolvedName,
            resolvedApplicationName: resolvedName,
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            aliases: aliases
        )

        if let window = windowElement(containing: hitElement) {
            return HoveredWindowTarget(application: target, window: window)
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let fallbackWindow = focusedOrMainWindow(in: appElement) else {
            return nil
        }

        return HoveredWindowTarget(application: target, window: fallbackWindow)
    }

    private func windowElement(containing element: AXUIElement) -> AXUIElement? {
        AXAttributeReader.window(containing: element)
    }

    private func focusedOrMainWindow(in appElement: AXUIElement) -> AXUIElement? {
        AXAttributeReader.element(kAXFocusedWindowAttribute as CFString, from: appElement) ??
            AXAttributeReader.element(kAXMainWindowAttribute as CFString, from: appElement)
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

    private func titleBarFrame(for windowFrame: CGRect, titleBarHeight: CGFloat) -> CGRect {
        let height = SettingsStore.clampTitleBarTriggerHeight(Double(titleBarHeight))

        return CGRect(
            x: windowFrame.minX,
            y: windowFrame.maxY - CGFloat(height),
            width: windowFrame.width,
            height: CGFloat(height)
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
    guard let hitElement = AXAttributeReader.hitElement(at: appKitPoint) else {
        return nil
    }

    return AXAttributeReader.processIdentifier(of: hitElement)
}

@MainActor
private final class DockAccessibilityProbe {
    private let candidateCacheTTL: TimeInterval = 0.25
    private let regionCacheTTL: TimeInterval = 1.0
    private let logTTL: TimeInterval = 0.4
    private var cachedSnapshot: CachedSnapshot?
    private var cachedHoverHit: CachedHoverHit?
    private var preheatTask: Task<Void, Never>?
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
        preheatTask?.cancel()
        preheatTask = nil
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
                // 快过期时异步预热（距离过期还有 ≤0.5 秒）
                if now >= cachedSnapshot.candidateExpiresAt.addingTimeInterval(-0.5) {
                    startPreheatIfNeeded()
                }
                return cachedSnapshot.snapshot
            }

            if
                now < cachedSnapshot.regionExpiresAt,
                cachedSnapshot.snapshot.containsApproximateDockRegion(appKitPoint) == false
            {
                // 区域缓存有效，同样检查预热
                if now >= cachedSnapshot.candidateExpiresAt.addingTimeInterval(-0.5) {
                    startPreheatIfNeeded()
                }
                return cachedSnapshot.snapshot
            }
        }

        // 缓存过期 → 同步重建
        preheatTask?.cancel()
        preheatTask = nil
        let snapshot = rebuildDockSnapshot()
        cachedSnapshot = CachedSnapshot(
            snapshot: snapshot,
            candidateExpiresAt: now.addingTimeInterval(candidateCacheTTL),
            regionExpiresAt: now.addingTimeInterval(regionCacheTTL)
        )
        return snapshot
    }

    private func startPreheatIfNeeded() {
        guard preheatTask == nil else {
        #if DEBUG
            DebugLog.debug(DebugLog.dock, "Dock preheat skipped: task already running")
        #endif
            return
        }

        preheatTask = Task { @MainActor [weak self] in
            guard let self else { return }
        #if DEBUG
            let start = Date()
            DebugLog.debug(DebugLog.dock, "Dock preheat started")
            defer {
                let elapsed = Date().timeIntervalSince(start)
                let elapsedText = String(format: "%.3f", elapsed)
                DebugLog.debug(
                    DebugLog.dock,
                    "Dock preheat finished in \(elapsedText)s; hasSnapshot = \(self.cachedSnapshot != nil)"
                )
            }
        #endif

            let newSnapshot = self.rebuildDockSnapshot()
            let now = Date()

            self.cachedSnapshot = CachedSnapshot(
                snapshot: newSnapshot,
                candidateExpiresAt: now.addingTimeInterval(self.candidateCacheTTL),
                regionExpiresAt: now.addingTimeInterval(self.regionCacheTTL)
            )

            self.preheatTask = nil
        }
    }

    private func rebuildDockSnapshot() -> DockHoverSnapshot {
        guard AXIsProcessTrusted() else { return DockHoverSnapshot(candidates: []) }
        guard let dockProcess = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return DockHoverSnapshot(candidates: [])
        }

        let dockElement = AXUIElementCreateApplication(dockProcess.processIdentifier)
        guard let dockList = AXAttributeReader.elements(kAXChildrenAttribute as CFString, from: dockElement).first else {
            return DockHoverSnapshot(candidates: [])
        }

        let geometry = ScreenGeometry(screenFrames: NSScreen.screens.map(\.frame))
        var candidates: [DockHoverCandidate] = []
        let applicationRecords = runningApplicationRecords()
        var qualityScoreCache: [pid_t: Int] = [:]

        for item in AXAttributeReader.elements(kAXChildrenAttribute as CFString, from: dockList) {
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
            let normalizedDockName = RunningApplicationIdentity.normalizedAlias(itemName)
            let dockItemKind: DockItemKind =
                matchedRecord.normalizedAliases.contains(normalizedDockName) ? .applicationIcon : .recentWindow
            let target = DockApplicationTarget(
                dockItemName: itemName,
                resolvedApplicationName: matchedApplication.localizedName ?? itemName,
                processIdentifier: matchedApplication.processIdentifier,
                bundleIdentifier: matchedApplication.bundleIdentifier,
                aliases: matchedRecord.aliases,
                dockItemKind: dockItemKind
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

        if let exactAliasMatch = applicationRecords.first(where: { record in
            record.normalizedAliases.contains(normalizedDockName)
        }) {
            return exactAliasMatch
        }

        var bestRecord: ApplicationRecord?
        var bestCombinedScore = Int.min
        var minimizedWindowTitleCache: [pid_t: [String]] = [:]

        for record in applicationRecords {
            let matchScore = DockItemApplicationMatcher.matchScore(
                forNormalizedDockName: normalizedDockName,
                normalizedAliases: record.normalizedAliases,
                normalizedMinimizedWindowTitles: normalizedMinimizedWindowTitles(
                    for: record.application,
                    cache: &minimizedWindowTitleCache
                )
            )
            guard matchScore > 0 else {
                continue
            }

            let qualityScore = cachedApplicationQualityScore(
                for: record.application,
                qualityScoreCache: &qualityScoreCache
            )
            let combinedScore = (matchScore * 1_000) + qualityScore

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

    private func normalizedMinimizedWindowTitles(
        for application: NSRunningApplication,
        cache: inout [pid_t: [String]]
    ) -> [String] {
        if let cachedTitles = cache[application.processIdentifier] {
            return cachedTitles
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let titles = AXAttributeReader
            .elements(kAXWindowsAttribute as CFString, from: appElement)
            .filter { AXAttributeReader.bool(kAXMinimizedAttribute as CFString, from: $0) == true }
            .compactMap { AXAttributeReader.string(kAXTitleAttribute as CFString, from: $0) }
            .map(RunningApplicationIdentity.normalizedAlias)
            .filter { $0.isEmpty == false }

        cache[application.processIdentifier] = titles
        return titles
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

enum DockItemApplicationMatcher {
    static func matchScore(
        forNormalizedDockName normalizedDockName: String,
        normalizedAliases: [String],
        normalizedMinimizedWindowTitles: [String]
    ) -> Int {
        guard normalizedDockName.isEmpty == false else {
            return 0
        }

        if normalizedAliases.contains(normalizedDockName) {
            return 4
        }

        if normalizedMinimizedWindowTitles.contains(normalizedDockName) {
            return 3
        }

        for normalizedTitle in normalizedMinimizedWindowTitles {
            if normalizedTitle.hasPrefix(normalizedDockName) || normalizedTitle.hasSuffix(normalizedDockName) {
                return 2
            }
        }

        return 0
    }
}

final class MultitouchInputMonitor {
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

    func receiveCallbackPayload(
        fingers: UnsafePointer<SwooshyMTFinger>?,
        fingerCount: Int,
        timestamp: Double
    ) {
        guard fingerCount > 0 else {
            deliverZeroTouchFrame(timestamp: timestamp)
            return
        }

        guard let fingers else {
            DebugLog.error(
                DebugLog.dock,
                "Multitouch callback dropped a non-zero finger payload because the finger buffer was nil"
            )
            return
        }

        receive(
            fingers: fingers,
            fingerCount: fingerCount,
            timestamp: timestamp
        )
    }

    fileprivate func receive(
        fingers: UnsafePointer<SwooshyMTFinger>,
        fingerCount: Int,
        timestamp: Double
    ) {
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

    private func deliverZeroTouchFrame(timestamp: Double) {
        guard lastDeliveredFingerCount != 0 else { return }
        lastDeliveredFingerCount = 0
        onFrame?(
            TrackpadTouchFrame(
                touches: [],
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
    guard let context else { return }
    let monitor = Unmanaged<MultitouchInputMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.receiveCallbackPayload(
        fingers: data,
        fingerCount: Int(fingerCount),
        timestamp: timestamp
    )
}
