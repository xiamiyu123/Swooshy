import ApplicationServices
import Testing
@testable import Swooshy

@MainActor
struct WindowObservationCenterTests {
    @Test
    func windowNotificationsIncludeMoveAndResizeEvents() {
        let names = Set(WindowObservationCenter.defaultWindowNotificationNames.map { $0 as String })

        #expect(names.contains(kAXWindowMovedNotification as String))
        #expect(names.contains(kAXWindowResizedNotification as String))
    }

    @Test
    func cannotCompleteNotificationRegistrationRequestsRetryWithoutLogging() {
        var result = AXNotificationRegistrationResult()

        result.record(.cannotComplete)

        #expect(result.needsRetry)
        #expect(result.takeErrorsToLog().isEmpty)
    }

    @Test
    func permanentNotificationRegistrationErrorsAreLoggedWithoutRetry() {
        var result = AXNotificationRegistrationResult()

        result.record(.apiDisabled)

        #expect(!result.needsRetry)
        #expect(result.takeErrorsToLog().map(\.rawValue) == [AXError.apiDisabled.rawValue])
        #expect(result.takeErrorsToLog().isEmpty)
    }

    @Test
    func supportedBenignNotificationRegistrationResultsAreIgnored() {
        var result = AXNotificationRegistrationResult()

        result.record(.success)
        result.record(.notificationAlreadyRegistered)
        result.record(.notificationUnsupported)

        #expect(!result.needsRetry)
        #expect(result.takeErrorsToLog().isEmpty)
    }

    @Test
    func appNotificationRetryDelayBacksOffExponentially() {
        let base: UInt64 = 500_000_000

        #expect(WindowObservationCenter.appNotificationRetryDelayNanoseconds(base: base, attempt: 0) == base)
        #expect(WindowObservationCenter.appNotificationRetryDelayNanoseconds(base: base, attempt: 1) == base * 2)
        #expect(WindowObservationCenter.appNotificationRetryDelayNanoseconds(base: base, attempt: 4) == base * 16)
    }

    @Test
    func appNotificationRetryDelayIsCappedAndOverflowSafe() {
        let base: UInt64 = 500_000_000

        #expect(
            WindowObservationCenter.appNotificationRetryDelayNanoseconds(base: base, attempt: 100)
                == base * 64
        )
        #expect(
            WindowObservationCenter.appNotificationRetryDelayNanoseconds(base: .max, attempt: 6)
                == .max
        )
        #expect(
            WindowObservationCenter.appNotificationRetryDelayNanoseconds(base: base, attempt: -1)
                == base
        )
    }

    @Test
    func appNotificationRetriesAreBoundedByDefault() {
        #expect(WindowObservationCenter.defaultMaxAppNotificationRetryAttempts == 5)
    }
}
