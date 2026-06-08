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
            lastMinimizedAt: lastMinimizedAt,
            boundDockMinimizedHandle: handle
        )
    }
}

@MainActor
final class WindowRegistry {
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

    private var workspaceObservers: [NSObjectProtocol] = []
    private var applicationsByProcessIdentifier: [pid_t: ApplicationRecord] = [:]
    private var applicationsByBundleURL: [URL: AppIdentity] = [:]
    private var windowsByIdentity: [WindowIdentity: WindowRecord] = [:]
    private var windowIdentitiesByToken: [DockElementToken: WindowIdentity] = [:]

    init(
        observationCenter: WindowObservationCenter = WindowObservationCenter(),
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        now: @escaping () -> Date = Date.init
    ) {
        self.observationCenter = observationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.now = now

        observationCenter.onAccessibilityEvent = { [weak self] processIdentifier, _ in
            guard let self else {
                return
            }

            self.refreshApplication(processIdentifier: processIdentifier)
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
                    self?.refreshRunningApplications()
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
        windowsByIdentity = [:]
        windowIdentitiesByToken = [:]
        applicationsByProcessIdentifier = [:]
        applicationsByBundleURL = [:]
        observationCenter.shutdown()
    }

    func refreshRunningApplications() {
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
        guard let applicationRecord = applicationsByProcessIdentifier[processIdentifier] else {
            removeWindows(forProcessIdentifier: processIdentifier)
            return
        }

        let appElement = AXUIElementCreateApplication(processIdentifier)
        let windows = AXAttributeReader.elements(kAXWindowsAttribute as CFString, from: appElement)
        syncWindows(
            windows,
            for: applicationRecord.application,
            identity: applicationRecord.identity
        )
        observationCenter.updateObservedWindows(windows, for: processIdentifier)
    }

    func appIdentity(forProcessIdentifier processIdentifier: pid_t) -> AppIdentity? {
        if applicationsByProcessIdentifier[processIdentifier] == nil {
            refreshRunningApplicationRecords()
        }

        return applicationsByProcessIdentifier[processIdentifier]?.identity
    }

    func appIdentity(forBundleURL bundleURL: URL) -> AppIdentity? {
        let canonicalBundleURL = AppIdentity.canonicalBundleURL(from: bundleURL)

        let matchingApplications = applicationsByProcessIdentifier.values
            .filter { $0.identity.bundleURL == canonicalBundleURL }

        if let appIdentity = applicationsByBundleURL[canonicalBundleURL] {
            return appIdentity
        }

        guard !matchingApplications.isEmpty else {
            refreshRunningApplicationRecords()
            return applicationsByBundleURL[canonicalBundleURL]
        }

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
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
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
        visibleWindowSnapshots(for: identity)
            .sorted { lhs, rhs in
                if lhs.isFocused != rhs.isFocused {
                    return lhs.isFocused
                }

                if lhs.isMain != rhs.isMain {
                    return lhs.isMain
                }

                return lhs.identity.hashValue < rhs.identity.hashValue
            }
    }

    func minimizedWindowSnapshotsEligibleForDockBinding() -> [WindowRecordSnapshot] {
        windowsByIdentity.values
            .map(\.snapshot)
            .filter {
                $0.isMinimized &&
                    $0.lastMinimizedAt != nil &&
                    $0.boundDockMinimizedHandle == nil
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.lastMinimizedAt ?? .distantPast
                let rhsDate = rhs.lastMinimizedAt ?? .distantPast
                if lhsDate == rhsDate {
                    return lhs.identity.hashValue < rhs.identity.hashValue
                }

                return lhsDate < rhsDate
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
        }

        for existingRecord in existingRecords where !liveWindowTokens.contains(existingRecord.token) {
            windowIdentitiesByToken.removeValue(forKey: existingRecord.token)
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

        if windowsByIdentity.values.contains(where: { $0.ownerProcessIdentifier == application.processIdentifier }) {
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
