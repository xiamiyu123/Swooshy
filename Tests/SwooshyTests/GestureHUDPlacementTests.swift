import CoreGraphics
import Testing
@testable import Swooshy

struct GestureHUDPositionTests {
    @Test
    func storageValuesRemainStable() {
        #expect(GestureHUDPosition.followPointer.storageValue == "followPointer")
        #expect(GestureHUDPosition.topCenter.storageValue == "topCenter")
        #expect(GestureHUDPosition.customOffset.storageValue == "customOffset")
    }

    @Test
    func storageValuesDecodeKnownAndUnknownNames() {
        let cases: [(storageValue: String?, position: GestureHUDPosition)] = [
            ("followPointer", .followPointer),
            ("topCenter", .topCenter),
            ("customOffset", .customOffset),
            ("unknown", .followPointer),
            (nil, .followPointer),
        ]

        for (storageValue, position) in cases {
            #expect(GestureHUDPosition(storageValue: storageValue) == position)
        }
    }
}

struct GestureHUDPlacementResolverTests {
    private let primaryVisibleFrame = CGRect(x: 0, y: 24, width: 1440, height: 836)
    private let anchorPoint = CGPoint(x: 720, y: 400)
    private let panelSizes = [
        CGSize(width: 208, height: 42),
        CGSize(width: 182, height: 40),
        CGSize(width: 40, height: 40),
    ]

    @Test
    func followPointerPreservesExistingPositionForEveryHUDSize() {
        for panelSize in panelSizes {
            let frame = GestureHUDPlacementResolver.frame(
                anchorPoint: anchorPoint,
                visibleFrame: primaryVisibleFrame,
                panelSize: panelSize,
                placement: GestureHUDPlacement(position: .followPointer)
            )

            #expect(
                frame == CGRect(
                    x: anchorPoint.x - panelSize.width / 2,
                    y: anchorPoint.y + GestureHUDPlacementResolver.pointerVerticalGap,
                    width: panelSize.width,
                    height: panelSize.height
                )
            )
        }
    }

    @Test
    func topCenterUsesTheCurrentVisibleFrameForEveryHUDSize() {
        for panelSize in panelSizes {
            let frame = GestureHUDPlacementResolver.frame(
                anchorPoint: anchorPoint,
                visibleFrame: primaryVisibleFrame,
                panelSize: panelSize,
                placement: GestureHUDPlacement(position: .topCenter)
            )

            #expect(frame.midX == primaryVisibleFrame.midX)
            #expect(frame.maxY == primaryVisibleFrame.maxY - GestureHUDPlacementResolver.sideMargin)
            #expect(frame.size == panelSize)
        }
    }

    @Test
    func customOffsetMovesThePointerPlacementInBothDirections() {
        let panelSize = CGSize(width: 182, height: 40)
        let cases: [(horizontalOffset: CGFloat, verticalOffset: CGFloat, expectedOrigin: CGPoint)] = [
            (60, -80, CGPoint(x: 369, y: 138)),
            (-60, 80, CGPoint(x: 249, y: 298)),
        ]

        for testCase in cases {
            let frame = GestureHUDPlacementResolver.frame(
                anchorPoint: CGPoint(x: 400, y: 200),
                visibleFrame: primaryVisibleFrame,
                panelSize: panelSize,
                placement: GestureHUDPlacement(
                    position: .customOffset,
                    horizontalOffset: testCase.horizontalOffset,
                    verticalOffset: testCase.verticalOffset
                )
            )

            #expect(frame.origin == testCase.expectedOrigin)
            #expect(frame.size == panelSize)
        }
    }

    @Test
    func placementClampsToEveryVisibleFrameEdge() {
        let panelSize = CGSize(width: 208, height: 42)
        let cases: [(anchorPoint: CGPoint, expectedOrigin: CGPoint)] = [
            (CGPoint(x: 0, y: 400), CGPoint(x: 10, y: 418)),
            (CGPoint(x: 1440, y: 400), CGPoint(x: 1_222, y: 418)),
            (CGPoint(x: 720, y: -100), CGPoint(x: 616, y: 34)),
            (CGPoint(x: 720, y: 860), CGPoint(x: 616, y: 808)),
        ]

        for testCase in cases {
            let frame = GestureHUDPlacementResolver.frame(
                anchorPoint: testCase.anchorPoint,
                visibleFrame: primaryVisibleFrame,
                panelSize: panelSize,
                placement: GestureHUDPlacement(position: .followPointer)
            )

            #expect(frame.origin == testCase.expectedOrigin)
        }
    }

    @Test
    func topCenterUsesEachDisplayVisibleFrameInMixedResolutionLayouts() {
        let panelSize = CGSize(width: 182, height: 40)
        let visibleFrames = [
            CGRect(x: 0, y: 24, width: 1_920, height: 1_056), // 1080p
            CGRect(x: -1_512, y: 0, width: 1_512, height: 982), // Retina logical points
            CGRect(x: -1_280, y: 900, width: 1_280, height: 720), // Left and above
        ]

        for visibleFrame in visibleFrames {
            let frame = GestureHUDPlacementResolver.frame(
                anchorPoint: CGPoint(x: visibleFrame.midX, y: visibleFrame.midY),
                visibleFrame: visibleFrame,
                panelSize: panelSize,
                placement: GestureHUDPlacement(position: .topCenter)
            )

            #expect(frame.midX == visibleFrame.midX)
            #expect(frame.maxY == visibleFrame.maxY - GestureHUDPlacementResolver.sideMargin)
            #expect(frame.size == panelSize)
        }
    }

    @Test
    func oversizedHUDCentersInsteadOfUsingInvertedClampBounds() {
        let visibleFrame = CGRect(x: 100, y: 200, width: 100, height: 40)
        let panelSize = CGSize(width: 208, height: 42)
        let frame = GestureHUDPlacementResolver.frame(
            anchorPoint: CGPoint(x: 150, y: 240),
            visibleFrame: visibleFrame,
            panelSize: panelSize,
            placement: GestureHUDPlacement(position: .followPointer)
        )

        #expect(frame.midX == visibleFrame.midX)
        #expect(frame.midY == visibleFrame.midY)
    }
}
