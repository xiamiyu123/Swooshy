import CoreGraphics

struct ReleaseDeferredGestureState {
    enum Action: Equatable {
        case dock(action: DockGestureAction, application: InteractionTarget)
        case titleBar(
            action: WindowAction,
            event: DockGestureEvent,
            anchorPoint: CGPoint,
            replacesWithTabClose: Bool
        )
        case cornerDrag(
            action: WindowAction,
            application: InteractionTarget,
            anchorPoint: CGPoint,
            source: CornerDragSource
        )
    }

    enum ActionKind: Equatable {
        case dock
        case titleBar
        case cornerDrag
    }

    private(set) var action: Action?
    private(set) var gestureKind: DockGestureKind?
    private var highWaterMark: CGFloat?
    private var pinchHighWaterMark: CGFloat?

    var hasAction: Bool {
        action != nil
    }

    var hasGestureAnchor: Bool {
        gestureKind != nil
    }

    var actionKind: ActionKind? {
        switch action {
        case .dock:
            .dock
        case .titleBar:
            .titleBar
        case .cornerDrag:
            .cornerDrag
        case .none:
            nil
        }
    }

    var actionDebugDescription: String {
        switch actionKind {
        case .dock:
            "dock"
        case .titleBar:
            "titleBar"
        case .cornerDrag:
            "cornerDrag"
        case .none:
            "none"
        }
    }

    mutating func stageDockAction(
        _ dockAction: DockGestureAction,
        application: InteractionTarget,
        gesture: DockGestureKind,
        touches: [TrackpadTouchSample]
    ) {
        action = .dock(action: dockAction, application: application)
        storeTouchAnchor(gesture: gesture, touches: touches)
    }

    mutating func stageTitleBarAction(
        _ windowAction: WindowAction,
        event: DockGestureEvent,
        anchorPoint: CGPoint,
        replacesWithTabClose: Bool,
        touches: [TrackpadTouchSample]
    ) {
        action = .titleBar(
            action: windowAction,
            event: event,
            anchorPoint: anchorPoint,
            replacesWithTabClose: replacesWithTabClose
        )
        storeTouchAnchor(gesture: event.gesture, touches: touches)
    }

    mutating func stageCornerDragAction(
        _ windowAction: WindowAction,
        application: InteractionTarget,
        anchorPoint: CGPoint,
        source: CornerDragSource
    ) {
        action = .cornerDrag(
            action: windowAction,
            application: application,
            anchorPoint: anchorPoint,
            source: source
        )
    }

    mutating func clearCornerDragAction() {
        if case .cornerDrag = action {
            action = nil
        }
    }

    mutating func clear() {
        action = nil
        clearTouchAnchor()
    }

    mutating func takeAction() -> (action: Action, gesture: DockGestureKind?)? {
        guard let action else {
            return nil
        }
        let gesture = gestureKind
        clear()
        return (action, gesture)
    }

    mutating func reverseCancellationGesture(
        for frame: TrackpadTouchFrame,
        threshold: CGFloat
    ) -> DockGestureKind? {
        guard
            let gestureKind,
            let highWaterMark,
            frame.touches.count == 2
        else {
            return nil
        }

        let p0 = frame.touches[0].position
        let p1 = frame.touches[1].position
        let avg = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        let shouldCancel: Bool

        if gestureKind == .pinchIn {
            let currentDistance = hypot(p1.x - p0.x, p1.y - p0.y)
            let pinchHighWater = pinchHighWaterMark ?? currentDistance
            if currentDistance < pinchHighWater {
                pinchHighWaterMark = currentDistance
            }
            let retreat = currentDistance - (pinchHighWaterMark ?? currentDistance)
            shouldCancel = retreat > threshold
        } else if gestureKind == .pinchOut {
            let currentDistance = hypot(p1.x - p0.x, p1.y - p0.y)
            let pinchHighWater = pinchHighWaterMark ?? currentDistance
            if currentDistance > pinchHighWater {
                pinchHighWaterMark = currentDistance
            }
            let retreat = (pinchHighWaterMark ?? currentDistance) - currentDistance
            shouldCancel = retreat > threshold
        } else {
            let current = gestureDirectionComponent(for: gestureKind, point: avg)
            if current > highWaterMark {
                self.highWaterMark = current
            }
            let retreat = (self.highWaterMark ?? current) - current
            shouldCancel = retreat > threshold
        }

        return shouldCancel ? gestureKind : nil
    }

    static func reverseCancelThreshold(sensitivity: Double) -> CGFloat {
        let minThreshold: CGFloat = 0.005
        let maxThreshold: CGFloat = 0.06
        return CGFloat(maxThreshold - sensitivity * (maxThreshold - minThreshold))
    }

    private mutating func storeTouchAnchor(
        gesture: DockGestureKind,
        touches: [TrackpadTouchSample]
    ) {
        gestureKind = gesture
        guard touches.count >= 2 else {
            highWaterMark = nil
            pinchHighWaterMark = nil
            return
        }

        let p0 = touches[0].position
        let p1 = touches[1].position
        let avg = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        highWaterMark = gestureDirectionComponent(for: gesture, point: avg)
        pinchHighWaterMark = hypot(p1.x - p0.x, p1.y - p0.y)
    }

    private mutating func clearTouchAnchor() {
        gestureKind = nil
        highWaterMark = nil
        pinchHighWaterMark = nil
    }

    private func gestureDirectionComponent(
        for gesture: DockGestureKind,
        point: CGPoint
    ) -> CGFloat {
        switch gesture {
        case .swipeLeft:
            -point.x
        case .swipeRight:
            point.x
        case .swipeUp:
            point.y
        case .swipeDown:
            -point.y
        case .pinchIn, .pinchOut:
            0
        }
    }
}
