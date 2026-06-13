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
