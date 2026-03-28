import AppKit
import ApplicationServices
import CMultitouchShim
import Foundation

@MainActor
final class DockGestureController {
    private let windowManager: WindowManager
    private let alertPresenter: AlertPresenting
    private let settingsStore: SettingsStore
    private let dockProbe = DockAccessibilityProbe()
    private let monitor = MultitouchInputMonitor()
    private var recognizer = DockSwipeGestureRecognizer()
    private var hasShownPermissionHint = false
    private var settingsObserver: NSObjectProtocol?

    init(
        windowManager: WindowManager,
        alertPresenter: AlertPresenting,
        settingsStore: SettingsStore
    ) {
        self.windowManager = windowManager
        self.alertPresenter = alertPresenter
        self.settingsStore = settingsStore

        monitor.onFrame = { [weak self] frame in
            Task { @MainActor in
                self?.handle(frame: frame)
            }
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
            monitor.startIfAvailable()
        } else {
            monitor.stop()
        }
    }

    private func handle(frame: TrackpadTouchFrame) {
        guard settingsStore.dockGesturesEnabled else { return }

        let hoveredApplication = dockProbe.hoveredApplicationName(at: NSEvent.mouseLocation)
        guard let event = recognizer.process(frame: frame, hoveredApplicationName: hoveredApplication) else {
            return
        }

        do {
            switch event {
            case .minimize(let applicationName):
                _ = try windowManager.minimizeVisibleWindow(ofApplicationNamed: applicationName)
            case .restore(let applicationName):
                _ = try windowManager.restoreMinimizedWindow(ofApplicationNamed: applicationName)
            }
        } catch let error as WindowManagerError {
            handleWindowManagerError(error)
        } catch {
            NSSound.beep()
            NSLog("Dock gesture action failed: %@", error.localizedDescription)
        }
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
            NSLog("Dock gesture action failed: %@", error.localizedDescription)
        }
    }
}

private struct DockAccessibilityProbe {
    func hoveredApplicationName(at appKitPoint: CGPoint) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        guard let dockProcess = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }

        let dockElement = AXUIElementCreateApplication(dockProcess.processIdentifier)
        guard let dockList = childElement(
            attribute: kAXChildrenAttribute as CFString,
            from: dockElement
        )?.first else {
            return nil
        }

        let geometry = ScreenGeometry(screenFrames: NSScreen.screens.map(\.frame))

        for item in childElements(attribute: kAXChildrenAttribute as CFString, from: dockList) {
            guard let itemName = stringAttribute(kAXTitleAttribute as CFString, from: item) else {
                continue
            }

            guard NSWorkspace.shared.runningApplications.contains(where: { $0.localizedName == itemName }) else {
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

            if appKitFrame.contains(appKitPoint) {
                return itemName
            }
        }

        return nil
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
}

private final class MultitouchInputMonitor {
    var onFrame: ((TrackpadTouchFrame) -> Void)?

    private var isMonitoring = false

    func startIfAvailable() {
        guard isMonitoring == false else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        isMonitoring = SweeeshMTStartMonitoring(multitouchCallback, context)
        if isMonitoring == false {
            NSLog("MultitouchSupport monitoring unavailable")
        }
    }

    func stop() {
        guard isMonitoring else { return }
        SweeeshMTStopMonitoring()
        isMonitoring = false
    }

    fileprivate func receive(
        fingers: UnsafePointer<SweeeshMTFinger>,
        fingerCount: Int,
        timestamp: Double
    ) {
        guard fingerCount > 0 else {
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
