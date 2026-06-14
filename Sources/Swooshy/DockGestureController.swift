import AppKit
import ApplicationServices
import CMultitouchShim
import Foundation

protocol MultitouchMonitoring: AnyObject {
    var onFrame: ((TrackpadTouchFrame) -> Void)? { get set }
    var isMonitoringActive: Bool { get }

    func startIfAvailable()
    func stop()
}

@MainActor
final class DockGestureController {
    private let windowManager: WindowManager
    private let layoutEngine: WindowLayoutEngine
    private let alertPresenter: AlertPresenting
    private let gestureFeedbackPresenter: GestureFeedbackPresenting
    private let settingsStore: SettingsStore
    private let gestureTargetCaptureController: GestureTargetCaptureController
    private let registry: WindowRegistry
    private let dockProbe: DockTargetResolving
    private let titleBarProbe: TitleBarAccessibilityProbe
    private let triggerRegionOverlayController: GestureTriggerRegionOverlayController
    private let monitor: MultitouchMonitoring
    private let multitouchDeviceRestartCoordinator: MultitouchDeviceRestartCoordinator
    private var dockRecognizer = DockGestureRecognizer()
    private var dockCornerDragRecognizer = TitleBarCornerDragRecognizer()
    private var titleBarRecognizer = DockGestureRecognizer()
    private var titleBarCornerDragRecognizer = TitleBarCornerDragRecognizer()
    private var gestureTargetCaptureRecognizer = GestureTargetCaptureRecognizer()
    private var hasShownPermissionHint = false
    private var settingsObserver: NSObjectProtocol?
    private var workspaceWakeObserver: NSObjectProtocol?
#if DEBUG
    private var lastFrameLogAt = Date.distantPast
    private var lastLoggedTouchCount = -1
    private var lastLoggedHover: String?
#endif
    private var pendingTouchFrame: TrackpadTouchFrame?
    private var isProcessingTouchFrame = false
    private var monitoringState: MonitoringState?
    private var settingsWindowHoverSuppressionRequested = false
    private var isShuttingDown = false
    private let restoreHUDLeadDelay: UInt64 = 16_000_000
    private let gestureStateTimeout: TimeInterval = 30
    private var gestureStateWatchdog: Timer?
    private var gestureStateWatchdogState: GestureStateSnapshot?

    private var touchSequenceTracker = TwoFingerTouchSequenceTracker()
    // Deprecated: pending-release state belongs to the legacy preview-mode
    // gesture flow. It remains because smooth docking, cancellation, and
    // corner-drag commit logic still branch through release-time execution.
    private var pendingReleaseAction: PendingReleaseAction?
    private var globalEscMonitor: Any?
    private var localEscMonitor: Any?
    private var lastTouchCount: Int = 0
    private var pendingReleaseGestureKind: DockGestureKind?
    private var pendingReleaseHighWaterMark: CGFloat?
    private var pendingReleasePinchHighWaterMark: CGFloat?
    private var titleBarSessionHoverSource: TitleBarHoverSource?
    private var activeCornerDragApplication: InteractionTarget?
    private var activeCornerDragSource: CornerDragSource?
    private var activeCornerDragAction: WindowAction?
    private var activeCornerDragAnchorPoint: CGPoint?
    private var activeCornerDragTouchOrigin: CGPoint?
    private var activeCornerDragTouchReferencePoint: CGPoint?
    private var smoothDockingSession: SmoothDockingSession?
    // A session that has begun its restore animation and is awaiting delayed
    // teardown. Kept separate from `smoothDockingSession` so an in-flight
    // gesture update can't revive a session that is already ending.
    private var finishingSmoothDockingSession: SmoothDockingSession?
    // Monotonic tag identifying the current pending teardown, so a stale
    // delayed-finish task can't fire against a re-armed teardown of the same
    // session object. Incremented on every restore teardown.
    private var finishingSmoothDockingGeneration: UInt64 = 0
    private let cornerDragTranslationThreshold: CGFloat = 0.06

    // Deprecated: legacy preview-mode actions are staged here until release.
    private enum PendingReleaseAction {
        case dock(action: DockGestureAction, application: InteractionTarget)
        case titleBar(
            action: WindowAction,
            event: DockGestureEvent,
            anchorPoint: CGPoint,
            replacesWithTabClose: Bool
        )
        case cornerDrag(
            action: WindowAction,
            application: InteractionTarget,
            anchorPoint: CGPoint,
            source: CornerDragSource
        )
    }

    private struct PendingDangerGestureConfirmation {
        enum Source {
            case dock(action: DockGestureAction, application: InteractionTarget)
            case titleBar(
                action: WindowAction,
                event: DockGestureEvent,
                anchorPoint: CGPoint,
                replacesWithTabClose: Bool
            )
        }
        let triggerGesture: DockGestureKind
        let confirmationGesture: DockGestureKind
        let source: Source
        let anchorPoint: CGPoint
        var timeoutTask: Task<Void, Never>?
    }

    private var pendingDangerGestureConfirmation: PendingDangerGestureConfirmation?

    private struct MonitoringState: Equatable {
        let dockCornerDragEnabled: Bool
        let titleBarCornerDragEnabled: Bool
        let dockGesturesEnabled: Bool
        let titleBarGesturesEnabled: Bool
        let displayMoveActionsEnabled: Bool
    }

    private enum CornerDragSource: Equatable {
        case dock
        case titleBar

        var logLabel: String {
            switch self {
            case .dock:
                "dock"
            case .titleBar:
                "title-bar"
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
        registry: WindowRegistry,
        dockTargetResolver: DockTargetResolving,
        layoutEngine: WindowLayoutEngine,
        alertPresenter: AlertPresenting,
        gestureFeedbackPresenter: GestureFeedbackPresenting,
        settingsStore: SettingsStore,
        gestureTargetCaptureController: GestureTargetCaptureController = GestureTargetCaptureController(),
        monitor: MultitouchMonitoring = MultitouchInputMonitor(),
        multitouchDeviceObserver: MultitouchDeviceObserving = HIDMultitouchDeviceObserver()
    ) {
        self.windowManager = windowManager
        self.dockProbe = dockTargetResolver
        self.registry = registry
        self.titleBarProbe = TitleBarAccessibilityProbe(registry: registry)
        self.layoutEngine = layoutEngine
        self.alertPresenter = alertPresenter
        self.gestureFeedbackPresenter = gestureFeedbackPresenter
        self.settingsStore = settingsStore
        self.gestureTargetCaptureController = gestureTargetCaptureController
        self.triggerRegionOverlayController = GestureTriggerRegionOverlayController()
        self.monitor = monitor
        self.multitouchDeviceRestartCoordinator = MultitouchDeviceRestartCoordinator(
            observer: multitouchDeviceObserver
        )

        monitor.onFrame = { [weak self] frame in
            MainActor.assumeIsolated {
                guard let self, !self.isShuttingDown else { return }
                self.schedule(frame: frame)
            }
        }

        observeSettings()
        observeWorkspaceWake()
        observeGestureTargetCapture()
        syncMonitoring()
        observeMultitouchDevices()
    }

    func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        invalidateGestureStateWatchdog()

        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
        if let workspaceWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceWakeObserver)
            self.workspaceWakeObserver = nil
        }
        gestureTargetCaptureController.onStateChanged = nil
        gestureTargetCaptureController.cancel()
        multitouchDeviceRestartCoordinator.stop()

        pendingTouchFrame = nil
        isProcessingTouchFrame = false
        monitoringState = nil
        touchSequenceTracker.reset()
        dockRecognizer = makeConfiguredRecognizer()
        dockCornerDragRecognizer = makeConfiguredCornerDragRecognizer()
        titleBarRecognizer = makeConfiguredRecognizer()
        titleBarCornerDragRecognizer = makeConfiguredCornerDragRecognizer()
        gestureTargetCaptureRecognizer.reset()
        titleBarSessionHoverSource = nil
        activeCornerDragApplication = nil
        activeCornerDragSource = nil
        activeCornerDragAction = nil
        activeCornerDragAnchorPoint = nil
        activeCornerDragTouchOrigin = nil
        activeCornerDragTouchReferencePoint = nil
        pendingDangerGestureConfirmation?.timeoutTask?.cancel()
        pendingDangerGestureConfirmation = nil
        triggerRegionOverlayController.dismiss()
        endSmoothDockingSession(restore: true)
        dockProbe.clearCache()
        titleBarProbe.clearCache()
        windowManager.shutdown()
        monitor.onFrame = nil
        monitor.stop()
        cancelPendingReleaseAction()
    }

    func showGestureTriggerRegions(settingsWindowFrame: CGRect?) {
        guard !isShuttingDown else {
            return
        }

        registry.refreshRunningApplications()

        var items: [GestureTriggerRegionOverlayItem] = []
        if settingsStore.dockGesturesEnabled {
            let dockRegions = dockProbe.currentDockTriggerRegions()
            items += dockRegions.enumerated().map { index, dockRegion in
                GestureTriggerRegionOverlayItem(
                    kind: .dock,
                    frame: dockRegion,
                    title: index == 0 ? settingsStore.localized("settings.trigger_regions.dock.title") : "",
                    detail: index == 0 ? settingsStore.localized("settings.trigger_regions.dock.detail") : ""
                )
            }
        }

        if
            settingsStore.titleBarGesturesEnabled,
            let settingsWindowFrame,
            let titleBarRegion = GestureTriggerRegionOverlayLayout.titleBarRegion(
                forWindowFrame: settingsWindowFrame,
                titleBarHeight: settingsStore.titleBarTriggerHeight
            )
        {
            items.append(
                GestureTriggerRegionOverlayItem(
                    kind: .titleBar,
                    frame: titleBarRegion,
                    title: settingsStore.localized("settings.trigger_regions.title_bar.title"),
                    detail: String(
                        format: settingsStore.localized("settings.trigger_regions.title_bar.detail"),
                        Int(SettingsStore.clampTitleBarTriggerHeight(settingsStore.titleBarTriggerHeight))
                    )
                )
            )
        }

        triggerRegionOverlayController.show(
            items: items,
            localized: settingsStore.localized
        )
    }

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: settingsStore,
            queue: .main
        ) { [weak self] notification in
            let categories = notification.settingsChangeCategories
            MainActor.assumeIsolated {
                guard !categories.intersection([.gestureMonitoring, .advancedGestureBehavior]).isEmpty else {
                    return
                }

                self?.dockProbe.clearCache()
                self?.titleBarProbe.clearCache()
                self?.syncMonitoring()
            }
        }
    }

    private func observeWorkspaceWake() {
        workspaceWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWorkspaceDidWake()
            }
        }
    }

    private func observeMultitouchDevices() {
        multitouchDeviceRestartCoordinator.start(
            shouldRestart: { [weak self] in
                guard let self else {
                    return false
                }

                return !self.isShuttingDown && self.shouldMonitorTrackpad
            },
            restart: { [weak self] in
                self?.handleMultitouchDeviceConfigurationChanged()
            }
        )
    }

    private func observeGestureTargetCapture() {
        gestureTargetCaptureController.onStateChanged = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShuttingDown else { return }
                self.handleGestureTargetCaptureStateChanged()
            }
        }
    }

    func startGestureTargetCapture() {
        guard !isShuttingDown else { return }
        resetGestureStateForNewTouchSequence()
        gestureTargetCaptureRecognizer.reset()
        gestureTargetCaptureController.start()
    }

    func cancelGestureTargetCapture() {
        guard !isShuttingDown else { return }
        gestureTargetCaptureRecognizer.reset()
        gestureTargetCaptureController.cancel()
    }

    private func handleGestureTargetCaptureStateChanged() {
        gestureTargetCaptureRecognizer.reset()
        if gestureTargetCaptureController.isCapturing {
            resetGestureStateForNewTouchSequence()
        }
        applyTrackpadMonitoringState()
    }

    private func handleWorkspaceDidWake() {
        guard !isShuttingDown else {
            return
        }

        DebugLog.info(DebugLog.dock, "Workspace woke; refreshing trackpad gesture monitoring")
        resetTrackpadInputStateForMonitoringRestart()
        restartTrackpadMonitoringIfNeeded(reason: "workspace wake")
    }

    private func handleMultitouchDeviceConfigurationChanged() {
        guard !isShuttingDown else {
            return
        }

        DebugLog.info(DebugLog.dock, "Multitouch device configuration changed; refreshing trackpad gesture monitoring")
        resetTrackpadInputStateForMonitoringRestart()
        restartTrackpadMonitoringIfNeeded(reason: "multitouch device change")
    }

    private func resetTrackpadInputStateForMonitoringRestart() {
        pendingTouchFrame = nil
        isProcessingTouchFrame = false
        lastTouchCount = 0
        touchSequenceTracker.reset()
        dockProbe.clearCache()
        titleBarProbe.clearCache()
        resetGestureStateForNewTouchSequence(rebuildRecognizers: true)
    }

    private func syncMonitoring() {
        guard !isShuttingDown else {
            return
        }

        let state = MonitoringState(
            dockCornerDragEnabled: settingsStore.dockCornerDragSnapEnabled,
            titleBarCornerDragEnabled: settingsStore.titleBarCornerDragSnapEnabled,
            dockGesturesEnabled: settingsStore.dockGesturesEnabled,
            titleBarGesturesEnabled: settingsStore.titleBarGesturesEnabled,
            displayMoveActionsEnabled: settingsStore.experimentalDisplayMoveActionsEnabled
        )
        guard state != monitoringState else { return }

        monitoringState = state
        DebugLog.info(
            DebugLog.dock,
            "Syncing gesture monitoring; dockGesturesEnabled=\(state.dockGesturesEnabled), titleBarGesturesEnabled=\(state.titleBarGesturesEnabled), dockCornerDragEnabled=\(state.dockCornerDragEnabled), titleBarCornerDragEnabled=\(state.titleBarCornerDragEnabled), displayMoveActionsEnabled=\(state.displayMoveActionsEnabled)"
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

        applyTrackpadMonitoringState()

        syncGestureStateWatchdog()
    }

    func setSettingsWindowHoverSuppressed(_ isSuppressed: Bool) {
        guard !isShuttingDown else {
            return
        }

        guard settingsWindowHoverSuppressionRequested != isSuppressed else {
            return
        }

        settingsWindowHoverSuppressionRequested = isSuppressed

        if isSuppressed && !activeInteractionPreventsSettingsHoverPause {
            pendingTouchFrame = nil
            isProcessingTouchFrame = false
            lastTouchCount = 0
            touchSequenceTracker.reset()
            dockProbe.clearCache()
            titleBarProbe.clearCache()
            resetGestureStateForNewTouchSequence()
        }

        applyTrackpadMonitoringState()
    }

    private var monitoringRequestedBySettings: Bool {
        guard let monitoringState else {
            return gestureTargetCaptureController.isCapturing
        }

        return monitoringState.dockGesturesEnabled ||
            monitoringState.titleBarGesturesEnabled ||
            gestureTargetCaptureController.isCapturing
    }

    private var activeInteractionPreventsSettingsHoverPause: Bool {
        hasActiveGestureState ||
            smoothDockingSession != nil ||
            finishingSmoothDockingSession != nil ||
            gestureTargetCaptureController.isCapturing
    }

    private var shouldSuppressTrackpadMonitoringForSettingsHover: Bool {
        settingsWindowHoverSuppressionRequested && !activeInteractionPreventsSettingsHoverPause
    }

    private var shouldMonitorTrackpad: Bool {
        monitoringRequestedBySettings && !shouldSuppressTrackpadMonitoringForSettingsHover
    }

    private func applyTrackpadMonitoringState() {
        if shouldMonitorTrackpad {
            guard !monitor.isMonitoringActive else {
                return
            }

            DebugLog.info(DebugLog.dock, "Starting trackpad gesture monitoring")
            monitor.startIfAvailable()
            return
        }

        guard monitor.isMonitoringActive else {
            return
        }

        if shouldSuppressTrackpadMonitoringForSettingsHover {
            DebugLog.info(
                DebugLog.dock,
                "Pausing trackpad gesture monitoring while pointer is inside settings window"
            )
        } else {
            DebugLog.info(DebugLog.dock, "Stopping trackpad gesture monitoring")
        }

        monitor.stop()
    }

    private func restartTrackpadMonitoringIfNeeded(reason: String) {
        guard shouldMonitorTrackpad else {
            return
        }

        DebugLog.info(DebugLog.dock, "Restarting trackpad gesture monitoring after \(reason)")
        monitor.stop()
        monitor.startIfAvailable()
        DebugLog.info(DebugLog.dock, "Trackpad gesture monitoring restart requested after \(reason)")
    }

    private func schedule(frame: TrackpadTouchFrame) {
        guard !isShuttingDown else { return }

        pendingTouchFrame = frame
        guard !isProcessingTouchFrame else { return }

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
        guard !isShuttingDown else { return }
        defer {
            syncGestureStateWatchdog()
        }

        let dockGesturesEnabled = settingsStore.dockGesturesEnabled
        let titleBarGesturesEnabled = settingsStore.titleBarGesturesEnabled
        let dockCornerDragEnabled = dockGesturesEnabled && settingsStore.dockCornerDragSnapEnabled
        let titleBarCornerDragEnabled = titleBarGesturesEnabled && settingsStore.titleBarCornerDragSnapEnabled
        let targetCaptureEnabled = gestureTargetCaptureController.isCapturing
        guard dockGesturesEnabled || titleBarGesturesEnabled || targetCaptureEnabled else { return }

        let touchCount = frame.touches.count
        let previousTouchCount = lastTouchCount
        lastTouchCount = touchCount

        refreshRecognizerConfiguration()

        if targetCaptureEnabled {
            handleGestureTargetCapture(frame: frame)
            return
        }

        guard dockGesturesEnabled || titleBarGesturesEnabled else { return }

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
            return
        }

        let needsDockLookup = gestureHoverLookupRequired(
            gesturesEnabled: dockGesturesEnabled,
            standardRecognizerRequiresHoveredApplication: dockRecognizer.requiresHoveredApplication,
            cornerDragEnabled: dockCornerDragEnabled,
            cornerDragRecognizerRequiresHoveredApplication: dockCornerDragRecognizer.requiresHoveredApplication,
            hasActiveCornerDragApplication: activeCornerDragApplication != nil
        )
        let needsTitleBarLookup = gestureHoverLookupRequired(
            gesturesEnabled: titleBarGesturesEnabled,
            standardRecognizerRequiresHoveredApplication: titleBarRecognizer.requiresHoveredApplication,
            cornerDragEnabled: titleBarCornerDragEnabled,
            cornerDragRecognizerRequiresHoveredApplication: titleBarCornerDragRecognizer.requiresHoveredApplication,
            hasActiveCornerDragApplication: activeCornerDragApplication != nil
        )
        let mouseLocation = (needsDockLookup || needsTitleBarLookup) ? NSEvent.mouseLocation : nil
        let hoveredDockApplication = needsDockLookup ? mouseLocation.flatMap {
            dockProbe.hoveredTarget(
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

    private func handleGestureTargetCapture(frame: TrackpadTouchFrame) {
        guard frame.touches.count == 2 else {
            _ = gestureTargetCaptureRecognizer.process(frame: frame)
            return
        }

        guard let gesture = gestureTargetCaptureRecognizer.process(frame: frame) else {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        if let appIdentity = capturedAppIdentity(at: mouseLocation) {
            showGestureTargetCaptureHUD(
                gesture: gesture,
                applicationName: appIdentity.localizedName,
                anchorPoint: mouseLocation
            )
            gestureTargetCaptureController.complete(with: GestureExcludedApplication(appIdentity))
            DebugLog.info(
                DebugLog.dock,
                "Captured gesture exclusion target \(appIdentity.logDescription) at \(NSStringFromPoint(mouseLocation))"
            )
        } else {
            gestureTargetCaptureController.miss()
            DebugLog.info(
                DebugLog.dock,
                "Gesture exclusion target capture missed at \(NSStringFromPoint(mouseLocation))"
            )
        }

        gestureTargetCaptureRecognizer.reset()
        // The capture success HUD uses the same presenter, so a full gesture reset here would hide it immediately.
    }

    private func capturedAppIdentity(at appKitPoint: CGPoint) -> AppIdentity? {
        if let dockTarget = dockProbe.hoveredTarget(at: appKitPoint, requireFrontmostOwnership: false) {
            return dockTarget.appIdentity
        }

        if let hitAppIdentity = appIdentityAtHitPoint(appKitPoint) {
            return hitAppIdentity
        }

        if let titleBarTarget = titleBarProbe.hoveredTarget(
            at: appKitPoint,
            requireFrontmostOwnership: false,
            titleBarHeight: CGFloat(settingsStore.titleBarTriggerHeight),
            allowFullScreen: true,
            allowBrowserTabFallback: false
        ) {
            return titleBarTarget.application.appIdentity
        }

        return nil
    }

    private func appIdentityAtHitPoint(_ appKitPoint: CGPoint) -> AppIdentity? {
        guard let processIdentifier = AXAttributeReader.processIdentifier(at: appKitPoint) else {
            return nil
        }

        if let appIdentity = registry.appIdentity(forProcessIdentifier: processIdentifier) {
            return appIdentity
        }

        guard let application = NSRunningApplication(processIdentifier: processIdentifier) else {
            return nil
        }

        return AppIdentity(application: application)
    }

    private func showGestureTargetCaptureHUD(
        gesture: DockGestureKind,
        applicationName: String,
        anchorPoint: CGPoint
    ) {
        gestureFeedbackPresenter.show(
            gesture: gesture,
            gestureTitle: settingsStore.localized("gesture.capture.selected.title"),
            actionTitle: String(
                format: settingsStore.localized("gesture.capture.selected.application_format"),
                applicationName
            ),
            anchor: anchorPoint,
            persistent: false,
            preview: nil
        )
        gestureFeedbackPresenter.scheduleDismiss()
    }

    private func handleCornerDragEvent(
        _ event: TitleBarCornerDragEvent?,
        frame: TrackpadTouchFrame,
        hoveredApplication: InteractionTarget?,
        anchorPoint: CGPoint,
        source: CornerDragSource
    ) -> Bool {
        switch event {
        case .began(let application, let startAveragePoint, let currentAveragePoint):
            let surface: GestureExclusionSurface = source == .dock ? .dock : .titleBar
            guard !settingsStore.isCornerDragExcluded(on: surface, for: application) else {
                resetCornerDragRecognizer(for: source)
                DebugLog.debug(
                    DebugLog.dock,
                    "Ignoring excluded \(source.logLabel) corner drag for \(application.logDescription)"
                )
                return false
            }

            guard !standardGestureWouldTrigger(
                beforeCornerDragFrom: source,
                frame: frame,
                hoveredApplication: hoveredApplication ?? application
            ) else {
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
        case .changed(let application, _, let currentAveragePoint):
            let surface: GestureExclusionSurface = source == .dock ? .dock : .titleBar
            guard !settingsStore.isCornerDragExcluded(on: surface, for: application) else {
                resetCornerDragSession(dismissFeedback: true)
                DebugLog.debug(
                    DebugLog.dock,
                    "Cancelled excluded \(source.logLabel) corner drag for \(application.logDescription)"
                )
                return true
            }
            updateCornerDragFeedback(currentTouchPoint: currentAveragePoint)
            return true
        case .ended:
            return activeCornerDragApplication != nil
        case .none:
            let recognizerIsActive = source == .dock
                ? dockCornerDragRecognizer.isActive
                : titleBarCornerDragRecognizer.isActive
            guard recognizerIsActive else {
                return false
            }
            return hoveredApplication != nil || activeCornerDragApplication != nil
        }
    }

    private func handleDockGestureEvent(_ event: DockGestureEvent, anchorPoint: CGPoint, touches: [TrackpadTouchSample]) {
        let application = event.application

        if let pending = pendingDangerGestureConfirmation,
           case .dock(let pendingAction, let pendingApp) = pending.source,
           dockDangerGestureConfirmationMatches(
               pendingConfirmationGesture: pending.confirmationGesture,
               pendingApplication: pendingApp,
               confirmationGesture: event.gesture,
               application: application
        ) {
            guard !settingsStore.isGestureExcluded(event.gesture, on: .dock, for: application) else {
                clearDangerGestureConfirmation()
                DebugLog.debug(
                    DebugLog.dock,
                    "Ignoring excluded Dock confirmation gesture \(event.gesture.rawValue) for \(application.logDescription)"
                )
                return
            }

            clearDangerGestureConfirmation()
            DebugLog.info(DebugLog.dock, "Danger gesture confirmation accepted for dock action \(pendingAction.rawValue)")
            scheduleDockGestureAction(pendingAction, for: pendingApp, gesture: pending.triggerGesture)
            return
        }

        guard settingsStore.dockGestureIsEnabled(for: event.gesture) else {
            DebugLog.debug(DebugLog.dock, "Ignoring disabled Dock gesture \(event.gesture.rawValue)")
            return
        }
        guard !settingsStore.isGestureExcluded(event.gesture, on: .dock, for: event.application) else {
            clearDangerGestureConfirmation()
            DebugLog.debug(
                DebugLog.dock,
                "Ignoring excluded Dock gesture \(event.gesture.rawValue) for \(event.application.logDescription)"
            )
            return
        }
        let action = settingsStore.dockGestureAction(for: event.gesture)

        if requiresDangerGestureConfirmation(dockGesture: event.gesture, dockAction: action) {
            showDangerGestureConfirmation(
                gesture: event.gesture,
                actionTitle: action.title(preferredLanguages: settingsStore.preferredLanguages),
                anchorPoint: anchorPoint,
                source: .dock(action: action, application: application)
            )
            return
        }

        clearDangerGestureConfirmation(dismissFeedback: false)

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
            scheduleDockGestureAction(action, for: application, gesture: event.gesture)
        }
    }

    private func scheduleDockGestureAction(
        _ action: DockGestureAction,
        for application: InteractionTarget,
        gesture: DockGestureKind
    ) {
        Task { @MainActor [weak self] in
            guard let self, !self.isShuttingDown else { return }

            await Task.yield()
            guard !self.settingsStore.isGestureExcluded(gesture, on: .dock, for: application) else {
                DebugLog.info(DebugLog.dock, "Ignoring deferred excluded Dock gesture \(gesture.rawValue)")
                return
            }
            guard self.settingsStore.isDockGestureActionAvailable(action) else {
                DebugLog.info(DebugLog.dock, "Ignoring unavailable Dock gesture action \(action.rawValue)")
                return
            }

            // Give AppKit one frame to present HUD before heavier restore AX work.
            if action == .restoreWindow {
                try? await Task.sleep(nanoseconds: self.restoreHUDLeadDelay)
                guard !self.isShuttingDown else { return }
            }

            self.performDockGestureAction(action, for: application)
        }
    }

    private func performDockGestureAction(_ action: DockGestureAction, for application: InteractionTarget) {
        guard settingsStore.isDockGestureActionAvailable(action) else {
            DebugLog.info(DebugLog.dock, "Ignoring unavailable Dock gesture action \(action.rawValue)")
            return
        }

        runWindowAction(failureMessage: "Dock gesture action failed") {
            switch action {
            case .minimizeWindow:
                try requireWindowActionPerformed(
                    try windowManager.minimizeVisibleWindow(of: application)
                )
            case .restoreWindow:
                switch application {
                case .window(let windowIdentity, _, let source) where source.isDockMinimizedItem:
                    try requireWindowActionPerformed(
                        try windowManager.restoreWindow(windowIdentity)
                    )
                case .unresolvedDockMinimizedItem(let handle):
                    try requireWindowActionPerformed(
                        try windowManager.restoreDockItem(handle)
                    )
                case .application(let appIdentity, _), .window(_, let appIdentity, _):
                    try requireWindowActionPerformed(
                        try windowManager.restoreMinimizedWindow(of: appIdentity)
                    )
                }
            case .cycleWindowsForward:
                try requireWindowActionPerformed(
                    try windowManager.cycleVisibleWindows(of: application, direction: .forward)
                )
            case .cycleWindowsBackward:
                try requireWindowActionPerformed(
                    try windowManager.cycleVisibleWindows(of: application, direction: .backward)
                )
            case .closeWindow:
                try requireWindowActionPerformed(
                    try windowManager.closeWindow(of: application, preferredAppKitPoint: nil)
                )
            case .closeTab:
                guard BrowserTabProbe.simulateMiddleClickAtMouseLocation() else {
                    throw WindowManagerError.unableToPerformAction
                }
            case .quitApplication:
                guard let appIdentity = application.appIdentity else {
                    throw WindowManagerError.unableToPerformAction
                }
                try requireWindowActionPerformed(
                    try windowManager.quitApplication(matching: appIdentity)
                )
            case .toggleFullScreenWindow:
                try requireWindowActionPerformed(
                    try windowManager.toggleFullScreenWindow(of: application)
                )
            case .exitFullScreenWindow:
                try requireWindowActionPerformed(
                    try windowManager.exitFullScreenWindow(of: application)
                )
            case .moveWindowToNextDisplay:
                try windowManager.perform(
                    .moveToNextDisplay,
                    on: application,
                    layoutEngine: layoutEngine,
                    preferredAppKitPoint: nil
                )
            case .moveWindowToPreviousDisplay:
                try windowManager.perform(
                    .moveToPreviousDisplay,
                    on: application,
                    layoutEngine: layoutEngine,
                    preferredAppKitPoint: nil
                )
            }
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

        if let pending = pendingDangerGestureConfirmation,
           case .titleBar(let pendingAction, let pendingEvent, let pendingAnchorPoint, let pendingReplaces) = pending.source,
           titleBarDangerGestureConfirmationMatches(
               pendingConfirmationGesture: pending.confirmationGesture,
               pendingApplication: pendingEvent.application,
               confirmationGesture: event.gesture,
               application: event.application
        ) {
            guard !settingsStore.isGestureExcluded(event.gesture, on: .titleBar, for: event.application) else {
                clearDangerGestureConfirmation()
                DebugLog.debug(
                    DebugLog.dock,
                    "Ignoring excluded title-bar confirmation gesture \(event.gesture.rawValue) for \(event.application.logDescription)"
                )
                return
            }

            clearDangerGestureConfirmation()
            DebugLog.info(DebugLog.dock, "Danger gesture confirmation accepted for title-bar action \(String(describing: pendingAction))")
            executeTitleBarAction(
                pendingAction,
                event: pendingEvent,
                anchorPoint: pendingAnchorPoint,
                replacesWithTabClose: pendingReplaces
            )
            return
        }

        guard settingsStore.titleBarGestureIsEnabled(for: event.gesture) else {
            DebugLog.debug(DebugLog.dock, "Ignoring disabled title-bar gesture \(event.gesture.rawValue)")
            return
        }

        guard !settingsStore.isGestureExcluded(event.gesture, on: .titleBar, for: event.application) else {
            clearDangerGestureConfirmation()
            DebugLog.debug(
                DebugLog.dock,
                "Ignoring excluded title-bar gesture \(event.gesture.rawValue) for \(event.application.logDescription)"
            )
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
        let replacesWithFullScreenExit = titleBarGestureReplacesWithFullScreenExit(
            gesture: event.gesture,
            isInFullScreen: isInFullScreen
        )

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

        if !replacesWithTabClose,
           requiresDangerGestureConfirmation(
               titleBarGesture: event.gesture,
               action: action,
               application: event.application,
               isReplacedBySmartFullScreenExit: replacesWithFullScreenExit
           ) {
            showDangerGestureConfirmation(
                gesture: event.gesture,
                actionTitle: action.title(preferredLanguages: settingsStore.preferredLanguages),
                anchorPoint: anchorPoint,
                source: .titleBar(
                    action: action,
                    event: event,
                    anchorPoint: anchorPoint,
                    replacesWithTabClose: replacesWithTabClose
                )
            )
            return
        }

        clearDangerGestureConfirmation(dismissFeedback: false)

        var actionTitle = action.title(preferredLanguages: settingsStore.preferredLanguages)
        if replacesWithTabClose {
            actionTitle = L10n.string(
                "action.close_tab",
                preferredLanguages: settingsStore.preferredLanguages
            )
        } else if replacesWithFullScreenExit {
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
        guard !settingsStore.isGestureExcluded(event.gesture, on: .titleBar, for: event.application) else {
            DebugLog.info(DebugLog.dock, "Ignoring excluded title-bar gesture \(event.gesture.rawValue)")
            return
        }

        guard settingsStore.isWindowActionAvailable(action) else {
            DebugLog.info(DebugLog.dock, "Ignoring unavailable title-bar gesture action \(String(describing: action))")
            return
        }

        runWindowAction(failureMessage: "Title-bar gesture action failed") {
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
        }
    }

    private func titleBarAction(for gesture: DockGestureKind) -> WindowAction? {
        settingsStore.titleBarGestureAction(for: gesture)
    }

    private func titleBarGestureReplacesWithFullScreenExit(
        gesture: DockGestureKind,
        isInFullScreen: Bool
    ) -> Bool {
        settingsStore.smartPinchExitFullScreenEnabled && isInFullScreen && gesture == .pinchIn
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
            !dockRecognizer.requiresHoveredApplication ||
            !titleBarRecognizer.requiresHoveredApplication ||
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
        hoveredApplication: InteractionTarget?
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
        clearDangerGestureConfirmation()
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
            dockRecognizerCaptured: !dockRecognizer.requiresHoveredApplication,
            titleBarRecognizerCaptured: !titleBarRecognizer.requiresHoveredApplication,
            dockCornerDragActive: dockCornerDragRecognizer.isActive,
            titleBarCornerDragActive: titleBarCornerDragRecognizer.isActive,
            activeCornerDragProcessIdentifier: activeCornerDragApplication?.processIdentifier
        )
    }

    private func syncGestureStateWatchdog() {
        let nextState = gestureStateSnapshot()
        applyTrackpadMonitoringState()
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
        guard !isShuttingDown else { return }
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
        restartTrackpadMonitoringIfNeeded(reason: "watchdog recovery")
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

        guard action.supportsBrowserTabCloseReplacement else {
            DebugLog.debug(DebugLog.dock, "Smart browser tab close skipped for non-close action \(String(describing: action))")
            return false
        }

        if hoverSource == .browserTabFallback {
            DebugLog.debug(DebugLog.dock, "Smart browser tab close accepted from browser-tab fallback")
            return true
        }

        guard let processIdentifier = event.application.processIdentifier else {
            return false
        }

        let isBrowserTab = BrowserTabProbe.isBrowserTab(
            at: anchorPoint,
            processIdentifier: processIdentifier
        )

        DebugLog.debug(
            DebugLog.dock,
            "Smart browser tab probe for \(event.application.logDescription) at \(NSStringFromPoint(anchorPoint)) => \(isBrowserTab)"
        )

        if isInFullScreen && !isBrowserTab {
            DebugLog.debug(DebugLog.dock, "Smart browser tab close skipped in full screen outside browser tab")
        }

        return isBrowserTab
    }

    // MARK: - Execute on Release

    private func installEscMonitor() {
        guard globalEscMonitor == nil, localEscMonitor == nil else { return }
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return } // 53 = Esc
            Task { @MainActor [weak self] in
                self?.cancelPendingReleaseAction()
            }
        }
        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // 53 = Esc
            Task { @MainActor [weak self] in
                self?.cancelPendingReleaseAction()
            }
            return event
        }
        DebugLog.debug(DebugLog.dock, "Installed Esc monitors for pending gesture")
    }

    private func removeEscMonitor() {
        let didRemoveMonitor = globalEscMonitor != nil || localEscMonitor != nil
        if let globalEscMonitor {
            NSEvent.removeMonitor(globalEscMonitor)
            self.globalEscMonitor = nil
        }
        if let localEscMonitor {
            NSEvent.removeMonitor(localEscMonitor)
            self.localEscMonitor = nil
        }
        if didRemoveMonitor {
            DebugLog.debug(DebugLog.dock, "Removed Esc monitors")
        }
    }

    // Deprecated: cancellation here only exists for the legacy preview-mode
    // flow that can still back out before finger release.
    private func cancelPendingReleaseAction() {
        guard pendingReleaseAction != nil || activeCornerDragApplication != nil else {
            endSmoothDockingSession(restore: true)
            removeEscMonitor()
            return
        }
        DebugLog.info(DebugLog.dock, "Cancelled pending gesture action")
        resetGestureStateForNewTouchSequence()
    }

    // MARK: - Danger Gesture Confirmation

    private func requiresDangerGestureConfirmation(
        titleBarGesture gesture: DockGestureKind,
        action: WindowAction,
        application: InteractionTarget,
        isReplacedBySmartFullScreenExit: Bool
    ) -> Bool {
        CloseGestureConfirmationPolicy.requiresConfirmationForTitleBarGesture(
            gesture: gesture,
            action: action,
            application: application,
            requiresDangerConfirmation: settingsStore.dangerGestureConfirmationEnabled
                && settingsStore.requiresDangerGestureConfirmation(gesture, on: .titleBar),
            isReplacedBySmartFullScreenExit: isReplacedBySmartFullScreenExit
        )
    }

    private func requiresDangerGestureConfirmation(
        dockGesture gesture: DockGestureKind,
        dockAction: DockGestureAction
    ) -> Bool {
        CloseGestureConfirmationPolicy.requiresConfirmationForDockGesture(
            gesture: gesture,
            action: dockAction,
            requiresDangerConfirmation: settingsStore.dangerGestureConfirmationEnabled
                && settingsStore.requiresDangerGestureConfirmation(gesture, on: .dock)
        )
    }

    private func showDangerGestureConfirmation(
        gesture: DockGestureKind,
        actionTitle: String,
        anchorPoint: CGPoint,
        source: PendingDangerGestureConfirmation.Source
    ) {
        clearDangerGestureConfirmation(dismissFeedback: false)

        // Confirmation is always the same gesture repeated, so the HUD shows the
        // triggering gesture glyph plus a "repeat to confirm" prompt naming the
        // action that is waiting.
        let confirmationGestureTitle = gesture.title(preferredLanguages: settingsStore.preferredLanguages)
        let confirmationText = String(
            format: settingsStore.localized("confirmation.repeat_gesture.format"),
            actionTitle
        )
        gestureFeedbackPresenter.show(
            gesture: gesture,
            gestureTitle: confirmationGestureTitle,
            actionTitle: confirmationText,
            anchor: anchorPoint,
            persistent: true,
            preview: nil
        )

        let timeout = UInt64(settingsStore.dangerGestureConfirmationDuration * 1_000_000_000)
        let timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeout)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.clearDangerGestureConfirmation()
        }

        pendingDangerGestureConfirmation = PendingDangerGestureConfirmation(
            triggerGesture: gesture,
            confirmationGesture: gesture,
            source: source,
            anchorPoint: anchorPoint,
            timeoutTask: timeoutTask
        )

        DebugLog.info(DebugLog.dock, "Showing danger gesture confirmation HUD")
    }

    private func clearDangerGestureConfirmation(dismissFeedback: Bool = true) {
        guard pendingDangerGestureConfirmation != nil else {
            return
        }

        pendingDangerGestureConfirmation?.timeoutTask?.cancel()
        pendingDangerGestureConfirmation = nil
        if dismissFeedback {
            gestureFeedbackPresenter.dismiss()
        }
    }

    // Deprecated: once preview mode is fully removed, actions should no longer
    // need this release-time commit path.
    private func executePendingReleaseAction() {
        guard let action = pendingReleaseAction else { return }
        let releasedGesture = pendingReleaseGestureKind
        pendingReleaseAction = nil
        clearTouchAnchor()
        removeEscMonitor()
        gestureFeedbackPresenter.scheduleDismiss()

        switch action {
        case .dock(let dockAction, let application):
            guard let releasedGesture else {
                DebugLog.info(DebugLog.dock, "Ignoring deferred Dock action without a recorded gesture")
                break
            }
            guard !settingsStore.isGestureExcluded(releasedGesture, on: .dock, for: application) else {
                DebugLog.info(DebugLog.dock, "Ignoring deferred excluded Dock gesture \(releasedGesture.rawValue)")
                break
            }
            guard settingsStore.isDockGestureActionAvailable(dockAction) else {
                DebugLog.info(DebugLog.dock, "Ignoring deferred unavailable Dock action \(dockAction.rawValue)")
                break
            }
            endSmoothDockingSession(restore: false)
            DebugLog.info(DebugLog.dock, "Executing deferred dock action \(dockAction.rawValue) on finger release")
            scheduleDockGestureAction(dockAction, for: application, gesture: releasedGesture)
        case .titleBar(let windowAction, let event, let anchorPoint, let replacesWithTabClose):
            guard !settingsStore.isGestureExcluded(event.gesture, on: .titleBar, for: event.application) else {
                DebugLog.info(DebugLog.dock, "Ignoring deferred excluded title-bar gesture \(event.gesture.rawValue)")
                break
            }
            guard settingsStore.isWindowActionAvailable(windowAction) else {
                DebugLog.info(DebugLog.dock, "Ignoring deferred unavailable title-bar action \(String(describing: windowAction))")
                break
            }
            DebugLog.info(DebugLog.dock, "Executing deferred title-bar action \(String(describing: windowAction)) on finger release")
            if !commitSmoothDockingSessionIfNeeded(for: windowAction) {
                executeTitleBarAction(
                    windowAction,
                    event: event,
                    anchorPoint: anchorPoint,
                    replacesWithTabClose: replacesWithTabClose
                )
            }
        case .cornerDrag(let windowAction, let application, let anchorPoint, let source):
            let surface: GestureExclusionSurface = source == .dock ? .dock : .titleBar
            guard !settingsStore.isCornerDragExcluded(on: surface, for: application) else {
                DebugLog.info(DebugLog.dock, "Ignoring deferred excluded \(source.logLabel) corner drag")
                break
            }
            DebugLog.info(DebugLog.dock, "Executing deferred corner drag action \(String(describing: windowAction)) on finger release")
            if !commitSmoothDockingSessionIfNeeded(for: windowAction) {
                executeCornerDragAction(
                    windowAction,
                    application: application,
                    anchorPoint: anchorPoint,
                    source: source
                )
            }
        }

        // Clear any corner-drag session left over from the switch above so
        // hasActiveGestureState drops back to idle; otherwise the
        // activeCornerDrag* fields keep monitoring armed and the watchdog
        // ticking until the next touch sequence or the 30s timeout. This also
        // covers the corner-drag exclusion `break` path. For dock/title-bar
        // actions there is no active corner drag, so this is a harmless no-op.
        // Feedback dismissal was already scheduled at the top of this method.
        resetCornerDragSession(dismissFeedback: false)
        resetStandardRecognizers()
    }

    private func executeCornerDragAction(
        _ action: WindowAction,
        application: InteractionTarget,
        anchorPoint: CGPoint,
        source: CornerDragSource
    ) {
        let surface: GestureExclusionSurface = source == .dock ? .dock : .titleBar
        guard !settingsStore.isCornerDragExcluded(on: surface, for: application) else {
            DebugLog.info(DebugLog.dock, "Ignoring excluded \(source.logLabel) corner drag action")
            return
        }

        runWindowAction(failureMessage: "Corner drag action failed") {
            try windowManager.perform(
                action,
                on: application,
                layoutEngine: layoutEngine,
                preferredAppKitPoint: anchorPoint
            )
        }
    }

    // Deprecated preview-mode helper: tracks gesture progress so reverse motion
    // can cancel a pending action before finger release.
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

    // Deprecated preview-mode helper: reverse cancellation only applies while a
    // release-deferred gesture is pending.
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
        application: InteractionTarget,
        anchorPoint: CGPoint
    ) {
        guard action.supportsSmoothDocking else {
            endSmoothDockingSession(restore: true)
            return
        }

        // A session may be mid-teardown: it has begun its restore animation and
        // is awaiting the delayed finish task. Reclaim it instead of starting a
        // second session that would fight over the same window. Niling
        // finishingSmoothDockingSession makes the pending finish task's identity
        // guard fail, so it returns early and won't finish the session out from
        // under us. The update(action:) below redirects its animation.
        if smoothDockingSession == nil, let reclaimed = finishingSmoothDockingSession {
            finishingSmoothDockingSession = nil
            smoothDockingSession = reclaimed
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

        if runWindowAction(failureMessage: "Smooth docking commit failed", {
            _ = try smoothDockingSession.commit()
            smoothDockingSession.finish()
            self.smoothDockingSession = nil
            applyTrackpadMonitoringState()
        }) {
            return true
        }

        smoothDockingSession.finish()
        self.smoothDockingSession = nil
        applyTrackpadMonitoringState()
        return false
    }

    private func endSmoothDockingSession(restore: Bool) {
        guard let smoothDockingSession else {
            return
        }

        if restore {
            smoothDockingSession.restore()
            let session = smoothDockingSession
            // Move the session out of `smoothDockingSession` immediately so an
            // in-flight gesture update can't call `.update(...)` on a session
            // that is already restoring/ending during the delayed teardown.
            self.smoothDockingSession = nil
            finishingSmoothDockingSession = session
            // Tag this teardown with a monotonic generation. The delayed task
            // only finishes the session if this exact generation is still the
            // one pending. An object-identity check is insufficient: reclaiming
            // and re-ending the same session object within 160ms would let an
            // earlier task's `=== session` guard pass again and prematurely
            // finish (truncating) the second restore animation.
            finishingSmoothDockingGeneration &+= 1
            let generation = finishingSmoothDockingGeneration
            applyTrackpadMonitoringState()
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 160_000_000)
                guard let self,
                    self.finishingSmoothDockingGeneration == generation,
                    self.finishingSmoothDockingSession === session
                else {
                    return
                }

                session.finish()
                self.finishingSmoothDockingSession = nil
                self.applyTrackpadMonitoringState()
            }
            return
        }

        smoothDockingSession.finish()
        self.smoothDockingSession = nil
        applyTrackpadMonitoringState()
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
        dockHoveredApplication: InteractionTarget?,
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

    @discardableResult
    private func runWindowAction(
        failureMessage: String,
        _ action: () throws -> Void
    ) -> Bool {
        do {
            try action()
            return true
        } catch let error as WindowManagerError {
            handleWindowManagerError(error)
        } catch {
            NSSound.beep()
            DebugLog.error(DebugLog.dock, "\(failureMessage): \(error.localizedDescription)")
        }

        return false
    }

    private func requireWindowActionPerformed(_ didPerform: Bool) throws {
        guard didPerform else {
            throw WindowManagerError.unableToPerformAction
        }
    }

    private func handleWindowManagerError(_ error: WindowManagerError) {
        switch error {
        case .accessibilityPermissionMissing:
            guard !hasShownPermissionHint else { return }

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

    return hasPendingReleaseAction || hasActiveCornerDrag ? .invalidAdditionalTouch : nil
}

func gestureHoverLookupRequired(
    gesturesEnabled: Bool,
    standardRecognizerRequiresHoveredApplication: Bool,
    cornerDragEnabled: Bool,
    cornerDragRecognizerRequiresHoveredApplication: Bool,
    hasActiveCornerDragApplication: Bool
) -> Bool {
    guard gesturesEnabled, !hasActiveCornerDragApplication else {
        return false
    }

    return standardRecognizerRequiresHoveredApplication ||
        (cornerDragEnabled && cornerDragRecognizerRequiresHoveredApplication)
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

    if abs(translation.x) >= abs(translation.y) {
        return horizontalCornerDragTransition(
            from: currentAction,
            movingRight: translation.x > 0
        )
    }

    return verticalCornerDragTransition(
        from: currentAction,
        movingUp: translation.y > 0
    )
}

private func horizontalCornerDragTransition(
    from currentAction: WindowAction,
    movingRight: Bool
) -> WindowAction {
    switch (currentAction, movingRight) {
    case (.topLeftQuarter, true):
        .topRightQuarter
    case (.bottomLeftQuarter, true):
        .bottomRightQuarter
    case (.topRightQuarter, false):
        .topLeftQuarter
    case (.bottomRightQuarter, false):
        .bottomLeftQuarter
    default:
        currentAction
    }
}

private func verticalCornerDragTransition(
    from currentAction: WindowAction,
    movingUp: Bool
) -> WindowAction {
    switch (currentAction, movingUp) {
    case (.bottomLeftQuarter, true):
        .topLeftQuarter
    case (.bottomRightQuarter, true):
        .topRightQuarter
    case (.topLeftQuarter, false):
        .bottomLeftQuarter
    case (.topRightQuarter, false):
        .bottomRightQuarter
    default:
        currentAction
    }
}

func titleBarDangerGestureConfirmationMatches(
    pendingConfirmationGesture: DockGestureKind,
    pendingApplication: InteractionTarget,
    confirmationGesture: DockGestureKind,
    application: InteractionTarget
) -> Bool {
    pendingConfirmationGesture == confirmationGesture &&
        pendingApplication == application
}

func dockDangerGestureConfirmationMatches(
    pendingConfirmationGesture: DockGestureKind,
    pendingApplication: InteractionTarget,
    confirmationGesture: DockGestureKind,
    application: InteractionTarget
) -> Bool {
    pendingConfirmationGesture == confirmationGesture &&
        pendingApplication == application
}

@MainActor
private final class TitleBarAccessibilityProbe {
    private let registry: WindowRegistry
    private let cacheTTL: TimeInterval = 0.2
    private let logTTL: TimeInterval = 0.4
    private var cachedHitRegion: CachedHitRegion?
    private var lastProbeLogAt = Date.distantPast
    private var lastProbeLogKey = ""
    private var preheatTask: Task<Void, Never>?

    private struct CachedHitRegion {
        let application: InteractionTarget
        let processIdentifier: pid_t
        let frame: CGRect
        let isFullScreen: Bool
        let expiresAt: Date
    }

    private struct HoveredWindowTarget {
        let application: InteractionTarget
        let processIdentifier: pid_t
        let window: AXUIElement
    }

    init(registry: WindowRegistry) {
        self.registry = registry
    }

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
                    processIdentifier: cachedHitRegion.processIdentifier,
                    required: requireFrontmostOwnership
                )
            {
                logProbeIfNeeded(
                    key: "hit-cache:\(cachedHitRegion.processIdentifier):\(Int(appKitPoint.x)):\(Int(appKitPoint.y))",
                    message: {
                        "Pointer hit cached title-bar region for \(cachedHitRegion.application.logDescription) at \(NSStringFromPoint(appKitPoint)); frame = \(NSStringFromRect(cachedHitRegion.frame))"
                    }
                )
                return TitleBarHoverTarget(
                    application: cachedHitRegion.application,
                    source: .titleBar
                )
            }

            self.cachedHitRegion = nil
        }

        guard AXIsProcessTrusted() else {
            cachedHitRegion = nil
            return nil
        }

        preheatTask?.cancel()
        preheatTask = nil

        if let registryHit = registry.titleBarHoverHit(
            at: appKitPoint,
            titleBarHeight: titleBarHeight,
            allowFullScreen: allowFullScreen
        ) {
            if pointBelongsToFrontmostApplication(
                appKitPoint,
                processIdentifier: registryHit.processIdentifier,
                required: requireFrontmostOwnership
            ) {
                cachedHitRegion = CachedHitRegion(
                    application: registryHit.target.application,
                    processIdentifier: registryHit.processIdentifier,
                    frame: registryHit.frame,
                    isFullScreen: registryHit.isFullScreen,
                    expiresAt: now.addingTimeInterval(cacheTTL)
                )
                logProbeIfNeeded(
                    key: "hit-registry:\(registryHit.processIdentifier):\(Int(registryHit.frame.minX)):\(Int(registryHit.frame.minY)):\(Int(registryHit.frame.width)):\(Int(registryHit.frame.height))",
                    message: {
                        "Pointer hit registry title-bar region for \(registryHit.target.application.logDescription) at \(NSStringFromPoint(appKitPoint)); frame = \(NSStringFromRect(registryHit.frame))"
                    }
                )
                return registryHit.target
            }
        }

        guard let hitRegion = hitRegion(
            at: appKitPoint,
            titleBarHeight: titleBarHeight,
            allowFullScreen: allowFullScreen,
            expiresAt: { now.addingTimeInterval(cacheTTL) }
        ) else {
            cachedHitRegion = nil
            return nil
        }

        cachedHitRegion = hitRegion

        if
            hitRegion.frame.contains(appKitPoint),
            pointBelongsToFrontmostApplication(
                appKitPoint,
                processIdentifier: hitRegion.processIdentifier,
                required: requireFrontmostOwnership
            )
        {
            logProbeIfNeeded(
                key: "hit:\(hitRegion.processIdentifier):\(Int(hitRegion.frame.minX)):\(Int(hitRegion.frame.minY)):\(Int(hitRegion.frame.width)):\(Int(hitRegion.frame.height))",
                message: {
                    "Pointer hit title-bar region for \(hitRegion.application.logDescription) at \(NSStringFromPoint(appKitPoint)); frame = \(NSStringFromRect(hitRegion.frame))"
                }
            )
            return TitleBarHoverTarget(
                application: hitRegion.application.withSource(.titleBar),
                source: .titleBar
            )
        }

        if
            allowBrowserTabFallback,
            !hitRegion.isFullScreen,
            pointBelongsToFrontmostApplication(
                appKitPoint,
                processIdentifier: hitRegion.processIdentifier,
                required: requireFrontmostOwnership
            ),
            BrowserTabProbe.isBrowserTab(
                at: appKitPoint,
                processIdentifier: hitRegion.processIdentifier
            )
        {
            logProbeIfNeeded(
                key: "hit-browser-tab:\(hitRegion.processIdentifier):\(Int(appKitPoint.x)):\(Int(appKitPoint.y))",
                message: {
                    "Pointer hit browser-tab fallback region for \(hitRegion.application.logDescription) at \(NSStringFromPoint(appKitPoint))"
                }
            )
            return TitleBarHoverTarget(
                application: hitRegion.application.withSource(.browserTabFallback),
                source: .browserTabFallback
            )
        }

        logProbeIfNeeded(
            key: "miss:\(hitRegion.processIdentifier):\(Int(hitRegion.frame.minX)):\(Int(hitRegion.frame.minY)):\(Int(hitRegion.frame.width)):\(Int(hitRegion.frame.height))",
            message: {
                "Pointer missed title-bar region for \(hitRegion.application.logDescription) at \(NSStringFromPoint(appKitPoint)); frame = \(NSStringFromRect(hitRegion.frame))"
            }
        )
        return nil
    }

    private func startPreheatIfNeeded(titleBarHeight: CGFloat, allowFullScreen: Bool) {
        guard preheatTask == nil else {
            return
        }

        preheatTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else {
                return
            }

            let mouseLocation = NSEvent.mouseLocation

            guard !Task.isCancelled else {
                return
            }

            guard AXIsProcessTrusted() else {
                self.cachedHitRegion = nil
                self.preheatTask = nil
                return
            }

            guard !Task.isCancelled else {
                return
            }

            guard let hitRegion = self.hitRegion(
                at: mouseLocation,
                titleBarHeight: titleBarHeight,
                allowFullScreen: allowFullScreen,
                expiresAt: { Date().addingTimeInterval(self.cacheTTL) }
            ) else {
                guard !Task.isCancelled else {
                    return
                }

                self.cachedHitRegion = nil
                self.preheatTask = nil
                return
            }

            guard !Task.isCancelled else {
                return
            }

            self.cachedHitRegion = hitRegion
            self.preheatTask = nil
        }
    }

    private func hitRegion(
        at appKitPoint: CGPoint,
        titleBarHeight: CGFloat,
        allowFullScreen: Bool,
        expiresAt: () -> Date
    ) -> CachedHitRegion? {
        guard
            let hoveredTarget = hoveredWindowTarget(at: appKitPoint),
            let appKitWindowFrame = appKitFrame(of: hoveredTarget.window)
        else {
            return nil
        }

        let windowIsFullScreen = isFullScreen(hoveredTarget.window)
        if windowIsFullScreen, !allowFullScreen {
            return nil
        }

        let titleBarFrame = titleBarFrame(for: appKitWindowFrame, titleBarHeight: titleBarHeight)
        guard !titleBarFrame.isEmpty else {
            return nil
        }

        return CachedHitRegion(
            application: hoveredTarget.application,
            processIdentifier: hoveredTarget.processIdentifier,
            frame: titleBarFrame,
            isFullScreen: windowIsFullScreen,
            expiresAt: expiresAt()
        )
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
            !application.isTerminated
        else {
            return nil
        }

        let window = AXAttributeReader.window(containing: hitElement) ?? focusedOrMainWindow(
            in: AXAttributeReader.applicationElement(for: application.processIdentifier)
        )
        guard
            let window,
            let appIdentity = registry.appIdentity(forProcessIdentifier: application.processIdentifier),
            let windowIdentity = registry.windowIdentity(for: window, in: application)
        else {
            return nil
        }

        return HoveredWindowTarget(
            application: .window(
                windowIdentity,
                app: appIdentity,
                source: .titleBar
            ),
            processIdentifier: application.processIdentifier,
            window: window
        )
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

        guard let hitProcessIdentifier = AXAttributeReader.processIdentifier(at: appKitPoint) else {
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

final class MultitouchInputMonitor: MultitouchMonitoring, @unchecked Sendable {
    var onFrame: ((TrackpadTouchFrame) -> Void)?

    private let frameDeliveryCoalescer = FrameDeliveryCoalescer()
    private let scheduleDrain: (@escaping @MainActor () -> Void) -> Void
    private let startMonitoring: (UnsafeMutableRawPointer) -> Bool
    private let stopMonitoring: () -> Void
    private var isMonitoring = false

    init(
        scheduleDrain: @escaping (@escaping @MainActor () -> Void) -> Void = { operation in
            Task { @MainActor in
                operation()
            }
        },
        startMonitoring: @escaping (UnsafeMutableRawPointer) -> Bool = { context in
            SwooshyMTStartMonitoring(multitouchCallback, context)
        },
        stopMonitoring: @escaping () -> Void = {
            SwooshyMTStopMonitoring()
        }
    ) {
        self.scheduleDrain = scheduleDrain
        self.startMonitoring = startMonitoring
        self.stopMonitoring = stopMonitoring
    }

    var isMonitoringActive: Bool {
        isMonitoring
    }

    func startIfAvailable() {
        guard !isMonitoring else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        isMonitoring = startMonitoring(context)
        frameDeliveryCoalescer.reset()
        if !isMonitoring {
            stopMonitoring()
            DebugLog.error(DebugLog.dock, "MultitouchSupport monitoring unavailable")
        } else {
            DebugLog.info(DebugLog.dock, "MultitouchSupport monitoring active")
        }
    }

    func stop() {
        if isMonitoring {
            stopMonitoring()
        }
        isMonitoring = false
        frameDeliveryCoalescer.reset()
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

        enqueueForDelivery(
            TrackpadTouchFrame(
                touches: touches,
                timestamp: timestamp
            )
        )
    }

    private func deliverZeroTouchFrame(timestamp: Double) {
        enqueueForDelivery(
            TrackpadTouchFrame(
                touches: [],
                timestamp: timestamp
            )
        )
    }

    private func enqueueForDelivery(_ frame: TrackpadTouchFrame) {
        guard frameDeliveryCoalescer.enqueue(frame) == .scheduleDrain else {
            return
        }

        scheduleDrain { [weak self] in
            self?.drainPendingFrames()
        }
    }

    @MainActor
    private func drainPendingFrames() {
        while let frame = frameDeliveryCoalescer.nextFrameForDrain() {
            onFrame?(frame)
        }
    }
}

private final class FrameDeliveryCoalescer {
    enum EnqueueResult {
        case ignored
        case queued
        case scheduleDrain
    }

    private let lock = NSLock()
    private var queuedFrames: [TrackpadTouchFrame] = []
    private var drainScheduled = false
    private var lastQueuedFingerCount = -1

    func enqueue(_ frame: TrackpadTouchFrame) -> EnqueueResult {
        lock.lock()
        defer { lock.unlock() }

        if frame.touches.isEmpty, lastQueuedFingerCount == 0 {
            return .ignored
        }

        lastQueuedFingerCount = frame.touches.count
        if
            let lastIndex = queuedFrames.indices.last,
            sameCoalescingBucket(lhs: queuedFrames[lastIndex], rhs: frame)
        {
            queuedFrames[lastIndex] = frame
        } else {
            queuedFrames.append(frame)
        }

        guard !drainScheduled else {
            return .queued
        }

        drainScheduled = true
        return .scheduleDrain
    }

    func nextFrameForDrain() -> TrackpadTouchFrame? {
        lock.lock()
        defer { lock.unlock() }

        if !queuedFrames.isEmpty {
            return queuedFrames.removeFirst()
        }

        drainScheduled = false
        return nil
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        queuedFrames = []
        drainScheduled = false
        lastQueuedFingerCount = -1
    }

    private func sameCoalescingBucket(
        lhs: TrackpadTouchFrame,
        rhs: TrackpadTouchFrame
    ) -> Bool {
        coalescingBucket(for: lhs) == coalescingBucket(for: rhs)
    }

    private func coalescingBucket(for frame: TrackpadTouchFrame) -> Int {
        frame.touches.count
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
