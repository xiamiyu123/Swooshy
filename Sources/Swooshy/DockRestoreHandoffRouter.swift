import Foundation

struct MinimizedWindowReference: Equatable, Sendable {
    let appIdentity: AppIdentity
    let windowIdentity: WindowIdentity

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.appIdentity == rhs.appIdentity &&
            lhs.appIdentity.processIdentifier == rhs.appIdentity.processIdentifier &&
            lhs.windowIdentity == rhs.windowIdentity
    }
}

struct MinimizeVisibleWindowResult: Equatable, Sendable {
    let performed: Bool
    let reference: MinimizedWindowReference?
}

@MainActor
struct DockRestoreHandoffRouter {
    private struct PendingHandoff {
        let reference: MinimizedWindowReference
        let expiresAt: Date
    }

    private let ttl: TimeInterval
    private let now: () -> Date
    private var pendingHandoff: PendingHandoff?

    init(
        ttl: TimeInterval = 1.5,
        now: @escaping () -> Date = Date.init
    ) {
        self.ttl = ttl
        self.now = now
    }

    mutating func record(_ reference: MinimizedWindowReference) {
        pendingHandoff = PendingHandoff(
            reference: reference,
            expiresAt: now().addingTimeInterval(ttl)
        )
    }

    mutating func consumeRestoreWindow(for target: InteractionTarget) -> WindowIdentity? {
        guard let pendingHandoff else {
            return nil
        }

        guard now() <= pendingHandoff.expiresAt else {
            self.pendingHandoff = nil
            return nil
        }

        guard
            let appIdentity = target.appIdentity,
            target.source?.isDockAppItem == true,
            matches(pendingHandoff.reference.appIdentity, appIdentity)
        else {
            return nil
        }

        self.pendingHandoff = nil
        return pendingHandoff.reference.windowIdentity
    }

    private func matches(_ lhs: AppIdentity, _ rhs: AppIdentity) -> Bool {
        lhs == rhs && lhs.processIdentifier == rhs.processIdentifier
    }
}

extension InteractionSource {
    var isDockAppItem: Bool {
        switch self {
        case .dockAppItem:
            true
        case .dockMinimizedItem, .titleBar, .browserTabFallback:
            false
        }
    }
}
