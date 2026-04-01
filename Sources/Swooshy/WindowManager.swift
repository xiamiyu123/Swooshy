import AppKit
import ApplicationServices
import CoreGraphics

enum WindowCycleDirection {
    case forward
    case backward
}

private enum FrameWriteOrder: String {
    case sizeThenPosition
    case positionThenSize

    var alternate: Self {
        switch self {
        case .sizeThenPosition:
            return .positionThenSize
        case .positionThenSize:
            return .sizeThenPosition
        }
    }
}

private enum FrameApplicationOutcome {
    case exact(CGRect)
    case constrained(CGRect)
}

private struct FrameWriteResult {
    let sizeError: AXError
    let positionError: AXError

    var succeeded: Bool {
        sizeError == .success && positionError == .success
    }
}

@MainActor
final class ObservedWindowConstraintStore {
    private static let maxIdleRounds = 1_000

    private struct ApplicationConstraints {
        var sharedMaximumSizeBounds = WindowActionPreview.SizeBounds(
            minimumWidth: nil,
            maximumWidth: nil,
            minimumHeight: nil,
            maximumHeight: nil
        )
        var observationsByAction: [WindowAction: WindowActionPreview.Observation] = [:]
        var lastHitRound: Int = 0
    }

    private var constraintsByApplicationKey: [String: ApplicationConstraints] = [:]
    private var currentRound = 0

    func observation(
        for applicationKey: String,
        action: WindowAction
    ) -> WindowActionPreview.Observation? {
        currentRound += 1
        evictExpiredConstraints()

        guard var applicationConstraints = constraintsByApplicationKey[applicationKey] else {
            return nil
        }

        let sharedMaximumSizeBounds = applicationConstraints.sharedMaximumSizeBounds
        let actionObservation = applicationConstraints.observationsByAction[action]
        let mergedSizeBounds = merged(
            actionObservation?.sizeBounds ?? emptySizeBounds(),
            with: sharedMaximumSizeBounds
        )

        guard
            mergedSizeBounds.hasConstraints ||
            actionObservation?.horizontalAnchor != nil ||
            actionObservation?.verticalAnchor != nil
        else {
            return nil
        }

        applicationConstraints.lastHitRound = currentRound
        constraintsByApplicationKey[applicationKey] = applicationConstraints

        return WindowActionPreview.Observation(
            sizeBounds: mergedSizeBounds,
            horizontalAnchor: actionObservation?.horizontalAnchor,
            verticalAnchor: actionObservation?.verticalAnchor
        )
    }

    func record(
        sizeBounds: WindowActionPreview.SizeBounds,
        horizontalAnchor: WindowActionPreview.AxisAnchor?,
        verticalAnchor: WindowActionPreview.AxisAnchor?,
        action: WindowAction,
        for applicationKey: String
    ) {
        var applicationConstraints = constraintsByApplicationKey[applicationKey] ?? ApplicationConstraints()
        evictExpiredConstraints()

        let sharedMaximumSizeBounds = sharedMaximumBounds(from: sizeBounds)
        if sharedMaximumSizeBounds.hasConstraints {
            applicationConstraints.sharedMaximumSizeBounds = merged(
                applicationConstraints.sharedMaximumSizeBounds,
                with: sharedMaximumSizeBounds
            )
        }

        if var existingObservation = applicationConstraints.observationsByAction[action] {
            existingObservation.sizeBounds = merged(
                existingObservation.sizeBounds,
                with: sizeBounds
            )
            if let horizontalAnchor {
                existingObservation.horizontalAnchor = horizontalAnchor
            }
            if let verticalAnchor {
                existingObservation.verticalAnchor = verticalAnchor
            }
            applicationConstraints.observationsByAction[action] = existingObservation
        } else {
            applicationConstraints.observationsByAction[action] = WindowActionPreview.Observation(
                sizeBounds: sizeBounds,
                horizontalAnchor: horizontalAnchor,
                verticalAnchor: verticalAnchor
            )
        }

        applicationConstraints.lastHitRound = currentRound
        constraintsByApplicationKey[applicationKey] = applicationConstraints
    }

    private func evictExpiredConstraints() {
        constraintsByApplicationKey = constraintsByApplicationKey.filter { _, constraints in
            currentRound - constraints.lastHitRound <= Self.maxIdleRounds
        }
    }

    private func merged(
        _ lhs: WindowActionPreview.SizeBounds,
        with rhs: WindowActionPreview.SizeBounds
    ) -> WindowActionPreview.SizeBounds {
        WindowActionPreview.SizeBounds(
            minimumWidth: mergeMaximum(lhs.minimumWidth, rhs.minimumWidth),
            maximumWidth: mergeMinimum(lhs.maximumWidth, rhs.maximumWidth),
            minimumHeight: mergeMaximum(lhs.minimumHeight, rhs.minimumHeight),
            maximumHeight: mergeMinimum(lhs.maximumHeight, rhs.maximumHeight)
        )
    }

    private func sharedMaximumBounds(
        from sizeBounds: WindowActionPreview.SizeBounds
    ) -> WindowActionPreview.SizeBounds {
        WindowActionPreview.SizeBounds(
            minimumWidth: nil,
            maximumWidth: sizeBounds.maximumWidth,
            minimumHeight: nil,
            maximumHeight: sizeBounds.maximumHeight
        )
    }

    private func emptySizeBounds() -> WindowActionPreview.SizeBounds {
        WindowActionPreview.SizeBounds(
            minimumWidth: nil,
            maximumWidth: nil,
            minimumHeight: nil,
            maximumHeight: nil
        )
    }

    private func mergeMaximum(_ lhs: CGFloat?, _ rhs: CGFloat?) -> CGFloat? {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            return max(lhs, rhs)
        case let (.some(lhs), .none):
            return lhs
        case let (.none, .some(rhs)):
            return rhs
        case (.none, .none):
            return nil
        }
    }

    private func mergeMinimum(_ lhs: CGFloat?, _ rhs: CGFloat?) -> CGFloat? {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            return min(lhs, rhs)
        case let (.some(lhs), .none):
            return lhs
        case let (.none, .some(rhs)):
            return rhs
        case (.none, .none):
            return nil
        }
    }
}

@MainActor
protocol WindowManaging {
    func perform(_ action: WindowAction, layoutEngine: WindowLayoutEngine) throws
}

@MainActor
struct WindowManager: WindowManaging {
    private let windowOrdering = WindowOrdering()
    private let cycleSessions = WindowCycleSessionStore()
    private let observedWindowConstraintStore = ObservedWindowConstraintStore()

    private struct ResolvedWindowActionLayout {
        let focusedWindow: AXUIElement
        let screenGeometry: ScreenGeometry
        let targetFrame: CGRect
        let targetAXFrame: CGRect
    }

    func perform(_ action: WindowAction, layoutEngine: WindowLayoutEngine) throws {
        try perform(
            action,
            layoutEngine: layoutEngine,
            preferredAppKitPoint: nil
        )
    }

    func perform(
        _ action: WindowAction,
        layoutEngine: WindowLayoutEngine,
        preferredAppKitPoint: CGPoint?
    ) throws {
        DebugLog.info(DebugLog.windows, "Performing window action \(String(describing: action))")
        if action == .quitApplication {
            try quitFrontmostApplication()
            return
        }

        guard AXIsProcessTrusted() else {
            DebugLog.error(DebugLog.accessibility, "Accessibility permission missing before action \(String(describing: action))")
            throw WindowManagerError.accessibilityPermissionMissing
        }

        let app = try frontmostApplication()
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        switch action {
        case .minimize:
            let window = try focusedWindowElement(in: appElement)
            try setMinimized(true, for: window)
            return
        case .closeWindow:
            let window = try focusedWindowElement(in: appElement)
            guard try closeWindow(window, owningApp: app) else {
                throw WindowManagerError.unableToPerformAction
            }
            return
        case .closeTab:
            guard BrowserTabProbe.simulateMiddleClickAtMouseLocation() else {
                throw WindowManagerError.unableToPerformAction
            }
            return
        case .cycleSameAppWindowsForward:
            let currentWindow = try focusedWindowElement(in: appElement)
            try focusAdjacentVisibleWindow(
                in: app,
                appElement: appElement,
                currentWindow: currentWindow,
                direction: .forward
            )
            return
        case .cycleSameAppWindowsBackward:
            let currentWindow = try focusedWindowElement(in: appElement)
            try focusAdjacentVisibleWindow(
                in: app,
                appElement: appElement,
                currentWindow: currentWindow,
                direction: .backward
            )
            return
        case .leftHalf,
             .rightHalf,
             .topLeftQuarter,
             .topRightQuarter,
             .bottomLeftQuarter,
             .bottomRightQuarter,
             .maximize,
             .center:
            break
        case .quitApplication:
            return
        case .toggleFullScreen:
            let window = try focusedWindowElement(in: appElement)
            let isFullScreen = isFullScreen(window)
            if !isFullScreen {
                try setFullScreen(true, for: window)
            }
            return
        }

        let resolvedLayout = try resolvedWindowActionLayout(
            for: action,
            application: app,
            appElement: appElement,
            layoutEngine: layoutEngine,
            preferredAppKitPoint: preferredAppKitPoint
        )

        let frameOutcome = try setFrame(resolvedLayout.targetAXFrame, for: resolvedLayout.focusedWindow)
        let appliedAXFrame: CGRect
        switch frameOutcome {
        case .exact(let frame), .constrained(let frame):
            appliedAXFrame = frame
        }

        let appliedAppKitFrame = resolvedLayout.screenGeometry.appKitFrame(fromAXFrame: appliedAXFrame)
        recordObservedConstraintIfNeeded(
            requestedFrame: resolvedLayout.targetFrame,
            appliedFrame: appliedAppKitFrame,
            action: action,
            application: app
        )
        DebugLog.debug(
            DebugLog.windows,
            "Read back window frame after \(String(describing: action)): AX \(NSStringFromRect(appliedAXFrame)), AppKit \(NSStringFromRect(appliedAppKitFrame))"
        )
    }

    func perform(
        _ action: WindowAction,
        on target: DockApplicationTarget,
        layoutEngine: WindowLayoutEngine,
        preferredAppKitPoint: CGPoint?
    ) throws {
        DebugLog.info(DebugLog.windows, "Performing window action \(String(describing: action)) for Dock target \(target.logDescription)")

        guard AXIsProcessTrusted() else {
            DebugLog.error(DebugLog.accessibility, "Accessibility permission missing before Dock-target action \(String(describing: action))")
            throw WindowManagerError.accessibilityPermissionMissing
        }

        let app = try runningApplication(matching: target)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        switch action {
        case .quitApplication:
            _ = try quitApplication(matching: target)
            return
        case .minimize:
            _ = try minimizeVisibleWindow(of: target)
            return
        case .closeWindow:
            _ = try closeVisibleWindow(of: target)
            return
        case .toggleFullScreen:
            _ = try toggleFullScreenWindow(of: target)
            return
        case .closeTab:
            guard BrowserTabProbe.simulateMiddleClick(at: preferredAppKitPoint ?? NSEvent.mouseLocation) else {
                throw WindowManagerError.unableToPerformAction
            }
            return
        case .cycleSameAppWindowsForward:
            _ = try cycleVisibleWindows(of: target, direction: .forward)
            return
        case .cycleSameAppWindowsBackward:
            _ = try cycleVisibleWindows(of: target, direction: .backward)
            return
        case .leftHalf,
             .rightHalf,
             .topLeftQuarter,
             .topRightQuarter,
             .bottomLeftQuarter,
             .bottomRightQuarter,
             .maximize,
             .center:
            break
        }

        let targetWindow = try preferredWindowActionTarget(in: app, appElement: appElement)
        try bringWindowToFront(targetWindow, for: app)

        let resolvedLayout = try resolvedWindowActionLayout(
            for: action,
            application: app,
            window: targetWindow,
            layoutEngine: layoutEngine,
            preferredAppKitPoint: preferredAppKitPoint
        )

        let frameOutcome = try setFrame(resolvedLayout.targetAXFrame, for: resolvedLayout.focusedWindow)
        let appliedAXFrame: CGRect
        switch frameOutcome {
        case .exact(let frame), .constrained(let frame):
            appliedAXFrame = frame
        }

        let appliedAppKitFrame = resolvedLayout.screenGeometry.appKitFrame(fromAXFrame: appliedAXFrame)
        recordObservedConstraintIfNeeded(
            requestedFrame: resolvedLayout.targetFrame,
            appliedFrame: appliedAppKitFrame,
            action: action,
            application: app
        )
        DebugLog.debug(
            DebugLog.windows,
            "Read back Dock-target window frame after \(String(describing: action)): AX \(NSStringFromRect(appliedAXFrame)), AppKit \(NSStringFromRect(appliedAppKitFrame))"
        )
    }

    func previewTarget(
        for action: WindowAction,
        layoutEngine: WindowLayoutEngine,
        preferredAppKitPoint: CGPoint?
    ) throws -> WindowActionPreview? {
        guard action.supportsSnapPreview else {
            throw WindowManagerError.unableToPerformAction
        }

        let app = try frontmostApplication()
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let resolvedLayout = try resolvedWindowActionLayout(
            for: action,
            application: app,
            appElement: appElement,
            layoutEngine: layoutEngine,
            preferredAppKitPoint: preferredAppKitPoint
        )
        let observedObservation = observedConstraintObservation(for: app, action: action)
        return layoutEngine.preview(
            for: action,
            targetFrame: resolvedLayout.targetFrame,
            observation: observedObservation
        )
    }

    func previewTarget(
        for action: WindowAction,
        on target: DockApplicationTarget,
        layoutEngine: WindowLayoutEngine,
        preferredAppKitPoint: CGPoint?
    ) throws -> WindowActionPreview? {
        guard action.supportsSnapPreview else {
            throw WindowManagerError.unableToPerformAction
        }

        let app = try runningApplication(matching: target)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let targetWindow = try preferredWindowActionTarget(in: app, appElement: appElement)
        let resolvedLayout = try resolvedWindowActionLayout(
            for: action,
            application: app,
            window: targetWindow,
            layoutEngine: layoutEngine,
            preferredAppKitPoint: preferredAppKitPoint
        )
        let observedObservation = observedConstraintObservation(for: app, action: action)
        return layoutEngine.preview(
            for: action,
            targetFrame: resolvedLayout.targetFrame,
            observation: observedObservation
        )
    }

    private func frontmostApplication() throws -> NSRunningApplication {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw WindowManagerError.noFrontmostApplication
        }

        return app
    }

    private func resolvedWindowActionLayout(
        for action: WindowAction,
        application: NSRunningApplication,
        appElement: AXUIElement,
        layoutEngine: WindowLayoutEngine,
        preferredAppKitPoint: CGPoint?
    ) throws -> ResolvedWindowActionLayout {
        let focusedWindow = try focusedWindowElement(in: appElement)
        return try resolvedWindowActionLayout(
            for: action,
            application: application,
            window: focusedWindow,
            layoutEngine: layoutEngine,
            preferredAppKitPoint: preferredAppKitPoint
        )
    }

    private func resolvedWindowActionLayout(
        for action: WindowAction,
        application: NSRunningApplication,
        window: AXUIElement,
        layoutEngine: WindowLayoutEngine,
        preferredAppKitPoint: CGPoint?
    ) throws -> ResolvedWindowActionLayout {
        let screens = NSScreen.screens
        guard screens.isEmpty == false else {
            throw WindowManagerError.unableToResolveScreen
        }
        logScreenConfiguration(screens, preferredAppKitPoint: preferredAppKitPoint)

        let screenGeometry = ScreenGeometry(screenFrames: screens.map(\.frame))
        let currentAXFrame = try frame(of: window)
        let currentFrame = screenGeometry.appKitFrame(fromAXFrame: currentAXFrame)
        logFrameRead(
            for: window,
            action: action,
            application: application,
            axFrame: currentAXFrame,
            appKitFrame: currentFrame
        )

        let screenFrames = screens.map(\.visibleFrame)
        guard let currentScreenFrame = layoutEngine.resolvedVisibleFrame(
            preferredPoint: preferredAppKitPoint,
            currentWindowFrame: currentFrame,
            screenFrames: screenFrames
        ) else {
            throw WindowManagerError.unableToResolveScreen
        }

        DebugLog.debug(
            DebugLog.windows,
            "Resolved current visible frame for action \(String(describing: action)): \(NSStringFromRect(currentScreenFrame))"
        )

        if
            let preferredAppKitPoint,
            let preferredScreenFrame = screenFrames.first(where: { $0.contains(preferredAppKitPoint) })
        {
            DebugLog.debug(
                DebugLog.windows,
                "Resolved target screen from preferred point \(NSStringFromPoint(preferredAppKitPoint)): \(NSStringFromRect(preferredScreenFrame))"
            )
        }

        let targetFrame = layoutEngine.targetFrame(
            for: action,
            currentWindowFrame: currentFrame,
            currentVisibleFrame: currentScreenFrame
        )

        DebugLog.debug(
            DebugLog.windows,
            "Calculated target frame \(NSStringFromRect(targetFrame)) from current frame \(NSStringFromRect(currentFrame))"
        )

        let targetAXFrame = screenGeometry.axFrame(fromAppKitFrame: targetFrame)
        DebugLog.debug(
            DebugLog.windows,
            "Writing target AX frame \(NSStringFromRect(targetAXFrame)) converted from AppKit target \(NSStringFromRect(targetFrame))"
        )

        return ResolvedWindowActionLayout(
            focusedWindow: window,
            screenGeometry: screenGeometry,
            targetFrame: targetFrame,
            targetAXFrame: targetAXFrame
        )
    }

    private func preferredWindowActionTarget(
        in app: NSRunningApplication,
        appElement: AXUIElement
    ) throws -> AXUIElement {
        let visibleWindows = try orderedVisibleWindowElements(in: app, appElement: appElement)
        if let window = visibleWindows.first {
            return window
        }

        if let referenceWindow = preferredCycleReferenceWindow(in: appElement) {
            return referenceWindow
        }

        throw WindowManagerError.noFocusedWindow
    }

    private func observedConstraintObservation(
        for application: NSRunningApplication,
        action: WindowAction
    ) -> WindowActionPreview.Observation? {
        observedWindowConstraintStore.observation(
            for: observationKey(for: application),
            action: action
        )
    }

    private func recordObservedConstraintBounds(
        _ sizeBounds: WindowActionPreview.SizeBounds,
        horizontalAnchor: WindowActionPreview.AxisAnchor?,
        verticalAnchor: WindowActionPreview.AxisAnchor?,
        action: WindowAction,
        for application: NSRunningApplication
    ) {
        observedWindowConstraintStore.record(
            sizeBounds: sizeBounds,
            horizontalAnchor: horizontalAnchor,
            verticalAnchor: verticalAnchor,
            action: action,
            for: observationKey(for: application)
        )
    }

    private func observationKey(for application: NSRunningApplication) -> String {
        if let bundleIdentifier = application.bundleIdentifier, bundleIdentifier.isEmpty == false {
            return bundleIdentifier
        }

        if let localizedName = application.localizedName, localizedName.isEmpty == false {
            return "name:\(localizedName)"
        }

        return "pid:\(application.processIdentifier)"
    }

    private func recordObservedConstraintIfNeeded(
        requestedFrame: CGRect,
        appliedFrame: CGRect,
        action: WindowAction,
        application: NSRunningApplication
    ) {
        guard action.supportsSnapPreview else {
            return
        }

        let previewObservation = observedPreviewObservation(
            requestedFrame: requestedFrame,
            appliedFrame: appliedFrame
        )
        guard previewObservation.sizeBounds.hasConstraints else {
            return
        }

        recordObservedConstraintBounds(
            previewObservation.sizeBounds,
            horizontalAnchor: previewObservation.horizontalAnchor,
            verticalAnchor: previewObservation.verticalAnchor,
            action: action,
            for: application
        )
        DebugLog.debug(
            DebugLog.windows,
            "Recorded observed window constraint bounds \(constraintBoundsDescription(previewObservation.sizeBounds)) for \(application.bundleIdentifier ?? application.localizedName ?? "unknown") after requested \(NSStringFromRect(requestedFrame)) applied as \(NSStringFromRect(appliedFrame)); horizontalAnchor = \(String(describing: previewObservation.horizontalAnchor)), verticalAnchor = \(String(describing: previewObservation.verticalAnchor))"
        )
    }

    private func observedPreviewObservation(
        requestedFrame: CGRect,
        appliedFrame: CGRect,
        tolerance: CGFloat = 1
    ) -> WindowActionPreview.Observation {
        WindowActionPreview.Observation(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: appliedFrame.width > requestedFrame.width + tolerance ? appliedFrame.width : nil,
                maximumWidth: appliedFrame.width < requestedFrame.width - tolerance ? appliedFrame.width : nil,
                minimumHeight: appliedFrame.height > requestedFrame.height + tolerance ? appliedFrame.height : nil,
                maximumHeight: appliedFrame.height < requestedFrame.height - tolerance ? appliedFrame.height : nil
            ),
            horizontalAnchor: observedAnchor(
                requestedMin: requestedFrame.minX,
                requestedMax: requestedFrame.maxX,
                appliedMin: appliedFrame.minX,
                appliedMax: appliedFrame.maxX,
                tolerance: tolerance
            ),
            verticalAnchor: observedAnchor(
                requestedMin: requestedFrame.minY,
                requestedMax: requestedFrame.maxY,
                appliedMin: appliedFrame.minY,
                appliedMax: appliedFrame.maxY,
                tolerance: tolerance
            )
        )
    }

    private func observedAnchor(
        requestedMin: CGFloat,
        requestedMax: CGFloat,
        appliedMin: CGFloat,
        appliedMax: CGFloat,
        tolerance: CGFloat
    ) -> WindowActionPreview.AxisAnchor? {
        let matchesLeadingEdge = abs(appliedMin - requestedMin) <= tolerance
        let matchesTrailingEdge = abs(appliedMax - requestedMax) <= tolerance
        let requestedMidpoint = (requestedMin + requestedMax) / 2
        let appliedMidpoint = (appliedMin + appliedMax) / 2
        let matchesCenter = abs(appliedMidpoint - requestedMidpoint) <= tolerance

        if matchesLeadingEdge && matchesTrailingEdge == false {
            return .leadingEdge
        }
        if matchesTrailingEdge && matchesLeadingEdge == false {
            return .trailingEdge
        }
        if matchesCenter {
            return .centered
        }
        return nil
    }

    private func constraintBoundsDescription(_ sizeBounds: WindowActionPreview.SizeBounds) -> String {
        "[minWidth=\(constraintBoundValue(sizeBounds.minimumWidth)), maxWidth=\(constraintBoundValue(sizeBounds.maximumWidth)), minHeight=\(constraintBoundValue(sizeBounds.minimumHeight)), maxHeight=\(constraintBoundValue(sizeBounds.maximumHeight))]"
    }

    private func constraintBoundValue(_ value: CGFloat?) -> String {
        guard let value else {
            return "nil"
        }

        return String(format: "%.1f", value)
    }

    func minimizeVisibleWindow(of application: DockApplicationTarget) throws -> Bool {
        guard AXIsProcessTrusted() else {
            throw WindowManagerError.accessibilityPermissionMissing
        }

        DebugLog.info(DebugLog.windows, "Attempting to minimize a visible window for \(application.logDescription)")

        let app = try runningApplication(matching: application)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows = try orderedVisibleWindowElements(in: app, appElement: appElement)
        DebugLog.debug(
            DebugLog.windows,
            "Visible window candidates for \(application.logDescription): [\(windowSummary(windows))]"
        )

        guard let targetWindow = windows.first else {
            DebugLog.debug(DebugLog.windows, "No visible window found to minimize for \(application.logDescription)")
            return false
        }

        try setMinimized(true, for: targetWindow)
        cycleSessions.invalidate(for: app.processIdentifier)
        DebugLog.info(DebugLog.windows, "Minimized one visible window for \(application.logDescription)")
        return true
    }

    func restoreMinimizedWindow(of application: DockApplicationTarget) throws -> Bool {
        guard AXIsProcessTrusted() else {
            throw WindowManagerError.accessibilityPermissionMissing
        }

        DebugLog.info(DebugLog.windows, "Attempting to restore a minimized window for \(application.logDescription)")

        let app = try runningApplication(matching: application)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows = try windowElements(in: appElement).filter { isMinimized($0) }
        DebugLog.debug(
            DebugLog.windows,
            "Minimized window candidates for \(application.logDescription): [\(windowSummary(windows))]"
        )

        guard let targetWindow = windows.first else {
            requestForegroundActivation(for: app)
            DebugLog.debug(DebugLog.windows, "No minimized window found for \(application.logDescription); activated app instead")
            return false
        }

        try setMinimized(false, for: targetWindow)
        try bringWindowToFront(targetWindow, for: app)
        cycleSessions.invalidate(for: app.processIdentifier)
        DebugLog.info(DebugLog.windows, "Restored and raised one minimized window for \(application.logDescription)")
        return true
    }

    func toggleFullScreenWindow(of application: DockApplicationTarget) throws -> Bool {
        guard AXIsProcessTrusted() else {
            throw WindowManagerError.accessibilityPermissionMissing
        }

        DebugLog.info(DebugLog.windows, "Attempting to toggle full screen for a visible window of \(application.logDescription)")

        let app = try runningApplication(matching: application)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows = try orderedVisibleWindowElements(in: app, appElement: appElement)
        
        guard let targetWindow = windows.first else {
            DebugLog.debug(DebugLog.windows, "No visible window found to toggle full screen for \(application.logDescription)")
            return false
        }

        try bringWindowToFront(targetWindow, for: app)
        let currentState = isFullScreen(targetWindow)
        if !currentState {
            try setFullScreen(true, for: targetWindow)
        }
        
        cycleSessions.invalidate(for: app.processIdentifier)
        DebugLog.info(DebugLog.windows, "Entered full screen for one visible window of \(application.logDescription)")
        return true
    }

    func closeVisibleWindow(of application: DockApplicationTarget) throws -> Bool {
        guard AXIsProcessTrusted() else {
            throw WindowManagerError.accessibilityPermissionMissing
        }

        DebugLog.info(DebugLog.windows, "Attempting to close a visible window for \(application.logDescription)")

        let app = try runningApplication(matching: application)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows = try orderedVisibleWindowElements(in: app, appElement: appElement)
        DebugLog.debug(
            DebugLog.windows,
            "Close-window candidates for \(application.logDescription): [\(windowSummary(windows))]"
        )

        guard let targetWindow = windows.first else {
            DebugLog.debug(DebugLog.windows, "No visible window found to close for \(application.logDescription)")
            return false
        }

        if try closeWindow(targetWindow, owningApp: app) {
            cycleSessions.invalidate(for: app.processIdentifier)
            DebugLog.info(DebugLog.windows, "Closed one visible window for \(application.logDescription)")
            return true
        }

        for fallbackWindow in windows.dropFirst() {
            if try closeWindow(fallbackWindow, owningApp: app) {
                cycleSessions.invalidate(for: app.processIdentifier)
                DebugLog.info(DebugLog.windows, "Closed one fallback visible window for \(application.logDescription)")
                return true
            }
        }

        DebugLog.debug(DebugLog.windows, "No closeable visible window found for \(application.logDescription)")
        return false
    }

    func quitApplication(matching target: DockApplicationTarget) throws -> Bool {
        guard AXIsProcessTrusted() else {
            throw WindowManagerError.accessibilityPermissionMissing
        }

        let app = try runningApplication(matching: target)
        guard app.terminate() else {
            throw WindowManagerError.unableToQuitApplication
        }

        cycleSessions.invalidate(for: app.processIdentifier)
        DebugLog.info(DebugLog.windows, "Terminated app for Dock target \(target.logDescription)")
        return true
    }

    func cycleVisibleWindows(
        of application: DockApplicationTarget,
        direction: WindowCycleDirection
    ) throws -> Bool {
        guard AXIsProcessTrusted() else {
            throw WindowManagerError.accessibilityPermissionMissing
        }

        DebugLog.info(
            DebugLog.windows,
            "Attempting to cycle visible windows \(direction == .forward ? "forward" : "backward") for \(application.logDescription)"
        )

        let app = try runningApplication(matching: application)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        try focusAdjacentVisibleWindow(
            in: app,
            appElement: appElement,
            currentWindow: preferredCycleReferenceWindow(in: appElement),
            direction: direction
        )
        return true
    }

    func runningApplication(matching target: DockApplicationTarget) throws -> NSRunningApplication {
        var windowPresenceCache: [pid_t: Bool] = [:]
        var fallbackCandidates: [NSRunningApplication] = []

        if
            let app = NSRunningApplication(processIdentifier: target.processIdentifier),
            app.isTerminated == false
        {
            if isPreferredWindowTargetApplication(app, windowPresenceCache: &windowPresenceCache) {
                return app
            }

            fallbackCandidates.append(app)
            DebugLog.debug(
                DebugLog.windows,
                "Discarding pid-matched app \(app.localizedName ?? "unknown") [\(app.bundleIdentifier ?? "unknown")] as primary target because it appears to be a helper without windows"
            )
        }

        if let bundleIdentifier = target.bundleIdentifier {
            for candidateBundleIdentifier in canonicalBundleIdentifiers(from: bundleIdentifier) {
                if
                    let app = NSWorkspace.shared.runningApplications.first(where: {
                        $0.bundleIdentifier == candidateBundleIdentifier && $0.isTerminated == false
                    })
                {
                    if isPreferredWindowTargetApplication(app, windowPresenceCache: &windowPresenceCache) {
                        return app
                    }

                    fallbackCandidates.append(app)
                }
            }
        }

        let targetAliases = RunningApplicationIdentity.normalizedAliases(
            from: target.aliases + [target.dockItemName, target.resolvedApplicationName]
        )
        let aliasCandidates = NSWorkspace.shared.runningApplications.filter { application in
            guard application.isTerminated == false else {
                return false
            }

            let aliases = RunningApplicationIdentity.normalizedAliases(
                from: RunningApplicationIdentity.aliases(for: application)
            )
            return aliases.isDisjoint(with: targetAliases) == false
        }

        if let app = bestWindowTargetApplication(
            from: aliasCandidates,
            windowPresenceCache: &windowPresenceCache
        ) {
            return app
        }

        if let fallback = bestWindowTargetApplication(
            from: fallbackCandidates,
            windowPresenceCache: &windowPresenceCache,
            allowHelperWithoutWindows: true
        ) {
            return fallback
        }

        DebugLog.error(
            DebugLog.windows,
            "Unable to find running application for target \(target.logDescription); pid=\(target.processIdentifier); aliases=\(target.aliases.joined(separator: "|"))"
        )
        throw WindowManagerError.noFrontmostApplication
    }

    private func canonicalBundleIdentifiers(from bundleIdentifier: String) -> [String] {
        var candidates: [String] = []

        func appendCandidate(_ candidate: String) {
            guard candidate.isEmpty == false else { return }
            guard candidates.contains(candidate) == false else { return }
            candidates.append(candidate)
        }

        appendCandidate(bundleIdentifier)

        if let frameworkRange = bundleIdentifier.range(of: ".framework.") {
            appendCandidate(String(bundleIdentifier[..<frameworkRange.lowerBound]))
        }

        if let helperRange = bundleIdentifier.range(of: ".helper", options: [.caseInsensitive]) {
            appendCandidate(String(bundleIdentifier[..<helperRange.lowerBound]))
        }

        return candidates
    }

    private func bestWindowTargetApplication(
        from candidates: [NSRunningApplication],
        windowPresenceCache: inout [pid_t: Bool],
        allowHelperWithoutWindows: Bool = false
    ) -> NSRunningApplication? {
        let uniqueCandidates = Dictionary(
            candidates.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { current, _ in current }
        ).values

        return uniqueCandidates.max { lhs, rhs in
            let lhsScore = windowTargetQualityScore(
                for: lhs,
                windowPresenceCache: &windowPresenceCache,
                allowHelperWithoutWindows: allowHelperWithoutWindows
            )
            let rhsScore = windowTargetQualityScore(
                for: rhs,
                windowPresenceCache: &windowPresenceCache,
                allowHelperWithoutWindows: allowHelperWithoutWindows
            )

            if lhsScore == rhsScore {
                return lhs.processIdentifier > rhs.processIdentifier
            }

            return lhsScore < rhsScore
        }
    }

    private func windowTargetQualityScore(
        for application: NSRunningApplication,
        windowPresenceCache: inout [pid_t: Bool],
        allowHelperWithoutWindows: Bool
    ) -> Int {
        var score = 0
        let hasWindow = hasAnyWindow(for: application, windowPresenceCache: &windowPresenceCache)

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

        if hasWindow {
            score += 120
        }

        if application.isHidden == false {
            score += 20
        }

        if RunningApplicationIdentity.isLikelyHelperProcess(application) {
            score -= allowHelperWithoutWindows ? 80 : 220
            if hasWindow == false {
                score -= allowHelperWithoutWindows ? 30 : 300
            }
        }

        return score
    }

    private func isPreferredWindowTargetApplication(
        _ application: NSRunningApplication,
        windowPresenceCache: inout [pid_t: Bool]
    ) -> Bool {
        if RunningApplicationIdentity.isLikelyHelperProcess(application) {
            return hasAnyWindow(for: application, windowPresenceCache: &windowPresenceCache)
        }

        return true
    }

    private func hasAnyWindow(
        for application: NSRunningApplication,
        windowPresenceCache: inout [pid_t: Bool]
    ) -> Bool {
        if let cachedValue = windowPresenceCache[application.processIdentifier] {
            return cachedValue
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)

        let hasWindow = (error == .success) && ((value as? [AnyObject])?.isEmpty == false)
        windowPresenceCache[application.processIdentifier] = hasWindow
        return hasWindow
    }

    func focusedWindowElement(in appElement: AXUIElement) throws -> AXUIElement {
        var focusedWindowValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )

        guard error == .success, let focusedWindow = focusedWindowValue else {
            DebugLog.error(DebugLog.accessibility, "Failed to read focused window; AX error = \(error.rawValue)")
            throw WindowManagerError.noFocusedWindow
        }

        guard CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() else {
            DebugLog.error(DebugLog.accessibility, "Focused window is not AXUIElement")
            throw WindowManagerError.noFocusedWindow
        }
        let focusedWindowElement = unsafeDowncast(focusedWindow, to: AXUIElement.self)

        DebugLog.debug(DebugLog.windows, "Resolved focused window: \(windowSummary([focusedWindowElement]))")
        return focusedWindowElement
    }

    private func mainWindowElement(in appElement: AXUIElement) throws -> AXUIElement {
        var mainWindowValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            appElement,
            kAXMainWindowAttribute as CFString,
            &mainWindowValue
        )

        guard error == .success, let mainWindow = mainWindowValue else {
            DebugLog.error(DebugLog.accessibility, "Failed to read main window; AX error = \(error.rawValue)")
            throw WindowManagerError.noFocusedWindow
        }

        guard CFGetTypeID(mainWindow) == AXUIElementGetTypeID() else {
            DebugLog.error(DebugLog.accessibility, "Main window is not AXUIElement")
            throw WindowManagerError.noFocusedWindow
        }
        let mainWindowElement = unsafeDowncast(mainWindow, to: AXUIElement.self)

        DebugLog.debug(DebugLog.windows, "Resolved main window: \(windowSummary([mainWindowElement]))")
        return mainWindowElement
    }

    private func frame(of window: AXUIElement) throws -> CGRect {
        let position = try pointAttribute(kAXPositionAttribute as CFString, from: window)
        let size = try sizeAttribute(kAXSizeAttribute as CFString, from: window)
        return CGRect(origin: position, size: size).integral
    }

    private func setMinimized(_ minimized: Bool, for window: AXUIElement) throws {
        var settable = DarwinBoolean(false)
        let settableError = AXUIElementIsAttributeSettable(
            window,
            kAXMinimizedAttribute as CFString,
            &settable
        )

        if settableError == .success, settable.boolValue {
            let value: CFTypeRef = minimized ? kCFBooleanTrue : kCFBooleanFalse
            let setError = AXUIElementSetAttributeValue(
                window,
                kAXMinimizedAttribute as CFString,
                value
            )
            guard setError == .success else {
                DebugLog.error(DebugLog.accessibility, "Setting AXMinimized=\(minimized) failed with error \(setError.rawValue) for window \(windowSummary([window]))")
                throw WindowManagerError.unableToPerformAction
            }
            DebugLog.debug(DebugLog.windows, "Set AXMinimized=\(minimized) for window \(windowSummary([window]))")
            return
        }

        if minimized {
            do {
                let minimizeButton = try childElement(
                    attribute: kAXMinimizeButtonAttribute as CFString,
                    from: window
                )
                try performAction(kAXPressAction as CFString, on: minimizeButton)
                return
            } catch {
                DebugLog.debug(
                    DebugLog.accessibility,
                    "Fallback minimize via AXMinimizeButton failed: \(error.localizedDescription)"
                )
            }
        }

        throw WindowManagerError.unableToPerformAction
    }

    private func closeWindow(
        _ window: AXUIElement,
        owningApp: NSRunningApplication
    ) throws -> Bool {
        prepareWindowForClosing(window, owningApp: owningApp)

        if tryCloseViaCloseButton(window, context: "AXCloseButton") {
            DebugLog.debug(DebugLog.windows, "Closed window via AXCloseButton: \(windowSummary([window]))")
            return true
        }

        if tryPerformAction("AXClose" as CFString, on: window, context: "AXClose") {
            DebugLog.debug(DebugLog.windows, "Closed window via AXClose action: \(windowSummary([window]))")
            return true
        }

        // Some apps expose only Press on the close control but not AXClose on the window node.
        if tryCloseViaCloseButton(window, context: "AXCloseButtonRetry") {
            DebugLog.debug(DebugLog.windows, "Closed window via AXCloseButton retry: \(windowSummary([window]))")
            return true
        }

        DebugLog.debug(DebugLog.windows, "Unable to close window via AXCloseButton/AXClose: \(windowSummary([window]))")
        return false
    }

    private func prepareWindowForClosing(
        _ window: AXUIElement,
        owningApp: NSRunningApplication
    ) {
        _ = owningApp.activate(options: [.activateAllWindows])
        performBestEffort(
            context: "raising window before close",
            fallbackMessage: "AXRaise"
        ) {
            try performAction(kAXRaiseAction as CFString, on: window)
        }
        performBestEffort(
            context: "setting AXMain before close",
            fallbackMessage: "AXMain=true"
        ) {
            try setBooleanAttribute(kAXMainAttribute as CFString, value: true, on: window)
        }
        performBestEffort(
            context: "setting AXFocused before close",
            fallbackMessage: "AXFocused=true"
        ) {
            try setBooleanAttribute(kAXFocusedAttribute as CFString, value: true, on: window)
        }
    }

    func isFullScreen(_ window: AXUIElement) -> Bool {
        AXAttributeReader.bool("AXFullScreen" as CFString, from: window) ?? false
    }

    func setFullScreen(_ fullScreen: Bool, for window: AXUIElement) throws {
        let value: CFTypeRef = fullScreen ? kCFBooleanTrue : kCFBooleanFalse
        let setError = AXUIElementSetAttributeValue(
            window,
            "AXFullScreen" as CFString,
            value
        )
        guard setError == .success else {
            throw WindowManagerError.unableToPerformAction
        }
    }

    private func tryCloseViaCloseButton(_ window: AXUIElement, context: String) -> Bool {
        let closeButton: AXUIElement
        do {
            closeButton = try childElement(attribute: kAXCloseButtonAttribute as CFString, from: window)
        } catch {
            DebugLog.debug(
                DebugLog.accessibility,
                "Failed to resolve AXCloseButton while \(context): \(error.localizedDescription)"
            )
            return false
        }

        return tryPerformAction(kAXPressAction as CFString, on: closeButton, context: context)
    }

    private func tryPerformAction(
        _ action: CFString,
        on element: AXUIElement,
        context: String
    ) -> Bool {
        let error = AXUIElementPerformAction(element, action)
        guard error == .success else {
            DebugLog.debug(
                DebugLog.accessibility,
                "AX action \(action as String) failed with error \(error.rawValue) while \(context)"
            )
            return false
        }

        return true
    }

    private func focusAdjacentVisibleWindow(
        in app: NSRunningApplication,
        appElement: AXUIElement,
        currentWindow: AXUIElement?,
        direction: WindowCycleDirection
    ) throws {
        let windows = try orderedVisibleWindowElements(in: app, appElement: appElement)
        let descriptors = try windows.map { try windowDescriptor(for: $0) }

        guard windows.count > 1 else {
            cycleSessions.invalidate(for: app.processIdentifier)
            throw WindowManagerError.noAlternateWindow
        }

        let currentDescriptor = currentWindow.flatMap { window in
            do {
                return try windowDescriptor(for: window)
            } catch {
                DebugLog.debug(
                    DebugLog.windows,
                    "Unable to derive current window descriptor for cycling: \(error.localizedDescription)"
                )
                return nil
            }
        }
        guard let targetDescriptor = cycleSessions.nextTarget(
            for: app.processIdentifier,
            liveOrder: descriptors,
            currentWindow: currentDescriptor,
            direction: direction
        ), let targetIndex = descriptors.firstIndex(of: targetDescriptor) else {
            throw WindowManagerError.noAlternateWindow
        }

        let targetWindow = windows[targetIndex]

        try bringWindowToFront(targetWindow, for: app)
    }

    private func preferredCycleReferenceWindow(in appElement: AXUIElement) -> AXUIElement? {
        do {
            let focusedWindow = try focusedWindowElement(in: appElement)
            return focusedWindow
        } catch {
            DebugLog.debug(
                DebugLog.windows,
                "Unable to resolve focused window for cycle reference: \(error.localizedDescription)"
            )
        }

        do {
            let mainWindow = try mainWindowElement(in: appElement)
            return mainWindow
        } catch {
            DebugLog.debug(
                DebugLog.windows,
                "Unable to resolve main window for cycle reference: \(error.localizedDescription)"
            )
        }

        return nil
    }

    private func quitFrontmostApplication() throws {
        let app = try frontmostApplication()
        guard app.terminate() else {
            throw WindowManagerError.unableToQuitApplication
        }

        cycleSessions.invalidate(for: app.processIdentifier)
    }

    private func performAction(_ action: CFString, on element: AXUIElement) throws {
        let error = AXUIElementPerformAction(element, action)
        guard error == .success else {
            DebugLog.error(DebugLog.accessibility, "AX action \(action as String) failed with error \(error.rawValue)")
            throw WindowManagerError.unableToPerformAction
        }
    }

    private func bringWindowToFront(_ window: AXUIElement, for app: NSRunningApplication) throws {
        DebugLog.debug(DebugLog.windows, "Bringing window to front for app \(app.localizedName ?? "unknown"): \(windowSummary([window]))")
        requestForegroundActivation(for: app)

        // Restored windows can take a moment to become orderable, so raise twice
        // around the focus attributes to make the behavior more reliable.
        performBestEffort(
            context: "initial AXRaise during bring-to-front",
            fallbackMessage: "AXRaise"
        ) {
            try performAction(kAXRaiseAction as CFString, on: window)
        }
        try setBooleanAttribute(kAXMainAttribute as CFString, value: true, on: window)
        try setBooleanAttribute(kAXFocusedAttribute as CFString, value: true, on: window)
        try performAction(kAXRaiseAction as CFString, on: window)
        requestForegroundActivation(for: app)
        DebugLog.debug(DebugLog.windows, "Finished bring-to-front sequence for window \(windowSummary([window]))")
    }

    private func performBestEffort(
        context: String,
        fallbackMessage: String,
        operation: () throws -> Void
    ) {
        do {
            try operation()
        } catch {
            let message = error.localizedDescription.isEmpty ? fallbackMessage : error.localizedDescription
            DebugLog.debug(
                DebugLog.accessibility,
                "Best-effort AX step failed while \(context): \(message)"
            )
        }
    }

    private func requestForegroundActivation(for app: NSRunningApplication) {
        _ = app.activate(options: [.activateAllWindows])

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let error = AXUIElementSetAttributeValue(
            appElement,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )

        if error != .success {
            DebugLog.debug(
                DebugLog.accessibility,
                "Failed to request AXFrontmost for app \(app.localizedName ?? "unknown") with error \(error.rawValue)"
            )
        }
    }

    private func setBooleanAttribute(_ attribute: CFString, value: Bool, on element: AXUIElement) throws {
        let cfValue: CFTypeRef = value ? kCFBooleanTrue : kCFBooleanFalse
        let error = AXUIElementSetAttributeValue(element, attribute, cfValue)
        guard error == .success else {
            DebugLog.error(DebugLog.accessibility, "Failed to set AX bool attribute \(attribute as String) to \(value); error \(error.rawValue)")
            throw WindowManagerError.unableToPerformAction
        }
    }

    private func childElement(attribute: CFString, from element: AXUIElement) throws -> AXUIElement {
        guard let child = AXAttributeReader.element(attribute, from: element) else {
            throw WindowManagerError.unableToPerformAction
        }
        return child
    }

    private func setFrame(_ frame: CGRect, for window: AXUIElement) throws -> FrameApplicationOutcome {
        var size = CGSize(width: max(1, frame.width), height: max(1, frame.height))
        var origin = CGPoint(x: frame.origin.x, y: frame.origin.y)

        DebugLog.debug(
            DebugLog.windows,
            "Setting AX frame on window \(windowSummary([window])) to origin \(NSStringFromPoint(origin)) size \(NSStringFromSize(size))"
        )

        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw WindowManagerError.unableToSetFrame
        }

        guard let positionValue = AXValueCreate(.cgPoint, &origin) else {
            throw WindowManagerError.unableToSetFrame
        }

        let currentFrame = readFrameBestEffort(of: window, context: "before frame write")
        let preferredOrder = frameWriteOrder(from: currentFrame, to: frame)

        DebugLog.debug(
            DebugLog.windows,
            "Applying AX frame using \(preferredOrder.rawValue); current AX frame = \(currentFrame.map(NSStringFromRect) ?? "unknown"), target AX frame = \(NSStringFromRect(frame))"
        )

        let initialWriteResult = applyFrame(
            window: window,
            originValue: positionValue,
            sizeValue: sizeValue,
            origin: origin,
            size: size,
            order: preferredOrder
        )

        if initialWriteResult.succeeded == false {
            if let recoveredOutcome = recoveredFrameOutcome(
                for: window,
                targetFrame: frame,
                requestedOrigin: origin,
                requestedSize: size,
                order: preferredOrder,
                writeResult: initialWriteResult
            ) {
                return recoveredOutcome
            }

            let fallbackOrder = preferredOrder.alternate
            DebugLog.debug(
                DebugLog.windows,
                "AX frame write failed using \(preferredOrder.rawValue); retrying with \(fallbackOrder.rawValue)"
            )

            let fallbackWriteResult = applyFrame(
                window: window,
                originValue: positionValue,
                sizeValue: sizeValue,
                origin: origin,
                size: size,
                order: fallbackOrder
            )

            if let recoveredOutcome = recoveredFrameOutcome(
                for: window,
                targetFrame: frame,
                requestedOrigin: origin,
                requestedSize: size,
                order: fallbackOrder,
                writeResult: fallbackWriteResult
            ) {
                return recoveredOutcome
            }

            throw WindowManagerError.unableToSetFrame
        }

        guard let appliedFrame = readFrameBestEffort(of: window, context: "after \(preferredOrder.rawValue) frame write") else {
            return .exact(frame)
        }

        if framesAreClose(appliedFrame, frame) == false {
            let fallbackOrder = preferredOrder.alternate
            DebugLog.debug(
                DebugLog.windows,
                "AX frame readback mismatch after \(preferredOrder.rawValue). Applied = \(NSStringFromRect(appliedFrame)), target = \(NSStringFromRect(frame)). Retrying with \(fallbackOrder.rawValue)"
            )

            let fallbackWriteResult = applyFrame(
                window: window,
                originValue: positionValue,
                sizeValue: sizeValue,
                origin: origin,
                size: size,
                order: fallbackOrder
            )

            if fallbackWriteResult.succeeded == false {
                if let recoveredOutcome = recoveredFrameOutcome(
                    for: window,
                    targetFrame: frame,
                    requestedOrigin: origin,
                    requestedSize: size,
                    order: fallbackOrder,
                    writeResult: fallbackWriteResult
                ) {
                    return recoveredOutcome
                }

                throw WindowManagerError.unableToSetFrame
            }

            guard
                let retriedFrame = readFrameBestEffort(of: window, context: "after \(fallbackOrder.rawValue) frame write")
            else {
                let finalFrame = readFrameBestEffort(of: window, context: "final frame read after mismatch")
                    .map(NSStringFromRect) ?? "unavailable"
                DebugLog.error(
                    DebugLog.accessibility,
                    "Failed to apply requested frame for window \(windowSummary([window])). Requested origin = \(NSStringFromPoint(origin)), size = \(NSStringFromSize(size)), final AX frame = \(finalFrame)"
                )
                throw WindowManagerError.unableToSetFrame
            }

            if framesAreClose(retriedFrame, frame) {
                return .exact(retriedFrame)
            }

            if isConstraintLimitedFrame(retriedFrame, comparedTo: frame) {
                DebugLog.info(
                    DebugLog.windows,
                    "Accepted constrained frame for window \(windowSummary([window])). Requested = \(NSStringFromRect(frame)), applied = \(NSStringFromRect(retriedFrame))"
                )
                return .constrained(retriedFrame)
            }

            let finalFrame = NSStringFromRect(retriedFrame)
            DebugLog.error(
                DebugLog.accessibility,
                "Failed to apply requested frame for window \(windowSummary([window])). Requested origin = \(NSStringFromPoint(origin)), size = \(NSStringFromSize(size)), final AX frame = \(finalFrame)"
            )
            throw WindowManagerError.unableToSetFrame
        }

        return .exact(appliedFrame)
    }

    private func recoveredFrameOutcome(
        for window: AXUIElement,
        targetFrame: CGRect,
        requestedOrigin: CGPoint,
        requestedSize: CGSize,
        order: FrameWriteOrder,
        writeResult: FrameWriteResult
    ) -> FrameApplicationOutcome? {
        DebugLog.error(
            DebugLog.accessibility,
            "Failed to set frame for window \(windowSummary([window])) using \(order.rawValue). Requested origin = \(NSStringFromPoint(requestedOrigin)), size = \(NSStringFromSize(requestedSize)), size error = \(writeResult.sizeError.rawValue), position error = \(writeResult.positionError.rawValue)"
        )

        guard
            let recoveredFrame = readFrameBestEffort(of: window, context: "after failed \(order.rawValue) frame write")
        else {
            return nil
        }

        if framesAreClose(recoveredFrame, targetFrame) {
            DebugLog.info(
                DebugLog.windows,
                "Recovered exact frame after failed AX write for window \(windowSummary([window])). Requested = \(NSStringFromRect(targetFrame)), applied = \(NSStringFromRect(recoveredFrame))"
            )
            return .exact(recoveredFrame)
        }

        if isConstraintLimitedFrame(recoveredFrame, comparedTo: targetFrame) {
            DebugLog.info(
                DebugLog.windows,
                "Accepted constrained frame after failed AX write for window \(windowSummary([window])). Requested = \(NSStringFromRect(targetFrame)), applied = \(NSStringFromRect(recoveredFrame))"
            )
            return .constrained(recoveredFrame)
        }

        return nil
    }

    private func readFrameBestEffort(of window: AXUIElement, context: String) -> CGRect? {
        do {
            return try frame(of: window)
        } catch {
            DebugLog.debug(
                DebugLog.accessibility,
                "Failed to read AX frame (\(context)): \(error.localizedDescription)"
            )
            return nil
        }
    }

    private func applyFrame(
        window: AXUIElement,
        originValue: AXValue,
        sizeValue: AXValue,
        origin: CGPoint,
        size: CGSize,
        order: FrameWriteOrder
    ) -> FrameWriteResult {
        let sizeError: AXError
        let positionError: AXError

        switch order {
        case .sizeThenPosition:
            sizeError = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            positionError = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
        case .positionThenSize:
            positionError = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
            sizeError = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }

        return FrameWriteResult(sizeError: sizeError, positionError: positionError)
    }

    private func frameWriteOrder(from currentFrame: CGRect?, to targetFrame: CGRect) -> FrameWriteOrder {
        guard let currentFrame else {
            return .sizeThenPosition
        }

        // When a window needs to expand while also moving toward the origin,
        // some apps clamp the size before the position update lands. Move first.
        if targetFrame.minX < currentFrame.minX || targetFrame.minY < currentFrame.minY {
            return .positionThenSize
        }

        return .sizeThenPosition
    }

    private func framesAreClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance &&
        abs(lhs.minY - rhs.minY) <= tolerance &&
        abs(lhs.width - rhs.width) <= tolerance &&
        abs(lhs.height - rhs.height) <= tolerance
    }

    private func isConstraintLimitedFrame(
        _ appliedFrame: CGRect,
        comparedTo targetFrame: CGRect,
        tolerance: CGFloat = 1
    ) -> Bool {
        let materiallyDifferent = framesAreClose(appliedFrame, targetFrame, tolerance: tolerance) == false
        let horizontallyAnchored = axisLooksConstraintLimited(
            requestedMin: targetFrame.minX,
            requestedMax: targetFrame.maxX,
            appliedMin: appliedFrame.minX,
            appliedMax: appliedFrame.maxX,
            tolerance: tolerance
        )
        let verticallyAnchored = axisLooksConstraintLimited(
            requestedMin: targetFrame.minY,
            requestedMax: targetFrame.maxY,
            appliedMin: appliedFrame.minY,
            appliedMax: appliedFrame.maxY,
            tolerance: tolerance
        )

        return materiallyDifferent && horizontallyAnchored && verticallyAnchored
    }

    private func axisLooksConstraintLimited(
        requestedMin: CGFloat,
        requestedMax: CGFloat,
        appliedMin: CGFloat,
        appliedMax: CGFloat,
        tolerance: CGFloat
    ) -> Bool {
        let matchesBothEdges =
            abs(appliedMin - requestedMin) <= tolerance &&
            abs(appliedMax - requestedMax) <= tolerance

        return matchesBothEdges || observedAnchor(
            requestedMin: requestedMin,
            requestedMax: requestedMax,
            appliedMin: appliedMin,
            appliedMax: appliedMax,
            tolerance: tolerance
        ) != nil
    }

    private func logScreenConfiguration(_ screens: [NSScreen], preferredAppKitPoint: CGPoint?) {
        let screenSummary = screens.enumerated().map { index, screen in
            let name = screen.localizedName
            return "#\(index){name=\(name), frame=\(NSStringFromRect(screen.frame)), visible=\(NSStringFromRect(screen.visibleFrame))}"
        }.joined(separator: ", ")

        DebugLog.debug(
            DebugLog.windows,
            "Available screens: [\(screenSummary)]; preferred point = \(preferredAppKitPoint.map(NSStringFromPoint) ?? "nil")"
        )
    }

    private func logFrameRead(
        for window: AXUIElement,
        action: WindowAction,
        application: NSRunningApplication,
        axFrame: CGRect,
        appKitFrame: CGRect
    ) {
        let title = readOptionalAXAttribute(
            context: "AXTitle in logFrameRead",
            fallback: "<untitled>"
        ) {
            try stringAttribute(kAXTitleAttribute as CFString, from: window)
        }
        let role = readOptionalAXAttribute(
            context: "AXRole in logFrameRead",
            fallback: "<unknown>"
        ) {
            try stringAttribute(kAXRoleAttribute as CFString, from: window)
        }
        let subrole = readOptionalAXAttribute(
            context: "AXSubrole in logFrameRead",
            fallback: "<unknown>"
        ) {
            try stringAttribute(kAXSubroleAttribute as CFString, from: window)
        }
        let isMain = readOptionalAXAttribute(
            context: "AXMain in logFrameRead",
            fallback: false
        ) {
            try booleanAttribute(kAXMainAttribute as CFString, from: window)
        }
        let isFocused = readOptionalAXAttribute(
            context: "AXFocused in logFrameRead",
            fallback: false
        ) {
            try booleanAttribute(kAXFocusedAttribute as CFString, from: window)
        }
        let isMinimized = readOptionalAXAttribute(
            context: "AXMinimized in logFrameRead",
            fallback: false
        ) {
            try booleanAttribute(kAXMinimizedAttribute as CFString, from: window)
        }

        DebugLog.debug(
            DebugLog.windows,
            "Resolved geometry for action \(String(describing: action)) in app \(application.localizedName ?? "unknown") [\(application.bundleIdentifier ?? "unknown")]: title=\(title), role=\(role), subrole=\(subrole), main=\(isMain), focused=\(isFocused), minimized=\(isMinimized), AX frame=\(NSStringFromRect(axFrame)), AppKit frame=\(NSStringFromRect(appKitFrame))"
        )
    }

    private func pointAttribute(_ attribute: CFString, from element: AXUIElement) throws -> CGPoint {
        guard let point = AXAttributeReader.point(attribute, from: element) else {
            throw WindowManagerError.unableToReadWindowFrame
        }
        return point
    }

    private func sizeAttribute(_ attribute: CFString, from element: AXUIElement) throws -> CGSize {
        guard let size = AXAttributeReader.size(attribute, from: element) else {
            throw WindowManagerError.unableToReadWindowFrame
        }
        return size
    }

    private func booleanAttribute(_ attribute: CFString, from element: AXUIElement) throws -> Bool {
        guard let value = AXAttributeReader.bool(attribute, from: element) else {
            throw WindowManagerError.unableToPerformAction
        }
        return value
    }

    private func windowElements(in appElement: AXUIElement) throws -> [AXUIElement] {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)

        guard error == .success, let windows = value as? [AnyObject] else {
            DebugLog.error(DebugLog.accessibility, "Failed to enumerate windows; AX error = \(error.rawValue)")
            throw WindowManagerError.unableToEnumerateWindows
        }

        let elements: [AXUIElement] = windows.compactMap { window -> AXUIElement? in
            guard CFGetTypeID(window) == AXUIElementGetTypeID() else {
                return nil
            }
            return unsafeDowncast(window, to: AXUIElement.self)
        }
        if elements.count != windows.count {
            DebugLog.debug(
                DebugLog.accessibility,
                "Dropped \(windows.count - elements.count) non-AX entries while enumerating windows"
            )
        }
        return elements
    }

    private func visibleWindowElements(in appElement: AXUIElement) throws -> [AXUIElement] {
        try windowElements(in: appElement).filter { !isMinimized($0) }
    }

    private func orderedVisibleWindowElements(
        in app: NSRunningApplication,
        appElement: AXUIElement
    ) throws -> [AXUIElement] {
        let windows = try visibleWindowElements(in: appElement)
        guard windows.count > 1 else {
            return windows
        }

        let orderedWindowDescriptors = frontToBackWindowDescriptors(
            forOwnerProcessIdentifier: app.processIdentifier
        )
        guard orderedWindowDescriptors.isEmpty == false else {
            DebugLog.debug(
                DebugLog.windows,
                "CGWindowList returned no front-to-back descriptors for \(app.localizedName ?? "unknown"); using AX window order"
            )
            return windows
        }

        let orderedWindows = try windowOrdering.frontToBack(
            windows,
            descriptor: { try windowDescriptor(for: $0) },
            using: orderedWindowDescriptors
        )

        if sameWindowSequence(windows, orderedWindows) == false {
            DebugLog.debug(
                DebugLog.windows,
                "Reordered visible windows for \(app.localizedName ?? "unknown") from AX order [\(windowSummary(windows))] to front-to-back [\(windowSummary(orderedWindows))]"
            )
        }

        return orderedWindows
    }

    private func frontToBackWindowDescriptors(
        forOwnerProcessIdentifier processIdentifier: pid_t
    ) -> [WindowOrderDescriptor] {
        guard
            let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]]
        else {
            return []
        }

        return windowInfoList.compactMap { windowInfo in
            guard
                let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? NSNumber,
                ownerPID.int32Value == processIdentifier
            else {
                return nil
            }

            guard
                let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary
            else {
                return nil
            }

            var frame = CGRect.null
            guard
                CGRectMakeWithDictionaryRepresentation(boundsDictionary, &frame),
                frame.isNull == false,
                frame.isEmpty == false
            else {
                return nil
            }

            let title = (windowInfo[kCGWindowName as String] as? String) ?? ""
            return WindowOrderDescriptor(title: title, frame: frame.integral)
        }
    }

    private func windowDescriptor(for window: AXUIElement) throws -> WindowOrderDescriptor {
        WindowOrderDescriptor(
            title: readOptionalAXAttribute(
                context: "AXTitle in windowDescriptor",
                fallback: ""
            ) {
                try stringAttribute(kAXTitleAttribute as CFString, from: window)
            },
            frame: try frame(of: window)
        )
    }

    private func sameWindowSequence(_ lhs: [AXUIElement], _ rhs: [AXUIElement]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }

        return zip(lhs, rhs).allSatisfy { sameWindow($0, $1) }
    }

    private func sameWindow(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
        CFEqual(lhs as CFTypeRef, rhs as CFTypeRef)
    }

    private func isMinimized(_ window: AXUIElement) -> Bool {
        readOptionalAXAttribute(
            context: "AXMinimized in isMinimized",
            fallback: false
        ) {
            try booleanAttribute(kAXMinimizedAttribute as CFString, from: window)
        }
    }

    private func windowSummary(_ windows: [AXUIElement]) -> String {
        windows.map { window in
            let title = readOptionalAXAttribute(
                context: "AXTitle in windowSummary",
                fallback: "<untitled>"
            ) {
                try stringAttribute(kAXTitleAttribute as CFString, from: window)
            }
            let minimized = readOptionalAXAttribute(
                context: "AXMinimized in windowSummary",
                fallback: false
            ) {
                try booleanAttribute(kAXMinimizedAttribute as CFString, from: window)
            } ? "min" : "visible"
            let frameDescription: String
            frameDescription = readOptionalAXAttribute(
                context: "AXFrame in windowSummary",
                fallback: "<unknown-frame>"
            ) {
                NSStringFromRect(try frame(of: window))
            }
            return "\"\(title)\"{\(minimized), frame=\(frameDescription)}"
        }
        .joined(separator: ", ")
    }

    private func readOptionalAXAttribute<T>(
        context: String,
        fallback: T,
        read: () throws -> T
    ) -> T {
        do {
            return try read()
        } catch {
            DebugLog.debug(
                DebugLog.accessibility,
                "Failed to read \(context): \(error.localizedDescription)"
            )
            return fallback
        }
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) throws -> String {
        guard let stringValue = AXAttributeReader.string(attribute, from: element) else {
            throw WindowManagerError.unableToPerformAction
        }

        return stringValue
    }
}

enum WindowManagerError: LocalizedError, Equatable {
    case accessibilityPermissionMissing
    case noFrontmostApplication
    case noFocusedWindow
    case unableToReadWindowFrame
    case unableToSetFrame
    case unableToResolveScreen
    case unableToPerformAction
    case unableToQuitApplication
    case unableToEnumerateWindows
    case noAlternateWindow

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return L10n.string("error.permission_missing")
        case .noFrontmostApplication:
            return L10n.string("error.no_frontmost_app")
        case .noFocusedWindow:
            return L10n.string("error.no_focused_window")
        case .unableToReadWindowFrame:
            return L10n.string("error.read_window_frame_failed")
        case .unableToSetFrame:
            return L10n.string("error.set_window_frame_failed")
        case .unableToResolveScreen:
            return L10n.string("error.resolve_screen_failed")
        case .unableToPerformAction:
            return L10n.string("error.perform_action_failed")
        case .unableToQuitApplication:
            return L10n.string("error.quit_application_failed")
        case .unableToEnumerateWindows:
            return L10n.string("error.enumerate_windows_failed")
        case .noAlternateWindow:
            return L10n.string("error.no_alternate_window")
        }
    }
}
