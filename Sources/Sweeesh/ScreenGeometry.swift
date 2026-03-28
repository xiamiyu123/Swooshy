import CoreGraphics

struct ScreenGeometry {
    private let desktopBounds: CGRect

    init(screenFrames: [CGRect]) {
        self.desktopBounds = screenFrames.reduce(into: .null) { partialResult, frame in
            partialResult = partialResult.union(frame)
        }
    }

    func appKitFrame(fromAXFrame frame: CGRect) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: desktopBounds.maxY - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        ).integral
    }

    func axFrame(fromAppKitFrame frame: CGRect) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: desktopBounds.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        ).integral
    }
}
