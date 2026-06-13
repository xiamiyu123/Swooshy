import CoreGraphics
import Foundation
import Testing
@testable import Swooshy

@MainActor
struct ObservedWindowConstraintStoreTests {
    private let appKey = "com.example.app"
    private let cachedAppKey = "com.example.cached"
    private let dialogKey = "com.example.app|role=AXWindow|subrole=AXSystemDialog|title=<untitled>"
    private let day: TimeInterval = 24 * 60 * 60

    private func makeDefaults() -> UserDefaults {
        let suiteName = "Swooshy.ObservedWindowConstraintStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makePersistedStore(
        userDefaults: UserDefaults,
        now: @escaping () -> Date
    ) -> ObservedWindowConstraintStore {
        ObservedWindowConstraintStore(
            userDefaults: userDefaults,
            now: now,
            autosaveInterval: 0
        )
    }

    private func makePersistedStore(now: @escaping () -> Date) -> ObservedWindowConstraintStore {
        makePersistedStore(userDefaults: makeDefaults(), now: now)
    }

    private func sizeBounds(
        minimumWidth: CGFloat? = nil,
        maximumWidth: CGFloat? = nil,
        minimumHeight: CGFloat? = nil,
        maximumHeight: CGFloat? = nil
    ) -> WindowActionPreview.SizeBounds {
        WindowActionPreview.SizeBounds(
            minimumWidth: minimumWidth,
            maximumWidth: maximumWidth,
            minimumHeight: minimumHeight,
            maximumHeight: maximumHeight
        )
    }

    private func testDate(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    @Test
    func sharedMaximumBoundsApplyAcrossActions() {
        let store = ObservedWindowConstraintStore()

        store.record(
            sizeBounds: sizeBounds(maximumWidth: 1200, maximumHeight: 800),
            horizontalAnchor: .centered,
            verticalAnchor: .centered,
            action: .maximize,
            for: appKey
        )

        let observation = store.observation(
            for: appKey,
            action: .leftHalf
        )

        #expect(observation?.sizeBounds.maximumWidth == 1200)
        #expect(observation?.sizeBounds.maximumHeight == 800)
        #expect(observation?.horizontalAnchor == nil)
        #expect(observation?.verticalAnchor == nil)
    }

    @Test
    func sharedSizeBoundsCanBeReadWithoutAnAction() {
        let store = ObservedWindowConstraintStore()

        store.record(
            sizeBounds: sizeBounds(maximumWidth: 1200, minimumHeight: 520),
            horizontalAnchor: .centered,
            verticalAnchor: .centered,
            action: .maximize,
            for: appKey
        )

        let sharedSizeBounds = store.sharedSizeBounds(for: appKey)

        #expect(sharedSizeBounds?.maximumWidth == 1200)
        #expect(sharedSizeBounds?.minimumHeight == 520)
    }

    @Test
    func persistsConstraintsAcrossStoreInstances() {
        let defaults = makeDefaults()
        let referenceDate = testDate(1_000_000)
        let store = makePersistedStore(
            userDefaults: defaults,
            now: { referenceDate }
        )

        store.record(
            sizeBounds: sizeBounds(maximumWidth: 1200, maximumHeight: 800),
            horizontalAnchor: .centered,
            verticalAnchor: .centered,
            action: .maximize,
            for: appKey
        )

        store.record(
            sizeBounds: sizeBounds(minimumWidth: 860, minimumHeight: 520),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .leadingEdge,
            action: .leftHalf,
            for: appKey
        )
        store.flushPersistedConstraints()

        let reloadedStore = makePersistedStore(
            userDefaults: defaults,
            now: { referenceDate }
        )

        let leftObservation = reloadedStore.observation(
            for: appKey,
            action: .leftHalf
        )
        let rightObservation = reloadedStore.observation(
            for: appKey,
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
        var currentDate = testDate(2_000_000)

        let store = makePersistedStore(
            userDefaults: defaults,
            now: { currentDate }
        )
        store.record(
            sizeBounds: sizeBounds(minimumWidth: 860),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .leadingEdge,
            action: .leftHalf,
            for: appKey
        )
        store.flushPersistedConstraints()

        currentDate.addTimeInterval((8 * day))

        let reloadedStore = makePersistedStore(
            userDefaults: defaults,
            now: { currentDate }
        )

        let observation = reloadedStore.observation(
            for: appKey,
            action: .leftHalf
        )

        #expect(observation == nil)
    }

    @Test
    func touchingConstraintRefreshesSevenDayRetentionWindow() {
        let defaults = makeDefaults()
        var currentDate = testDate(3_000_000)

        let store = makePersistedStore(
            userDefaults: defaults,
            now: { currentDate }
        )
        store.record(
            sizeBounds: sizeBounds(maximumWidth: 1200, maximumHeight: 800),
            horizontalAnchor: .centered,
            verticalAnchor: .centered,
            action: .maximize,
            for: appKey
        )
        store.flushPersistedConstraints()

        currentDate.addTimeInterval(6 * day)

        let refreshedStore = makePersistedStore(
            userDefaults: defaults,
            now: { currentDate }
        )
        let refreshedObservation = refreshedStore.observation(
            for: appKey,
            action: .maximize
        )
        #expect(refreshedObservation?.sizeBounds.maximumWidth == 1200)
        refreshedStore.flushPersistedConstraints()

        currentDate.addTimeInterval(2 * day)

        let survivingStore = makePersistedStore(
            userDefaults: defaults,
            now: { currentDate }
        )
        let survivingObservation = survivingStore.observation(
            for: appKey,
            action: .maximize
        )

        #expect(survivingObservation?.sizeBounds.maximumWidth == 1200)
        #expect(survivingObservation?.sizeBounds.maximumHeight == 800)
    }

    @Test
    func sharedMinimumBoundsApplyAcrossActions() {
        let store = ObservedWindowConstraintStore()

        store.record(
            sizeBounds: sizeBounds(minimumWidth: 860, minimumHeight: 520),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .leadingEdge,
            action: .leftHalf,
            for: appKey
        )

        let rightObservation = store.observation(
            for: appKey,
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
            sizeBounds: sizeBounds(maximumWidth: 1200, maximumHeight: 800),
            horizontalAnchor: .centered,
            verticalAnchor: .centered,
            action: .maximize,
            for: appKey
        )

        store.record(
            sizeBounds: sizeBounds(minimumWidth: 860),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .leadingEdge,
            action: .leftHalf,
            for: appKey
        )

        let observation = store.observation(
            for: appKey,
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
            sizeBounds: sizeBounds(maximumWidth: 1200, maximumHeight: 800),
            horizontalAnchor: .centered,
            verticalAnchor: .centered,
            action: .maximize,
            for: appKey
        )

        let observation = store.observation(
            for: appKey,
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
            sizeBounds: sizeBounds(minimumWidth: 860, minimumHeight: 520),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .trailingEdge,
            action: .topLeftQuarter,
            for: appKey
        )

        let observation = store.observation(
            for: appKey,
            action: .bottomRightQuarter
        )

        #expect(observation?.sizeBounds.minimumWidth == 860)
        #expect(observation?.sizeBounds.minimumHeight == 520)
        #expect(observation?.horizontalAnchor == nil)
        #expect(observation?.verticalAnchor == nil)
    }

    @Test
    func discardsUnusedApplicationConstraintsAfterSevenDaysWithoutUse() {
        var currentDate = testDate(4_000_000)
        let store = makePersistedStore(now: { currentDate })

        store.record(
            sizeBounds: sizeBounds(maximumWidth: 1200, maximumHeight: 800),
            horizontalAnchor: .centered,
            verticalAnchor: .centered,
            action: .maximize,
            for: cachedAppKey
        )

        currentDate.addTimeInterval(8 * day)

        let cachedObservation = store.observation(
            for: cachedAppKey,
            action: .maximize
        )

        #expect(cachedObservation == nil)
    }

    @Test
    func usedApplicationConstraintsRemainAvailableInsideSevenDayWindow() {
        var currentDate = testDate(5_000_000)
        let store = makePersistedStore(now: { currentDate })

        store.record(
            sizeBounds: sizeBounds(maximumWidth: 1200, maximumHeight: 800),
            horizontalAnchor: .centered,
            verticalAnchor: .centered,
            action: .maximize,
            for: cachedAppKey
        )

        currentDate.addTimeInterval(6 * day)

        let refreshedObservation = store.observation(
            for: cachedAppKey,
            action: .maximize
        )

        #expect(refreshedObservation?.sizeBounds.maximumWidth == 1200)

        let survivingObservation = store.observation(
            for: cachedAppKey,
            action: .maximize
        )

        #expect(survivingObservation?.sizeBounds.maximumWidth == 1200)
    }

    @Test
    func latestMinimumConstraintClearsConflictingMaximumBound() {
        let store = ObservedWindowConstraintStore()

        store.record(
            sizeBounds: sizeBounds(maximumWidth: 182, maximumHeight: 40),
            horizontalAnchor: .trailingEdge,
            verticalAnchor: .trailingEdge,
            action: .topRightQuarter,
            for: dialogKey
        )

        store.record(
            sizeBounds: sizeBounds(minimumWidth: 560, minimumHeight: 672),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .trailingEdge,
            action: .topRightQuarter,
            for: dialogKey
        )

        let observation = store.observation(
            for: dialogKey,
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
            sizeBounds: sizeBounds(minimumWidth: 560, minimumHeight: 672),
            horizontalAnchor: .leadingEdge,
            verticalAnchor: .trailingEdge,
            action: .topRightQuarter,
            for: dialogKey
        )

        store.record(
            sizeBounds: sizeBounds(maximumWidth: 182, maximumHeight: 40),
            horizontalAnchor: .trailingEdge,
            verticalAnchor: .trailingEdge,
            action: .topRightQuarter,
            for: dialogKey
        )

        let observation = store.observation(
            for: dialogKey,
            action: .topRightQuarter
        )

        #expect(observation?.sizeBounds.minimumWidth == nil)
        #expect(observation?.sizeBounds.maximumWidth == 182)
        #expect(observation?.sizeBounds.minimumHeight == nil)
        #expect(observation?.sizeBounds.maximumHeight == 40)
    }
}
