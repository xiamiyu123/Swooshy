import CoreGraphics

struct WindowLayoutEngine {
    private let centeredFillRatio: CGFloat = 0.8

    func targetFrame(
        for action: WindowAction,
        currentWindowFrame: CGRect,
        currentVisibleFrame: CGRect
    ) -> CGRect {
        switch action {
        case .leftHalf:
            return leftHalfFrame(in: currentVisibleFrame)
        case .rightHalf:
            return rightHalfFrame(in: currentVisibleFrame)
        case .maximize:
            return currentVisibleFrame.integral
        case .center:
            return centeredFrame(in: currentVisibleFrame)
        case .minimize, .closeWindow, .quitApplication, .cycleSameAppWindows:
            return currentWindowFrame
        }
    }

    func screenContainingMost(of windowFrame: CGRect, in screenFrames: [CGRect]) -> CGRect? {
        screenFrames.max { lhs, rhs in
            lhs.intersection(windowFrame).area < rhs.intersection(windowFrame).area
        }
    }

    private func leftHalfFrame(in visibleFrame: CGRect) -> CGRect {
        let splitX = visibleFrame.minX + floor(visibleFrame.width / 2)
        return CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: splitX - visibleFrame.minX,
            height: visibleFrame.height
        ).integral
    }

    private func rightHalfFrame(in visibleFrame: CGRect) -> CGRect {
        let splitX = visibleFrame.minX + floor(visibleFrame.width / 2)
        return CGRect(
            x: splitX,
            y: visibleFrame.minY,
            width: visibleFrame.maxX - splitX,
            height: visibleFrame.height
        ).integral
    }

    private func centeredFrame(in visibleFrame: CGRect) -> CGRect {
        let width = min(visibleFrame.width, floor(visibleFrame.width * centeredFillRatio))
        let height = min(visibleFrame.height, floor(visibleFrame.height * centeredFillRatio))

        return CGRect(
            x: floor(visibleFrame.midX - (width / 2)),
            y: floor(visibleFrame.midY - (height / 2)),
            width: width,
            height: height
        )
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
