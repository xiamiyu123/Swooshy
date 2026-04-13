import CoreGraphics
import Foundation

struct WindowOrderDescriptor: Equatable, Sendable {
    let windowID: CGWindowID?
    let frame: CGRect
}

struct WindowOrdering {
    private let frameTolerance: CGFloat = 12
    private let centerTolerance: CGFloat = 24

    func frontToBack<T>(
        _ windows: [T],
        descriptor: (T) throws -> WindowOrderDescriptor,
        using orderedDescriptors: [WindowOrderDescriptor]
    ) rethrows -> [T] {
        guard windows.count > 1, orderedDescriptors.isEmpty == false else {
            return windows
        }

        let windowDescriptors = try windows.map(descriptor)
        let allWindowIndices = Array(windows.indices)
        var unmatchedWindowIndexSet = Set(allWindowIndices)
        var orderedWindowIndices: [Int] = []
        orderedWindowIndices.reserveCapacity(windows.count)

        for orderedDescriptor in orderedDescriptors {
            guard let bestMatch = bestMatchingWindowIndex(
                allWindowIndices: allWindowIndices,
                unmatchedWindowIndexSet: unmatchedWindowIndexSet,
                windowDescriptors: windowDescriptors,
                orderedDescriptor: orderedDescriptor
            ) else {
                continue
            }

            orderedWindowIndices.append(bestMatch)
            unmatchedWindowIndexSet.remove(bestMatch)
        }

        orderedWindowIndices.append(
            contentsOf: allWindowIndices.filter { unmatchedWindowIndexSet.contains($0) }
        )
        return orderedWindowIndices.map { windows[$0] }
    }

    private func bestMatchingWindowIndex(
        allWindowIndices: [Int],
        unmatchedWindowIndexSet: Set<Int>,
        windowDescriptors: [WindowOrderDescriptor],
        orderedDescriptor: WindowOrderDescriptor
    ) -> Int? {
        var bestMatchIndex: Int?
        var bestScore = Int.min

        for windowIndex in allWindowIndices where unmatchedWindowIndexSet.contains(windowIndex) {
            guard let score = matchScore(
                windowDescriptor: windowDescriptors[windowIndex],
                orderedDescriptor: orderedDescriptor
            ) else {
                continue
            }

            if score > bestScore {
                bestScore = score
                bestMatchIndex = windowIndex
            }
        }

        return bestMatchIndex
    }

    private func matchScore(
        windowDescriptor: WindowOrderDescriptor,
        orderedDescriptor: WindowOrderDescriptor
    ) -> Int? {
        if
            let windowID = windowDescriptor.windowID,
            let orderedWindowID = orderedDescriptor.windowID,
            windowID == orderedWindowID
        {
            let delta = frameDelta(windowDescriptor.frame, orderedDescriptor.frame)
            return 1_000_000 - Int(delta.rounded(.down))
        }

        if framesAreClose(windowDescriptor.frame, orderedDescriptor.frame) {
            let delta = frameDelta(windowDescriptor.frame, orderedDescriptor.frame)
            return 100_000 - Int(delta.rounded(.down))
        }

        guard sizesAreClose(windowDescriptor.frame, orderedDescriptor.frame) else {
            return nil
        }

        let distance = centerDistance(windowDescriptor.frame, orderedDescriptor.frame)
        guard distance <= centerTolerance else {
            return nil
        }

        return 10_000 - Int(distance.rounded(.down))
    }

    private func framesAreClose(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= frameTolerance &&
        abs(lhs.minY - rhs.minY) <= frameTolerance &&
        abs(lhs.width - rhs.width) <= frameTolerance &&
        abs(lhs.height - rhs.height) <= frameTolerance
    }

    private func sizesAreClose(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.width - rhs.width) <= frameTolerance &&
        abs(lhs.height - rhs.height) <= frameTolerance
    }

    private func frameDelta(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.minX - rhs.minX) +
        abs(lhs.minY - rhs.minY) +
        abs(lhs.width - rhs.width) +
        abs(lhs.height - rhs.height)
    }

    private func centerDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        hypot(lhs.midX - rhs.midX, lhs.midY - rhs.midY)
    }
}

@MainActor
final class WindowCycleSessionStore<Item> {
    private struct Session {
        let processIdentifier: pid_t
        let orderedWindows: [Item]
        let lastTarget: Item
        let updatedAt: Date
    }

    private let expirationInterval: TimeInterval = 5
    private let areEqual: (Item, Item) -> Bool
    private var session: Session?

    init(areEqual: @escaping (Item, Item) -> Bool) {
        self.areEqual = areEqual
    }

    func nextTarget(
        for processIdentifier: pid_t,
        liveOrder: [Item],
        currentWindow: Item?,
        direction: WindowCycleDirection,
        now: Date = Date()
    ) -> Item? {
        guard liveOrder.count > 1 else {
            invalidate(for: processIdentifier)
            return nil
        }

        let baseOrder: [Item]
        if shouldContinueSession(
            for: processIdentifier,
            currentWindow: currentWindow,
            now: now
        ), let session {
            baseOrder = mergedOrder(
                rememberedOrder: session.orderedWindows,
                liveOrder: liveOrder
            )
        } else {
            baseOrder = liveOrder
        }

        guard baseOrder.count > 1 else {
            invalidate(for: processIdentifier)
            return nil
        }

        let currentIndex = currentWindow.flatMap { currentWindow in
            firstIndex(of: currentWindow, in: baseOrder)
        } ?? 0
        let targetIndex: Int

        switch direction {
        case .forward:
            targetIndex = (currentIndex + 1) % baseOrder.count
        case .backward:
            targetIndex = (currentIndex + baseOrder.count - 1) % baseOrder.count
        }

        let target = baseOrder[targetIndex]
        session = Session(
            processIdentifier: processIdentifier,
            orderedWindows: baseOrder,
            lastTarget: target,
            updatedAt: now
        )
        return target
    }

    func invalidate(for processIdentifier: pid_t? = nil) {
        guard let session else { return }

        if let processIdentifier, session.processIdentifier != processIdentifier {
            return
        }

        self.session = nil
    }

    private func shouldContinueSession(
        for processIdentifier: pid_t,
        currentWindow: Item?,
        now: Date
    ) -> Bool {
        guard let session else {
            return false
        }

        guard session.processIdentifier == processIdentifier else {
            return false
        }

        guard now.timeIntervalSince(session.updatedAt) <= expirationInterval else {
            return false
        }

        guard let currentWindow else {
            return false
        }

        return areEqual(currentWindow, session.lastTarget)
    }

    private func mergedOrder(
        rememberedOrder: [Item],
        liveOrder: [Item]
    ) -> [Item] {
        let retainedWindows = rememberedOrder.filter { rememberedWindow in
            contains(rememberedWindow, in: liveOrder)
        }
        let newWindows = liveOrder.filter { liveWindow in
            contains(liveWindow, in: retainedWindows) == false
        }
        return retainedWindows + newWindows
    }

    private func contains(_ candidate: Item, in windows: [Item]) -> Bool {
        windows.contains { areEqual($0, candidate) }
    }

    private func firstIndex(of candidate: Item, in windows: [Item]) -> Int? {
        windows.firstIndex { areEqual($0, candidate) }
    }
}
