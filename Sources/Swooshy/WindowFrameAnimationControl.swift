import ApplicationServices

/// Prevents native AX animations from interrupting a joint frame transition.
@MainActor
final class WindowFrameAnimationControl {
    private struct State {
        var users = 1
        let restoreEnhancedUI: Bool
    }

    private static let attribute = "AXEnhancedUserInterface" as CFString
    private let readEnabled: (pid_t) -> Bool?
    private let writeEnabled: (pid_t, Bool) -> AXError
    private var states: [pid_t: State] = [:]

    init(
        readEnabled: @escaping (pid_t) -> Bool? = {
            AXAttributeReader.bool(attribute, from: AXAttributeReader.applicationElement(for: $0))
        },
        writeEnabled: @escaping (pid_t, Bool) -> AXError = {
            AXUIElementSetAttributeValue(
                AXAttributeReader.applicationElement(for: $0), attribute,
                $1 ? kCFBooleanTrue : kCFBooleanFalse
            )
        }
    ) {
        self.readEnabled = readEnabled
        self.writeEnabled = writeEnabled
    }

    func begin(for pid: pid_t) throws {
        if var state = states[pid] {
            state.users += 1
            states[pid] = state
            return
        }
        let enabled = readEnabled(pid)
        if enabled == true {
            let error = writeEnabled(pid, false)
            guard error == .success else {
                DebugLog.error(DebugLog.windows, "Cannot suspend native AX animation: pid=\(pid), error=\(error.rawValue)")
                throw WindowManagerError.unableToSetFrame
            }
        }
        states[pid] = State(restoreEnhancedUI: enabled == true)
        DebugLog.debug(DebugLog.windows, "Joint transition scope: pid=\(pid), enhancedUI=\(enabled.map(String.init) ?? "unknown")")
    }

    func end(for pid: pid_t) {
        guard var state = states[pid] else { return }
        state.users -= 1
        if state.users > 0 {
            states[pid] = state
            return
        }
        states.removeValue(forKey: pid)
        restore(for: pid, state: state)
    }

    func shutdown() {
        for (pid, state) in states { restore(for: pid, state: state) }
        states.removeAll()
    }

    private func restore(for pid: pid_t, state: State) {
        guard state.restoreEnhancedUI else { return }
        let error = writeEnabled(pid, true)
        if error != .success {
            DebugLog.error(DebugLog.windows, "Cannot restore enhanced AX UI: pid=\(pid), error=\(error.rawValue)")
        }
    }
}
