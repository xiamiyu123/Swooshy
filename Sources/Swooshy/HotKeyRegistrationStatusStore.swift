import Carbon.HIToolbox
import Observation

struct HotKeyRegistrationFailure: Equatable, Sendable {
    let action: WindowAction
    let binding: HotKeyBinding
    let status: OSStatus
}

@MainActor
@Observable
final class HotKeyRegistrationStatusStore {
    private(set) var failures: [WindowAction: HotKeyRegistrationFailure] = [:]
    private(set) var handlerUnavailable = false

    var hasIssue: Bool {
        handlerUnavailable || failures.isEmpty == false
    }

    func failure(for action: WindowAction) -> HotKeyRegistrationFailure? {
        failures[action]
    }

    func issueKind(for action: WindowAction) -> HotKeyRegistrationIssueKind? {
        if handlerUnavailable {
            return .handlerUnavailable
        }

        if failures[action] != nil {
            return .registrationFailed
        }

        return nil
    }

    func recordFailure(_ failure: HotKeyRegistrationFailure) {
        handlerUnavailable = false
        failures[failure.action] = failure
    }

    func markHandlerUnavailable() {
        failures.removeAll()
        handlerUnavailable = true
    }

    func clear() {
        failures.removeAll()
        handlerUnavailable = false
    }
}

enum HotKeyRegistrationIssueKind: Equatable, Sendable {
    case registrationFailed
    case handlerUnavailable
}
