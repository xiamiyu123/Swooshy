import Foundation
import Testing
@testable import Swooshy

@MainActor
struct ObservedWindowConstraintStoreTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "Swooshy.ObservedWindowConstraintStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test
    func sharedMaximumBoundsApplyAcrossActions() {
        let store = ObservedWindowConstraintStore()

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: nil,
                maximumWidth: 1200,
                minimumHeight: nil,
                maximumHeight: 800
            ),
            horizontalAnchor: .centered,
            verticalAnchor: .centered,
            action: .maximize,
            for: "com.example.app"
        )

        let observation = store.observation(
            for: "com.example.app",
            action: .leftHalf
        )

        #expect(observation?.sizeBounds.maximumWidth == 1200)
        #expect(observation?.sizeBounds.maximumHeight == 800)
        #expect(observation?.horizontalAnchor == nil)
        #expect(observation?.verticalAnchor == nil)
    }

    @Test
    func persistsConstraintsAcrossStoreInstances() {
        let defaults = makeDefaults()
        let referenceDate = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let store = ObservedWindowConstraintStore(
            userDefaults: defaults,
            now: { referenceDate },
            autosaveInterval: 0
        )

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: nil,
                maximumWidth: 1200,
                minimumHeight: nil,
                maximumHeight: 800
            ),
            horizontalAnchor: .centered,
            verticalAnchor: .centered,
            action: .maximize,
            for: "com.example.app"
        )

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: 860,
                maximumWidth: nil,
                minimumHeight: 520,
                maximumHeight: nil
            ),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .leadingEdge,
            action: .leftHalf,
            for: "com.example.app"
        )
        store.flushPersistedConstraints()

        let reloadedStore = ObservedWindowConstraintStore(
            userDefaults: defaults,
            now: { referenceDate },
            autosaveInterval: 0
        )

        let leftObservation = reloadedStore.observation(
            for: "com.example.app",
            action: .leftHalf
        )
        let rightObservation = reloadedStore.observation(
            for: "com.example.app",
            action: .rightHalf
        )

        #expect(leftObservation?.sizeBounds.minimumWidth == 860)
        #expect(leftObservation?.sizeBounds.maximumWidth == nil)
        #expect(leftObservation?.sizeBounds.minimumHeight == 520)
        #expect(leftObservation?.sizeBounds.maximumHeight == nil)
        #expect(leftObservation?.horizontalAnchor == .leadingEdge)
        #expect(leftObservation?.verticalAnchor == .leadingEdge)
        #expect(rightObservation?.sizeBounds.minimumWidth == 860)
        #expect(rightObservation?.sizeBounds.maximumWidth == 1200)
        #expect(rightObservation?.sizeBounds.minimumHeight == 520)
        #expect(rightObservation?.sizeBounds.maximumHeight == 800)
        #expect(rightObservation?.horizontalAnchor == nil)
        #expect(rightObservation?.verticalAnchor == nil)
    }

    @Test
    func discardsPersistedConstraintsUnusedForMoreThanSevenDays() {
        let defaults = makeDefaults()
        var currentDate = Date(timeIntervalSinceReferenceDate: 2_000_000)

        let store = ObservedWindowConstraintStore(
            userDefaults: defaults,
            now: { currentDate },
            autosaveInterval: 0
        )
        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: 860,
                maximumWidth: nil,
                minimumHeight: nil,
                maximumHeight: nil
            ),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .leadingEdge,
            action: .leftHalf,
            for: "com.example.app"
        )
        store.flushPersistedConstraints()

        currentDate.addTimeInterval((8 * 24 * 60 * 60))

        let reloadedStore = ObservedWindowConstraintStore(
            userDefaults: defaults,
            now: { currentDate },
            autosaveInterval: 0
        )

        let observation = reloadedStore.observation(
            for: "com.example.app",
            action: .leftHalf
        )

        #expect(observation == nil)
    }

    @Test
    func touchingConstraintRefreshesSevenDayRetentionWindow() {
        let defaults = makeDefaults()
        var currentDate = Date(timeIntervalSinceReferenceDate: 3_000_000)

        let store = ObservedWindowConstraintStore(
            userDefaults: defaults,
            now: { currentDate },
            autosaveInterval: 0
        )
        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: nil,
                maximumWidth: 1200,
                minimumHeight: nil,
                maximumHeight: 800
            ),
            horizontalAnchor: .centered,
            verticalAnchor: .centered,
            action: .maximize,
            for: "com.example.app"
        )
        store.flushPersistedConstraints()

        currentDate.addTimeInterval(6 * 24 * 60 * 60)

        let refreshedStore = ObservedWindowConstraintStore(
            userDefaults: defaults,
            now: { currentDate },
            autosaveInterval: 0
        )
        let refreshedObservation = refreshedStore.observation(
            for: "com.example.app",
            action: .maximize
        )
        #expect(refreshedObservation?.sizeBounds.maximumWidth == 1200)
        refreshedStore.flushPersistedConstraints()

        currentDate.addTimeInterval(2 * 24 * 60 * 60)

        let survivingStore = ObservedWindowConstraintStore(
            userDefaults: defaults,
            now: { currentDate },
            autosaveInterval: 0
        )
        let survivingObservation = survivingStore.observation(
            for: "com.example.app",
            action: .maximize
        )

        #expect(survivingObservation?.sizeBounds.maximumWidth == 1200)
        #expect(survivingObservation?.sizeBounds.maximumHeight == 800)
    }

    @Test
    func sharedMinimumBoundsApplyAcrossActions() {
        let store = ObservedWindowConstraintStore()

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: 860,
                maximumWidth: nil,
                minimumHeight: 520,
                maximumHeight: nil
            ),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .leadingEdge,
            action: .leftHalf,
            for: "com.example.app"
        )

        let rightObservation = store.observation(
            for: "com.example.app",
            action: .rightHalf
        )

        #expect(rightObservation?.sizeBounds.minimumWidth == 860)
        #expect(rightObservation?.sizeBounds.minimumHeight == 520)
        #expect(rightObservation?.horizontalAnchor == nil)
        #expect(rightObservation?.verticalAnchor == nil)
    }

    @Test
    func actionSpecificObservationOverridesSharedBounds() {
        let store = ObservedWindowConstraintStore()

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: nil,
                maximumWidth: 1200,
                minimumHeight: nil,
                maximumHeight: 800
            ),
            horizontalAnchor: .centered,
            verticalAnchor: .centered,
            action: .maximize,
            for: "com.example.app"
        )

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: 860,
                maximumWidth: nil,
                minimumHeight: nil,
                maximumHeight: nil
            ),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .leadingEdge,
            action: .leftHalf,
            for: "com.example.app"
        )

        let observation = store.observation(
            for: "com.example.app",
            action: .leftHalf
        )

        #expect(observation?.sizeBounds.minimumWidth == 860)
        #expect(observation?.sizeBounds.maximumWidth == nil)
        #expect(observation?.sizeBounds.maximumHeight == nil)
        #expect(observation?.horizontalAnchor == .leadingEdge)
        #expect(observation?.verticalAnchor == .leadingEdge)
    }

    @Test
    func sharedBoundsRemainFallbackWhenActionHasNoObservation() {
        let store = ObservedWindowConstraintStore()

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: nil,
                maximumWidth: 1200,
                minimumHeight: nil,
                maximumHeight: 800
            ),
            horizontalAnchor: .centered,
            verticalAnchor: .centered,
            action: .maximize,
            for: "com.example.app"
        )

        let observation = store.observation(
            for: "com.example.app",
            action: .rightHalf
        )

        #expect(observation?.sizeBounds.maximumWidth == 1200)
        #expect(observation?.sizeBounds.maximumHeight == 800)
        #expect(observation?.horizontalAnchor == nil)
        #expect(observation?.verticalAnchor == nil)
    }

    @Test
    func sharedMinimumBoundsApplyAcrossQuarterActions() {
        let store = ObservedWindowConstraintStore()

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: 860,
                maximumWidth: nil,
                minimumHeight: 520,
                maximumHeight: nil
            ),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .trailingEdge,
            action: .topLeftQuarter,
            for: "com.example.app"
        )

        let observation = store.observation(
            for: "com.example.app",
            action: .bottomRightQuarter
        )

        #expect(observation?.sizeBounds.minimumWidth == 860)
        #expect(observation?.sizeBounds.minimumHeight == 520)
        #expect(observation?.horizontalAnchor == nil)
        #expect(observation?.verticalAnchor == nil)
    }

    @Test
    func discardsUnusedApplicationConstraintsAfterSevenDaysWithoutUse() {
        var currentDate = Date(timeIntervalSinceReferenceDate: 4_000_000)
        let store = ObservedWindowConstraintStore(
            userDefaults: makeDefaults(),
            now: { currentDate },
            autosaveInterval: 0
        )

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: nil,
                maximumWidth: 1200,
                minimumHeight: nil,
                maximumHeight: 800
            ),
            horizontalAnchor: .centered,
            verticalAnchor: .centered,
            action: .maximize,
            for: "com.example.cached"
        )

        currentDate.addTimeInterval(8 * 24 * 60 * 60)

        let cachedObservation = store.observation(
            for: "com.example.cached",
            action: .maximize
        )

        #expect(cachedObservation == nil)
    }

    @Test
    func usedApplicationConstraintsRemainAvailableInsideSevenDayWindow() {
        var currentDate = Date(timeIntervalSinceReferenceDate: 5_000_000)
        let store = ObservedWindowConstraintStore(
            userDefaults: makeDefaults(),
            now: { currentDate },
            autosaveInterval: 0
        )

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: nil,
                maximumWidth: 1200,
                minimumHeight: nil,
                maximumHeight: 800
            ),
            horizontalAnchor: .centered,
            verticalAnchor: .centered,
            action: .maximize,
            for: "com.example.cached"
        )

        currentDate.addTimeInterval(6 * 24 * 60 * 60)

        let refreshedObservation = store.observation(
            for: "com.example.cached",
            action: .maximize
        )

        #expect(refreshedObservation?.sizeBounds.maximumWidth == 1200)

        let survivingObservation = store.observation(
            for: "com.example.cached",
            action: .maximize
        )

        #expect(survivingObservation?.sizeBounds.maximumWidth == 1200)
    }

    @Test
    func latestMinimumConstraintClearsConflictingMaximumBound() {
        let store = ObservedWindowConstraintStore()

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: nil,
                maximumWidth: 182,
                minimumHeight: nil,
                maximumHeight: 40
            ),
            horizontalAnchor: .trailingEdge,
            verticalAnchor: .trailingEdge,
            action: .topRightQuarter,
            for: "com.example.app|role=AXWindow|subrole=AXSystemDialog|title=<untitled>"
        )

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: 560,
                maximumWidth: nil,
                minimumHeight: 672,
                maximumHeight: nil
            ),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .trailingEdge,
            action: .topRightQuarter,
            for: "com.example.app|role=AXWindow|subrole=AXSystemDialog|title=<untitled>"
        )

        let observation = store.observation(
            for: "com.example.app|role=AXWindow|subrole=AXSystemDialog|title=<untitled>",
            action: .topRightQuarter
        )

        #expect(observation?.sizeBounds.minimumWidth == 560)
        #expect(observation?.sizeBounds.maximumWidth == nil)
        #expect(observation?.sizeBounds.minimumHeight == 672)
        #expect(observation?.sizeBounds.maximumHeight == nil)
    }

    @Test
    func latestMaximumConstraintClearsConflictingMinimumBound() {
        let store = ObservedWindowConstraintStore()

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: 560,
                maximumWidth: nil,
                minimumHeight: 672,
                maximumHeight: nil
            ),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .trailingEdge,
            action: .topRightQuarter,
            for: "com.example.app|role=AXWindow|subrole=AXSystemDialog|title=<untitled>"
        )

        store.record(
            sizeBounds: WindowActionPreview.SizeBounds(
                minimumWidth: nil,
                maximumWidth: 182,
                minimumHeight: nil,
                maximumHeight: 40
            ),
            horizontalAnchor: .trailingEdge,
            verticalAnchor: .trailingEdge,
            action: .topRightQuarter,
            for: "com.example.app|role=AXWindow|subrole=AXSystemDialog|title=<untitled>"
        )

        let observation = store.observation(
            for: "com.example.app|role=AXWindow|subrole=AXSystemDialog|title=<untitled>",
            action: .topRightQuarter
        )

        #expect(observation?.sizeBounds.minimumWidth == nil)
        #expect(observation?.sizeBounds.maximumWidth == 182)
        #expect(observation?.sizeBounds.minimumHeight == nil)
        #expect(observation?.sizeBounds.maximumHeight == 40)
    }
}
