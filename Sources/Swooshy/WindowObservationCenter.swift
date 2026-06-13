import AppKit
import ApplicationServices
import CoreFoundation
import Foundation

struct AXNotificationRegistrationResult {
    private(set) var needsRetry = false
    private var errorsToLog: [AXError] = []

    mutating func record(_ error: AXError) {
        switch error {
        case .success, .notificationAlreadyRegistered, .notificationUnsupported:
            break
        case .cannotComplete:
            needsRetry = true
        default:
            errorsToLog.append(error)
        }
    }

    mutating func takeErrorsToLog() -> [AXError] {
        defer {
            errorsToLog = []
        }
        return errorsToLog
    }
}

@MainActor
final class WindowObservationCenter {
    static let defaultWindowNotificationNames: [CFString] = [
        kAXUIElementDestroyedNotification as CFString,
        kAXWindowMiniaturizedNotification as CFString,
        kAXWindowDeminiaturizedNotification as CFString,
        kAXWindowMovedNotification as CFString,
        kAXWindowResizedNotification as CFString,
    ]

    private final class ObserverContext {
        weak var center: WindowObservationCenter?
        let processIdentifier: pid_t

        init(center: WindowObservationCenter, processIdentifier: pid_t) {
            self.center = center
            self.processIdentifier = processIdentifier
        }
    }

    private struct ObservedApplication {
        let observer: AXObserver
        let refcon: UnsafeMutableRawPointer
        var appNotificationRetryTask: Task<Void, Never>?
        var appNotificationRetryAttempts: Int
        var observedWindowTokens: Set<DockElementToken>
        var observedWindowsByToken: [DockElementToken: AXUIElement]
    }

    private let appNotificationNames: [CFString] = [
        kAXWindowCreatedNotification as CFString,
        kAXFocusedWindowChangedNotification as CFString,
        kAXMainWindowChangedNotification as CFString,
    ]
    private let windowNotificationNames = WindowObservationCenter.defaultWindowNotificationNames
    private let appNotificationRetryDelayNanoseconds: UInt64
    private let maxAppNotificationRetryAttempts: Int

    static let defaultMaxAppNotificationRetryAttempts = 5

    private var observedApplications: [pid_t: ObservedApplication] = [:]

    var onAccessibilityEvent: ((pid_t, String) -> Void)?

    init(
        appNotificationRetryDelayNanoseconds: UInt64 = 500_000_000,
        maxAppNotificationRetryAttempts: Int = WindowObservationCenter.defaultMaxAppNotificationRetryAttempts
    ) {
        self.appNotificationRetryDelayNanoseconds = appNotificationRetryDelayNanoseconds
        self.maxAppNotificationRetryAttempts = maxAppNotificationRetryAttempts
    }

    static func appNotificationRetryDelayNanoseconds(base: UInt64, attempt: Int) -> UInt64 {
        // Cap the shift so a misconfigured attempt count cannot overflow.
        let cappedAttempt = min(max(attempt, 0), 6)
        let multiplier = UInt64(1) << cappedAttempt
        let (delay, overflow) = base.multipliedReportingOverflow(by: multiplier)
        return overflow ? .max : delay
    }

    func shutdown() {
        let applications = observedApplications.values
        observedApplications = [:]
        for application in applications {
            releaseObserver(application)
        }
    }

    func syncApplications(_ applications: [NSRunningApplication]) {
        let nextProcessIdentifiers = Set(
            applications
                .filter { !$0.isTerminated }
                .map(\.processIdentifier)
        )

        let staleProcessIdentifiers = Set(observedApplications.keys).subtracting(nextProcessIdentifiers)
        for processIdentifier in staleProcessIdentifiers {
            guard let observedApplication = observedApplications.removeValue(forKey: processIdentifier) else {
                continue
            }
            releaseObserver(observedApplication)
        }

        for application in applications where observedApplications[application.processIdentifier] == nil {
            addObserver(for: application)
        }
    }

    func updateObservedWindows(
        _ windows: [AXUIElement],
        for processIdentifier: pid_t
    ) {
        guard var observedApplication = observedApplications[processIdentifier] else {
            return
        }

        let nextTokens = Set(windows.map(DockElementToken.init(element:)))
        let staleTokens = observedApplication.observedWindowTokens.subtracting(nextTokens)
        for staleToken in staleTokens {
            if let window = observedApplication.observedWindowsByToken.removeValue(forKey: staleToken) {
                removeNotifications(
                    windowNotificationNames,
                    from: window,
                    observer: observedApplication.observer
                )
            }
        }

        for window in windows {
            let token = DockElementToken(element: window)
            guard !observedApplication.observedWindowTokens.contains(token) else {
                continue
            }
            addNotifications(
                windowNotificationNames,
                to: window,
                observer: observedApplication.observer,
                refcon: observedApplication.refcon
            )
            observedApplication.observedWindowsByToken[token] = window
        }

        observedApplication.observedWindowTokens = nextTokens
        observedApplications[processIdentifier] = observedApplication
    }

    private func addObserver(for application: NSRunningApplication) {
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard
                let refcon
            else {
                return
            }

            let context = Unmanaged<ObserverContext>.fromOpaque(refcon).takeUnretainedValue()
            guard let center = context.center else {
                return
            }

            let notificationName = notification as String
            Task { @MainActor [weak center] in
                guard let center else {
                    return
                }

                center.handleAccessibilityEvent(
                    processIdentifier: context.processIdentifier,
                    element: element,
                    notification: notificationName
                )
            }
        }

        let createError = AXObserverCreate(application.processIdentifier, callback, &observer)
        guard createError == .success, let observer else {
            DebugLog.debug(
                DebugLog.accessibility,
                "Unable to create AXObserver for pid \(application.processIdentifier); error = \(createError.rawValue)"
            )
            return
        }

        let refcon = Unmanaged.passRetained(
            ObserverContext(center: self, processIdentifier: application.processIdentifier)
        ).toOpaque()
        let appElement = AXAttributeReader.applicationElement(for: application.processIdentifier)
        let registrationResult = addNotifications(
            appNotificationNames,
            to: appElement,
            observer: observer,
            refcon: refcon
        )

        let runLoopSource = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

        observedApplications[application.processIdentifier] = ObservedApplication(
            observer: observer,
            refcon: refcon,
            appNotificationRetryTask: nil,
            appNotificationRetryAttempts: 0,
            observedWindowTokens: [],
            observedWindowsByToken: [:]
        )
        if registrationResult.needsRetry {
            scheduleAppNotificationRetry(for: application.processIdentifier)
        }
    }

    private func handleAccessibilityEvent(
        processIdentifier: pid_t,
        element: AXUIElement,
        notification: String
    ) {
        if
            let actualProcessIdentifier = AXAttributeReader.processIdentifier(of: element),
            actualProcessIdentifier != processIdentifier,
            observedApplications[actualProcessIdentifier] != nil
        {
            onAccessibilityEvent?(actualProcessIdentifier, notification)
            return
        }

        onAccessibilityEvent?(processIdentifier, notification)
    }

    private func releaseObserver(_ observedApplication: ObservedApplication) {
        observedApplication.appNotificationRetryTask?.cancel()
        let runLoopSource = AXObserverGetRunLoopSource(observedApplication.observer)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        Unmanaged<ObserverContext>.fromOpaque(observedApplication.refcon).release()
    }

    private func scheduleAppNotificationRetry(for processIdentifier: pid_t) {
        guard
            var observedApplication = observedApplications[processIdentifier],
            observedApplication.appNotificationRetryTask == nil
        else {
            return
        }

        guard observedApplication.appNotificationRetryAttempts < maxAppNotificationRetryAttempts else {
            DebugLog.debug(
                DebugLog.accessibility,
                "Giving up app notification registration for pid \(processIdentifier) after \(observedApplication.appNotificationRetryAttempts) retries"
            )
            return
        }

        let delay = Self.appNotificationRetryDelayNanoseconds(
            base: appNotificationRetryDelayNanoseconds,
            attempt: observedApplication.appNotificationRetryAttempts
        )
        observedApplication.appNotificationRetryAttempts += 1
        observedApplication.appNotificationRetryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else {
                return
            }

            self.clearAppNotificationRetryTask(for: processIdentifier)
            self.retryAppNotificationRegistration(for: processIdentifier)
        }
        observedApplications[processIdentifier] = observedApplication
    }

    private func clearAppNotificationRetryTask(for processIdentifier: pid_t) {
        guard var observedApplication = observedApplications[processIdentifier] else {
            return
        }

        observedApplication.appNotificationRetryTask = nil
        observedApplications[processIdentifier] = observedApplication
    }

    private func retryAppNotificationRegistration(for processIdentifier: pid_t) {
        guard let observedApplication = observedApplications[processIdentifier] else {
            return
        }

        let appElement = AXAttributeReader.applicationElement(for: processIdentifier)
        let registrationResult = addNotifications(
            appNotificationNames,
            to: appElement,
            observer: observedApplication.observer,
            refcon: observedApplication.refcon
        )
        if registrationResult.needsRetry {
            scheduleAppNotificationRetry(for: processIdentifier)
        }
    }

    @discardableResult
    private func addNotifications(
        _ notifications: [CFString],
        to element: AXUIElement,
        observer: AXObserver,
        refcon: UnsafeMutableRawPointer
    ) -> AXNotificationRegistrationResult {
        var result = AXNotificationRegistrationResult()
        for notification in notifications {
            let error = AXObserverAddNotification(
                observer,
                element,
                notification,
                refcon
            )
            result.record(error)

            for errorToLog in result.takeErrorsToLog() {
                DebugLog.debug(
                    DebugLog.accessibility,
                    "AXObserverAddNotification failed for \(notification as String); error = \(errorToLog.rawValue)"
                )
            }
        }

        return result
    }

    private func removeNotifications(
        _ notifications: [CFString],
        from element: AXUIElement,
        observer: AXObserver
    ) {
        for notification in notifications {
            _ = AXObserverRemoveNotification(observer, element, notification)
        }
    }

}
