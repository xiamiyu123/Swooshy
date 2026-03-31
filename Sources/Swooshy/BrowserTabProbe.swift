import AppKit
import ApplicationServices
import CoreGraphics

/// Detects whether the pointer is hovering over a browser tab and can simulate
/// a middle-click to close that specific tab without switching to it first.
///
/// Supported browsers: Safari, Chrome, Edge, Firefox, Arc, Brave, Vivaldi, Opera, Orion.
/// When the pointer is not over a tab, the caller should fall back to the
/// normal close-window or quit-application action.
@MainActor
enum BrowserTabProbe {
    // MARK: - Public API

    /// Returns `true` if the element at `appKitPoint` belongs to a known browser
    /// and appears to be a tab UI element.
    static func isBrowserTab(
        at appKitPoint: CGPoint,
        processIdentifier: pid_t
    ) -> Bool {
        guard let bundleIdentifier = browserBundleIdentifierIfKnown(processIdentifier: processIdentifier) else {
            DebugLog.debug(
                DebugLog.dock,
                "BrowserTabProbe skipped non-browser pid=\(processIdentifier) at \(NSStringFromPoint(appKitPoint))"
            )
            return false
        }

        let isTab = axElementIsTab(at: appKitPoint)
        DebugLog.debug(
            DebugLog.dock,
            "BrowserTabProbe result pid=\(processIdentifier) bundle=\(bundleIdentifier) point=\(NSStringFromPoint(appKitPoint)) => \(isTab ? "tab" : "not-tab")"
        )
        return isTab
    }

    /// Sends a synthetic middle-click (button 3) at the given AppKit coordinate.
    /// This closes the tab under the pointer in every major browser.
    @discardableResult
    static func simulateMiddleClick(at appKitPoint: CGPoint) -> Bool {
        let geometry = ScreenGeometry(screenFrames: NSScreen.screens.map(\.frame))
        let cgPoint = geometry.axPoint(fromAppKitPoint: appKitPoint)

        guard
            let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: .otherMouseDown,
                mouseCursorPosition: cgPoint,
                mouseButton: .center
            ),
            let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: .otherMouseUp,
                mouseCursorPosition: cgPoint,
                mouseButton: .center
            )
        else {
            DebugLog.error(DebugLog.dock, "Failed to create CGEvent for middle-click at \(NSStringFromPoint(appKitPoint))")
            return false
        }

        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)

        DebugLog.info(
            DebugLog.dock,
            "Simulated middle-click at CG point \(NSStringFromPoint(cgPoint)) (AppKit \(NSStringFromPoint(appKitPoint)))"
        )

        return true
    }

    // MARK: - Browser Identification

    private static let knownBrowserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "company.thebrowser.Browser",       // Arc
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.kagi.kagimacOS",               // Orion
        "org.chromium.Chromium",
        "com.nickvision.nickelchrome",       // Nickel
    ]

    /// Cache resolved bundle identifiers per PID to avoid repeated lookups.
    private static var bundleIdentifierCache: [pid_t: String] = [:]

    private static func browserBundleIdentifierIfKnown(processIdentifier: pid_t) -> String? {
        if let cached = bundleIdentifierCache[processIdentifier] {
            return knownBrowserBundleIdentifiers.contains(cached) ? cached : nil
        }

        guard
            let app = NSRunningApplication(processIdentifier: processIdentifier),
            let bundleIdentifier = app.bundleIdentifier
        else {
            return nil
        }

        bundleIdentifierCache[processIdentifier] = bundleIdentifier
        return knownBrowserBundleIdentifiers.contains(bundleIdentifier) ? bundleIdentifier : nil
    }

    // MARK: - AX Tab Detection

    /// Known AX roles and subroles that indicate a tab element in various browsers.
    private static let tabRoles: Set<String> = [
        "AXTab",           // Chrome, Chromium-based
        "AXRadioButton",   // Safari (with AXTabButton subrole)
    ]

    private static let tabSubroles: Set<String> = [
        "AXTabButton",  // Safari
    ]

    /// Walks upward from the deepest hit element to check if it (or any ancestor
    /// up to a small depth) has a tab-related AX role.
    private static func axElementIsTab(at appKitPoint: CGPoint) -> Bool {
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

        guard result == .success, let element = hitElement else {
            DebugLog.debug(
                DebugLog.dock,
                "BrowserTabProbe hit-test failed at AX point \(NSStringFromPoint(axPoint)) (AppKit \(NSStringFromPoint(appKitPoint))), result=\(result.rawValue)"
            )
            return false
        }

        // Walk the element and its ancestors (up to 6 levels) looking for a tab.
        var current: AXUIElement? = element
        let maxDepth = 6
        var ancestry: [String] = []

        for depth in 0..<maxDepth {
            guard let node = current else { break }

            let role = stringAttribute(kAXRoleAttribute as CFString, from: node) ?? "<nil>"
            let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: node) ?? "<nil>"
            let title = stringAttribute(kAXTitleAttribute as CFString, from: node) ?? "<nil>"
            ancestry.append("d\(depth):\(role)/\(subrole)/\(title)")

            if isTabElement(node, at: axPoint) {
                DebugLog.debug(
                    DebugLog.dock,
                    "BrowserTabProbe matched tab ancestry at AX point \(NSStringFromPoint(axPoint)): [\(ancestry.joined(separator: " -> "))]"
                )
                return true
            }

            // Walk to parent.
            var parentRef: CFTypeRef?
            let parentResult = AXUIElementCopyAttributeValue(
                node,
                kAXParentAttribute as CFString,
                &parentRef
            )

            guard parentResult == .success, let parent = parentRef else {
                DebugLog.debug(
                    DebugLog.dock,
                    "BrowserTabProbe stopped parent walk (result=\(parentResult.rawValue)) with ancestry [\(ancestry.joined(separator: " -> "))]"
                )
                break
            }

            guard CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                DebugLog.debug(
                    DebugLog.dock,
                    "BrowserTabProbe stopped parent walk due non-AX parent with ancestry [\(ancestry.joined(separator: " -> "))]"
                )
                break
            }

            current = unsafeDowncast(parent, to: AXUIElement.self)
        }

        DebugLog.debug(
            DebugLog.dock,
            "BrowserTabProbe no tab match at AX point \(NSStringFromPoint(axPoint)) (AppKit \(NSStringFromPoint(appKitPoint))); ancestry [\(ancestry.joined(separator: " -> "))]"
        )
        return false
    }

    private static func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success else {
            return nil
        }

        return valueRef as? String
    }

    private static func isTabElement(_ element: AXUIElement, at axPoint: CGPoint) -> Bool {
        // Read AXRole.
        var roleRef: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleRef
        )

        guard roleResult == .success, let role = roleRef as? String else {
            return false
        }

        // Chromium may expose a top-level AXTabGroup for the full strip, so we
        // only treat it as a tab hit when a point-contained child looks like a tab.
        if role == "AXTabGroup" {
            return tabGroupContainsTab(at: axPoint, within: element)
        }

        // Direct tab role match (Chrome, Chromium-based).
        if tabRoles.contains(role) {
            // For AXRadioButton, further verify the subrole is AXTabButton (Safari).
            if role == "AXRadioButton" {
                return subroleMatches(element)
            }
            return true
        }

        // Some browsers expose tab groups; check subrole on other roles too.
        return subroleMatches(element)
    }

    private static func tabGroupContainsTab(at axPoint: CGPoint, within tabGroup: AXUIElement) -> Bool {
        var queue: [(AXUIElement, Int)] = [(tabGroup, 0)]
        let maxDepth = 3

        while queue.isEmpty == false {
            let (node, depth) = queue.removeFirst()
            guard depth < maxDepth else { continue }

            for child in childElements(of: node) {
                if let frame = frameAttribute(from: child), frame.contains(axPoint) == false {
                    continue
                }

                let role = stringAttribute(kAXRoleAttribute as CFString, from: child) ?? ""
                let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: child) ?? ""
                let title = stringAttribute(kAXTitleAttribute as CFString, from: child) ?? ""

                if role == "AXTab" {
                    return true
                }

                if role == "AXRadioButton", tabSubroles.contains(subrole) {
                    return true
                }

                if tabSubroles.contains(subrole) {
                    return true
                }

                // Chromium fallback: tabs can appear as AXGroup with title + press action.
                if role == "AXGroup", title.isEmpty == false, supportsPressAction(child) {
                    return true
                }

                queue.append((child, depth + 1))
            }
        }

        return false
    }

    private static func childElements(of element: AXUIElement) -> [AXUIElement] {
        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        )

        guard result == .success, let children = childrenRef as? [AXUIElement] else {
            return []
        }

        return children
    }

    private static func frameAttribute(from element: AXUIElement) -> CGRect? {
        var frameRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            "AXFrame" as CFString,
            &frameRef
        )

        guard result == .success, let frameRef else {
            return nil
        }

        guard CFGetTypeID(frameRef) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(frameRef, to: AXValue.self)

        var frame = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &frame) else {
            return nil
        }

        return frame
    }

    private static func supportsPressAction(_ element: AXUIElement) -> Bool {
        var actionNamesRef: CFArray?
        let result = AXUIElementCopyActionNames(element, &actionNamesRef)
        guard result == .success, let actions = actionNamesRef as? [String] else {
            return false
        }

        return actions.contains("AXPress")
    }

    private static func subroleMatches(_ element: AXUIElement) -> Bool {
        var subroleRef: CFTypeRef?
        let subroleResult = AXUIElementCopyAttributeValue(
            element,
            kAXSubroleAttribute as CFString,
            &subroleRef
        )

        guard subroleResult == .success, let subrole = subroleRef as? String else {
            return false
        }

        return tabSubroles.contains(subrole)
    }

    // MARK: - Cache Maintenance

    static func clearCache() {
        bundleIdentifierCache.removeAll()
    }
}
