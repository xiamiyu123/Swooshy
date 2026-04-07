import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum AXAttributeReader {
    private static func attributeValue(_ attribute: CFString, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else { return nil }
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
        guard let children = attributeValue(attribute, from: element) as? [AnyObject] else {
            return []
        }

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

        if let boolValue = value as? Bool {
            return boolValue
        }

        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }

        return nil
    }

    static func actionNames(of element: AXUIElement) -> [String] {
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

    static func hitElement(atAXPoint axPoint: CGPoint) -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var hitElement: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(axPoint.x),
            Float(axPoint.y),
            &hitElement
        )

        guard result == .success else {
            return nil
        }

        return hitElement
    }

    static func window(containing element: AXUIElement, maxDepth: Int = 12) -> AXUIElement? {
        if let window = self.element(kAXWindowAttribute as CFString, from: element) {
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
}
