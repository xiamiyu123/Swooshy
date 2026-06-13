import CoreGraphics
import Foundation
import Testing
@testable import Swooshy

struct TitleBarHoverSnapshotTests {
    private let screenFrames = [CGRect(x: 0, y: 0, width: 1000, height: 1000)]

    @Test
    func pointInsideTitleBarReturnsWindowTarget() throws {
        let windowIdentity = WindowIdentity(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let snapshot = windowSnapshot(
            identity: windowIdentity,
            appKitFrame: CGRect(x: 100, y: 200, width: 500, height: 300)
        )

        let hit = try #require(WindowRegistry.titleBarHoverHit(
            at: CGPoint(x: 120, y: 485),
            titleBarHeight: 40,
            allowFullScreen: false,
            snapshots: [snapshot],
            screenFrames: screenFrames
        ))

        #expect(hit.target.application == .window(windowIdentity, app: snapshot.appIdentity, source: .titleBar))
        #expect(hit.target.source == .titleBar)
        #expect(hit.frame == CGRect(x: 100, y: 460, width: 500, height: 40))
    }

    @Test
    func pointOutsideTitleBarDoesNotReturnTarget() {
        let snapshot = windowSnapshot(
            appKitFrame: CGRect(x: 100, y: 200, width: 500, height: 300)
        )

        #expect(WindowRegistry.titleBarHoverHit(
            at: CGPoint(x: 120, y: 440),
            titleBarHeight: 40,
            allowFullScreen: false,
            snapshots: [snapshot],
            screenFrames: screenFrames
        ) == nil)

        #expect(WindowRegistry.titleBarHoverHit(
            at: CGPoint(x: 20, y: 485),
            titleBarHeight: 40,
            allowFullScreen: false,
            snapshots: [snapshot],
            screenFrames: screenFrames
        ) == nil)
    }

    @Test
    func minimizedWindowDoesNotReturnTarget() {
        let snapshot = windowSnapshot(
            appKitFrame: CGRect(x: 100, y: 200, width: 500, height: 300),
            isMinimized: true
        )

        #expect(WindowRegistry.titleBarHoverHit(
            at: CGPoint(x: 120, y: 485),
            titleBarHeight: 40,
            allowFullScreen: false,
            snapshots: [snapshot],
            screenFrames: screenFrames
        ) == nil)
    }

    @Test
    func fullScreenWindowRequiresExplicitAllowance() throws {
        let snapshot = windowSnapshot(
            appKitFrame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            isFullScreen: true
        )

        #expect(WindowRegistry.titleBarHoverHit(
            at: CGPoint(x: 120, y: 985),
            titleBarHeight: 40,
            allowFullScreen: false,
            snapshots: [snapshot],
            screenFrames: screenFrames
        ) == nil)

        let hit = try #require(WindowRegistry.titleBarHoverHit(
            at: CGPoint(x: 120, y: 985),
            titleBarHeight: 40,
            allowFullScreen: true,
            snapshots: [snapshot],
            screenFrames: screenFrames
        ))
        #expect(hit.isFullScreen)
    }

    @Test
    func overlappingWindowsPreferFocusedThenMainThenStableOrdering() throws {
        let plain = windowSnapshot(
            identity: WindowIdentity(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
            appKitFrame: CGRect(x: 100, y: 200, width: 500, height: 300)
        )
        let main = windowSnapshot(
            identity: WindowIdentity(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!),
            appKitFrame: CGRect(x: 100, y: 200, width: 500, height: 300),
            isMain: true
        )
        let focused = windowSnapshot(
            identity: WindowIdentity(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!),
            appKitFrame: CGRect(x: 100, y: 200, width: 500, height: 300),
            isFocused: true
        )

        let focusedHit = try #require(WindowRegistry.titleBarHoverHit(
            at: CGPoint(x: 120, y: 485),
            titleBarHeight: 40,
            allowFullScreen: false,
            snapshots: [plain, main, focused],
            screenFrames: screenFrames
        ))
        #expect(focusedHit.target.application.windowIdentity == focused.identity)

        let mainHit = try #require(WindowRegistry.titleBarHoverHit(
            at: CGPoint(x: 120, y: 485),
            titleBarHeight: 40,
            allowFullScreen: false,
            snapshots: [plain, main],
            screenFrames: screenFrames
        ))
        #expect(mainHit.target.application.windowIdentity == main.identity)

        let stableHit = try #require(WindowRegistry.titleBarHoverHit(
            at: CGPoint(x: 120, y: 485),
            titleBarHeight: 40,
            allowFullScreen: false,
            snapshots: [main.withFlags(isMain: false), plain],
            screenFrames: screenFrames
        ))
        #expect(stableHit.target.application.windowIdentity == plain.identity)
    }

    private func windowSnapshot(
        identity: WindowIdentity = WindowIdentity(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!),
        appKitFrame: CGRect,
        isMinimized: Bool = false,
        isFocused: Bool = false,
        isMain: Bool = false,
        isFullScreen: Bool = false
    ) -> WindowRecordSnapshot {
        WindowRecordSnapshot(
            identity: identity,
            appIdentity: appIdentity(processIdentifier: 100),
            ownerProcessIdentifier: 100,
            title: "Window",
            frame: axFrame(from: appKitFrame),
            isMinimized: isMinimized,
            isFocused: isFocused,
            isMain: isMain,
            isFullScreen: isFullScreen,
            lastMinimizedAt: nil,
            boundDockMinimizedHandle: nil
        )
    }

    private func appIdentity(processIdentifier: pid_t) -> AppIdentity {
        AppIdentity(
            bundleURL: URL(fileURLWithPath: "/Applications/Test.app"),
            bundleIdentifier: "com.example.test",
            processIdentifier: processIdentifier,
            localizedName: "Test"
        )!
    }

    private func axFrame(from appKitFrame: CGRect) -> CGRect {
        ScreenGeometry(screenFrames: screenFrames).axFrame(fromAppKitFrame: appKitFrame)
    }
}

private extension WindowRecordSnapshot {
    func withFlags(isMain: Bool) -> WindowRecordSnapshot {
        WindowRecordSnapshot(
            identity: identity,
            appIdentity: appIdentity,
            ownerProcessIdentifier: ownerProcessIdentifier,
            title: title,
            frame: frame,
            isMinimized: isMinimized,
            isFocused: isFocused,
            isMain: isMain,
            isFullScreen: isFullScreen,
            lastMinimizedAt: lastMinimizedAt,
            boundDockMinimizedHandle: boundDockMinimizedHandle
        )
    }
}

