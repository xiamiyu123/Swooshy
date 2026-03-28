import AppKit
import ApplicationServices
import CoreGraphics

enum WindowCycleDirection {
    case forward
    case backward
}

@MainActor
protocol WindowManaging {
    func perform(_ action: WindowAction, layoutEngine: WindowLayoutEngine) throws
}

@MainActor
struct WindowManager: WindowManaging {
    private let windowOrdering = WindowOrdering()
    private let cycleSessions = WindowCycleSessionStore()

    func perform(_ action: WindowAction, layoutEngine: WindowLayoutEngine) throws {
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
        case .leftHalf, .rightHalf, .maximize, .center:
            break
        case .quitApplication:
            return
        }

        let screens = NSScreen.screens
        let screenGeometry = ScreenGeometry(screenFrames: screens.map(\.frame))
        let focusedWindow = try focusedWindowElement(in: appElement)
        let currentFrame = screenGeometry.appKitFrame(
            fromAXFrame: try frame(of: focusedWindow)
        )
        let screenFrames = screens.map(\.visibleFrame)

        guard
            let currentScreenFrame = layoutEngine.screenContainingMost(
                of: currentFrame,
                in: screenFrames
            )
        else {
            throw WindowManagerError.unableToResolveScreen
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

        try setFrame(
            screenGeometry.axFrame(fromAppKitFrame: targetFrame),
            for: focusedWindow
        )
    }

    private func frontmostApplication() throws -> NSRunningApplication {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw WindowManagerError.noFrontmostApplication
        }

        return app
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
            _ = app.activate(options: [.activateAllWindows])
            DebugLog.debug(DebugLog.windows, "No minimized window found for \(application.logDescription); activated app instead")
            return false
        }

        try setMinimized(false, for: targetWindow)
        try bringWindowToFront(targetWindow, for: app)
        cycleSessions.invalidate(for: app.processIdentifier)
        DebugLog.info(DebugLog.windows, "Restored and raised one minimized window for \(application.logDescription)")
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

    private func runningApplication(matching target: DockApplicationTarget) throws -> NSRunningApplication {
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

        let targetAliases = normalizedAliases(from: target.aliases + [target.dockItemName, target.resolvedApplicationName])
        let aliasCandidates = NSWorkspace.shared.runningApplications.filter { application in
            let aliases = normalizedAliases(from: Array(applicationAliases(for: application)))
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
        candidates.max { lhs, rhs in
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

        if isLikelyHelperProcess(application) {
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
        if isLikelyHelperProcess(application) {
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

    private func applicationAliases(for application: NSRunningApplication) -> Set<String> {
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

        return aliases
    }

    private func normalizedAliases(from aliases: [String]) -> Set<String> {
        Set(
            aliases
                .map(normalizedAlias)
                .filter { $0.isEmpty == false }
        )
    }

    private func normalizedAlias(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private func focusedWindowElement(in appElement: AXUIElement) throws -> AXUIElement {
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

        DebugLog.debug(DebugLog.windows, "Resolved focused window: \(windowSummary([unsafeDowncast(focusedWindow, to: AXUIElement.self)]))")
        return unsafeDowncast(focusedWindow, to: AXUIElement.self)
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

        DebugLog.debug(DebugLog.windows, "Resolved main window: \(windowSummary([unsafeDowncast(mainWindow, to: AXUIElement.self)]))")
        return unsafeDowncast(mainWindow, to: AXUIElement.self)
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

        if minimized, let minimizeButton = try? childElement(
            attribute: kAXMinimizeButtonAttribute as CFString,
            from: window
        ) {
            try performAction(kAXPressAction as CFString, on: minimizeButton)
            return
        }

        throw WindowManagerError.unableToPerformAction
    }

    private func closeWindow(
        _ window: AXUIElement,
        owningApp: NSRunningApplication
    ) throws -> Bool {
        _ = owningApp.activate(options: [.activateAllWindows])
        try? performAction(kAXRaiseAction as CFString, on: window)
        try? setBooleanAttribute(kAXMainAttribute as CFString, value: true, on: window)
        try? setBooleanAttribute(kAXFocusedAttribute as CFString, value: true, on: window)

        if
            let closeButton = try? childElement(attribute: kAXCloseButtonAttribute as CFString, from: window),
            tryPerformAction(kAXPressAction as CFString, on: closeButton, context: "AXCloseButton")
        {
            DebugLog.debug(DebugLog.windows, "Closed window via AXCloseButton: \(windowSummary([window]))")
            return true
        }

        if tryPerformAction("AXClose" as CFString, on: window, context: "AXClose") {
            DebugLog.debug(DebugLog.windows, "Closed window via AXClose action: \(windowSummary([window]))")
            return true
        }

        // Some apps expose only Press on the close control but not AXClose on the window node.
        if
            let closeButton = try? childElement(attribute: kAXCloseButtonAttribute as CFString, from: window),
            tryPerformAction(kAXPressAction as CFString, on: closeButton, context: "AXCloseButtonRetry")
        {
            DebugLog.debug(DebugLog.windows, "Closed window via AXCloseButton retry: \(windowSummary([window]))")
            return true
        }

        DebugLog.debug(DebugLog.windows, "Unable to close window via AXCloseButton/AXClose: \(windowSummary([window]))")
        return false
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

        let currentDescriptor = currentWindow.flatMap { try? windowDescriptor(for: $0) }
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
        if let focusedWindow = try? focusedWindowElement(in: appElement) {
            return focusedWindow
        }

        if let mainWindow = try? mainWindowElement(in: appElement) {
            return mainWindow
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
        _ = app.activate(options: [.activateAllWindows])

        // Restored windows can take a moment to become orderable, so raise twice
        // around the focus attributes to make the behavior more reliable.
        try? performAction(kAXRaiseAction as CFString, on: window)
        try setBooleanAttribute(kAXMainAttribute as CFString, value: true, on: window)
        try setBooleanAttribute(kAXFocusedAttribute as CFString, value: true, on: window)
        try performAction(kAXRaiseAction as CFString, on: window)
        NSApp.activate(ignoringOtherApps: true)
        DebugLog.debug(DebugLog.windows, "Finished bring-to-front sequence for window \(windowSummary([window]))")
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
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard error == .success, let child = value else {
            throw WindowManagerError.unableToPerformAction
        }

        return unsafeDowncast(child, to: AXUIElement.self)
    }

    private func setFrame(_ frame: CGRect, for window: AXUIElement) throws {
        var size = CGSize(width: max(1, frame.width), height: max(1, frame.height))
        var origin = CGPoint(x: frame.origin.x, y: frame.origin.y)

        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw WindowManagerError.unableToSetFrame
        }

        guard let positionValue = AXValueCreate(.cgPoint, &origin) else {
            throw WindowManagerError.unableToSetFrame
        }

        let sizeError = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let positionError = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)

        guard sizeError == .success, positionError == .success else {
            DebugLog.error(
                DebugLog.accessibility,
                "Failed to set frame. Size error = \(sizeError.rawValue), position error = \(positionError.rawValue)"
            )
            throw WindowManagerError.unableToSetFrame
        }
    }

    private func pointAttribute(_ attribute: CFString, from element: AXUIElement) throws -> CGPoint {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard error == .success, let axValue = value else {
            throw WindowManagerError.unableToReadWindowFrame
        }

        let pointValue = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(pointValue) == .cgPoint else {
            throw WindowManagerError.unableToReadWindowFrame
        }

        var point = CGPoint.zero
        guard AXValueGetValue(pointValue, .cgPoint, &point) else {
            throw WindowManagerError.unableToReadWindowFrame
        }

        return point
    }

    private func sizeAttribute(_ attribute: CFString, from element: AXUIElement) throws -> CGSize {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard error == .success, let axValue = value else {
            throw WindowManagerError.unableToReadWindowFrame
        }

        let sizeValue = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(sizeValue) == .cgSize else {
            throw WindowManagerError.unableToReadWindowFrame
        }

        var size = CGSize.zero
        guard AXValueGetValue(sizeValue, .cgSize, &size) else {
            throw WindowManagerError.unableToReadWindowFrame
        }

        return size
    }

    private func booleanAttribute(_ attribute: CFString, from element: AXUIElement) throws -> Bool {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard error == .success, let cfValue = value else {
            throw WindowManagerError.unableToPerformAction
        }

        guard CFGetTypeID(cfValue) == CFBooleanGetTypeID() else {
            throw WindowManagerError.unableToPerformAction
        }

        return CFBooleanGetValue((cfValue as! CFBoolean))
    }

    private func windowElements(in appElement: AXUIElement) throws -> [AXUIElement] {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)

        guard error == .success, let windows = value as? [AnyObject] else {
            DebugLog.error(DebugLog.accessibility, "Failed to enumerate windows; AX error = \(error.rawValue)")
            throw WindowManagerError.unableToEnumerateWindows
        }

        return windows.map { unsafeDowncast($0, to: AXUIElement.self) }
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
            title: (try? stringAttribute(kAXTitleAttribute as CFString, from: window)) ?? "",
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
        (try? booleanAttribute(kAXMinimizedAttribute as CFString, from: window)) ?? false
    }

    private func windowSummary(_ windows: [AXUIElement]) -> String {
        windows.map { window in
            let title = (try? stringAttribute(kAXTitleAttribute as CFString, from: window)) ?? "<untitled>"
            let minimized = ((try? booleanAttribute(kAXMinimizedAttribute as CFString, from: window)) ?? false) ? "min" : "visible"
            let frameDescription: String
            if let frame = try? frame(of: window) {
                frameDescription = NSStringFromRect(frame)
            } else {
                frameDescription = "<unknown-frame>"
            }
            return "\"\(title)\"{\(minimized), frame=\(frameDescription)}"
        }
        .joined(separator: ", ")
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) throws -> String {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard error == .success, let stringValue = value as? String else {
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
