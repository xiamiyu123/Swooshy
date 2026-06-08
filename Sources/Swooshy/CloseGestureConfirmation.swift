import Foundation

enum CloseGestureConfirmationAction: Equatable {
    case closeWindow
    case quitApplication

    init?(_ action: WindowAction) {
        switch action {
        case .closeWindow:
            self = .closeWindow
        case .quitApplication:
            self = .quitApplication
        default:
            return nil
        }
    }

    init?(_ action: DockGestureAction) {
        switch action {
        case .closeWindow:
            self = .closeWindow
        case .quitApplication:
            self = .quitApplication
        default:
            return nil
        }
    }

    var confirmationPromptLocalizationKey: String {
        switch self {
        case .closeWindow:
            "confirmation.pinch_again.close_window"
        case .quitApplication:
            "confirmation.pinch_again.quit_application"
        }
    }
}

@MainActor
enum CloseGestureConfirmationPolicy {
    static func confirmationActionForDockGesture(
        gesture: DockGestureKind,
        action: DockGestureAction,
        closeAndQuitConfirmationEnabled: Bool
    ) -> CloseGestureConfirmationAction? {
        guard gesture.isPinch, closeAndQuitConfirmationEnabled else {
            return nil
        }

        return CloseGestureConfirmationAction(action)
    }

    static func confirmationActionForTitleBarGesture(
        gesture: DockGestureKind,
        action: WindowAction,
        application: InteractionTarget,
        legacyBrowserWindowCloseConfirmationEnabled: Bool,
        closeAndQuitConfirmationEnabled: Bool
    ) -> CloseGestureConfirmationAction? {
        guard gesture.isPinch else {
            return nil
        }

        if closeAndQuitConfirmationEnabled {
            return CloseGestureConfirmationAction(action)
        }

        guard
            legacyBrowserWindowCloseConfirmationEnabled,
            action == .closeWindow,
            let appIdentity = application.appIdentity,
            BrowserTabProbe.supportsTabCloseHost(
                bundleIdentifier: appIdentity.bundleIdentifier,
                localizedName: appIdentity.localizedName
            )
        else {
            return nil
        }

        return .closeWindow
    }
}

extension DockGestureKind {
    var isPinch: Bool {
        self == .pinchIn || self == .pinchOut
    }
}
