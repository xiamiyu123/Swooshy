import CoreGraphics
import Testing
@testable import Swooshy

struct WindowLayoutEngineTests {
    private let engine = WindowLayoutEngine()
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test
    func leftHalfUsesLeftSideOfVisibleFrame() {
        let frame = engine.targetFrame(
            for: .leftHalf,
            currentWindowFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            currentVisibleFrame: visibleFrame
        )

        #expect(frame == CGRect(x: 0, y: 0, width: 720, height: 900))
    }

    @Test
    func rightHalfUsesRightSideOfVisibleFrame() {
        let frame = engine.targetFrame(
            for: .rightHalf,
            currentWindowFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            currentVisibleFrame: visibleFrame
        )

        #expect(frame == CGRect(x: 720, y: 0, width: 720, height: 900))
    }

    @Test
    func maximizeUsesEntireVisibleFrame() {
        let frame = engine.targetFrame(
            for: .maximize,
            currentWindowFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            currentVisibleFrame: visibleFrame
        )

        #expect(frame == visibleFrame)
    }

    @Test
    func centerUsesEntireVisibleFrame() {
        let frame = engine.targetFrame(
            for: .center,
            currentWindowFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            currentVisibleFrame: visibleFrame
        )

        #expect(frame == visibleFrame)
    }

    @Test
    func topLeftQuarterUsesTopLeftAreaOfVisibleFrame() {
        let frame = engine.targetFrame(
            for: .topLeftQuarter,
            currentWindowFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            currentVisibleFrame: visibleFrame
        )

        #expect(frame == CGRect(x: 0, y: 450, width: 720, height: 450))
    }

    @Test
    func topRightQuarterUsesTopRightAreaOfVisibleFrame() {
        let frame = engine.targetFrame(
            for: .topRightQuarter,
            currentWindowFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            currentVisibleFrame: visibleFrame
        )

        #expect(frame == CGRect(x: 720, y: 450, width: 720, height: 450))
    }

    @Test
    func bottomLeftQuarterUsesBottomLeftAreaOfVisibleFrame() {
        let frame = engine.targetFrame(
            for: .bottomLeftQuarter,
            currentWindowFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            currentVisibleFrame: visibleFrame
        )

        #expect(frame == CGRect(x: 0, y: 0, width: 720, height: 450))
    }

    @Test
    func bottomRightQuarterUsesBottomRightAreaOfVisibleFrame() {
        let frame = engine.targetFrame(
            for: .bottomRightQuarter,
            currentWindowFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            currentVisibleFrame: visibleFrame
        )

        #expect(frame == CGRect(x: 720, y: 0, width: 720, height: 450))
    }

    @Test
    func nonLayoutActionsPreserveCurrentFrame() {
        let currentWindowFrame = CGRect(x: 100, y: 100, width: 800, height: 600)

        for action in [
            WindowAction.minimize,
            .closeWindow,
            .quitApplication,
            .cycleSameAppWindowsForward,
            .cycleSameAppWindowsBackward,
        ] {
            let frame = engine.targetFrame(
                for: action,
                currentWindowFrame: currentWindowFrame,
                currentVisibleFrame: visibleFrame
            )

            #expect(frame == currentWindowFrame)
        }
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
            observation: WindowActionPreview.Observation(
                sizeBounds: WindowActionPreview.SizeBounds(
                    minimumWidth: 860,
                    maximumWidth: nil,
                    minimumHeight: nil,
                    maximumHeight: nil
                ),
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
            observation: WindowActionPreview.Observation(
                sizeBounds: WindowActionPreview.SizeBounds(
                    minimumWidth: 860,
                    maximumWidth: nil,
                    minimumHeight: nil,
                    maximumHeight: nil
                ),
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
            observation: WindowActionPreview.Observation(
                sizeBounds: WindowActionPreview.SizeBounds(
                    minimumWidth: 860,
                    maximumWidth: nil,
                    minimumHeight: nil,
                    maximumHeight: nil
                ),
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
            observation: WindowActionPreview.Observation(
                sizeBounds: WindowActionPreview.SizeBounds(
                    minimumWidth: nil,
                    maximumWidth: 1200,
                    minimumHeight: nil,
                    maximumHeight: 800
                ),
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
            observation: WindowActionPreview.Observation(
                sizeBounds: WindowActionPreview.SizeBounds(
                    minimumWidth: 860,
                    maximumWidth: nil,
                    minimumHeight: 520,
                    maximumHeight: nil
                ),
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
            observation: WindowActionPreview.Observation(
                sizeBounds: WindowActionPreview.SizeBounds(
                    minimumWidth: nil,
                    maximumWidth: 560,
                    minimumHeight: 672,
                    maximumHeight: nil
                ),
                horizontalAnchor: .leadingEdge,
                verticalAnchor: .trailingEdge
            )
        )

        #expect(preview?.frame == CGRect(x: 848, y: 179, width: 560, height: 672))
        #expect(preview?.style == .area)
    }
}
