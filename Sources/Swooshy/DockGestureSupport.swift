import CoreGraphics

enum CornerDragSource: Equatable {
    case dock
    case titleBar

    var logLabel: String {
        switch self {
        case .dock:
            "dock"
        case .titleBar:
            "title-bar"
        }
    }
}

enum TwoFingerTouchSequenceTransition: Equatable {
    case none
    case restarted(previousIdentifiers: [Int], currentIdentifiers: [Int])
}

struct TwoFingerTouchSequenceTracker {
    private var previousIdentifiers: [Int] = []

    mutating func consume(_ frame: TrackpadTouchFrame) -> TwoFingerTouchSequenceTransition {
        let currentIdentifiers = sortedTwoFingerIdentifiers(in: frame)
        defer {
            previousIdentifiers = currentIdentifiers
        }

        guard previousIdentifiers.count == 2, currentIdentifiers.count == 2 else {
            return .none
        }

        if previousIdentifiers != currentIdentifiers {
            return .restarted(
                previousIdentifiers: previousIdentifiers,
                currentIdentifiers: currentIdentifiers
            )
        }

        return .none
    }

    mutating func reset() {
        previousIdentifiers = []
    }

    private func sortedTwoFingerIdentifiers(in frame: TrackpadTouchFrame) -> [Int] {
        guard frame.touches.count == 2 else {
            return []
        }

        return frame.touches.map(\.identifier).sorted()
    }
}

enum GestureSessionTouchInterruption: Equatable {
    case release
    case invalidAdditionalTouch
}

func gestureSessionTouchInterruption(
    touchCount: Int,
    previousTouchCount: Int,
    hasPendingReleaseAction: Bool,
    hasActiveCornerDrag: Bool
) -> GestureSessionTouchInterruption? {
    if touchCount < 2, previousTouchCount == 2 {
        return .release
    }

    guard touchCount > 2 else {
        return nil
    }

    return hasPendingReleaseAction || hasActiveCornerDrag ? .invalidAdditionalTouch : nil
}

func gestureHoverLookupRequired(
    gesturesEnabled: Bool,
    standardRecognizerRequiresHoveredApplication: Bool,
    cornerDragEnabled: Bool,
    cornerDragRecognizerRequiresHoveredApplication: Bool,
    hasActiveCornerDragApplication: Bool
) -> Bool {
    guard gesturesEnabled, !hasActiveCornerDragApplication else {
        return false
    }

    return standardRecognizerRequiresHoveredApplication ||
        (cornerDragEnabled && cornerDragRecognizerRequiresHoveredApplication)
}

func cornerDragAction(
    forTouchTranslation translation: CGPoint,
    threshold: CGFloat
) -> WindowAction? {
    guard abs(translation.x) >= threshold, abs(translation.y) >= threshold else {
        return nil
    }

    if translation.x < 0, translation.y > 0 {
        return .topLeftQuarter
    }
    if translation.x > 0, translation.y > 0 {
        return .topRightQuarter
    }
    if translation.x < 0, translation.y < 0 {
        return .bottomLeftQuarter
    }
    if translation.x > 0, translation.y < 0 {
        return .bottomRightQuarter
    }

    return nil
}

func cornerDragTransitionAction(
    from currentAction: WindowAction,
    forTouchTranslation translation: CGPoint,
    threshold: CGFloat
) -> WindowAction {
    guard abs(translation.x) >= threshold || abs(translation.y) >= threshold else {
        return currentAction
    }

    if abs(translation.x) >= abs(translation.y) {
        return horizontalCornerDragTransition(
            from: currentAction,
            movingRight: translation.x > 0
        )
    }

    return verticalCornerDragTransition(
        from: currentAction,
        movingUp: translation.y > 0
    )
}

private func horizontalCornerDragTransition(
    from currentAction: WindowAction,
    movingRight: Bool
) -> WindowAction {
    switch (currentAction, movingRight) {
    case (.topLeftQuarter, true):
        .topRightQuarter
    case (.bottomLeftQuarter, true):
        .bottomRightQuarter
    case (.topRightQuarter, false):
        .topLeftQuarter
    case (.bottomRightQuarter, false):
        .bottomLeftQuarter
    default:
        currentAction
    }
}

private func verticalCornerDragTransition(
    from currentAction: WindowAction,
    movingUp: Bool
) -> WindowAction {
    switch (currentAction, movingUp) {
    case (.bottomLeftQuarter, true):
        .topLeftQuarter
    case (.bottomRightQuarter, true):
        .topRightQuarter
    case (.topLeftQuarter, false):
        .bottomLeftQuarter
    case (.topRightQuarter, false):
        .bottomRightQuarter
    default:
        currentAction
    }
}

func titleBarDangerGestureConfirmationMatches(
    pendingConfirmationGesture: DockGestureKind,
    pendingApplication: InteractionTarget,
    confirmationGesture: DockGestureKind,
    application: InteractionTarget
) -> Bool {
    pendingConfirmationGesture == confirmationGesture &&
        pendingApplication == application
}

func dockDangerGestureConfirmationMatches(
    pendingConfirmationGesture: DockGestureKind,
    pendingApplication: InteractionTarget,
    confirmationGesture: DockGestureKind,
    application: InteractionTarget
) -> Bool {
    pendingConfirmationGesture == confirmationGesture &&
        pendingApplication == application
}
