import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

/// Centralizes AX reads so callers can treat missing attributes, AX errors,
/// and unexpected value types as the same "best effort" failure case.
enum AXAttributeReader {
    enum AttributeReadResult<Value> {
        case success(Value)
        case failure(AXError)
    }

    static let defaultMessagingTimeout: Float = 0.35

    private static let windowIdentifierResolver = AXWindowIdentifierResolver()

    static func applicationElement(for processIdentifier: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(processIdentifier)
        configureMessagingTimeout(for: element)
        return element
    }

    static func systemWideElement() -> AXUIElement {
        let element = AXUIElementCreateSystemWide()
        configureMessagingTimeout(for: element)
        return element
    }

    static func configureMessagingTimeout(for element: AXUIElement) {
        _ = AXUIElementSetMessagingTimeout(element, defaultMessagingTimeout)
    }

    private static func attributeValueResult(_ attribute: CFString, from element: AXUIElement) -> AttributeReadResult<CFTypeRef> {
        configureMessagingTimeout(for: element)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success, let value else {
            return .failure(error == .success ? AXError.failure : error)
        }
        return .success(value)
    }

    private static func attributeValue(_ attribute: CFString, from element: AXUIElement) -> CFTypeRef? {
        guard case .success(let value) = attributeValueResult(attribute, from: element) else {
            return nil
        }

        return value
    }

    private static func axValue(_ attribute: CFString, from element: AXUIElement) -> AXValue? {
        guard let value = attributeValue(attribute, from: element) else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }

    static func element(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        guard let value = attributeValue(attribute, from: element) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func elements(_ attribute: CFString, from element: AXUIElement) -> [AXUIElement] {
        guard case .success(let children) = elementArray(attribute, from: element) else {
            return []
        }

        return children
    }

    static func elementArray(_ attribute: CFString, from element: AXUIElement) -> AttributeReadResult<[AXUIElement]> {
        switch attributeValueResult(attribute, from: element) {
        case .success(let value):
            guard let children = value as? [AnyObject] else {
                return .success([])
            }

            return .success(elements(from: children))
        case .failure(let error):
            return .failure(error)
        }
    }

    private static func elements(from children: [AnyObject]) -> [AXUIElement] {
        return children.compactMap { child in
            guard CFGetTypeID(child) == AXUIElementGetTypeID() else {
                return nil
            }
            return unsafeDowncast(child, to: AXUIElement.self)
        }
    }

    static func string(_ attribute: CFString, from element: AXUIElement) -> String? {
        attributeValue(attribute, from: element) as? String
    }

    static func url(_ attribute: CFString, from element: AXUIElement) -> URL? {
        guard let value = attributeValue(attribute, from: element) else { return nil }

        switch value {
        case let url as URL:
            return url
        case let url as NSURL:
            return url as URL
        case let urlString as String:
            return URL(string: urlString)
        default:
            return nil
        }
    }

    static func point(_ attribute: CFString, from element: AXUIElement) -> CGPoint? {
        guard let pointValue = axValue(attribute, from: element) else { return nil }
        guard AXValueGetType(pointValue) == .cgPoint else { return nil }

        var point = CGPoint.zero
        guard AXValueGetValue(pointValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ attribute: CFString, from element: AXUIElement) -> CGSize? {
        guard let sizeValue = axValue(attribute, from: element) else { return nil }
        guard AXValueGetType(sizeValue) == .cgSize else { return nil }

        var size = CGSize.zero
        guard AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return size
    }

    static func rect(_ attribute: CFString, from element: AXUIElement) -> CGRect? {
        guard let rectValue = axValue(attribute, from: element) else { return nil }
        guard AXValueGetType(rectValue) == .cgRect else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(rectValue, .cgRect, &rect) else { return nil }
        return rect
    }

    static func bool(_ attribute: CFString, from element: AXUIElement) -> Bool? {
        guard let value = attributeValue(attribute, from: element) else { return nil }

        switch value {
        case let boolValue as Bool:
            return boolValue
        case let numberValue as NSNumber:
            return numberValue.boolValue
        default:
            return nil
        }
    }

    static func actionNames(of element: AXUIElement) -> [String] {
        configureMessagingTimeout(for: element)
        var actionNamesRef: CFArray?
        let result = AXUIElementCopyActionNames(element, &actionNamesRef)
        guard result == .success, let actionNames = actionNamesRef as? [String] else {
            return []
        }

        return actionNames
    }

    static func processIdentifier(of element: AXUIElement) -> pid_t? {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(element, &processIdentifier) == .success else {
            return nil
        }

        return processIdentifier
    }

    static func hitElement(at appKitPoint: CGPoint) -> AXUIElement? {
        let geometry = ScreenGeometry(screenFrames: NSScreen.screens.map(\.frame))
        return hitElement(atAXPoint: geometry.axPoint(fromAppKitPoint: appKitPoint))
    }

    static func processIdentifier(at appKitPoint: CGPoint) -> pid_t? {
        guard let hitElement = hitElement(at: appKitPoint) else {
            return nil
        }

        return processIdentifier(of: hitElement)
    }

    static func hitElement(atAXPoint axPoint: CGPoint) -> AXUIElement? {
        let rootElement = systemWideElement()
        var hitElement: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            rootElement,
            Float(axPoint.x),
            Float(axPoint.y),
            &hitElement
        )

        guard result == .success else {
            return nil
        }

        return hitElement
    }

    /// Walks up the parent chain because hit-testing often lands on a child
    /// inside the title bar or toolbar instead of the window element itself.
    static func window(containing element: AXUIElement, maxDepth: Int = 12) -> AXUIElement? {
        // Some apps (e.g. Tauri/WebView shells) expose an AXWindow attribute
        // that resolves to an invalid element where every AX call fails with
        // kAXErrorInvalidUIElement. Require a readable role before trusting it
        // so callers can fall back to their own window resolution.
        if
            let window = self.element(kAXWindowAttribute as CFString, from: element),
            string(kAXRoleAttribute as CFString, from: window) != nil
        {
            return window
        }

        var current: AXUIElement? = element
        for _ in 0..<maxDepth {
            guard let node = current else {
                break
            }

            if string(kAXRoleAttribute as CFString, from: node) == kAXWindowRole as String {
                return node
            }

            current = self.element(kAXParentAttribute as CFString, from: node)
        }

        return nil
    }

    static func sameElement(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
        CFEqual(lhs as CFTypeRef, rhs as CFTypeRef)
    }

    static func windowIdentifier(of element: AXUIElement) -> CGWindowID? {
        windowIdentifierResolver.windowIdentifier(of: element)
    }
}

private struct AXWindowIdentifierResolver {
    private typealias AXUIElementGetWindowFunction = @convention(c) (
        AXUIElement,
        UnsafeMutablePointer<UInt32>
    ) -> AXError

    private let function: AXUIElementGetWindowFunction?

    init() {
        if let symbol = dlsym(nil, "_AXUIElementGetWindow") {
            function = unsafeBitCast(symbol, to: AXUIElementGetWindowFunction.self)
        } else {
            function = nil
        }
    }

    func windowIdentifier(of element: AXUIElement) -> CGWindowID? {
        guard let function else {
            return nil
        }

        var windowIdentifier: UInt32 = 0
        guard function(element, &windowIdentifier) == .success else {
            return nil
        }

        return CGWindowID(windowIdentifier)
    }
}
