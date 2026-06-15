import CoreGraphics
import Foundation

@MainActor
final class CGWindowOrderingSnapshotCache {
    private struct CachedSnapshot {
        let descriptors: [CachedWindowDescriptor]
        let loadedAt: Date
    }

    private let ttl: TimeInterval
    private let now: () -> Date
    private let loadWindowInfoList: () -> [[String: Any]]?
    private var cachedSnapshot: CachedSnapshot?

    init(
        ttl: TimeInterval = 0.1,
        now: @escaping () -> Date = Date.init,
        loadWindowInfoList: @escaping () -> [[String: Any]]? = {
            CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        }
    ) {
        self.ttl = ttl
        self.now = now
        self.loadWindowInfoList = loadWindowInfoList
    }

    func frontToBackWindowDescriptors(
        forOwnerProcessIdentifier processIdentifier: pid_t
    ) -> [WindowOrderDescriptor] {
        cachedDescriptors()
            .filter { $0.ownerProcessIdentifier == processIdentifier }
            .map { WindowOrderDescriptor(windowID: $0.windowID, frame: $0.frame) }
    }

    func reset() {
        cachedSnapshot = nil
    }

    private func cachedDescriptors() -> [CachedWindowDescriptor] {
        let currentDate = now()

        if
            let cachedSnapshot,
            currentDate.timeIntervalSince(cachedSnapshot.loadedAt) < ttl
        {
            return cachedSnapshot.descriptors
        }

        let descriptors = loadWindowInfoList().map(Self.makeDescriptors) ?? []
        cachedSnapshot = CachedSnapshot(
            descriptors: descriptors,
            loadedAt: currentDate
        )
        return descriptors
    }

    private static func makeDescriptors(from windowInfoList: [[String: Any]]) -> [CachedWindowDescriptor] {
        windowInfoList.compactMap(CachedWindowDescriptor.init)
    }
}

private struct CachedWindowDescriptor {
    let ownerProcessIdentifier: pid_t
    let windowID: CGWindowID?
    let frame: CGRect

    init?(windowInfo: [String: Any]) {
        guard
            let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? NSNumber,
            let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary
        else {
            return nil
        }

        var frame = CGRect.null
        guard
            CGRectMakeWithDictionaryRepresentation(boundsDictionary, &frame),
            !frame.isNull,
            !frame.isEmpty
        else {
            return nil
        }

        ownerProcessIdentifier = ownerPID.int32Value
        windowID = (windowInfo[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        self.frame = frame.integral
    }
}
