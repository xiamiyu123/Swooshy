import AppKit
import ApplicationServices
import CoreFoundation
import Foundation

@MainActor
final class WindowObservationCenter {
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
        var observedWindowTokens: Set<DockElementToken>
        var observedWindowsByToken: [DockElementToken: AXUIElement]
    }

    private let appNotificationNames: [CFString] = [
        kAXWindowCreatedNotification as CFString,
        kAXFocusedWindowChangedNotification as CFString,
        kAXMainWindowChangedNotification as CFString,
    ]
    private let windowNotificationNames: [CFString] = [
        kAXUIElementDestroyedNotification as CFString,
        kAXWindowMiniaturizedNotification as CFString,
        kAXWindowDeminiaturizedNotification as CFString,
    ]

    private var observedApplications: [pid_t: ObservedApplication] = [:]

    var onAccessibilityEvent: ((pid_t, String) -> Void)?

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
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        addNotifications(
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
            observedWindowTokens: [],
            observedWindowsByToken: [:]
        )
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
        let runLoopSource = AXObserverGetRunLoopSource(observedApplication.observer)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        Unmanaged<ObserverContext>.fromOpaque(observedApplication.refcon).release()
    }

    private func addNotifications(
        _ notifications: [CFString],
        to element: AXUIElement,
        observer: AXObserver,
        refcon: UnsafeMutableRawPointer
    ) {
        for notification in notifications {
            let error = AXObserverAddNotification(
                observer,
                element,
                notification,
                refcon
            )

            guard shouldLogNotificationError(error) else {
                continue
            }

            DebugLog.debug(
                DebugLog.accessibility,
                "AXObserverAddNotification failed for \(notification as String); error = \(error.rawValue)"
            )
        }
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

    private func shouldLogNotificationError(_ error: AXError) -> Bool {
        switch error {
        case .success, .notificationAlreadyRegistered, .notificationUnsupported, .cannotComplete:
            return false
        default:
            return true
        }
    }
}
