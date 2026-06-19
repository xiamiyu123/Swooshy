import AppKit
import ApplicationServices
import Foundation

struct WindowRecordSnapshot: Equatable {
    let identity: WindowIdentity
    let appIdentity: AppIdentity
    let ownerProcessIdentifier: pid_t
    let title: String
    let frame: CGRect
    let isMinimized: Bool
    let isFocused: Bool
    let isMain: Bool
    let isFullScreen: Bool
    let lastMinimizedAt: Date?
    let boundDockMinimizedHandle: DockMinimizedItemHandle?

    func withBoundDockMinimizedHandle(_ handle: DockMinimizedItemHandle?) -> WindowRecordSnapshot {
        WindowRecordSnapshot(
            identity: identity,
            appIdentity: appIdentity,
            ownerProcessIdentifier: ownerProcessIdentifier,
            title: title,
            frame: frame,
            isMinimized: isMinimized,
            isFocused: isFocused,
            isMain: isMain,
            isFullScreen: isFullScreen,
            lastMinimizedAt: lastMinimizedAt,
            boundDockMinimizedHandle: handle
        )
    }
}

@MainActor
final class RefreshDebouncer<Key: Hashable & Sendable> {
    private let delayNanoseconds: UInt64
    private var tasks: [Key: Task<Void, Never>] = [:]

    var scheduledCount: Int {
        tasks.count
    }

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func schedule(
        key: Key,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        guard tasks[key] == nil else {
            return
        }

        let delayNanoseconds = delayNanoseconds
        tasks[key] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else {
                return
            }

            self.tasks.removeValue(forKey: key)
            action()
        }
    }

    func cancel(key: Key) {
        tasks.removeValue(forKey: key)?.cancel()
    }

    func cancelAll() {
        for task in tasks.values {
            task.cancel()
        }
        tasks = [:]
    }
}

@MainActor
final class WindowRegistry {
    private enum RefreshRequest: Hashable, Sendable {
        case runningApplications
        case application(pid_t)
    }

    private struct ApplicationRecord {
        let application: NSRunningApplication
        let identity: AppIdentity
    }

    private struct WindowRecord {
        let identity: WindowIdentity
        let ownerProcessIdentifier: pid_t
        let token: DockElementToken
        let window: AXUIElement
        var snapshot: WindowRecordSnapshot
    }

    private let observationCenter: WindowObservationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private let now: () -> Date
    private let refreshDebouncer: RefreshDebouncer<RefreshRequest>

    private var workspaceObservers: [NSObjectProtocol] = []
    private var applicationsByProcessIdentifier: [pid_t: ApplicationRecord] = [:]
    private var applicationsByBundleURL: [URL: AppIdentity] = [:]
    private var windowsByIdentity: [WindowIdentity: WindowRecord] = [:]
    private var windowIdentitiesByToken: [DockElementToken: WindowIdentity] = [:]
    // Reverse index: pid -> number of live windows. Lets `applicationQualityScore`
    // (called from sort comparators) answer "does this app own a window?" in
    // O(1) instead of scanning every window record. Kept in sync with
    // `windowsByIdentity` at each mutation site (syncWindows / removeWindows /
    // shutdown).
    private var windowCountByPID: [pid_t: Int] = [:]

    private func incrementWindowCount(for processIdentifier: pid_t) {
        windowCountByPID[processIdentifier, default: 0] += 1
    }

    private func decrementWindowCount(for processIdentifier: pid_t) {
        guard let count = windowCountByPID[processIdentifier] else { return }
        if count <= 1 {
            windowCountByPID.removeValue(forKey: processIdentifier)
        } else {
            windowCountByPID[processIdentifier] = count - 1
        }
    }

    #if DEBUG
    /// Debug-only invariant: the reverse index must agree with a fresh scan of
    /// `windowsByIdentity`. Catches any mutation site that forgets to update
    /// the pid→window count, which would silently skew `applicationQualityScore`.
    private func assertWindowCountIndexConsistent() {
        var expected: [pid_t: Int] = [:]
        for record in windowsByIdentity.values {
            expected[record.ownerProcessIdentifier, default: 0] += 1
        }
        assert(expected == windowCountByPID, "windowCountByPID out of sync with windowsByIdentity")
    }
    #else
    @inline(__always) private func assertWindowCountIndexConsistent() {}
    #endif

    init(
        observationCenter: WindowObservationCenter = WindowObservationCenter(),
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        now: @escaping () -> Date = Date.init,
        refreshCoalescingDelayNanoseconds: UInt64 = 80_000_000
    ) {
        self.observationCenter = observationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.now = now
        refreshDebouncer = RefreshDebouncer(delayNanoseconds: refreshCoalescingDelayNanoseconds)

        observationCenter.onAccessibilityEvent = { [weak self] processIdentifier, _ in
            guard let self else {
                return
            }

            self.scheduleApplicationRefresh(processIdentifier: processIdentifier)
        }

        let notificationNames: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]

        for notificationName in notificationNames {
            let observer = workspaceNotificationCenter.addObserver(
                forName: notificationName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleRunningApplicationsRefresh()
                }
            }
            workspaceObservers.append(observer)
        }

        refreshRunningApplications()
    }

    func shutdown() {
        for observer in workspaceObservers {
            workspaceNotificationCenter.removeObserver(observer)
        }
        workspaceObservers = []
        refreshDebouncer.cancelAll()
        windowsByIdentity = [:]
        windowIdentitiesByToken = [:]
        applicationsByProcessIdentifier = [:]
        applicationsByBundleURL = [:]
        windowCountByPID = [:]
        observationCenter.shutdown()
    }

    func refreshRunningApplications() {
        refreshDebouncer.cancel(key: .runningApplications)
        let applications = refreshRunningApplicationRecords()

        for application in applications {
            refreshApplication(processIdentifier: application.application.processIdentifier)
        }
    }

    @discardableResult
    private func refreshRunningApplicationRecords() -> [ApplicationRecord] {
        let applications = NSWorkspace.shared.runningApplications.compactMap { application -> ApplicationRecord? in
            guard !application.isTerminated else {
                return nil
            }

            guard application.activationPolicy != .prohibited else {
                return nil
            }

            guard let identity = AppIdentity(application: application) else {
                return nil
            }

            return ApplicationRecord(application: application, identity: identity)
        }

        let nextProcessIdentifiers = Set(applications.map { $0.application.processIdentifier })
        let staleProcessIdentifiers = Set(applicationsByProcessIdentifier.keys).subtracting(nextProcessIdentifiers)

        for processIdentifier in staleProcessIdentifiers {
            applicationsByProcessIdentifier.removeValue(forKey: processIdentifier)
            removeWindows(forProcessIdentifier: processIdentifier)
        }

        applicationsByProcessIdentifier = Dictionary(
            uniqueKeysWithValues: applications.map { ($0.application.processIdentifier, $0) }
        )
        applicationsByBundleURL = Dictionary(
            uniqueKeysWithValues: Dictionary(
                grouping: applications,
                by: { $0.identity.bundleURL }
            ).compactMap { bundleURL, records in
                guard let bestRecord = records.max(by: {
                    applicationQualityScore(for: $0.application) < applicationQualityScore(for: $1.application)
                }) else {
                    return nil
                }

                return (bundleURL, bestRecord.identity)
            }
        )
        observationCenter.syncApplications(applications.map(\.application))

        return applications
    }

    func refreshApplication(processIdentifier: pid_t) {
        refreshDebouncer.cancel(key: .application(processIdentifier))
        guard let applicationRecord = applicationsByProcessIdentifier[processIdentifier] else {
            removeWindows(forProcessIdentifier: processIdentifier)
            return
        }

        let appElement = AXAttributeReader.applicationElement(for: processIdentifier)
        let windows: [AXUIElement]
        switch AXAttributeReader.elementArray(kAXWindowsAttribute as CFString, from: appElement) {
        case .success(let elements):
            windows = elements
        case .failure(let error) where shouldPreserveWindowsAfterEnumerationFailure(error):
            DebugLog.debug(
                DebugLog.accessibility,
                "Skipping window registry refresh for pid \(processIdentifier) after transient AX window enumeration failure; error = \(error.rawValue)"
            )
            return
        case .failure:
            windows = []
        }

        syncWindows(
            windows,
            for: applicationRecord.application,
            identity: applicationRecord.identity
        )
        observationCenter.updateObservedWindows(windows, for: processIdentifier)
    }

    private func scheduleRunningApplicationsRefresh() {
        refreshDebouncer.schedule(key: .runningApplications) { [weak self] in
            self?.refreshRunningApplications()
        }
    }

    private func scheduleApplicationRefresh(processIdentifier: pid_t) {
        refreshDebouncer.schedule(key: .application(processIdentifier)) { [weak self] in
            self?.refreshApplication(processIdentifier: processIdentifier)
        }
    }

    func appIdentity(forProcessIdentifier processIdentifier: pid_t) -> AppIdentity? {
        // Pure cache lookup. Do not trigger a refresh here: this method is on
        // the gesture-capture path and a synchronous AX/table rebuild would
        // stall input. App records are kept fresh by the workspace observers.
        applicationsByProcessIdentifier[processIdentifier]?.identity
    }

    func appIdentity(forBundleURL bundleURL: URL) -> AppIdentity? {
        let canonicalBundleURL = AppIdentity.canonicalBundleURL(from: bundleURL)

        if let appIdentity = applicationsByBundleURL[canonicalBundleURL] {
            return appIdentity
        }

        // Cache miss: fall back to recomputing from the per-pid records that
        // are already cached, without a blocking refresh. If nothing matches,
        // callers handle nil (the workspace observers will populate the cache
        // and the next lookup succeeds).
        let matchingApplications = applicationsByProcessIdentifier.values
            .filter { $0.identity.bundleURL == canonicalBundleURL }

        return matchingApplications.max(by: {
            applicationQualityScore(for: $0.application) < applicationQualityScore(for: $1.application)
        })?.identity
    }

    func runningApplication(
        matching identity: AppIdentity,
        preferredProcessIdentifier: pid_t? = nil
    ) -> NSRunningApplication? {
        if
            let preferredProcessIdentifier,
            let preferredRecord = applicationsByProcessIdentifier[preferredProcessIdentifier],
            preferredRecord.identity == identity,
            !preferredRecord.application.isTerminated
        {
            return preferredRecord.application
        }

        if
            let processRecord = applicationsByProcessIdentifier[identity.processIdentifier],
            processRecord.identity == identity,
            !processRecord.application.isTerminated
        {
            return processRecord.application
        }

        let matchingApplications = applicationsByProcessIdentifier.values
            .filter { $0.identity == identity && !$0.application.isTerminated }
            .sorted { lhs, rhs in
                let lhsScore = applicationQualityScore(for: lhs.application)
                let rhsScore = applicationQualityScore(for: rhs.application)
                if lhsScore == rhsScore {
                    return lhs.application.processIdentifier < rhs.application.processIdentifier
                }

                return lhsScore > rhsScore
            }

        return matchingApplications.first?.application
    }

    func windowIdentity(
        for window: AXUIElement,
        in application: NSRunningApplication
    ) -> WindowIdentity? {
        let token = DockElementToken(element: window)
        if let windowIdentity = windowIdentitiesByToken[token] {
            return windowIdentity
        }

        refreshApplication(processIdentifier: application.processIdentifier)
        return windowIdentitiesByToken[token]
    }

    func windowElement(for identity: WindowIdentity) -> AXUIElement? {
        windowsByIdentity[identity]?.window
    }

    func windowSnapshot(for identity: WindowIdentity) -> WindowRecordSnapshot? {
        windowsByIdentity[identity]?.snapshot
    }

    func focusedWindowIdentity(in identity: AppIdentity) -> WindowIdentity? {
        guard let application = runningApplication(matching: identity) else {
            return nil
        }

        return windowIdentity(matching: kAXFocusedWindowAttribute as CFString, in: application)
    }

    func mainWindowIdentity(in identity: AppIdentity) -> WindowIdentity? {
        guard let application = runningApplication(matching: identity) else {
            return nil
        }

        return windowIdentity(matching: kAXMainWindowAttribute as CFString, in: application)
    }

    private func windowIdentity(
        matching attribute: CFString,
        in application: NSRunningApplication
    ) -> WindowIdentity? {
        let appElement = AXAttributeReader.applicationElement(for: application.processIdentifier)
        guard let window = AXAttributeReader.element(attribute, from: appElement) else {
            return nil
        }

        return windowIdentity(for: window, in: application)
    }

    func windowSnapshots(for identity: AppIdentity) -> [WindowRecordSnapshot] {
        windowsByIdentity.values
            .map(\.snapshot)
            .filter { $0.appIdentity == identity }
    }

    func visibleWindowSnapshots(for identity: AppIdentity) -> [WindowRecordSnapshot] {
        windowSnapshots(for: identity).filter { !$0.isMinimized }
    }

    func orderedVisibleWindowSnapshots(for identity: AppIdentity) -> [WindowRecordSnapshot] {
        Self.visibleWindowSnapshotsInStableOrder(visibleWindowSnapshots(for: identity))
    }

    func minimizedWindowSnapshotsEligibleForDockBinding() -> [WindowRecordSnapshot] {
        Self.minimizedWindowSnapshotsEligibleForDockBinding(
            windowsByIdentity.values
            .map(\.snapshot)
        )
    }

    nonisolated static func visibleWindowSnapshotsInStableOrder(
        _ snapshots: [WindowRecordSnapshot]
    ) -> [WindowRecordSnapshot] {
        snapshots
            .filter { !$0.isMinimized }
            .sorted { lhs, rhs in
                if lhs.isFocused != rhs.isFocused {
                    return lhs.isFocused
                }

                if lhs.isMain != rhs.isMain {
                    return lhs.isMain
                }

                return lhs.identity.stableSortKey < rhs.identity.stableSortKey
            }
    }

    nonisolated static func minimizedWindowSnapshotsEligibleForDockBinding(
        _ snapshots: [WindowRecordSnapshot]
    ) -> [WindowRecordSnapshot] {
        snapshots
            .filter {
                $0.isMinimized &&
                    $0.lastMinimizedAt != nil &&
                    $0.boundDockMinimizedHandle == nil
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.lastMinimizedAt ?? .distantPast
                let rhsDate = rhs.lastMinimizedAt ?? .distantPast
                if lhsDate == rhsDate {
                    return lhs.identity.stableSortKey < rhs.identity.stableSortKey
                }

                return lhsDate < rhsDate
            }
    }

    func titleBarHoverTarget(
        at appKitPoint: CGPoint,
        titleBarHeight: CGFloat,
        allowFullScreen: Bool
    ) -> TitleBarHoverTarget? {
        titleBarHoverHit(
            at: appKitPoint,
            titleBarHeight: titleBarHeight,
            allowFullScreen: allowFullScreen
        )?.target
    }

    func titleBarHoverHit(
        at appKitPoint: CGPoint,
        titleBarHeight: CGFloat,
        allowFullScreen: Bool
    ) -> TitleBarHoverHit? {
        Self.titleBarHoverHit(
            at: appKitPoint,
            titleBarHeight: titleBarHeight,
            allowFullScreen: allowFullScreen,
            snapshots: windowsByIdentity.values.map(\.snapshot),
            screenFrames: NSScreen.screens.map(\.frame)
        )
    }

    nonisolated static func titleBarHoverHit(
        at appKitPoint: CGPoint,
        titleBarHeight: CGFloat,
        allowFullScreen: Bool,
        snapshots: [WindowRecordSnapshot],
        screenFrames: [CGRect]
    ) -> TitleBarHoverHit? {
        guard !screenFrames.isEmpty else {
            return nil
        }

        let geometry = ScreenGeometry(screenFrames: screenFrames)
        let triggerHeight = CGFloat(SettingsStore.clampTitleBarTriggerHeight(Double(titleBarHeight)))
        return snapshots
            .compactMap { snapshot -> (snapshot: WindowRecordSnapshot, frame: CGRect)? in
                guard !snapshot.isMinimized else {
                    return nil
                }
                guard allowFullScreen || !snapshot.isFullScreen else {
                    return nil
                }

                let appKitFrame = geometry.appKitFrame(fromAXFrame: snapshot.frame)
                guard appKitFrame.width >= 120, appKitFrame.height >= 80 else {
                    return nil
                }

                let titleBarFrame = CGRect(
                    x: appKitFrame.minX,
                    y: appKitFrame.maxY - triggerHeight,
                    width: appKitFrame.width,
                    height: triggerHeight
                ).integral
                guard !titleBarFrame.isEmpty, titleBarFrame.contains(appKitPoint) else {
                    return nil
                }

                return (snapshot, titleBarFrame)
            }
            .min { lhs, rhs in
                Self.titleBarHoverSnapshotPrecedes(lhs.snapshot, rhs.snapshot)
            }
            .map { candidate in
                TitleBarHoverHit(
                    target: TitleBarHoverTarget(
                        application: .window(
                            candidate.snapshot.identity,
                            app: candidate.snapshot.appIdentity,
                            source: .titleBar
                        ),
                        source: .titleBar
                    ),
                    processIdentifier: candidate.snapshot.ownerProcessIdentifier,
                    frame: candidate.frame,
                    isFullScreen: candidate.snapshot.isFullScreen
                )
            }
    }

    func bindDockMinimizedHandle(
        _ handle: DockMinimizedItemHandle,
        to windowIdentity: WindowIdentity
    ) {
        guard var record = windowsByIdentity[windowIdentity] else {
            return
        }

        record.snapshot = record.snapshot.withBoundDockMinimizedHandle(handle)
        windowsByIdentity[windowIdentity] = record
    }

    func unbindDockMinimizedHandle(_ handle: DockMinimizedItemHandle) {
        for (identity, var record) in windowsByIdentity where record.snapshot.boundDockMinimizedHandle == handle {
            record.snapshot = record.snapshot.withBoundDockMinimizedHandle(nil)
            windowsByIdentity[identity] = record
        }
    }

    private func syncWindows(
        _ windows: [AXUIElement],
        for application: NSRunningApplication,
        identity: AppIdentity
    ) {
        let existingRecords = windowsByIdentity.values.filter { $0.ownerProcessIdentifier == application.processIdentifier }
        var matchedIdentityByToken: [DockElementToken: WindowIdentity] = [:]

        for record in existingRecords {
            matchedIdentityByToken[record.token] = record.identity
        }

        var liveWindowIdentities: Set<WindowIdentity> = []
        var liveWindowTokens: Set<DockElementToken> = []

        for window in windows {
            let token = DockElementToken(element: window)
            let recordIdentity = matchedIdentityByToken[token] ?? WindowIdentity()
            let previousRecord = windowsByIdentity[recordIdentity]
            let previousSnapshot = previousRecord?.snapshot
            if let previousRecord, previousRecord.token != token {
                windowIdentitiesByToken.removeValue(forKey: previousRecord.token)
            }
            // Index: only a newly-seen identity grows the pid's window count;
            // overwriting an existing identity for the same pid is in-place.
            if previousRecord == nil {
                incrementWindowCount(for: application.processIdentifier)
            }
            let nextSnapshot = makeSnapshot(
                for: window,
                identity: recordIdentity,
                application: application,
                appIdentity: identity,
                previousSnapshot: previousSnapshot
            )

            windowsByIdentity[recordIdentity] = WindowRecord(
                identity: recordIdentity,
                ownerProcessIdentifier: application.processIdentifier,
                token: token,
                window: window,
                snapshot: nextSnapshot
            )
            windowIdentitiesByToken[token] = recordIdentity
            liveWindowIdentities.insert(recordIdentity)
            liveWindowTokens.insert(token)
        }

        for existingRecord in existingRecords where !liveWindowIdentities.contains(existingRecord.identity) {
            windowsByIdentity.removeValue(forKey: existingRecord.identity)
            windowIdentitiesByToken.removeValue(forKey: existingRecord.token)
            // Index: an identity we previously tracked is gone for this pid.
            decrementWindowCount(for: existingRecord.ownerProcessIdentifier)
        }

        for existingRecord in existingRecords where !liveWindowTokens.contains(existingRecord.token) {
            windowIdentitiesByToken.removeValue(forKey: existingRecord.token)
        }

        assertWindowCountIndexConsistent()
    }

    private func shouldPreserveWindowsAfterEnumerationFailure(_ error: AXError) -> Bool {
        switch error {
        case .cannotComplete, .apiDisabled:
            return true
        default:
            return false
        }
    }

    private func makeSnapshot(
        for window: AXUIElement,
        identity: WindowIdentity,
        application: NSRunningApplication,
        appIdentity: AppIdentity,
        previousSnapshot: WindowRecordSnapshot?
    ) -> WindowRecordSnapshot {
        let title = AXAttributeReader.string(kAXTitleAttribute as CFString, from: window) ?? ""
        let frame = CGRect(
            origin: AXAttributeReader.point(kAXPositionAttribute as CFString, from: window) ?? .zero,
            size: AXAttributeReader.size(kAXSizeAttribute as CFString, from: window) ?? .zero
        ).integral
        let isMinimized = AXAttributeReader.bool(kAXMinimizedAttribute as CFString, from: window) ?? false
        let isFocused = AXAttributeReader.bool(kAXFocusedAttribute as CFString, from: window) ?? false
        let isMain = AXAttributeReader.bool(kAXMainAttribute as CFString, from: window) ?? false
        let isFullScreen = AXAttributeReader.bool("AXFullScreen" as CFString, from: window) ?? false

        let lastMinimizedAt: Date?
        if
            previousSnapshot?.isMinimized == false,
            isMinimized
        {
            lastMinimizedAt = now()
        } else {
            lastMinimizedAt = previousSnapshot?.lastMinimizedAt
        }

        return WindowRecordSnapshot(
            identity: identity,
            appIdentity: appIdentity,
            ownerProcessIdentifier: application.processIdentifier,
            title: title,
            frame: frame,
            isMinimized: isMinimized,
            isFocused: isFocused,
            isMain: isMain,
            isFullScreen: isFullScreen,
            lastMinimizedAt: lastMinimizedAt,
            boundDockMinimizedHandle: previousSnapshot?.boundDockMinimizedHandle
        )
    }

    private func removeWindows(forProcessIdentifier processIdentifier: pid_t) {
        let recordsToRemove = windowsByIdentity.compactMap { identity, record in
            record.ownerProcessIdentifier == processIdentifier ? (identity, record.token) : nil
        }

        for (identity, token) in recordsToRemove {
            windowsByIdentity.removeValue(forKey: identity)
            windowIdentitiesByToken.removeValue(forKey: token)
        }

        // Index: every window for this pid is gone.
        if !recordsToRemove.isEmpty {
            windowCountByPID.removeValue(forKey: processIdentifier)
        }

        assertWindowCountIndexConsistent()
    }

    nonisolated private static func titleBarHoverSnapshotPrecedes(
        _ lhs: WindowRecordSnapshot,
        _ rhs: WindowRecordSnapshot
    ) -> Bool {
        if lhs.isFocused != rhs.isFocused {
            return lhs.isFocused
        }
        if lhs.isMain != rhs.isMain {
            return lhs.isMain
        }
        if lhs.ownerProcessIdentifier != rhs.ownerProcessIdentifier {
            return lhs.ownerProcessIdentifier < rhs.ownerProcessIdentifier
        }
        if lhs.title != rhs.title {
            return lhs.title < rhs.title
        }
        if lhs.frame != rhs.frame {
            return framePrecedes(lhs.frame, rhs.frame)
        }
        return lhs.identity.stableSortKey < rhs.identity.stableSortKey
    }

    nonisolated private static func framePrecedes(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        if lhs.minX != rhs.minX {
            return lhs.minX < rhs.minX
        }
        if lhs.minY != rhs.minY {
            return lhs.minY < rhs.minY
        }
        if lhs.width != rhs.width {
            return lhs.width < rhs.width
        }
        return lhs.height < rhs.height
    }

    private func applicationQualityScore(for application: NSRunningApplication) -> Int {
        var score = 0

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

        if (windowCountByPID[application.processIdentifier] ?? 0) > 0 {
            score += 120
        }

        if !application.isHidden {
            score += 20
        }

        if RunningApplicationIdentity.isLikelyHelperProcess(application) {
            score -= 220
        }

        return score
    }
}

extension WindowRegistry: DockMinimizedWindowBindingManaging {}
