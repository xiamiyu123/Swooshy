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

    private func candidate(
        dockItemName: String,
        processIdentifier: pid_t,
        x: CGFloat
    ) -> DockHoverCandidate {
        DockHoverCandidate(
            target: target(
                dockItemName: dockItemName,
                processIdentifier: processIdentifier
            ),
            frame: CGRect(x: x, y: 0, width: 32, height: 32)
        )
    }

    @Test
    func hoveredCandidateReturnsMatchingDockItem() {
        let finder = candidate(
            dockItemName: "Finder",
            processIdentifier: 100,
            x: 0
        )
        let safari = candidate(
            dockItemName: "Safari",
            processIdentifier: 101,
            x: 40
        )
        let snapshot = DockHoverSnapshot(candidates: [finder, safari])

        #expect(snapshot.hoveredCandidate(at: CGPoint(x: 16, y: 16)) == finder)
        #expect(snapshot.hoveredCandidate(at: CGPoint(x: 56, y: 16)) == safari)
    }

    @Test
    func approximateDockRegionUsesCandidateBounds() {
        let snapshot = DockHoverSnapshot(
            candidates: [
                candidate(
                    dockItemName: "Finder",
                    processIdentifier: 100,
                    x: 0
                ),
                candidate(
                    dockItemName: "Safari",
                    processIdentifier: 101,
                    x: 48
                ),
            ]
        )

        let pointsInsideRegion = [
            CGPoint(x: 12, y: 12),
            CGPoint(x: 60, y: 12),
            CGPoint(x: 40, y: 12),
        ]

        #expect(pointsInsideRegion.allSatisfy { snapshot.containsApproximateDockRegion($0) })
        #expect(!snapshot.containsApproximateDockRegion(CGPoint(x: 120, y: 12)))
    }

    @Test
    func boundsCoverAllDockCandidates() {
        let snapshot = DockHoverSnapshot(
            candidates: [
                candidate(
                    dockItemName: "Finder",
                    processIdentifier: 100,
                    x: 12
                ),
                candidate(
                    dockItemName: "Safari",
                    processIdentifier: 101,
                    x: 60
                ),
            ]
        )

        #expect(snapshot.bounds == CGRect(x: 12, y: 0, width: 80, height: 32))
    }

    @Test
    func emptySnapshotDoesNotReportDockRegionOrHits() {
        let snapshot = DockHoverSnapshot(candidates: [])

        #expect(!snapshot.containsApproximateDockRegion(CGPoint(x: 1, y: 1)))
        #expect(snapshot.hoveredCandidate(at: CGPoint(x: 1, y: 1)) == nil)
    }

    @Test
    func cachePolicyPreheatsOnlyNearCandidateExpiry() {
        let policy = DockSnapshotCachePolicy(
            candidateTTL: 0.25,
            regionTTL: 1,
            preheatLeadTime: 0.08
        )
        let refreshedAt = Date(timeIntervalSinceReferenceDate: 100)
        let expiresAt = refreshedAt.addingTimeInterval(policy.candidateTTL)

        let cases: [(elapsed: TimeInterval, shouldPreheat: Bool)] = [
            (0, false),
            (0.16, false),
            (0.18, true),
        ]

        for (elapsed, shouldPreheat) in cases {
            #expect(
                policy.shouldPreheat(
                    now: refreshedAt.addingTimeInterval(elapsed),
                    candidateExpiresAt: expiresAt
                ) == shouldPreheat
            )
        }
    }

    @Test
    func cachePolicyCapsPreheatLeadTimeAtCandidateTTL() {
        let policy = DockSnapshotCachePolicy(
            candidateTTL: 0.25,
            regionTTL: 1,
            preheatLeadTime: 0.5
        )

        #expect(policy.preheatLeadTime == policy.candidateTTL)
    }
}
