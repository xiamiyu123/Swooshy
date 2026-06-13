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
        legacyBrowserWindowCloseConfirmationEnabled: Bool,
        requiresDangerConfirmation: Bool,
        isReplacedBySmartFullScreenExit: Bool
    ) -> Bool {
        guard !isReplacedBySmartFullScreenExit else {
            return false
        }

        if requiresDangerConfirmation {
            return true
        }

        guard
            gesture.isPinch,
            legacyBrowserWindowCloseConfirmationEnabled,
            action == .closeWindow,
            let appIdentity = application.appIdentity,
            BrowserTabProbe.supportsTabCloseHost(
                bundleIdentifier: appIdentity.bundleIdentifier,
                localizedName: appIdentity.localizedName
            )
        else {
            return false
        }

        return true
    }
}

extension DockGestureKind {
    var isPinch: Bool {
        self == .pinchIn || self == .pinchOut
    }
}
