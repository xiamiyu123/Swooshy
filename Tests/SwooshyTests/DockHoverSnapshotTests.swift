import CoreGraphics
import Foundation
import Testing
@testable import Swooshy

struct DockHoverSnapshotTests {
    private func target(
        dockItemName: String,
        processIdentifier: pid_t
    ) -> InteractionTarget {
        let appIdentity = AppIdentity(
            bundleURL: URL(fileURLWithPath: "/Applications/\(dockItemName).app"),
            bundleIdentifier: "com.example.\(dockItemName.lowercased())",
            processIdentifier: processIdentifier,
            localizedName: dockItemName
        )!
        return .application(appIdentity, source: .dockAppItem(DockItemHandle()))
    }

    @Test
    func hoveredCandidateReturnsMatchingDockItem() {
        let finder = DockHoverCandidate(
            target: target(dockItemName: "Finder", processIdentifier: 100),
            frame: CGRect(x: 0, y: 0, width: 32, height: 32)
        )
        let safari = DockHoverCandidate(
            target: target(dockItemName: "Safari", processIdentifier: 101),
            frame: CGRect(x: 40, y: 0, width: 32, height: 32)
        )
        let snapshot = DockHoverSnapshot(candidates: [finder, safari])

        #expect(snapshot.hoveredCandidate(at: CGPoint(x: 16, y: 16)) == finder)
        #expect(snapshot.hoveredCandidate(at: CGPoint(x: 56, y: 16)) == safari)
    }

    @Test
    func approximateDockRegionUsesCandidateBounds() {
        let snapshot = DockHoverSnapshot(
            candidates: [
                DockHoverCandidate(
                    target: target(dockItemName: "Finder", processIdentifier: 100),
                    frame: CGRect(x: 0, y: 0, width: 32, height: 32)
                ),
                DockHoverCandidate(
                    target: target(dockItemName: "Safari", processIdentifier: 101),
                    frame: CGRect(x: 48, y: 0, width: 32, height: 32)
                ),
            ]
        )

        #expect(snapshot.containsApproximateDockRegion(CGPoint(x: 12, y: 12)))
        #expect(snapshot.containsApproximateDockRegion(CGPoint(x: 60, y: 12)))
        #expect(snapshot.containsApproximateDockRegion(CGPoint(x: 40, y: 12)))
        #expect(snapshot.containsApproximateDockRegion(CGPoint(x: 120, y: 12)) == false)
    }

    @Test
    func emptySnapshotDoesNotReportDockRegionOrHits() {
        let snapshot = DockHoverSnapshot(candidates: [])

        #expect(snapshot.containsApproximateDockRegion(CGPoint(x: 1, y: 1)) == false)
        #expect(snapshot.hoveredCandidate(at: CGPoint(x: 1, y: 1)) == nil)
    }
}
