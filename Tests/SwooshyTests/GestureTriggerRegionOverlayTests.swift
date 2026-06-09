import CoreGraphics
import Testing
@testable import Swooshy

@MainActor
struct GestureTriggerRegionOverlayTests {
    @Test
    func titleBarRegionUsesConfiguredTopBandOfSettingsWindow() {
        let region = GestureTriggerRegionOverlayLayout.titleBarRegion(
            forWindowFrame: CGRect(x: 120, y: 80, width: 800, height: 600),
            titleBarHeight: 42
        )

        #expect(region == CGRect(x: 120, y: 638, width: 800, height: 42))
    }

    @Test
    func titleBarRegionClampsHeightAndIgnoresTinyWindows() {
        let region = GestureTriggerRegionOverlayLayout.titleBarRegion(
            forWindowFrame: CGRect(x: 50, y: 60, width: 320, height: 90),
            titleBarHeight: 120
        )

        #expect(region == CGRect(x: 50, y: 94, width: 320, height: 56))
        #expect(GestureTriggerRegionOverlayLayout.titleBarRegion(
            forWindowFrame: CGRect(x: 0, y: 0, width: 119, height: 200),
            titleBarHeight: 40
        ) == nil)
        #expect(GestureTriggerRegionOverlayLayout.titleBarRegion(
            forWindowFrame: CGRect(x: 20, y: 30, width: 300, height: 70),
            titleBarHeight: 40
        ) == nil)
    }

    @Test
    func localFrameClipsRegionToScreenBeforeConverting() {
        let localFrame = GestureTriggerRegionOverlayLayout.localFrame(
            for: CGRect(x: 1380, y: 20, width: 120, height: 36),
            onScreen: CGRect(x: 1440, y: 0, width: 1280, height: 900)
        )

        #expect(localFrame == CGRect(x: 0, y: 20, width: 60, height: 36))
        #expect(GestureTriggerRegionOverlayLayout.localFrame(
            for: CGRect(x: 100, y: 20, width: 120, height: 36),
            onScreen: CGRect(x: 1440, y: 0, width: 1280, height: 900)
        ) == nil)
    }
}
