import AppKit
import Foundation

enum TitleBarHoverSource: Equatable {
    case titleBar
    case browserTabFallback

    func allowsGestureAction(_ action: WindowAction) -> Bool {
        switch self {
        case .titleBar:
            return true
        case .browserTabFallback:
            return action.supportsBrowserTabCloseReplacement
        }
    }
}

struct TitleBarHoverTarget: Equatable {
    let application: InteractionTarget
    let source: TitleBarHoverSource

    var logDescription: String {
        switch source {
        case .titleBar:
            return application.logDescription
        case .browserTabFallback:
            return "\(application.logDescription) via browser-tab fallback"
        }
    }
}

struct TitleBarHoverHit: Equatable {
    let target: TitleBarHoverTarget
    let processIdentifier: pid_t
    let frame: CGRect
    let isFullScreen: Bool
}
