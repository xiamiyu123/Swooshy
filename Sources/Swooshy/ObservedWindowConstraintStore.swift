import CoreGraphics
import Foundation

@MainActor
final class ObservedWindowConstraintStore {
    private static let persistenceKey = "windowManager.observedWindowConstraintStore"
    private static let expirationInterval: TimeInterval = 7 * 24 * 60 * 60
    private static let defaultAutosaveInterval: TimeInterval = 60 * 60

    private struct PersistedSnapshot: Codable {
        var applications: [PersistedApplicationConstraints]
    }

    private struct PersistedApplicationConstraints: Codable {
        var applicationKey: String
        var sharedSizeBounds: WindowActionPreview.SizeBounds
        var observations: [PersistedActionObservation]
        var lastUsedAt: Date
    }

    private struct PersistedActionObservation: Codable {
        var action: WindowAction
        var observation: WindowActionPreview.Observation
    }

    private struct ApplicationConstraints {
        var sharedSizeBounds = WindowActionPreview.SizeBounds(
            minimumWidth: nil,
            maximumWidth: nil,
            minimumHeight: nil,
            maximumHeight: nil
        )
        var observationsByAction: [WindowAction: WindowActionPreview.Observation] = [:]
        var lastUsedAt: Date
    }

    private let userDefaults: UserDefaults
    private let now: () -> Date
    private let autosaveInterval: TimeInterval
    private var autosaveTimer: Timer?
    private var constraintsByApplicationKey: [String: ApplicationConstraints] = [:]
    private var hasPendingPersistence = false

    init(
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        autosaveInterval: TimeInterval = ObservedWindowConstraintStore.defaultAutosaveInterval
    ) {
        self.userDefaults = userDefaults
        self.now = now
        self.autosaveInterval = autosaveInterval

        loadPersistedConstraints()
        scheduleAutosaveIfNeeded()
    }

    func observation(
        for applicationKey: String,
        action: WindowAction
    ) -> WindowActionPreview.Observation? {
        pruneExpiredConstraints()

        guard var applicationConstraints = constraintsByApplicationKey[applicationKey] else {
            return nil
        }

        applicationConstraints.lastUsedAt = now()
        constraintsByApplicationKey[applicationKey] = applicationConstraints
        hasPendingPersistence = true

        if let actionObservation = applicationConstraints.observationsByAction[action] {
            guard
                actionObservation.sizeBounds.hasConstraints ||
                actionObservation.horizontalAnchor != nil ||
                actionObservation.verticalAnchor != nil
            else {
                return nil
            }

            return actionObservation
        }

        guard applicationConstraints.sharedSizeBounds.hasConstraints else {
            return nil
        }

        return WindowActionPreview.Observation(
            sizeBounds: applicationConstraints.sharedSizeBounds,
            horizontalAnchor: nil,
            verticalAnchor: nil
        )
    }

    func sharedSizeBounds(for applicationKey: String) -> WindowActionPreview.SizeBounds? {
        pruneExpiredConstraints()

        guard var applicationConstraints = constraintsByApplicationKey[applicationKey] else {
            return nil
        }

        applicationConstraints.lastUsedAt = now()
        constraintsByApplicationKey[applicationKey] = applicationConstraints
        hasPendingPersistence = true

        guard applicationConstraints.sharedSizeBounds.hasConstraints else {
            return nil
        }

        return applicationConstraints.sharedSizeBounds
    }

    func record(
        sizeBounds: WindowActionPreview.SizeBounds,
        horizontalAnchor: WindowActionPreview.AxisAnchor?,
        verticalAnchor: WindowActionPreview.AxisAnchor?,
        action: WindowAction,
        for applicationKey: String
    ) {
        pruneExpiredConstraints()

        let currentDate = now()
        var applicationConstraints = constraintsByApplicationKey[applicationKey] ?? ApplicationConstraints(
            lastUsedAt: currentDate
        )

        if sizeBounds.hasConstraints {
            applicationConstraints.sharedSizeBounds = mergedConstraintSizeBounds(
                applicationConstraints.sharedSizeBounds,
                with: sizeBounds
            )
        }

        if var existingObservation = applicationConstraints.observationsByAction[action] {
            existingObservation.sizeBounds = mergedConstraintSizeBounds(
                existingObservation.sizeBounds,
                with: sizeBounds
            )
            if let horizontalAnchor {
                existingObservation.horizontalAnchor = horizontalAnchor
            }
            if let verticalAnchor {
                existingObservation.verticalAnchor = verticalAnchor
            }
            applicationConstraints.observationsByAction[action] = existingObservation
        } else {
            applicationConstraints.observationsByAction[action] = WindowActionPreview.Observation(
                sizeBounds: sizeBounds,
                horizontalAnchor: horizontalAnchor,
                verticalAnchor: verticalAnchor
            )
        }

        applicationConstraints.lastUsedAt = currentDate
        constraintsByApplicationKey[applicationKey] = applicationConstraints
        hasPendingPersistence = true
    }

    func flushPersistedConstraints() {
        persistIfNeeded(force: true)
    }

    func shutdown() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        flushPersistedConstraints()
    }

    static func resetPersistedConstraints(in userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: persistenceKey)
    }

    private func loadPersistedConstraints() {
        guard let data = userDefaults.data(forKey: Self.persistenceKey) else {
            return
        }

        do {
            let snapshot = try JSONDecoder().decode(PersistedSnapshot.self, from: data)
            constraintsByApplicationKey = Dictionary(
                uniqueKeysWithValues: snapshot.applications.map { application in
                    (
                        application.applicationKey,
                        ApplicationConstraints(
                            sharedSizeBounds: application.sharedSizeBounds,
                            observationsByAction: Dictionary(
                                uniqueKeysWithValues: application.observations.map { ($0.action, $0.observation) }
                            ),
                            lastUsedAt: application.lastUsedAt
                        )
                    )
                }
            )
            pruneExpiredConstraints()
            if hasPendingPersistence {
                persistIfNeeded(force: true)
            }
        } catch {
            DebugLog.error(
                DebugLog.windows,
                "Failed to decode observed window constraint store, clearing persisted cache: \(error.localizedDescription)"
            )
            constraintsByApplicationKey = [:]
            hasPendingPersistence = false
            userDefaults.removeObject(forKey: Self.persistenceKey)
        }
    }

    private func scheduleAutosaveIfNeeded() {
        guard autosaveInterval > 0 else {
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: autosaveInterval, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.persistIfNeeded()
            }
        }
        timer.tolerance = min(60, autosaveInterval * 0.1)
        autosaveTimer = timer
    }

    private func pruneExpiredConstraints(referenceDate: Date? = nil) {
        let currentDate = referenceDate ?? now()
        let cutoffDate = currentDate.addingTimeInterval(-Self.expirationInterval)
        let originalCount = constraintsByApplicationKey.count

        constraintsByApplicationKey = constraintsByApplicationKey.filter { _, constraints in
            constraints.lastUsedAt >= cutoffDate
        }

        if constraintsByApplicationKey.count != originalCount {
            hasPendingPersistence = true
        }
    }

    private func persistIfNeeded(force: Bool = false) {
        pruneExpiredConstraints()

        guard force || hasPendingPersistence else {
            return
        }

        guard !constraintsByApplicationKey.isEmpty else {
            userDefaults.removeObject(forKey: Self.persistenceKey)
            hasPendingPersistence = false
            return
        }

        let applications = constraintsByApplicationKey
            .sorted { $0.key < $1.key }
            .map { applicationKey, constraints in
                let observations = constraints.observationsByAction
                    .sorted { $0.key.rawValue < $1.key.rawValue }
                    .map { action, observation in
                        PersistedActionObservation(action: action, observation: observation)
                    }

                return PersistedApplicationConstraints(
                    applicationKey: applicationKey,
                    sharedSizeBounds: constraints.sharedSizeBounds,
                    observations: observations,
                    lastUsedAt: constraints.lastUsedAt
                )
            }

        do {
            let data = try JSONEncoder().encode(PersistedSnapshot(applications: applications))
            userDefaults.set(data, forKey: Self.persistenceKey)
            hasPendingPersistence = false
        } catch {
            DebugLog.error(
                DebugLog.windows,
                "Failed to persist observed window constraint store: \(error.localizedDescription)"
            )
        }
    }
}

private func mergedConstraintSizeBounds(
    _ lhs: WindowActionPreview.SizeBounds,
    with rhs: WindowActionPreview.SizeBounds
) -> WindowActionPreview.SizeBounds {
    let mergedBounds = WindowActionPreview.SizeBounds(
        minimumWidth: mergeConstraintMaximum(lhs.minimumWidth, rhs.minimumWidth),
        maximumWidth: mergeConstraintMinimum(lhs.maximumWidth, rhs.maximumWidth),
        minimumHeight: mergeConstraintMaximum(lhs.minimumHeight, rhs.minimumHeight),
        maximumHeight: mergeConstraintMinimum(lhs.maximumHeight, rhs.maximumHeight)
    )

    return normalizedConstraintSizeBounds(mergedBounds, favoring: rhs)
}

private func mergeConstraintMaximum(_ lhs: CGFloat?, _ rhs: CGFloat?) -> CGFloat? {
    mergeConstraintValues(lhs, rhs, combine: max)
}

private func mergeConstraintMinimum(_ lhs: CGFloat?, _ rhs: CGFloat?) -> CGFloat? {
    mergeConstraintValues(lhs, rhs, combine: min)
}

private func mergeConstraintValues(
    _ lhs: CGFloat?,
    _ rhs: CGFloat?,
    combine: (CGFloat, CGFloat) -> CGFloat
) -> CGFloat? {
    if let lhs, let rhs {
        return combine(lhs, rhs)
    }

    return lhs ?? rhs
}

private func normalizedConstraintSizeBounds(
    _ bounds: WindowActionPreview.SizeBounds,
    favoring latest: WindowActionPreview.SizeBounds
) -> WindowActionPreview.SizeBounds {
    WindowActionPreview.SizeBounds(
        minimumWidth: normalizedConstraintMinimum(
            minimum: bounds.minimumWidth,
            maximum: bounds.maximumWidth,
            latestMinimum: latest.minimumWidth,
            latestMaximum: latest.maximumWidth
        ),
        maximumWidth: normalizedConstraintMaximum(
            minimum: bounds.minimumWidth,
            maximum: bounds.maximumWidth,
            latestMinimum: latest.minimumWidth,
            latestMaximum: latest.maximumWidth
        ),
        minimumHeight: normalizedConstraintMinimum(
            minimum: bounds.minimumHeight,
            maximum: bounds.maximumHeight,
            latestMinimum: latest.minimumHeight,
            latestMaximum: latest.maximumHeight
        ),
        maximumHeight: normalizedConstraintMaximum(
            minimum: bounds.minimumHeight,
            maximum: bounds.maximumHeight,
            latestMinimum: latest.minimumHeight,
            latestMaximum: latest.maximumHeight
        )
    )
}

private func normalizedConstraintMinimum(
    minimum: CGFloat?,
    maximum: CGFloat?,
    latestMinimum: CGFloat?,
    latestMaximum: CGFloat?
) -> CGFloat? {
    guard
        latestMaximum != nil,
        latestMinimum == nil,
        let minimum,
        let maximum,
        minimum > maximum
    else {
        return minimum
    }

    return nil
}

private func normalizedConstraintMaximum(
    minimum: CGFloat?,
    maximum: CGFloat?,
    latestMinimum: CGFloat?,
    latestMaximum: CGFloat?
) -> CGFloat? {
    guard
        latestMinimum != nil,
        latestMaximum == nil,
        let minimum,
        let maximum,
        minimum > maximum
    else {
        return maximum
    }

    return nil
}
