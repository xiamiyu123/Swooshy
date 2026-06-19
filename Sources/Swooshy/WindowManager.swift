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
            .positionThenSize
        case .positionThenSize:
            .sizeThenPosition
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
protocol WindowManaging {
    func perform(_ action: WindowAction, layoutEngine: WindowLayoutEngine) throws
}

@MainActor
/// Coordinates AX window reads, window ordering, frame application, and the
/// higher-level actions exposed to gestures and keyboard shortcuts.
final class WindowManager: WindowManaging {
    private let registry: WindowRegistry
    private let dockTargetResolver: DockTargetResolving
    private let windowOrdering = WindowOrdering()
    private let cycleSessions = WindowCycleSessionStore<AXUIElement>(areEqual: AXAttributeReader.sameElement)
    private let observedWindowConstraintStore = ObservedWindowConstraintStore()
    private let windowOrderingSnapshotCache = CGWindowOrderingSnapshotCache()

    private struct ResolvedWindowActionLayout {
        let focusedWindow: AXUIElement
        let screenGeometry: ScreenGeometry
        let targetFrame: CGRect
        let targetAXFrame: CGRect
    }

    init(
        registry: WindowRegistry,
        dockTargetResolver: DockTargetResolving
    ) {
        self.registry = registry
        self.dockTargetResolver = dockTargetResolver
    }

    func shutdown() {
        observedWindowConstraintStore.shutdown()
        registry.shutdown()
    }

    private func requireAccessibilityPermission() throws {
        guard AXIsProcessTrusted() else {
            throw WindowManagerError.accessibilityPermissionMissing
        }
    }

    private func requirePerformed(_ didPerform: Bool) throws {
        guard didPerform else {
            throw WindowManagerError.unableToPerformAction
        }
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
        let appElement = AXAttributeReader.applicationElement(for: app.processIdentifier)

        func targetedFrontmostWindow() throws -> AXUIElement {
            try targetedWindow(
                in: app,
                appElement: appElement,
                preferredAppKitPoint: preferredAppKitPoint,
                fallback: { try focusedWindowElement(in: appElement) }
            )
        }

        switch action {
        case .minimize:
            let window = try targetedFrontmostWindow()
            try setMinimized(true, for: window)
            return
        case .closeWindow:
            let window = try targetedFrontmostWindow()
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
            let currentWindow = try targetedFrontmostWindow()
            try focusAdjacentVisibleWindow(
                in: app,
                appElement: appElement,
                currentWindow: currentWindow,
                direction: .forward
            )
            return
        case .cycleSameAppWindowsBackward:
            let currentWindow = try targetedFrontmostWindow()
            try focusAdjacentVisibleWindow(
                in: app,
                appElement: appElement,
                currentWindow: currentWindow,
                direction: .backward
            )
            return
        case .moveToNextDisplay, .moveToPreviousDisplay:
            let window = try targetedFrontmostWindow()
            try performDisplayMove(
                direction: action.displayMoveDirection,
                application: app,
                window: window,
                layoutEngine: layoutEngine,
                preferredAppKitPoint: preferredAppKitPoint,
                bringToFront: false
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
            let window = try focusedWindowElement(in: appElement)
            try performSmoothDockingAction(
                action,
                application: app,
                window: window,
                preferredAppKitPoint: preferredAppKitPoint,
                bringToFront: false
            )
            return
        case .quitApplication:
            return
        case .toggleFullScreen:
            let window = try targetedFrontmostWindow()
            try setFullScreen(!isFullScreen(window), for: window)
            return
        case .exitFullScreen:
            let window = try targetedFrontmostWindow()
            if isFullScreen(window) {
                try setFullScreen(false, for: window)
            }
            return
        }

    }

    func perform(
        _ action: WindowAction,
        on target: InteractionTarget,
        layoutEngine: WindowLayoutEngine,
        preferredAppKitPoint: CGPoint?
    ) throws {
        DebugLog.info(DebugLog.windows, "Performing window action \(String(describing: action)) for target \(target.logDescription)")

        guard AXIsProcessTrusted() else {
            DebugLog.error(DebugLog.accessibility, "Accessibility permission missing before target action \(String(describing: action))")
            throw WindowManagerError.accessibilityPermissionMissing
        }

        let resolvedApplication = try resolvedApplicationContext(for: target)

        switch action {
        case .quitApplication:
            guard let appIdentity = target.appIdentity else {
                throw WindowManagerError.unableToPerformAction
            }
            _ = try quitApplication(matching: appIdentity)
            return
        case .minimize:
            try requirePerformed(
                try minimizeVisibleWindow(
                    of: target,
                    preferredAppKitPoint: preferredAppKitPoint
                )
            )
            return
        case .closeWindow:
            try requirePerformed(
                try closeWindow(of: target, preferredAppKitPoint: preferredAppKitPoint)
            )
            return
        case .toggleFullScreen:
            try requirePerformed(
                try toggleFullScreenWindow(
                    of: target,
                    preferredAppKitPoint: preferredAppKitPoint
                )
            )
            return
        case .exitFullScreen:
            try requirePerformed(
                try exitFullScreenWindow(
                    of: target,
                    preferredAppKitPoint: preferredAppKitPoint
                )
            )
            return
        case .closeTab:
            guard BrowserTabProbe.simulateMiddleClick(at: preferredAppKitPoint ?? NSEvent.mouseLocation) else {
                throw WindowManagerError.unableToPerformAction
            }
            return
        case .cycleSameAppWindowsForward:
            try requirePerformed(
                try cycleVisibleWindows(
                    of: target,
                    direction: .forward,
                    preferredAppKitPoint: preferredAppKitPoint
                )
            )
            return
        case .cycleSameAppWindowsBackward:
            try requirePerformed(
                try cycleVisibleWindows(
                    of: target,
                    direction: .backward,
                    preferredAppKitPoint: preferredAppKitPoint
                )
            )
            return
        case .moveToNextDisplay, .moveToPreviousDisplay:
            let targetWindow = try preferredWindowActionTarget(
                for: target,
                preferredAppKitPoint: preferredAppKitPoint
            )
            try performDisplayMove(
                direction: action.displayMoveDirection,
                application: resolvedApplication.application,
                window: targetWindow,
                layoutEngine: layoutEngine,
                preferredAppKitPoint: preferredAppKitPoint,
                bringToFront: true
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
            let targetWindow = try preferredWindowActionTarget(
                for: target,
                preferredAppKitPoint: preferredAppKitPoint
            )
            try performSmoothDockingAction(
                action,
                application: resolvedApplication.application,
                window: targetWindow,
                preferredAppKitPoint: preferredAppKitPoint,
                bringToFront: true
            )
            return
        }
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
        let appElement = AXAttributeReader.applicationElement(for: app.processIdentifier)
        let resolvedLayout = try resolvedWindowActionLayout(
            for: action,
            application: app,
            appElement: appElement,
            layoutEngine: layoutEngine,
            preferredAppKitPoint: preferredAppKitPoint
        )
        let observedObservation = observedConstraintObservation(
            for: app,
            window: resolvedLayout.focusedWindow,
            action: action
        )
        return layoutEngine.preview(
            for: action,
            targetFrame: resolvedLayout.targetFrame,
            observation: observedObservation
        )
    }

    func previewTarget(
        for action: WindowAction,
        on target: InteractionTarget,
        layoutEngine: WindowLayoutEngine,
        preferredAppKitPoint: CGPoint?
    ) throws -> WindowActionPreview? {
        guard action.supportsSnapPreview else {
            throw WindowManagerError.unableToPerformAction
        }

        let resolvedApplication = try resolvedApplicationContext(for: target)
        let targetWindow = try preferredWindowActionTarget(
            for: target,
            preferredAppKitPoint: preferredAppKitPoint
        )
        let resolvedLayout = try resolvedWindowActionLayout(
            for: action,
            application: resolvedApplication.application,
            window: targetWindow,
            layoutEngine: layoutEngine,
            preferredAppKitPoint: preferredAppKitPoint
        )
        let observedObservation = observedConstraintObservation(
            for: resolvedApplication.application,
            window: targetWindow,
            action: action
        )
        return layoutEngine.preview(
            for: action,
            targetFrame: resolvedLayout.targetFrame,
            observation: observedObservation
        )
    }

    func beginSmoothDockingSession(
        on target: InteractionTarget,
        preferredAppKitPoint: CGPoint?
    ) throws -> SmoothDockingSession {
        try requireAccessibilityPermission()

        let resolvedApplication = try resolvedApplicationContext(for: target)
        let targetWindow = try preferredWindowActionTarget(
            for: target,
            preferredAppKitPoint: preferredAppKitPoint
        )

        return try makeSmoothDockingSession(
            application: resolvedApplication.application,
            window: targetWindow,
            preferredAppKitPoint: preferredAppKitPoint,
            bringToFront: true
        )
    }

    func preferredFullScreenWindow(
        matching target: InteractionTarget,
        preferredAppKitPoint: CGPoint?
    ) throws -> AXUIElement? {
        let resolvedApplication = try resolvedApplicationContext(for: target)
        return preferredFullScreenWindow(
            in: resolvedApplication.application,
            appElement: resolvedApplication.appElement,
            preferredAppKitPoint: preferredAppKitPoint
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
        preferredAppKitPoint: CGPoint?,
        usesObservedConstraints: Bool = true
    ) throws -> ResolvedWindowActionLayout {
        let focusedWindow = try focusedWindowElement(in: appElement)
        return try resolvedWindowActionLayout(
            for: action,
            application: application,
            window: focusedWindow,
            layoutEngine: layoutEngine,
            preferredAppKitPoint: preferredAppKitPoint,
            usesObservedConstraints: usesObservedConstraints
        )
    }

    private func resolvedWindowActionLayout(
        for action: WindowAction,
        application: NSRunningApplication,
        window: AXUIElement,
        layoutEngine: WindowLayoutEngine,
        preferredAppKitPoint: CGPoint?,
        usesObservedConstraints: Bool = true
    ) throws -> ResolvedWindowActionLayout {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
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
            currentScreenFrame.contains(preferredAppKitPoint)
        {
            DebugLog.debug(
                DebugLog.windows,
                "Resolved target screen from preferred point \(NSStringFromPoint(preferredAppKitPoint)): \(NSStringFromRect(currentScreenFrame))"
            )
        }

        let targetFrame = layoutEngine.targetFrame(
            for: action,
            currentWindowFrame: currentFrame,
            currentVisibleFrame: currentScreenFrame
        )

        let observedObservation = usesObservedConstraints
            ? observedConstraintObservation(for: application, window: window, action: action)
            : nil
        let constrainedTargetFrame = layoutEngine.constrainedTargetFrame(
            for: action,
            targetFrame: targetFrame,
            observation: observedObservation
        )
        let clampedTargetFrame = clampFrame(constrainedTargetFrame, to: currentScreenFrame)

        DebugLog.debug(
            DebugLog.windows,
            "Calculated target frame \(NSStringFromRect(clampedTargetFrame)) from current frame \(NSStringFromRect(currentFrame))"
        )

        let targetAXFrame = screenGeometry.axFrame(fromAppKitFrame: clampedTargetFrame)
        DebugLog.debug(
            DebugLog.windows,
            "Writing target AX frame \(NSStringFromRect(targetAXFrame)) converted from AppKit target \(NSStringFromRect(clampedTargetFrame))"
        )

        return ResolvedWindowActionLayout(
            focusedWindow: window,
            screenGeometry: screenGeometry,
            targetFrame: clampedTargetFrame,
            targetAXFrame: targetAXFrame
        )
    }

    private struct ResolvedApplicationContext {
        let identity: AppIdentity
        let application: NSRunningApplication
        let appElement: AXUIElement
    }

    private struct ResolvedWindowContext {
        let snapshot: WindowRecordSnapshot
        let application: NSRunningApplication
        let appElement: AXUIElement
        let window: AXUIElement
    }

    private func resolvedApplicationContext(for target: InteractionTarget) throws -> ResolvedApplicationContext {
        guard let appIdentity = target.appIdentity else {
            throw WindowManagerError.unableToPerformAction
        }

        let preferredProcessIdentifier: pid_t?
        if
            let windowIdentity = target.windowIdentity,
            let snapshot = registry.windowSnapshot(for: windowIdentity)
        {
            preferredProcessIdentifier = snapshot.ownerProcessIdentifier
        } else {
            preferredProcessIdentifier = target.processIdentifier
        }

        let application = try runningApplication(
            matching: appIdentity,
            preferredProcessIdentifier: preferredProcessIdentifier
        )
        return ResolvedApplicationContext(
            identity: appIdentity,
            application: application,
            appElement: AXAttributeReader.applicationElement(for: application.processIdentifier)
        )
    }

    private func resolvedWindowContext(for windowIdentity: WindowIdentity) throws -> ResolvedWindowContext {
        guard let snapshot = registry.windowSnapshot(for: windowIdentity) else {
            throw WindowManagerError.noFocusedWindow
        }

        guard let window = registry.windowElement(for: windowIdentity) else {
            throw WindowManagerError.noFocusedWindow
        }

        let application = try runningApplication(
            matching: snapshot.appIdentity,
            preferredProcessIdentifier: snapshot.ownerProcessIdentifier
        )
        return ResolvedWindowContext(
            snapshot: snapshot,
            application: application,
            appElement: AXAttributeReader.applicationElement(for: application.processIdentifier),
            window: window
        )
    }

    private func prefersWindowScopedAction(_ target: InteractionTarget) -> Bool {
        switch target {
        case .window(_, _, let source):
            return !source.isDockMinimizedItem
        case .application, .unresolvedDockMinimizedItem:
            return false
        }
    }

    func preferredWindowActionTarget(
        for target: InteractionTarget,
        preferredAppKitPoint: CGPoint?
    ) throws -> AXUIElement {
        switch target {
        case .window(let windowIdentity, _, _):
            return try resolvedWindowContext(for: windowIdentity).window
        case .application:
            let resolvedApplication = try resolvedApplicationContext(for: target)
            return try preferredWindowActionTarget(
                in: resolvedApplication.application,
                appElement: resolvedApplication.appElement,
                preferredAppKitPoint: preferredAppKitPoint
            )
        case .unresolvedDockMinimizedItem:
            throw WindowManagerError.unableToPerformAction
        }
    }

    func preferredWindowActionTarget(
        in app: NSRunningApplication,
        appElement: AXUIElement,
        preferredAppKitPoint: CGPoint?
    ) throws -> AXUIElement {
        if
            let preferredAppKitPoint,
            let window = try windowContainingPoint(
                preferredAppKitPoint,
                in: app,
                appElement: appElement
            )
        {
            return window
        }

        let visibleWindows = try orderedVisibleWindowElements(in: app, appElement: appElement)
        if let window = visibleWindows.first {
            return window
        }

        if let referenceWindow = preferredCycleReferenceWindow(in: appElement) {
            return referenceWindow
        }

        throw WindowManagerError.noFocusedWindow
    }

    private func targetedWindow(
        in app: NSRunningApplication,
        appElement: AXUIElement,
        preferredAppKitPoint: CGPoint?,
        fallback: () throws -> AXUIElement
    ) throws -> AXUIElement {
        if let preferredAppKitPoint {
            return try preferredWindowActionTarget(
                in: app,
                appElement: appElement,
                preferredAppKitPoint: preferredAppKitPoint
            )
        }

        return try fallback()
    }

    private func preferredFullScreenWindow(
        in app: NSRunningApplication,
        appElement: AXUIElement,
        preferredAppKitPoint: CGPoint?
    ) -> AXUIElement? {
        if
            let preferredAppKitPoint,
            let pointedWindow = try? preferredWindowActionTarget(
                in: app,
                appElement: appElement,
                preferredAppKitPoint: preferredAppKitPoint
            ),
            isFullScreen(pointedWindow)
        {
            return pointedWindow
        }

        if
            let focusedWindow = try? focusedWindowElement(in: appElement),
            isFullScreen(focusedWindow)
        {
            return focusedWindow
        }

        if
            let mainWindow = try? mainWindowElement(in: appElement),
            isFullScreen(mainWindow)
        {
            return mainWindow
        }

        if
            let visibleWindows = try? orderedVisibleWindowElements(in: app, appElement: appElement),
            let fullScreenVisibleWindow = visibleWindows.first(where: isFullScreen)
        {
            return fullScreenVisibleWindow
        }

        if
            let allWindows = try? windowElements(in: appElement),
            let fullScreenWindow = allWindows.first(where: isFullScreen)
        {
            return fullScreenWindow
        }

        return nil
    }

    private func windowContainingPoint(
        _ appKitPoint: CGPoint,
        in app: NSRunningApplication,
        appElement: AXUIElement
    ) throws -> AXUIElement? {
        if let hitWindow = hitTestWindow(at: appKitPoint, processIdentifier: app.processIdentifier) {
            DebugLog.debug(
                DebugLog.windows,
                "Resolved preferred window from hit-test at \(NSStringFromPoint(appKitPoint)): \(windowSummary([hitWindow]))"
            )
            return hitWindow
        }

        let visibleWindows = try orderedVisibleWindowElements(in: app, appElement: appElement)
        let geometry = ScreenGeometry(screenFrames: NSScreen.screens.map(\.frame))
        for window in visibleWindows {
            // Skip windows with unreadable frames so one broken AX element
            // cannot abort containment matching for the remaining windows.
            guard let axFrame = try? frame(of: window) else {
                continue
            }
            let appKitFrame = geometry.appKitFrame(fromAXFrame: axFrame)
            if appKitFrame.contains(appKitPoint) {
                DebugLog.debug(
                    DebugLog.windows,
                    "Resolved preferred window by frame containment at \(NSStringFromPoint(appKitPoint)): \(windowSummary([window]))"
                )
                return window
            }
        }

        return nil
    }

    private func hitTestWindow(
        at appKitPoint: CGPoint,
        processIdentifier: pid_t
    ) -> AXUIElement? {
        guard let hitElement = AXAttributeReader.hitElement(at: appKitPoint) else {
            return nil
        }

        guard
            AXAttributeReader.processIdentifier(of: hitElement) == processIdentifier,
            let window = AXAttributeReader.window(containing: hitElement)
        else {
            return nil
        }

        return window
    }

    private func performSmoothDockingAction(
        _ action: WindowAction,
        application: NSRunningApplication,
        window: AXUIElement,
        preferredAppKitPoint: CGPoint?,
        bringToFront: Bool
    ) throws {
        let session = try makeSmoothDockingSession(
            application: application,
            window: window,
            preferredAppKitPoint: preferredAppKitPoint,
            bringToFront: bringToFront
        )

        session.update(action: action)
        let appliedFrame = try session.commit()
        session.finish()

        DebugLog.debug(
            DebugLog.windows,
            "Applied smooth docking frame \(NSStringFromRect(appliedFrame)) for \(String(describing: action)) in \(application.bundleIdentifier ?? application.localizedName ?? "unknown")"
        )
    }

    private func performDisplayMove(
        direction: DisplayMoveDirection,
        application: NSRunningApplication,
        window: AXUIElement,
        layoutEngine: WindowLayoutEngine,
        preferredAppKitPoint: CGPoint?,
        bringToFront: Bool
    ) throws {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw WindowManagerError.unableToResolveScreen
        }
        guard screens.count > 1 else {
            DebugLog.debug(DebugLog.windows, "Skipping display move because only one display is available")
            throw WindowManagerError.noOtherDisplay
        }

        if isMinimized(window) {
            try setMinimized(false, for: window)
        }

        if bringToFront {
            try bringWindowToFront(window, for: application)
        }

        logScreenConfiguration(screens, preferredAppKitPoint: preferredAppKitPoint)

        let screenGeometry = ScreenGeometry(screenFrames: screens.map(\.frame))
        let currentAXFrame = try frame(of: window)
        let currentFrame = screenGeometry.appKitFrame(fromAXFrame: currentAXFrame)
        let visibleFrames = screens.map(\.visibleFrame)

        guard let targetFrame = layoutEngine.displayMoveTargetFrame(
            direction: direction,
            currentWindowFrame: currentFrame,
            preferredPoint: preferredAppKitPoint,
            screenFrames: visibleFrames
        ) else {
            throw WindowManagerError.unableToResolveScreen
        }
        guard !framesAreClose(currentFrame, targetFrame) else {
            DebugLog.debug(DebugLog.windows, "Display move resolved to current frame; no frame write needed")
            return
        }

        let targetAXFrame = screenGeometry.axFrame(fromAppKitFrame: targetFrame)
        let outcome = try setFrame(targetAXFrame, for: window)
        let appliedAXFrame: CGRect
        switch outcome {
        case .exact(let frame), .constrained(let frame):
            appliedAXFrame = frame
        }

        DebugLog.debug(
            DebugLog.windows,
            "Moved window to \(direction.logDescription) display from \(NSStringFromRect(currentFrame)) to \(NSStringFromRect(screenGeometry.appKitFrame(fromAXFrame: appliedAXFrame))) in \(application.bundleIdentifier ?? application.localizedName ?? "unknown")"
        )
    }

    private func makeSmoothDockingSession(
        application: NSRunningApplication,
        window: AXUIElement,
        preferredAppKitPoint: CGPoint?,
        bringToFront: Bool
    ) throws -> SmoothDockingSession {
        if isMinimized(window) {
            DebugLog.debug(
                DebugLog.windows,
                "Restoring minimized window before smooth docking for \(application.bundleIdentifier ?? application.localizedName ?? "unknown")"
            )
            try setMinimized(false, for: window)
        }

        if bringToFront {
            try bringWindowToFront(window, for: application)
        }

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw WindowManagerError.unableToResolveScreen
        }

        logScreenConfiguration(screens, preferredAppKitPoint: preferredAppKitPoint)

        let screenGeometry = ScreenGeometry(screenFrames: screens.map(\.frame))
        let currentAXFrame = try frame(of: window)
        let currentFrame = screenGeometry.appKitFrame(fromAXFrame: currentAXFrame)
        let dockingResolver = SmoothDockingResolver()
        guard let desktopFrame = dockingResolver.desktopFrame(
            preferredPoint: preferredAppKitPoint,
            currentWindowFrame: currentFrame,
            screens: screens
        ) else {
            throw WindowManagerError.unableToResolveScreen
        }

        let sizeConstraints = smoothDockingSizeConstraints(for: application, window: window)
        DebugLog.debug(
            DebugLog.windows,
            "Prepared smooth docking session for \(application.bundleIdentifier ?? application.localizedName ?? "unknown"): currentFrame = \(NSStringFromRect(currentFrame)), desktopFrame = \(NSStringFromRect(desktopFrame)), sizeConstraints = \(smoothDockingSizeConstraintDescription(sizeConstraints))"
        )

        return SmoothDockingSession(
            originalFrame: currentFrame,
            desktopFrame: desktopFrame,
            baseSizeConstraints: sizeConstraints,
            loadCurrentFrame: { [window] in
                guard let currentAXFrame = self.readFrameBestEffort(of: window, context: "during smooth docking") else {
                    return nil
                }

                return screenGeometry.appKitFrame(fromAXFrame: currentAXFrame)
            },
            applyFrame: { [window] targetAppKitFrame in
                let targetAXFrame = screenGeometry.axFrame(fromAppKitFrame: targetAppKitFrame.integral)
                let outcome = try self.setFrame(targetAXFrame, for: window)

                let appliedAXFrame: CGRect
                switch outcome {
                case .exact(let frame), .constrained(let frame):
                    appliedAXFrame = frame
                }

                return screenGeometry.appKitFrame(fromAXFrame: appliedAXFrame)
            },
            recordConstraintObservation: { [weak self, application, window] action, requestedFrame, appliedFrame in
                self?.recordObservedConstraintIfNeeded(
                    requestedFrame: requestedFrame,
                    appliedFrame: appliedFrame,
                    action: action,
                    application: application,
                    window: window
                )
            }
        )
    }

    private func smoothDockingSizeConstraints(
        for application: NSRunningApplication,
        window: AXUIElement
    ) -> SmoothDockingSizeConstraints {
        let axConstraints = smoothDockingAXSizeConstraints(for: window)
        guard
            let observedBounds = observedWindowConstraintStore.sharedSizeBounds(
                for: observationKey(for: application, window: window)
            )
        else {
            return axConstraints
        }

        return axConstraints.merged(with: SmoothDockingSizeConstraints(sizeBounds: observedBounds))
    }

    private func smoothDockingAXSizeConstraints(for window: AXUIElement) -> SmoothDockingSizeConstraints {
        let minimumSize = AXAttributeReader.size("AXMinSize" as CFString, from: window)
        let maximumSize = AXAttributeReader.size("AXMaxSize" as CFString, from: window)

        return SmoothDockingSizeConstraints(
            minimumWidth: normalizedSmoothDockingConstraintDimension(minimumSize?.width),
            maximumWidth: normalizedSmoothDockingConstraintDimension(maximumSize?.width),
            minimumHeight: normalizedSmoothDockingConstraintDimension(minimumSize?.height),
            maximumHeight: normalizedSmoothDockingConstraintDimension(maximumSize?.height)
        )
    }

    private func normalizedSmoothDockingConstraintDimension(_ value: CGFloat?) -> CGFloat? {
        guard let value, value.isFinite, value > 1 else {
            return nil
        }

        return value
    }

    private func smoothDockingSizeConstraintDescription(_ constraints: SmoothDockingSizeConstraints) -> String {
        "[minWidth=\(formattedConstraintValue(constraints.minimumWidth)), maxWidth=\(formattedConstraintValue(constraints.maximumWidth)), minHeight=\(formattedConstraintValue(constraints.minimumHeight)), maxHeight=\(formattedConstraintValue(constraints.maximumHeight))]"
    }

    private func observedConstraintObservation(
        for application: NSRunningApplication,
        window: AXUIElement,
        action: WindowAction
    ) -> WindowActionPreview.Observation? {
        observedWindowConstraintStore.observation(
            for: observationKey(for: application, window: window),
            action: action
        )
    }

    private func recordObservedConstraintBounds(
        _ sizeBounds: WindowActionPreview.SizeBounds,
        horizontalAnchor: WindowActionPreview.AxisAnchor?,
        verticalAnchor: WindowActionPreview.AxisAnchor?,
        action: WindowAction,
        for application: NSRunningApplication,
        window: AXUIElement
    ) {
        observedWindowConstraintStore.record(
            sizeBounds: sizeBounds,
            horizontalAnchor: horizontalAnchor,
            verticalAnchor: verticalAnchor,
            action: action,
            for: observationKey(for: application, window: window)
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

    private func baseObservationKey(for application: NSRunningApplication) -> String {
        if let bundleIdentifier = application.bundleIdentifier, !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }

        if let localizedName = application.localizedName, !localizedName.isEmpty {
            return "name:\(localizedName)"
        }

        return "pid:\(application.processIdentifier)"
    }

    private func observationKey(
        for application: NSRunningApplication,
        window: AXUIElement
    ) -> String {
        WindowConstraintObservationScope(
            applicationKey: baseObservationKey(for: application),
            role: readOptionalAXAttribute(
                context: "AXRole in observationKey",
                fallback: nil as String?
            ) {
                try stringAttribute(kAXRoleAttribute as CFString, from: window)
            },
            subrole: readOptionalAXAttribute(
                context: "AXSubrole in observationKey",
                fallback: nil as String?
            ) {
                try stringAttribute(kAXSubroleAttribute as CFString, from: window)
            },
            title: readOptionalAXAttribute(
                context: "AXTitle in observationKey",
                fallback: nil as String?
            ) {
                try stringAttribute(kAXTitleAttribute as CFString, from: window)
            }
        ).storageKey
    }

    private func recordObservedConstraintIfNeeded(
        requestedFrame: CGRect,
        appliedFrame: CGRect,
        action: WindowAction,
        application: NSRunningApplication,
        window: AXUIElement
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
            for: application,
            window: window
        )
        DebugLog.debug(
            DebugLog.windows,
            "Recorded observed window constraint bounds \(constraintBoundsDescription(previewObservation.sizeBounds)) for \(application.bundleIdentifier ?? application.localizedName ?? "unknown") after requested \(NSStringFromRect(requestedFrame)) applied as \(NSStringFromRect(appliedFrame)); horizontalAnchor = \(String(describing: previewObservation.horizontalAnchor)), verticalAnchor = \(String(describing: previewObservation.verticalAnchor))"
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

        if matchesLeadingEdge && !matchesTrailingEdge {
            return .leadingEdge
        }
        if matchesTrailingEdge && !matchesLeadingEdge {
            return .trailingEdge
        }
        if matchesCenter {
            return .centered
        }
        return nil
    }

    private func constraintBoundsDescription(_ sizeBounds: WindowActionPreview.SizeBounds) -> String {
        "[minWidth=\(formattedConstraintValue(sizeBounds.minimumWidth)), maxWidth=\(formattedConstraintValue(sizeBounds.maximumWidth)), minHeight=\(formattedConstraintValue(sizeBounds.minimumHeight)), maxHeight=\(formattedConstraintValue(sizeBounds.maximumHeight))]"
    }

    private func formattedConstraintValue(_ value: CGFloat?) -> String {
        guard let value else {
            return "nil"
        }

        return String(format: "%.1f", value)
    }

    func minimizeVisibleWindow(
        of target: InteractionTarget,
        preferredAppKitPoint: CGPoint? = nil
    ) throws -> Bool {
        try minimizeVisibleWindowWithResult(
            of: target,
            preferredAppKitPoint: preferredAppKitPoint
        ).performed
    }

    func minimizeVisibleWindowWithResult(
        of target: InteractionTarget,
        preferredAppKitPoint: CGPoint? = nil
    ) throws -> MinimizeVisibleWindowResult {
        try requireAccessibilityPermission()

        DebugLog.info(DebugLog.windows, "Attempting to minimize a visible window for \(target.logDescription)")

        let resolvedApplication = try resolvedApplicationContext(for: target)

        if preferredAppKitPoint != nil || prefersWindowScopedAction(target) {
            DebugLog.info(
                DebugLog.windows,
                "Attempting to minimize pointed window for \(target.logDescription) at \(preferredAppKitPoint.map(NSStringFromPoint) ?? "<target-window>")"
            )
            let targetWindow = try preferredWindowActionTarget(for: target, preferredAppKitPoint: preferredAppKitPoint)

            do {
                let reference = minimizedWindowReference(
                    for: targetWindow,
                    application: resolvedApplication.application,
                    fallbackIdentity: resolvedApplication.identity
                )
                try setMinimized(true, for: targetWindow)
                cycleSessions.invalidate(for: resolvedApplication.application.processIdentifier)
                DebugLog.info(DebugLog.windows, "Minimized pointed window for \(target.logDescription)")
                return MinimizeVisibleWindowResult(performed: true, reference: reference)
            } catch {
                DebugLog.debug(
                    DebugLog.windows,
                    "Pointed window was not minimizable for \(target.logDescription): \(windowSummary([targetWindow]))"
                )
                return MinimizeVisibleWindowResult(performed: false, reference: nil)
            }
        }

        let windows = try orderedVisibleWindowElements(
            in: resolvedApplication.application,
            appElement: resolvedApplication.appElement
        )
        DebugLog.debug(
            DebugLog.windows,
            "Visible window candidates for \(target.logDescription): [\(windowSummary(windows))]"
        )

        guard !windows.isEmpty else {
            DebugLog.debug(DebugLog.windows, "No visible window found to minimize for \(target.logDescription)")
            return MinimizeVisibleWindowResult(performed: false, reference: nil)
        }

        for targetWindow in windows {
            do {
                let reference = minimizedWindowReference(
                    for: targetWindow,
                    application: resolvedApplication.application,
                    fallbackIdentity: resolvedApplication.identity
                )
                try setMinimized(true, for: targetWindow)
                cycleSessions.invalidate(for: resolvedApplication.application.processIdentifier)
                DebugLog.info(DebugLog.windows, "Minimized one visible window for \(target.logDescription)")
                return MinimizeVisibleWindowResult(performed: true, reference: reference)
            } catch {
                DebugLog.debug(
                    DebugLog.windows,
                    "Visible window candidate was not minimizable for \(target.logDescription): \(windowSummary([targetWindow]))"
                )
            }
        }

        DebugLog.debug(DebugLog.windows, "No minimizable visible window found for \(target.logDescription)")
        return MinimizeVisibleWindowResult(performed: false, reference: nil)
    }

    private func minimizedWindowReference(
        for window: AXUIElement,
        application: NSRunningApplication,
        fallbackIdentity: AppIdentity
    ) -> MinimizedWindowReference? {
        guard let windowIdentity = registry.windowIdentity(for: window, in: application) else {
            return nil
        }

        return MinimizedWindowReference(
            appIdentity: AppIdentity(application: application) ?? fallbackIdentity,
            windowIdentity: windowIdentity
        )
    }

    func restoreMinimizedWindow(of application: AppIdentity) throws -> Bool {
        try requireAccessibilityPermission()

        DebugLog.info(DebugLog.windows, "Attempting to restore a minimized window for \(application.logDescription)")

        let app = try runningApplication(matching: application)
        let appElement = AXAttributeReader.applicationElement(for: app.processIdentifier)
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

    func restoreWindow(_ windowIdentity: WindowIdentity) throws -> Bool {
        try requireAccessibilityPermission()

        let resolvedWindow = try resolvedWindowContext(for: windowIdentity)
        guard isMinimized(resolvedWindow.window) else {
            try bringWindowToFront(resolvedWindow.window, for: resolvedWindow.application)
            return true
        }

        try setMinimized(false, for: resolvedWindow.window)
        try bringWindowToFront(resolvedWindow.window, for: resolvedWindow.application)
        cycleSessions.invalidate(for: resolvedWindow.application.processIdentifier)
        return true
    }

    func restoreDockItem(_ handle: DockMinimizedItemHandle) throws -> Bool {
        try requireAccessibilityPermission()

        guard dockTargetResolver.pressDockMinimizedItem(handle) else {
            throw WindowManagerError.unableToPerformAction
        }

        return true
    }

    func toggleFullScreenWindow(
        of target: InteractionTarget,
        preferredAppKitPoint: CGPoint? = nil
    ) throws -> Bool {
        try requireAccessibilityPermission()

        DebugLog.info(DebugLog.windows, "Attempting to toggle full screen for a visible window of \(target.logDescription)")

        let resolvedApplication = try resolvedApplicationContext(for: target)

        if preferredAppKitPoint != nil || prefersWindowScopedAction(target) {
            let targetWindow = try preferredWindowActionTarget(for: target, preferredAppKitPoint: preferredAppKitPoint)

            try bringWindowToFront(targetWindow, for: resolvedApplication.application)
            let shouldEnterFullScreen = !isFullScreen(targetWindow)
            try setFullScreen(shouldEnterFullScreen, for: targetWindow)

            cycleSessions.invalidate(for: resolvedApplication.application.processIdentifier)
            DebugLog.info(
                DebugLog.windows,
                "\(shouldEnterFullScreen ? "Entered" : "Exited") full screen for pointed window of \(target.logDescription)"
            )
            return true
        }

        let windows = try orderedVisibleWindowElements(
            in: resolvedApplication.application,
            appElement: resolvedApplication.appElement
        )
        guard !windows.isEmpty else {
            DebugLog.debug(DebugLog.windows, "No visible window found to toggle full screen for \(target.logDescription)")
            return false
        }

        for targetWindow in windows {
            do {
                try bringWindowToFront(targetWindow, for: resolvedApplication.application)
                let shouldEnterFullScreen = !isFullScreen(targetWindow)
                try setFullScreen(shouldEnterFullScreen, for: targetWindow)

                cycleSessions.invalidate(for: resolvedApplication.application.processIdentifier)
                DebugLog.info(
                    DebugLog.windows,
                    "\(shouldEnterFullScreen ? "Entered" : "Exited") full screen for one visible window of \(target.logDescription)"
                )
                return true
            } catch {
                DebugLog.debug(
                    DebugLog.windows,
                    "Visible window candidate could not toggle full screen for \(target.logDescription): \(windowSummary([targetWindow]))"
                )
            }
        }

        DebugLog.debug(DebugLog.windows, "No full-screen-toggle-capable visible window found for \(target.logDescription)")
        return false
    }

    func exitFullScreenWindow(
        of target: InteractionTarget,
        preferredAppKitPoint: CGPoint? = nil
    ) throws -> Bool {
        try requireAccessibilityPermission()

        DebugLog.info(DebugLog.windows, "Attempting to exit full screen for a visible window of \(target.logDescription)")

        let resolvedApplication = try resolvedApplicationContext(for: target)

        if preferredAppKitPoint != nil || prefersWindowScopedAction(target) {
            let targetWindow = try preferredWindowActionTarget(for: target, preferredAppKitPoint: preferredAppKitPoint)

            try bringWindowToFront(targetWindow, for: resolvedApplication.application)
            guard isFullScreen(targetWindow) else {
                DebugLog.debug(DebugLog.windows, "Pointed window is not full screen for \(target.logDescription); nothing to exit")
                return false
            }

            try setFullScreen(false, for: targetWindow)
            cycleSessions.invalidate(for: resolvedApplication.application.processIdentifier)
            DebugLog.info(DebugLog.windows, "Exited full screen for pointed window of \(target.logDescription)")
            return true
        }

        let windows = try orderedVisibleWindowElements(
            in: resolvedApplication.application,
            appElement: resolvedApplication.appElement
        )
        guard !windows.isEmpty else {
            DebugLog.debug(DebugLog.windows, "No visible window found to exit full screen for \(target.logDescription)")
            return false
        }

        for targetWindow in windows {
            guard isFullScreen(targetWindow) else {
                continue
            }

            do {
                try bringWindowToFront(targetWindow, for: resolvedApplication.application)
                try setFullScreen(false, for: targetWindow)
                cycleSessions.invalidate(for: resolvedApplication.application.processIdentifier)
                DebugLog.info(DebugLog.windows, "Exited full screen for one visible window of \(target.logDescription)")
                return true
            } catch {
                DebugLog.debug(
                    DebugLog.windows,
                    "Visible full screen window candidate could not exit full screen for \(target.logDescription): \(windowSummary([targetWindow]))"
                )
            }
        }

        DebugLog.debug(DebugLog.windows, "No full screen visible window found to exit for \(target.logDescription)")
        return false
    }

    func closeVisibleWindow(of application: AppIdentity) throws -> Bool {
        try requireAccessibilityPermission()

        DebugLog.info(DebugLog.windows, "Attempting to close a visible window for \(application.logDescription)")

        let app = try runningApplication(matching: application)
        let appElement = AXAttributeReader.applicationElement(for: app.processIdentifier)
        let windows = try orderedVisibleWindowElements(in: app, appElement: appElement)
        DebugLog.debug(
            DebugLog.windows,
            "Close-window candidates for \(application.logDescription): [\(windowSummary(windows))]"
        )

        guard !windows.isEmpty else {
            DebugLog.debug(DebugLog.windows, "No visible window found to close for \(application.logDescription)")
            return false
        }

        for (index, targetWindow) in windows.enumerated() {
            if try closeWindow(targetWindow, owningApp: app) {
                cycleSessions.invalidate(for: app.processIdentifier)
                let message = index == 0
                    ? "Closed one visible window for \(application.logDescription)"
                    : "Closed one fallback visible window for \(application.logDescription)"
                DebugLog.info(DebugLog.windows, message)
                return true
            }
        }

        DebugLog.debug(DebugLog.windows, "No closeable visible window found for \(application.logDescription)")
        return false
    }

    func closeWindow(
        of target: InteractionTarget,
        preferredAppKitPoint: CGPoint?
    ) throws -> Bool {
        try requireAccessibilityPermission()

        switch target {
        case .unresolvedDockMinimizedItem:
            return false
        case .window(let windowIdentity, _, _) where preferredAppKitPoint == nil:
            return try closeWindow(windowIdentity)
        case .application(let application, _):
            if let preferredAppKitPoint {
                let app = try runningApplication(matching: application)
                let appElement = AXAttributeReader.applicationElement(for: app.processIdentifier)
                DebugLog.info(
                    DebugLog.windows,
                    "Attempting to close pointed window for \(application.logDescription) at \(NSStringFromPoint(preferredAppKitPoint))"
                )
                let targetWindow = try preferredWindowActionTarget(
                    in: app,
                    appElement: appElement,
                    preferredAppKitPoint: preferredAppKitPoint
                )
                if try closeWindow(targetWindow, owningApp: app) {
                    cycleSessions.invalidate(for: app.processIdentifier)
                    DebugLog.info(DebugLog.windows, "Closed pointed window for \(application.logDescription)")
                    return true
                }
                DebugLog.debug(DebugLog.windows, "Pointed window was not closeable for \(application.logDescription)")
                return false
            }

            if try closeVisibleWindow(of: application) {
                return true
            }
            return try closeRecentWindow(of: application)
        case .window(let windowIdentity, let appIdentity, _):
            if let preferredAppKitPoint {
                let app = try runningApplication(matching: appIdentity, preferredProcessIdentifier: target.processIdentifier)
                let appElement = AXAttributeReader.applicationElement(for: app.processIdentifier)
                let targetWindow = try preferredWindowActionTarget(
                    in: app,
                    appElement: appElement,
                    preferredAppKitPoint: preferredAppKitPoint
                )
                return try closeWindow(targetWindow, owningApp: app)
            }

            return try closeWindow(windowIdentity)
        }
    }

    func closeWindow(_ windowIdentity: WindowIdentity) throws -> Bool {
        let resolvedWindow = try resolvedWindowContext(for: windowIdentity)
        if try closeWindow(resolvedWindow.window, owningApp: resolvedWindow.application) {
            cycleSessions.invalidate(for: resolvedWindow.application.processIdentifier)
            return true
        }

        return false
    }

    private func closeRecentWindow(of application: AppIdentity) throws -> Bool {
        let app = try runningApplication(matching: application)
        let appElement = AXAttributeReader.applicationElement(for: app.processIdentifier)
        let windows = try recentWindowCandidates(in: app, appElement: appElement)
        DebugLog.debug(
            DebugLog.windows,
            "Recent-window fallback candidates for \(application.logDescription): [\(windowSummary(windows))]"
        )

        guard !windows.isEmpty else {
            DebugLog.debug(DebugLog.windows, "No recent window candidate found for \(application.logDescription)")
            return false
        }

        for (index, targetWindow) in windows.enumerated() {
            if try closeWindow(targetWindow, owningApp: app) {
                cycleSessions.invalidate(for: app.processIdentifier)
                let message = index == 0
                    ? "Closed recent-window fallback target for \(application.logDescription)"
                    : "Closed fallback recent-window candidate for \(application.logDescription)"
                DebugLog.info(DebugLog.windows, message)
                return true
            }
        }

        DebugLog.debug(DebugLog.windows, "No closeable recent-window fallback candidate found for \(application.logDescription)")
        return false
    }

    func quitApplication(matching target: AppIdentity) throws -> Bool {
        try requireAccessibilityPermission()

        let app = try runningApplication(matching: target)
        guard app.terminate() else {
            throw WindowManagerError.unableToQuitApplication
        }

        cycleSessions.invalidate(for: app.processIdentifier)
        DebugLog.info(DebugLog.windows, "Terminated app for target \(target.logDescription)")
        return true
    }

    func cycleVisibleWindows(
        of target: InteractionTarget,
        direction: WindowCycleDirection,
        preferredAppKitPoint: CGPoint? = nil
    ) throws -> Bool {
        try requireAccessibilityPermission()

        DebugLog.info(
            DebugLog.windows,
            "Attempting to cycle visible windows \(direction == .forward ? "forward" : "backward") for \(target.logDescription)"
        )

        let resolvedApplication = try resolvedApplicationContext(for: target)
        let app = resolvedApplication.application
        let appElement = AXAttributeReader.applicationElement(for: app.processIdentifier)
        let currentWindow: AXUIElement?
        if let preferredAppKitPoint {
            currentWindow = try preferredWindowActionTarget(for: target, preferredAppKitPoint: preferredAppKitPoint)
        } else if prefersWindowScopedAction(target) {
            currentWindow = try preferredWindowActionTarget(for: target, preferredAppKitPoint: nil)
        } else {
            currentWindow = preferredCycleReferenceWindow(in: appElement)
        }

        try focusAdjacentVisibleWindow(
            in: app,
            appElement: appElement,
            currentWindow: currentWindow,
            direction: direction
        )
        return true
    }

    func runningApplication(
        matching target: AppIdentity,
        preferredProcessIdentifier: pid_t? = nil
    ) throws -> NSRunningApplication {
        if let application = registry.runningApplication(
            matching: target,
            preferredProcessIdentifier: preferredProcessIdentifier
        ) {
            return application
        }

        registry.refreshRunningApplications()
        if let application = registry.runningApplication(
            matching: target,
            preferredProcessIdentifier: preferredProcessIdentifier
        ) {
            return application
        }

        DebugLog.error(
            DebugLog.windows,
            "Unable to find running application for target \(target.logDescription); pid=\(target.processIdentifier)"
        )
        throw WindowManagerError.noFrontmostApplication
    }

    private func recentWindowCandidates(
        in app: NSRunningApplication,
        appElement: AXUIElement
    ) throws -> [AXUIElement] {
        let allWindows = try windowElements(in: appElement)
        guard !allWindows.isEmpty else {
            return []
        }

        let visibleWindows = allWindows.filter { !isMinimized($0) }
        var orderedVisibleWindows: [AXUIElement] = []
        if !visibleWindows.isEmpty {
            orderedVisibleWindows = try orderedVisibleWindowElements(in: app, appElement: appElement)
        }

        var candidates: [AXUIElement] = []

        if let referenceWindow = preferredCycleReferenceWindow(in: appElement) {
            candidates.append(referenceWindow)
        }

        func appendUniqueWindows(_ windows: [AXUIElement]) {
            for window in windows where !candidates.contains(where: { sameWindow($0, window) }) {
                candidates.append(window)
            }
        }

        appendUniqueWindows(orderedVisibleWindows)
        appendUniqueWindows(allWindows)

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

        if !application.isHidden {
            score += 20
        }

        if RunningApplicationIdentity.isLikelyHelperProcess(application) {
            score -= allowHelperWithoutWindows ? 80 : 220
            if !hasWindow {
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

        let appElement = AXAttributeReader.applicationElement(for: application.processIdentifier)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)

        let windows = value as? [AnyObject] ?? []
        let hasWindow = error == .success && !windows.isEmpty
        windowPresenceCache[application.processIdentifier] = hasWindow
        return hasWindow
    }

    func focusedWindowElement(in appElement: AXUIElement) throws -> AXUIElement {
        guard let focusedWindowElement = AXAttributeReader.element(
            kAXFocusedWindowAttribute as CFString,
            from: appElement
        ) else {
            DebugLog.error(DebugLog.accessibility, "Failed to read focused window")
            throw WindowManagerError.noFocusedWindow
        }

        DebugLog.debug(DebugLog.windows, "Resolved focused window: \(windowSummary([focusedWindowElement]))")
        return focusedWindowElement
    }

    private func mainWindowElement(in appElement: AXUIElement) throws -> AXUIElement {
        guard let mainWindowElement = AXAttributeReader.element(
            kAXMainWindowAttribute as CFString,
            from: appElement
        ) else {
            DebugLog.error(DebugLog.accessibility, "Failed to read main window")
            throw WindowManagerError.noFocusedWindow
        }

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

        guard windows.count > 1 else {
            cycleSessions.invalidate(for: app.processIdentifier)
            throw WindowManagerError.noAlternateWindow
        }

        guard let targetWindow = cycleSessions.nextTarget(
            for: app.processIdentifier,
            liveOrder: windows,
            currentWindow: currentWindow,
            direction: direction
        ) else {
            throw WindowManagerError.noAlternateWindow
        }

        DebugLog.debug(
            DebugLog.windows,
            "Selected cycle target for \(app.localizedName ?? "unknown") from \(currentWindow.map { windowSummary([$0]) } ?? "<none>") to \(windowSummary([targetWindow])) within [\(windowSummary(windows))]"
        )

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

        let appElement = AXAttributeReader.applicationElement(for: app.processIdentifier)
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

        if !initialWriteResult.succeeded {
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

        if !framesAreClose(appliedFrame, frame) {
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

            if !fallbackWriteResult.succeeded {
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
        let materiallyDifferent = !framesAreClose(appliedFrame, targetFrame, tolerance: tolerance)
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

    private func clampFrame(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        var clamped = frame

        if clamped.width > visibleFrame.width {
            clamped.size.width = visibleFrame.width
        }
        if clamped.height > visibleFrame.height {
            clamped.size.height = visibleFrame.height
        }

        if clamped.minX < visibleFrame.minX {
            clamped.origin.x = visibleFrame.minX
        }
        if clamped.maxX > visibleFrame.maxX {
            clamped.origin.x = visibleFrame.maxX - clamped.width
        }
        if clamped.minY < visibleFrame.minY {
            clamped.origin.y = visibleFrame.minY
        }
        if clamped.maxY > visibleFrame.maxY {
            clamped.origin.y = visibleFrame.maxY - clamped.height
        }

        return clamped.integral
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
            {
                let appName = application.localizedName ?? "unknown"
                let bundleID = application.bundleIdentifier ?? "unknown"
                return "Resolved geometry for action \(String(describing: action)) in app \(appName) [\(bundleID)]: title=\(title), role=\(role), subrole=\(subrole), main=\(isMain), focused=\(isFocused), minimized=\(isMinimized), AX frame=\(NSStringFromRect(axFrame)), AppKit frame=\(NSStringFromRect(appKitFrame))"
            }()
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
        guard !orderedWindowDescriptors.isEmpty else {
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

        if !sameWindowSequence(windows, orderedWindows) {
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
        // CGWindowList gives a more reliable front-to-back order than AX for
        // many apps, so we use it as an ordering hint and match back by title/frame.
        windowOrderingSnapshotCache.frontToBackWindowDescriptors(
            forOwnerProcessIdentifier: processIdentifier
        )
    }

    private func windowDescriptor(for window: AXUIElement) throws -> WindowOrderDescriptor {
        WindowOrderDescriptor(
            windowID: AXAttributeReader.windowIdentifier(of: window),
            frame: try frame(of: window)
        )
    }

    private func sameWindowSequence(_ lhs: [AXUIElement], _ rhs: [AXUIElement]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { sameWindow($0, $1) }
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

private extension DisplayMoveDirection {
    var logDescription: String {
        switch self {
        case .next:
            "next"
        case .previous:
            "previous"
        }
    }
}

private extension WindowAction {
    var displayMoveDirection: DisplayMoveDirection {
        switch self {
        case .moveToNextDisplay:
            .next
        case .moveToPreviousDisplay:
            .previous
        case .leftHalf,
             .rightHalf,
             .maximize,
             .center,
             .topLeftQuarter,
             .topRightQuarter,
             .bottomLeftQuarter,
             .bottomRightQuarter,
             .minimize,
             .closeWindow,
             .closeTab,
             .quitApplication,
             .cycleSameAppWindowsForward,
             .cycleSameAppWindowsBackward,
             .toggleFullScreen,
             .exitFullScreen:
            preconditionFailure("Display move direction requested for non-display action")
        }
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
    case noOtherDisplay

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
        case .noOtherDisplay:
            return L10n.string("error.no_other_display")
        }
    }
}
