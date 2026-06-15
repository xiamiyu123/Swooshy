import AppKit
import ApplicationServices
import Foundation

@MainActor
final class TitleBarAccessibilityProbe {
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
