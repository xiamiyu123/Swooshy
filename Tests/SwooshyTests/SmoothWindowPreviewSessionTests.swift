import CoreGraphics
import Testing
@testable import Swooshy

@MainActor
struct SmoothWindowPreviewSessionTests {
    @Test
    func animateMovesTowardTarget() async {
        let original = CGRect(x: 0, y: 0, width: 100, height: 100)
        var appliedFrames: [CGRect] = []

        let session = SmoothWindowPreviewSession(
            originalAppKitFrame: original,
            loadCurrentAppKitFrame: { original },
            applyAppKitFrame: { frame in
                appliedFrames.append(frame)
            }
        )

        let target = CGRect(x: 400, y: 300, width: 500, height: 400)
        session.animate(to: target)

        // 等待一段时间让追踪循环运行若干步
        try? await Task.sleep(nanoseconds: 200_000_000) // ~0.2 秒

        session.finish()

        #expect(appliedFrames.count >= 1)
        guard
            let first = appliedFrames.first,
            let last = appliedFrames.last
        else { return }

        func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
            abs(a.minX - b.minX)
            + abs(a.minY - b.minY)
            + abs(a.width - b.width)
            + abs(a.height - b.height)
        }

        // 最后一帧应该比第一帧更接近目标
        #expect(distance(last, target) < distance(first, target))
    }

    @Test
    func finishStopsFurtherAnimation() async {
        let original = CGRect(x: 0, y: 0, width: 100, height: 100)
        var appliedFrames: [CGRect] = []

        let session = SmoothWindowPreviewSession(
            originalAppKitFrame: original,
            loadCurrentAppKitFrame: { original },
            applyAppKitFrame: { frame in
                appliedFrames.append(frame)
            }
        )

        let target = CGRect(x: 200, y: 0, width: 300, height: 200)
        session.animate(to: target)

        // 先等几帧
        try? await Task.sleep(nanoseconds: 80_000_000)
        let countBeforeFinish = appliedFrames.count

        session.finish()

        // 再等一段时间，确保不会有新的帧被应用
        try? await Task.sleep(nanoseconds: 120_000_000)
        let countAfterFinish = appliedFrames.count

        #expect(countAfterFinish == countBeforeFinish)
    }
}
