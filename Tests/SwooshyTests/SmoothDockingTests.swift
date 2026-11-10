import CoreGraphics
import Foundation
import Testing
@testable import Swooshy

@MainActor
struct SmoothDockingTests {
    private let resolver = SmoothDockingResolver()
    private let desktopFrame = CGRect(x: 0, y: 85, width: 1408, height: 766)

    @Test
    func smoothDockingSupportStaysLimitedToLayoutActions() {
        for action in WindowAction.gestureCases {
            #expect(action.supportsSmoothDocking == action.supportsSnapPreview)
        }
    }

    @Test
    func smoothDockingIdealFramesMatchLayoutEngineTargets() {
        let layoutEngine = WindowLayoutEngine()

        for action in WindowAction.gestureCases where action.supportsSmoothDocking {
            let targetFrame = layoutEngine.targetFrame(
                for: action,
                currentWindowFrame: desktopFrame.integral,
                currentVisibleFrame: desktopFrame.integral
            )
            let plan = resolver.plan(
                for: action,
                in: desktopFrame,
                sizeConstraints: SmoothDockingSizeConstraints()
            )

            #expect(plan.idealFrame == targetFrame)
            #expect(plan.frame == targetFrame)
        }
    }

    @Test
    func smoothDockingSizeConstraintsMergeTightensObservedBounds() {
        let base = SmoothDockingSizeConstraints(
            minimumWidth: 520,
            maximumWidth: 1200,
            minimumHeight: 480,
            maximumHeight: nil
        )
        let observed = SmoothDockingSizeConstraints(
            minimumWidth: 560,
            maximumWidth: 900,
            minimumHeight: nil,
            maximumHeight: 700
        )

        #expect(
            base.merged(with: observed) == SmoothDockingSizeConstraints(
                minimumWidth: 560,
                maximumWidth: 900,
                minimumHeight: 480,
                maximumHeight: 700
            )
        )
    }

    @Test
    func smoothDockingSizeConstraintsNormalizeConflictingBounds() {
        let base = SmoothDockingSizeConstraints(minimumWidth: 900)
        let observed = SmoothDockingSizeConstraints(maximumWidth: 560)

        #expect(
            base.merged(with: observed) == SmoothDockingSizeConstraints(
                minimumWidth: 900,
                maximumWidth: 900
            )
        )
    }

    @Test
    func smoothDockingSizeConstraintsUseObservedPreviewBounds() {
        let sizeBounds = WindowActionPreview.SizeBounds(
            minimumWidth: 520,
            maximumWidth: 1200,
            minimumHeight: 480,
            maximumHeight: 700
        )

        #expect(
            SmoothDockingSizeConstraints(sizeBounds: sizeBounds) == SmoothDockingSizeConstraints(
                minimumWidth: 520,
                maximumWidth: 1200,
                minimumHeight: 480,
                maximumHeight: 700
            )
        )
    }

    @Test
    func topLeftQuarterAnchorsConstrainedWindowToDesktopTopLeft() {
        let plan = resolver.plan(
            for: .topLeftQuarter,
            in: desktopFrame,
            sizeConstraints: SmoothDockingSizeConstraints(
                minimumWidth: nil,
                maximumWidth: 560,
                minimumHeight: 672,
                maximumHeight: nil
            )
        )

        #expect(plan.anchor == .topLeading)
        #expect(plan.frame == CGRect(x: 0, y: 179, width: 560, height: 672))
    }

    @Test
    func rightHalfAnchorsConstrainedWindowToDesktopTopRight() {
        let plan = resolver.plan(
            for: .rightHalf,
            in: desktopFrame,
            sizeConstraints: SmoothDockingSizeConstraints(
                minimumWidth: nil,
                maximumWidth: 560,
                minimumHeight: nil,
                maximumHeight: 672
            )
        )

        #expect(plan.anchor == .topTrailing)
        #expect(plan.frame == CGRect(x: 848, y: 179, width: 560, height: 672))
    }

    @Test
    func maximizeAnchorsConstrainedWindowToDesktopTopLeft() {
        let plan = resolver.plan(
            for: .maximize,
            in: desktopFrame,
            sizeConstraints: SmoothDockingSizeConstraints(
                minimumWidth: nil,
                maximumWidth: 1200,
                minimumHeight: nil,
                maximumHeight: 700
            )
        )

        #expect(plan.anchor == .topLeading)
        #expect(plan.frame == CGRect(x: 0, y: 151, width: 1200, height: 700))
    }

    @Test
    func previewDoesNotPersistConstraintCandidates() async {
        var current = CGRect(x: 0, y: 83, width: 704, height: 384)
        var observations = 0
        let session = SmoothDockingSession(
            originalFrame: current,
            desktopFrame: desktopFrame,
            baseSizeConstraints: .init(),
            applyFrame: { requested in
                current.origin = requested.origin
                return current
            },
            recordConstraintObservation: { _, _, _ in observations += 1 }
        )
        session.update(action: .center)
        try? await Task.sleep(for: .milliseconds(40))
        session.finish()

        #expect(observations == 0)
    }

    @Test
    func commitVerifiesAndRemovesStaleCachedBounds() async throws {
        let defaults = UserDefaults(suiteName: "SmoothDockingTests.\(UUID().uuidString)")!
        var store = ObservedWindowConstraintStore(userDefaults: defaults, autosaveInterval: 0)
        let key = "chrome-window"
        store.record(
            sizeBounds: .init(minimumWidth: nil, maximumWidth: 704, minimumHeight: nil, maximumHeight: 384),
            horizontalAnchor: nil, verticalAnchor: nil, action: .topRightQuarter, for: key
        )
        store.shutdown()
        let data = try #require(defaults.data(forKey: "windowManager.observedWindowConstraintStore"))
        let object = try JSONSerialization.jsonObject(with: data)
        var snapshot = try #require(object as? [String: Any])
        var entries = try #require(snapshot["applications"] as? [[String: Any]])
        entries[0].removeValue(forKey: "verifiedMaximumWidth")
        entries[0].removeValue(forKey: "verifiedMaximumHeight")
        snapshot["applications"] = entries
        defaults.set(try JSONSerialization.data(withJSONObject: snapshot), forKey: "windowManager.observedWindowConstraintStore")
        store = ObservedWindowConstraintStore(userDefaults: defaults, autosaveInterval: 0)
        var current = CGRect(x: 704, y: 467, width: 704, height: 384)
        var writes: [CGRect] = []
        let session = SmoothDockingSession(
            originalFrame: current, desktopFrame: desktopFrame, baseSizeConstraints: .init(),
            observedSizeConstraints: store.dockingSizeBounds(for: key).map(SmoothDockingSizeConstraints.init(sizeBounds:)) ?? .init(),
            applyFrame: { requested in
                writes.append(requested)
                current = requested
                return current
            },
            recordAcceptedFrame: { store.discardBoundsContradicted(by: $0.size, for: key) }
        )
        session.update(action: .center)
        let result = try await session.commit()
        session.finish()

        #expect(result == desktopFrame)
        #expect(writes == [desktopFrame])
        #expect(store.sharedSizeBounds(for: key) == nil)
        store.shutdown()
        let reloaded = ObservedWindowConstraintStore(userDefaults: defaults, autosaveInterval: 0)
        #expect(reloaded.sharedSizeBounds(for: key) == nil)
        reloaded.shutdown()
    }

    @Test(arguments: [WindowAction.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter], [false, true])
    func confirmedConstraintsStillAnchorAndPersist(action: WindowAction, cached: Bool) async throws {
        let desktop = CGRect(x: -1408, y: -683, width: 1408, height: 768)
        var current = CGRect(x: -1200, y: -500, width: 800, height: 700)
        var time = 0.0
        var observations: [CGRect] = []
        let settler = WindowFrameSettler(now: { time }, sleep: { time += $0 })
        let bounds = SmoothDockingSizeConstraints(maximumWidth: 560, minimumHeight: 672)
        let session = SmoothDockingSession(
            originalFrame: current, desktopFrame: desktop, baseSizeConstraints: .init(),
            observedSizeConstraints: cached ? bounds : .init(),
            applyFrame: { requested in
                try await settler.apply(
                    requested,
                    writePosition: { current.origin = $0 },
                    writeSize: { current.size = CGSize(width: min($0.width, 560), height: max($0.height, 672)) },
                    read: { current }
                )
            },
            recordConstraintObservation: { _, _, applied in observations.append(applied) }
        )
        session.update(action: action)
        let result = try await session.commit()
        session.finish()
        let expected = resolver.plan(for: action, in: desktop, sizeConstraints: bounds).frame
        #expect(result == expected)
        #expect(current == expected)
        #expect(observations == (cached ? [] : [expected]))
    }

    @Test
    func cachedBoundsAvoidUnnecessaryPreviewResize() async throws {
        let cached = SmoothDockingSizeConstraints(maximumWidth: 560, minimumHeight: 672)
        var current = resolver.plan(for: .topRightQuarter, in: desktopFrame, sizeConstraints: cached).frame
        var time = 0.0
        var writes = 0
        let session = SmoothDockingSession(
            originalFrame: current, desktopFrame: desktopFrame, baseSizeConstraints: .init(),
            observedSizeConstraints: cached,
            applyFrame: { target in
                try await WindowFrameSettler(now: { time }, sleep: { time += $0 }).apply(
                    target,
                    writePosition: { current.origin = $0; writes += 1 },
                    writeSize: { current.size = $0; writes += 1 }, read: { current }
                )
            }
        )
        session.update(action: .topRightQuarter)
        _ = try await session.commit()
        session.finish()
        #expect(writes == 0)
    }

    @Test
    func delayedCommitDoesNotLearnTransientSizeBounds() async throws {
        var current = CGRect(x: 704, y: 467, width: 704, height: 384)
        var writes = 0
        var observations = 0
        let session = SmoothDockingSession(
            originalFrame: current, desktopFrame: desktopFrame, baseSizeConstraints: .init(),
            applyFrame: { requested in
                writes += 1
                await Task.yield()
                current = requested
                return current
            },
            recordConstraintObservation: { _, _, _ in observations += 1 }
        )
        session.update(action: .center)
        let result = try await session.commit()
        session.finish()
        #expect(result == desktopFrame)
        #expect(writes == 1)
        #expect(observations == 0)
    }

    @Test
    func finishingDuringCommitCancelsRetriesAndCacheWrites() async {
        let current = CGRect(x: 704, y: 467, width: 704, height: 384)
        var writes = 0
        var cacheWrites = 0
        let session = SmoothDockingSession(
            originalFrame: current, desktopFrame: desktopFrame, baseSizeConstraints: .init(),
            applyFrame: { requested in
                writes += 1
                try await Task.sleep(for: .seconds(10))
                return requested
            },
            recordConstraintObservation: { _, _, _ in cacheWrites += 1 },
            recordAcceptedFrame: { _ in cacheWrites += 1 }
        )
        session.update(action: .center)
        let task = Task { try await session.commit() }
        while writes == 0 { await Task.yield() }
        session.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(writes == 1)
        #expect(cacheWrites == 0)
    }

    @Test
    func unconfirmedCommitDoesNotRecordOrInvalidateCache() async {
        let current = CGRect(x: 704, y: 467, width: 704, height: 384)
        var writes = 0
        var cacheWrites = 0
        let session = SmoothDockingSession(
            originalFrame: current, desktopFrame: desktopFrame, baseSizeConstraints: .init(),
            applyFrame: { requested in
                writes += 1
                throw WindowManagerError.unableToSetFrame
            },
            recordConstraintObservation: { _, _, _ in cacheWrites += 1 },
            recordAcceptedFrame: { _ in cacheWrites += 1 }
        )
        session.update(action: .center)
        await #expect(throws: WindowManagerError.self) { try await session.commit() }
        session.finish()
        #expect(writes == 1)
        #expect(cacheWrites == 0)
    }

    @Test
    func restoreCommitConfirmsTheOriginalFrameWithoutLearningBounds() async throws {
        let original = CGRect(x: 120, y: 140, width: 800, height: 600)
        var current = original
        var time = 0.0
        var observations = 0
        let settler = WindowFrameSettler(now: { time }, sleep: { time += $0 })
        let session = SmoothDockingSession(
            originalFrame: original, desktopFrame: desktopFrame, baseSizeConstraints: .init(),
            applyFrame: { requested in
                try await settler.apply(
                    requested, writePosition: { current.origin = $0 }, writeSize: { current.size = $0 },
                    read: { current }
                )
            },
            recordConstraintObservation: { _, _, _ in observations += 1 }
        )
        session.update(action: .center)
        current = desktopFrame
        session.restore()
        let restored = try await session.commit()
        session.finish()
        #expect(restored == original)
        #expect(current == original)
        #expect(time > 0)
        #expect(observations == 0)
    }

    @Test
    func newTargetCancelsOlderConfirmation() async throws {
        var current = CGRect(x: 704, y: 467, width: 704, height: 384)
        var delayedWrites = 0
        var completeImmediately = false
        let session = SmoothDockingSession(
            originalFrame: current, desktopFrame: desktopFrame, baseSizeConstraints: .init(),
            applyFrame: { requested in
                if completeImmediately { current = requested; return current }
                delayedWrites += 1
                try await Task.sleep(for: .seconds(10))
                return requested
            }
        )
        session.update(action: .center)
        let oldCommit = Task { try await session.commit() }
        while delayedWrites == 0 { await Task.yield() }
        completeImmediately = true
        session.update(action: .bottomLeftQuarter)
        let result = try await session.commit()
        await #expect(throws: CancellationError.self) { try await oldCommit.value }
        session.finish()
        #expect(result == resolver.plan(for: .bottomLeftQuarter, in: desktopFrame, sizeConstraints: .init()).frame)
        #expect(delayedWrites == 1)
    }

    @Test
    func smoothDockingSessionRetargetsAfterDetectingSizeConstraint() async {
        let constrainedSize = CGSize(width: 560, height: 672)
        var currentFrame = CGRect(x: 323, y: 179, width: 560, height: 672)

        let session = SmoothDockingSession(
            originalFrame: currentFrame,
            desktopFrame: desktopFrame,
            baseSizeConstraints: SmoothDockingSizeConstraints(),
            applyFrame: { requestedFrame in
                if
                    abs(requestedFrame.width - constrainedSize.width) > 0.1 ||
                    abs(requestedFrame.height - constrainedSize.height) > 0.1
                {
                    currentFrame = CGRect(
                        x: requestedFrame.minX,
                        y: requestedFrame.minY,
                        width: constrainedSize.width,
                        height: constrainedSize.height
                    )
                } else {
                    currentFrame = requestedFrame
                }

                return currentFrame
            }
        )

        session.update(action: .topRightQuarter)
        _ = try? await session.commit()
        session.finish()

        #expect(currentFrame.size == constrainedSize)
        #expect(abs(currentFrame.maxX - desktopFrame.maxX) <= 1)
        #expect(abs(currentFrame.maxY - desktopFrame.maxY) <= 1)
    }

    @Test
    func smoothDockingSessionReportsObservedFrameWritesOnCommit() async throws {
        let constrainedSize = CGSize(width: 560, height: 672)
        var currentFrame = CGRect(x: 120, y: 120, width: 800, height: 600)
        var observations: [(action: WindowAction, requested: CGRect, applied: CGRect)] = []

        let session = SmoothDockingSession(
            originalFrame: currentFrame,
            desktopFrame: desktopFrame,
            baseSizeConstraints: SmoothDockingSizeConstraints(),
            applyFrame: { requestedFrame in
                currentFrame = CGRect(
                    x: requestedFrame.minX,
                    y: requestedFrame.minY,
                    width: constrainedSize.width,
                    height: constrainedSize.height
                )
                return currentFrame
            },
            recordConstraintObservation: { action, requestedFrame, appliedFrame in
                observations.append((action, requestedFrame, appliedFrame))
            }
        )

        session.update(action: .rightHalf)
        _ = try await session.commit()
        session.finish()

        #expect(
            observations.contains { observation in
                observation.action == .rightHalf &&
                    observation.requested.size != observation.applied.size &&
                    observation.applied.size == constrainedSize
            }
        )
    }

    @Test
    func matchingWindowIsConfirmedWithoutFurtherWrites() async throws {
        let targetFrame = resolver.plan(
            for: .topRightQuarter,
            in: desktopFrame,
            sizeConstraints: SmoothDockingSizeConstraints()
        ).frame
        var currentFrame = targetFrame
        var time = 0.0
        var writes = 0

        let session = SmoothDockingSession(
            originalFrame: currentFrame,
            desktopFrame: desktopFrame,
            baseSizeConstraints: SmoothDockingSizeConstraints(),
            applyFrame: { requestedFrame in
                try await WindowFrameSettler(now: { time }, sleep: { time += $0 }).apply(
                    requestedFrame,
                    writePosition: { currentFrame.origin = $0; writes += 1 },
                    writeSize: { currentFrame.size = $0; writes += 1 }, read: { currentFrame }
                )
            }
        )

        session.update(action: .topRightQuarter)
        _ = try await session.commit()
        session.finish()

        #expect(writes == 0)
        #expect(currentFrame == targetFrame)
    }
}
