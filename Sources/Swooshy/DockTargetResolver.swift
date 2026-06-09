import AppKit
import ApplicationServices
import Foundation

@MainActor
protocol DockTargetResolving: AnyObject {
    func clearCache()
    func currentDockTriggerRegions() -> [CGRect]
    func hoveredTarget(
        at appKitPoint: CGPoint,
        requireFrontmostOwnership: Bool
    ) -> InteractionTarget?
    func pressDockMinimizedItem(_ handle: DockMinimizedItemHandle) -> Bool
}

struct DockHoverCandidate: Equatable {
    let target: InteractionTarget
    let frame: CGRect
}

struct DockHoverSnapshot: Equatable {
    let candidates: [DockHoverCandidate]
    let bounds: CGRect

    init(candidates: [DockHoverCandidate]) {
        self.candidates = candidates
        self.bounds = candidates.reduce(CGRect.null) { $0.union($1.frame) }
    }

    func hoveredCandidate(at point: CGPoint) -> DockHoverCandidate? {
        candidates.first { $0.frame.contains(point) }
    }

    func containsApproximateDockRegion(_ point: CGPoint) -> Bool {
        !bounds.isNull && !bounds.isEmpty && bounds.contains(point)
    }
}

struct DockSnapshotCachePolicy: Equatable {
    let candidateTTL: TimeInterval
    let regionTTL: TimeInterval
    let preheatLeadTime: TimeInterval

    init(
        candidateTTL: TimeInterval = 0.25,
        regionTTL: TimeInterval = 1.0,
        preheatLeadTime: TimeInterval = 0.08
    ) {
        self.candidateTTL = candidateTTL
        self.regionTTL = regionTTL
        self.preheatLeadTime = min(preheatLeadTime, candidateTTL)
    }

    func shouldPreheat(now: Date, candidateExpiresAt: Date) -> Bool {
        now >= candidateExpiresAt.addingTimeInterval(-preheatLeadTime)
    }
}

@MainActor
protocol DockMinimizedWindowBindingManaging: AnyObject {
    func minimizedWindowSnapshotsEligibleForDockBinding() -> [WindowRecordSnapshot]
    func bindDockMinimizedHandle(_ handle: DockMinimizedItemHandle, to windowIdentity: WindowIdentity)
    func unbindDockMinimizedHandle(_ handle: DockMinimizedItemHandle)
    func windowSnapshot(for identity: WindowIdentity) -> WindowRecordSnapshot?
}

@MainActor
final class MinimizedDockLedger {
    struct SnapshotItem {
        let token: DockElementToken
        let element: AXUIElement
        let frame: CGRect
    }

    private struct Entry {
        let handle: DockMinimizedItemHandle
        var token: DockElementToken
        var element: AXUIElement
        var frame: CGRect
        var resolvedWindowIdentity: WindowIdentity?
    }

    private var entries: [Entry] = []

    func clear(registry: DockMinimizedWindowBindingManaging) {
        for entry in entries {
            registry.unbindDockMinimizedHandle(entry.handle)
        }
        entries = []
    }

    func reconcile(
        with items: [SnapshotItem],
        registry: DockMinimizedWindowBindingManaging
    ) {
        let previousEntriesByToken = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.token, $0) }
        )
        let availableSnapshots = registry.minimizedWindowSnapshotsEligibleForDockBinding()
        var availableIterator = availableSnapshots.makeIterator()
        var nextEntries: [Entry] = []

        for item in items {
            if var previousEntry = previousEntriesByToken[item.token] {
                previousEntry.element = item.element
                previousEntry.frame = item.frame
                nextEntries.append(previousEntry)
                continue
            }

            let handle = DockMinimizedItemHandle()
            let resolvedWindowIdentity = availableIterator.next()?.identity
            if let resolvedWindowIdentity {
                registry.bindDockMinimizedHandle(handle, to: resolvedWindowIdentity)
            }

            nextEntries.append(
                Entry(
                    handle: handle,
                    token: item.token,
                    element: item.element,
                    frame: item.frame,
                    resolvedWindowIdentity: resolvedWindowIdentity
                )
            )
        }

        let liveHandles = Set(nextEntries.map(\.handle))
        for previousEntry in entries where !liveHandles.contains(previousEntry.handle) {
            registry.unbindDockMinimizedHandle(previousEntry.handle)
        }

        entries = nextEntries
    }

    func target(
        for handle: DockMinimizedItemHandle,
        registry: DockMinimizedWindowBindingManaging
    ) -> InteractionTarget? {
        guard let entry = entries.first(where: { $0.handle == handle }) else {
            return nil
        }

        guard
            let windowIdentity = entry.resolvedWindowIdentity,
            let snapshot = registry.windowSnapshot(for: windowIdentity)
        else {
            return .unresolvedDockMinimizedItem(handle)
        }

        return .window(
            windowIdentity,
            app: snapshot.appIdentity,
            source: .dockMinimizedItem(handle)
        )
    }

    func handle(for token: DockElementToken) -> DockMinimizedItemHandle? {
        entries.first(where: { $0.token == token })?.handle
    }

    func press(_ handle: DockMinimizedItemHandle) -> Bool {
        guard let entry = entries.first(where: { $0.handle == handle }) else {
            return false
        }

        return AXUIElementPerformAction(entry.element, kAXPressAction as CFString) == .success
    }
}

@MainActor
final class DockTargetResolver: DockTargetResolving {
    private let registry: WindowRegistry
    private let minimizedDockLedger = MinimizedDockLedger()
    private let cachePolicy = DockSnapshotCachePolicy()
    private let logTTL: TimeInterval = 0.4

    private struct CachedSnapshot {
        let snapshot: DockHoverSnapshot
        let candidateExpiresAt: Date
        let regionExpiresAt: Date
    }

    private struct CachedHoverHit {
        let target: InteractionTarget
        let frame: CGRect
        let expiresAt: Date
    }

    private struct DockAppSnapshotItem {
        let token: DockElementToken
        let frame: CGRect
        let identity: AppIdentity
    }

    private var appHandlesByToken: [DockElementToken: DockItemHandle] = [:]
    private var cachedSnapshot: CachedSnapshot?
    private var cachedHoverHit: CachedHoverHit?
    private var preheatTask: Task<Void, Never>?
#if DEBUG
    private var lastProbeLogAt = Date.distantPast
    private var lastProbeLogKey = ""
#endif

    init(registry: WindowRegistry) {
        self.registry = registry
    }

    func clearCache() {
        preheatTask?.cancel()
        preheatTask = nil
        cachedSnapshot = nil
        cachedHoverHit = nil
        appHandlesByToken = [:]
        minimizedDockLedger.clear(registry: registry)
#if DEBUG
        lastProbeLogAt = .distantPast
        lastProbeLogKey = ""
#endif
    }

    func currentDockTriggerRegions() -> [CGRect] {
        dockElementFrames()
    }

    func hoveredTarget(
        at appKitPoint: CGPoint,
        requireFrontmostOwnership: Bool
    ) -> InteractionTarget? {
        let now = Date()

        if
            let cachedHoverHit,
            now < cachedHoverHit.expiresAt,
            cachedHoverHit.frame.contains(appKitPoint),
            pointBelongsToDock(at: appKitPoint, required: requireFrontmostOwnership)
        {
            logProbeIfNeeded(
                key: "hit-cache:\(cachedHoverHit.target.logDescription):\(Int(appKitPoint.x)):\(Int(appKitPoint.y))",
                message: {
                    "Pointer hit cached Dock target \(cachedHoverHit.target.logDescription) at \(NSStringFromPoint(appKitPoint)); frame = \(NSStringFromRect(cachedHoverHit.frame))"
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

        guard pointBelongsToDock(at: appKitPoint, required: requireFrontmostOwnership) else {
            cachedHoverHit = nil
            return nil
        }

        cachedHoverHit = CachedHoverHit(
            target: hoveredCandidate.target,
            frame: hoveredCandidate.frame,
            expiresAt: now.addingTimeInterval(cachePolicy.candidateTTL)
        )
        logProbeIfNeeded(
            key: "hit:\(hoveredCandidate.target.logDescription):\(Int(appKitPoint.x)):\(Int(appKitPoint.y))",
            message: {
                "Pointer hit Dock target \(hoveredCandidate.target.logDescription) at \(NSStringFromPoint(appKitPoint)); frame = \(NSStringFromRect(hoveredCandidate.frame))"
            }
        )
        return hoveredCandidate.target
    }

    func pressDockMinimizedItem(_ handle: DockMinimizedItemHandle) -> Bool {
        minimizedDockLedger.press(handle)
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

        guard let hitProcessIdentifier = AXAttributeReader.processIdentifier(at: appKitPoint) else {
            return true
        }

        return hitProcessIdentifier == dockProcess.processIdentifier
    }

    private func dockSnapshot(containing appKitPoint: CGPoint, at now: Date) -> DockHoverSnapshot {
        if let cachedSnapshot {
            if now < cachedSnapshot.candidateExpiresAt {
                if cachePolicy.shouldPreheat(now: now, candidateExpiresAt: cachedSnapshot.candidateExpiresAt) {
                    startPreheatIfNeeded()
                }
                return cachedSnapshot.snapshot
            }

            if
                now < cachedSnapshot.regionExpiresAt,
                !cachedSnapshot.snapshot.containsApproximateDockRegion(appKitPoint)
            {
                if cachePolicy.shouldPreheat(now: now, candidateExpiresAt: cachedSnapshot.candidateExpiresAt) {
                    startPreheatIfNeeded()
                }
                return cachedSnapshot.snapshot
            }
        }

        preheatTask?.cancel()
        preheatTask = nil
        let snapshot = rebuildDockSnapshot()
        cachedSnapshot = CachedSnapshot(
            snapshot: snapshot,
            candidateExpiresAt: now.addingTimeInterval(cachePolicy.candidateTTL),
            regionExpiresAt: now.addingTimeInterval(cachePolicy.regionTTL)
        )
        return snapshot
    }

    private func startPreheatIfNeeded() {
        guard preheatTask == nil else {
            return
        }

        preheatTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let snapshot = self.rebuildDockSnapshot()
            let now = Date()
            self.cachedSnapshot = CachedSnapshot(
                snapshot: snapshot,
                candidateExpiresAt: now.addingTimeInterval(self.cachePolicy.candidateTTL),
                regionExpiresAt: now.addingTimeInterval(self.cachePolicy.regionTTL)
            )
            self.preheatTask = nil
        }
    }

    private func rebuildDockSnapshot() -> DockHoverSnapshot {
        let dockElements = readableDockElements()
        guard !dockElements.isEmpty else {
            return emptyDockSnapshot()
        }

        var appItems: [DockAppSnapshotItem] = []
        var minimizedItems: [MinimizedDockLedger.SnapshotItem] = []

        for dockElement in dockElements {
            let appKitFrame = dockElement.frame
            let token = DockElementToken(element: dockElement.element)

            switch dockElement.subrole {
            case "AXApplicationDockItem":
                guard
                    let bundleURL = AXAttributeReader.url("AXURL" as CFString, from: dockElement.element),
                    let appIdentity = registry.appIdentity(forBundleURL: bundleURL)
                else {
                    continue
                }

                appItems.append(
                    DockAppSnapshotItem(
                        token: token,
                        frame: appKitFrame,
                        identity: appIdentity
                    )
                )
            case "AXMinimizedWindowDockItem":
                minimizedItems.append(
                    MinimizedDockLedger.SnapshotItem(
                        token: token,
                        element: dockElement.element,
                        frame: appKitFrame
                    )
                )
            default:
                continue
            }
        }

        minimizedDockLedger.reconcile(with: minimizedItems, registry: registry)

        let liveAppTokens = Set(appItems.map(\.token))
        appHandlesByToken = appHandlesByToken.filter { liveAppTokens.contains($0.key) }

        var candidates: [DockHoverCandidate] = []
        for appItem in appItems {
            let handle = appHandlesByToken[appItem.token] ?? DockItemHandle()
            appHandlesByToken[appItem.token] = handle
            candidates.append(
                DockHoverCandidate(
                    target: .application(
                        appItem.identity,
                        source: .dockAppItem(handle)
                    ),
                    frame: appItem.frame
                )
            )
        }

        for minimizedItem in minimizedItems {
            guard let handle = minimizedDockLedger.handle(for: minimizedItem.token) else {
                continue
            }

            guard let target = minimizedDockLedger.target(for: handle, registry: registry) else {
                continue
            }

            candidates.append(
                DockHoverCandidate(
                    target: target,
                    frame: minimizedItem.frame
                )
            )
        }

        return DockHoverSnapshot(candidates: candidates)
    }

    private struct ReadableDockElement {
        let element: AXUIElement
        let subrole: String
        let frame: CGRect
    }

    private func dockElementFrames() -> [CGRect] {
        readableDockElements().map(\.frame)
    }

    private func readableDockElements() -> [ReadableDockElement] {
        guard AXIsProcessTrusted() else {
            return []
        }

        guard let dockProcess = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return []
        }

        let dockElement = AXUIElementCreateApplication(dockProcess.processIdentifier)
        guard let dockList = AXAttributeReader.elements(kAXChildrenAttribute as CFString, from: dockElement).first else {
            return []
        }

        let geometry = ScreenGeometry(screenFrames: NSScreen.screens.map(\.frame))
        return AXAttributeReader.elements(kAXChildrenAttribute as CFString, from: dockList).compactMap { item in
            let subrole = AXAttributeReader.string(kAXSubroleAttribute as CFString, from: item) ?? ""
            guard subrole == "AXApplicationDockItem" || subrole == "AXMinimizedWindowDockItem" else {
                return nil
            }

            guard
                let axPosition = AXAttributeReader.point(kAXPositionAttribute as CFString, from: item),
                let axSize = AXAttributeReader.size(kAXSizeAttribute as CFString, from: item)
            else {
                return nil
            }

            return ReadableDockElement(
                element: item,
                subrole: subrole,
                frame: geometry.appKitFrame(
                    fromAXFrame: CGRect(origin: axPosition, size: axSize)
                )
            )
        }
    }

    private func emptyDockSnapshot() -> DockHoverSnapshot {
        minimizedDockLedger.clear(registry: registry)
        return DockHoverSnapshot(candidates: [])
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
            .map { "\($0.candidate.target.logDescription):\(Int($0.distance * 100))" }
            .joined(separator: ",")

        logProbeIfNeeded(
            key: "miss:\(nearestKey)",
            message: {
                let nearestSummary = nearestCandidates
                    .map {
                        "\($0.candidate.target.logDescription){frame=\(NSStringFromRect($0.candidate.frame)), distance=\(String(format: "%.2f", $0.distance))}"
                    }
                    .joined(separator: ", ")
                return "Pointer missed all Dock targets at \(NSStringFromPoint(appKitPoint)); evaluated \(snapshot.candidates.count) candidates; nearest = [\(nearestSummary)]"
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
