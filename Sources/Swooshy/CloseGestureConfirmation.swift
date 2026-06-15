import Foundation

/// Identifies a single gesture on a given surface that the user has marked as
/// requiring a second confirmation gesture before it executes.
struct DangerGestureConfirmationSelection: Codable, Hashable, Identifiable, Sendable {
    let surface: GestureExclusionSurface
    let gesture: DockGestureKind

    var id: String {
        "\(surface.rawValue).\(gesture.rawValue)"
    }
}

@MainActor
enum CloseGestureConfirmationPolicy {
    // Reserved for future per-action confirmation gating (e.g. only require
    // confirmation for destructive actions like quit, not for close). Today
    // confirmation is gated solely on `requiresDangerConfirmation`; the
    // `gesture`/`action`/`application` parameters are intentionally kept on
    // the API surface so call sites and tests already pass meaningful values,
    // and a future per-action policy can read them without reshuffling every
    // caller. Do not remove them thinking they are dead code.
    static func requiresConfirmationForDockGesture(
        gesture: DockGestureKind,
        action: DockGestureAction,
        requiresDangerConfirmation: Bool
    ) -> Bool {
        requiresDangerConfirmation
    }

    static func requiresConfirmationForTitleBarGesture(
        gesture: DockGestureKind,
        action: WindowAction,
        application: InteractionTarget,
        requiresDangerConfirmation: Bool,
        isReplacedBySmartFullScreenExit: Bool
    ) -> Bool {
        guard !isReplacedBySmartFullScreenExit else {
            return false
        }

        return requiresDangerConfirmation
    }
}

extension DockGestureKind {
    var isPinch: Bool {
        self == .pinchIn || self == .pinchOut
    }
}
