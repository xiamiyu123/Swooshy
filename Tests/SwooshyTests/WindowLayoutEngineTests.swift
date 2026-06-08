import CoreGraphics
import Testing
@testable import Swooshy

struct WindowLayoutEngineTests {
    private let engine = WindowLayoutEngine()
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let defaultWindowFrame = CGRect(x: 100, y: 100, width: 800, height: 600)

    private func targetFrame(for action: WindowAction) -> CGRect {
        engine.targetFrame(
            for: action,
            currentWindowFrame: defaultWindowFrame,
            currentVisibleFrame: visibleFrame
        )
    }

    private func observation(
        minimumWidth: CGFloat? = nil,
        maximumWidth: CGFloat? = nil,
        minimumHeight: CGFloat? = nil,
        maximumHeight: CGFloat? = nil,
        horizontalAnchor: WindowActionPreview.AxisAnchor,
        verticalAnchor: WindowActionPreview.AxisAnchor
    ) -> WindowActionPreview.Observation {
        WindowActionPreview.Observation(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: minimumWidth,
                maximumWidth: maximumWidth,
                minimumHeight: minimumHeight,
                maximumHeight: maximumHeight
            ),
            horizontalAnchor: horizontalAnchor,
            verticalAnchor: verticalAnchor
        )
    }

    @Test
    func leftHalfUsesLeftSideOfVisibleFrame() {
        let frame = targetFrame(for: .leftHalf)

        #expect(frame == CGRect(x: 0, y: 0, width: 720, height: 900))
    }

    @Test
    func rightHalfUsesRightSideOfVisibleFrame() {
        let frame = targetFrame(for: .rightHalf)

        #expect(frame == CGRect(x: 720, y: 0, width: 720, height: 900))
    }

    @Test
    func maximizeUsesEntireVisibleFrame() {
        let frame = targetFrame(for: .maximize)

        #expect(frame == visibleFrame)
    }

    @Test
    func centerUsesEntireVisibleFrame() {
        let frame = targetFrame(for: .center)

        #expect(frame == visibleFrame)
    }

    @Test
    func topLeftQuarterUsesTopLeftAreaOfVisibleFrame() {
        let frame = targetFrame(for: .topLeftQuarter)

        #expect(frame == CGRect(x: 0, y: 450, width: 720, height: 450))
    }

    @Test
    func topRightQuarterUsesTopRightAreaOfVisibleFrame() {
        let frame = targetFrame(for: .topRightQuarter)

        #expect(frame == CGRect(x: 720, y: 450, width: 720, height: 450))
    }

    @Test
    func bottomLeftQuarterUsesBottomLeftAreaOfVisibleFrame() {
        let frame = targetFrame(for: .bottomLeftQuarter)

        #expect(frame == CGRect(x: 0, y: 0, width: 720, height: 450))
    }

    @Test
    func bottomRightQuarterUsesBottomRightAreaOfVisibleFrame() {
        let frame = targetFrame(for: .bottomRightQuarter)

        #expect(frame == CGRect(x: 720, y: 0, width: 720, height: 450))
    }

    @Test
    func nonLayoutActionsPreserveCurrentFrame() {
        for action in [
            WindowAction.minimize,
            .closeWindow,
            .quitApplication,
            .cycleSameAppWindowsForward,
            .cycleSameAppWindowsBackward,
            .toggleFullScreen,
            .exitFullScreen,
            .moveToNextDisplay,
            .moveToPreviousDisplay,
        ] {
            let frame = targetFrame(for: action)

            #expect(frame == defaultWindowFrame)
        }
    }

    @Test
    func displayMoveToNextPreservesRelativeCenterAcrossDisplays() {
        let leftVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 860)
        let rightVisibleFrame = CGRect(x: 1440, y: 0, width: 1280, height: 800)
        let currentWindowFrame = CGRect(x: 360, y: 215, width: 720, height: 430)

        let frame = engine.displayMoveTargetFrame(
            direction: .next,
            currentWindowFrame: currentWindowFrame,
            currentVisibleFrame: leftVisibleFrame,
            screenFrames: [rightVisibleFrame, leftVisibleFrame]
        )

        #expect(frame == CGRect(x: 1720, y: 185, width: 720, height: 430))
    }

    @Test
    func displayMoveToPreviousWrapsThroughTraversalOrder() {
        let leftVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 860)
        let rightVisibleFrame = CGRect(x: 1440, y: 0, width: 1280, height: 800)
        let currentWindowFrame = CGRect(x: 1600, y: 100, width: 640, height: 400)

        let frame = engine.displayMoveTargetFrame(
            direction: .previous,
            currentWindowFrame: currentWindowFrame,
            currentVisibleFrame: rightVisibleFrame,
            screenFrames: [rightVisibleFrame, leftVisibleFrame]
        )

        #expect(frame == CGRect(x: 220, y: 122, width: 640, height: 401))
    }

    @Test
    func displayMoveUsesPreferredPointToResolveCurrentDisplay() throws {
        let leftVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 860)
        let rightVisibleFrame = CGRect(x: 1440, y: 0, width: 1280, height: 800)
        let currentWindowFrame = CGRect(x: 1320, y: 100, width: 640, height: 400)
        let preferredPoint = CGPoint(x: 100, y: 120)

        let frame = try #require(
            engine.displayMoveTargetFrame(
                direction: .next,
                currentWindowFrame: currentWindowFrame,
                preferredPoint: preferredPoint,
                screenFrames: [rightVisibleFrame, leftVisibleFrame]
            )
        )

        #expect(frame == CGRect(x: 2080, y: 79, width: 640, height: 401))
    }

    @Test
    func displayMoveShrinksAndClampsWindowToSmallerDisplay() {
        let largeVisibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let smallVisibleFrame = CGRect(x: 1200, y: 0, width: 500, height: 300)
        let oversizedWindowFrame = CGRect(x: 700, y: 650, width: 800, height: 500)

        let frame = engine.displayMoveTargetFrame(
            direction: .next,
            currentWindowFrame: oversizedWindowFrame,
            currentVisibleFrame: largeVisibleFrame,
            screenFrames: [largeVisibleFrame, smallVisibleFrame]
        )

        #expect(frame == smallVisibleFrame)
    }

    @Test
    func displayMovePreservesCurrentFrameWhenNoTargetDisplayExists() {
        let currentWindowFrame = CGRect(x: 100, y: 100, width: 800, height: 600)

        let frame = engine.displayMoveTargetFrame(
            direction: .next,
            currentWindowFrame: currentWindowFrame,
            currentVisibleFrame: visibleFrame,
            screenFrames: [visibleFrame]
        )

        #expect(frame == currentWindowFrame)
    }

    @Test
    func screenContainingMostPrefersScreenContainingWindowMidpoint() {
        let leftScreen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let rightScreen = CGRect(x: 1728, y: 0, width: 1728, height: 1117)
        let rightHalfOnRightScreen = CGRect(x: 2592, y: 0, width: 864, height: 1117)

        let resolvedScreen = engine.screenContainingMost(
            of: rightHalfOnRightScreen,
            in: [leftScreen, rightScreen]
        )

        #expect(resolvedScreen == rightScreen)
    }

    @Test
    func screenContainingMostFallsBackToNearestScreenWhenNoOverlapExists() {
        let leftScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let rightScreen = CGRect(x: 1440, y: 0, width: 1440, height: 900)
        let offScreenWindow = CGRect(x: 3000, y: 200, width: 400, height: 300)

        let resolvedScreen = engine.screenContainingMost(
            of: offScreenWindow,
            in: [leftScreen, rightScreen]
        )

        #expect(resolvedScreen == rightScreen)
    }

    @Test
    func resolvedVisibleFrameFallsBackToCurrentWindowScreenWhenPreferredPointIsOutsideVisibleFrames() {
        let leftVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 860)
        let rightVisibleFrame = CGRect(x: 1440, y: 0, width: 1440, height: 860)
        let currentWindowFrame = CGRect(x: 1600, y: 120, width: 900, height: 700)
        let preferredPointOutsideVisibleFrames = CGPoint(x: 1700, y: 880)

        let resolvedScreen = engine.resolvedVisibleFrame(
            preferredPoint: preferredPointOutsideVisibleFrames,
            currentWindowFrame: currentWindowFrame,
            screenFrames: [leftVisibleFrame, rightVisibleFrame]
        )

        #expect(resolvedScreen == rightVisibleFrame)
    }

    @Test
    func previewFrameExpandsLeftHalfFromLeadingEdgeForObservedMinimumWidth() {
        let targetFrame = CGRect(x: 0, y: 0, width: 720, height: 900)

        let preview = engine.preview(
            for: .leftHalf,
            targetFrame: targetFrame,
            observation: observation(
                minimumWidth: 860,
                horizontalAnchor: .leadingEdge,
                verticalAnchor: .leadingEdge
            )
        )

        #expect(preview?.frame == CGRect(x: 0, y: 0, width: 860, height: 900))
        #expect(preview?.style == .area)
    }

    @Test
    func previewFrameExpandsRightHalfFromTrailingEdgeForObservedMinimumWidth() {
        let targetFrame = CGRect(x: 720, y: 0, width: 720, height: 900)

        let preview = engine.preview(
            for: .rightHalf,
            targetFrame: targetFrame,
            observation: observation(
                minimumWidth: 860,
                horizontalAnchor: .trailingEdge,
                verticalAnchor: .leadingEdge
            )
        )

        #expect(preview?.frame == CGRect(x: 580, y: 0, width: 860, height: 900))
    }

    @Test
    func previewFrameCanExpandRightHalfFromLeadingEdgeWhenObservedAppDoesThat() {
        let targetFrame = CGRect(x: 720, y: 0, width: 720, height: 900)

        let preview = engine.preview(
            for: .rightHalf,
            targetFrame: targetFrame,
            observation: observation(
                minimumWidth: 860,
                horizontalAnchor: .leadingEdge,
                verticalAnchor: .leadingEdge
            )
        )

        #expect(preview?.frame == CGRect(x: 720, y: 0, width: 860, height: 900))
    }

    @Test
    func previewFrameShrinksMaximizeFromCenterForObservedMaximumSize() {
        let targetFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let preview = engine.preview(
            for: .maximize,
            targetFrame: targetFrame,
            observation: observation(
                maximumWidth: 1200,
                maximumHeight: 800,
                horizontalAnchor: .centered,
                verticalAnchor: .centered
            )
        )

        #expect(preview?.frame == CGRect(x: 120, y: 50, width: 1200, height: 800))
        #expect(preview?.style == .area)
    }

    @Test
    func previewIncludesAreaOverlayForMaximizeAction() {
        let targetFrame = CGRect(x: 0, y: 85, width: 1408, height: 766)

        let preview = engine.preview(
            for: .maximize,
            targetFrame: targetFrame,
            observation: nil
        )

        #expect(preview?.frame == targetFrame)
        #expect(preview?.style == .area)
    }

    @Test
    func previewFrameExpandsTopLeftQuarterFromOuterEdgesForObservedMinimumSize() {
        let targetFrame = CGRect(x: 0, y: 450, width: 720, height: 450)

        let preview = engine.preview(
            for: .topLeftQuarter,
            targetFrame: targetFrame,
            observation: observation(
                minimumWidth: 860,
                minimumHeight: 520,
                horizontalAnchor: .leadingEdge,
                verticalAnchor: .trailingEdge
            )
        )

        #expect(preview?.frame == CGRect(x: 0, y: 380, width: 860, height: 520))
        #expect(preview?.style == .area)
    }

    @Test
    func previewFrameKeepsTopRightQuarterFlushWithScreenEdgesWhenConstraintsShrinkWidth() {
        let targetFrame = CGRect(x: 704, y: 468, width: 704, height: 383)

        let preview = engine.preview(
            for: .topRightQuarter,
            targetFrame: targetFrame,
            observation: observation(
                maximumWidth: 560,
                minimumHeight: 672,
                horizontalAnchor: .leadingEdge,
                verticalAnchor: .trailingEdge
            )
        )

        #expect(preview?.frame == CGRect(x: 848, y: 179, width: 560, height: 672))
        #expect(preview?.style == .area)
    }
}
