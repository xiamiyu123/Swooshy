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
        guard windows.count > 1, !orderedDescriptors.isEmpty else {
            return windows
        }

        let windowDescriptors = try windows.map(descriptor)
        var unmatchedWindowIndices = Array(windows.indices)
        var orderedWindowIndices: [Int] = []
        orderedWindowIndices.reserveCapacity(windows.count)

        for orderedDescriptor in orderedDescriptors {
            guard let bestMatch = bestMatchingWindowIndex(
                unmatchedWindowIndices: unmatchedWindowIndices,
                windowDescriptors: windowDescriptors,
                orderedDescriptor: orderedDescriptor
            ) else {
                continue
            }

            orderedWindowIndices.append(bestMatch)
            unmatchedWindowIndices.removeAll { $0 == bestMatch }
        }

        orderedWindowIndices.append(contentsOf: unmatchedWindowIndices)
        return orderedWindowIndices.map { windows[$0] }
    }

    private func bestMatchingWindowIndex(
        unmatchedWindowIndices: [Int],
        windowDescriptors: [WindowOrderDescriptor],
        orderedDescriptor: WindowOrderDescriptor
    ) -> Int? {
        unmatchedWindowIndices.compactMap { windowIndex -> (index: Int, score: Int)? in
            guard let score = matchScore(
                windowDescriptor: windowDescriptors[windowIndex],
                orderedDescriptor: orderedDescriptor
            ) else {
                return nil
            }

            return (index: windowIndex, score: score)
        }
        .max { $0.score < $1.score }?
        .index
    }

    private func matchScore(
        windowDescriptor: WindowOrderDescriptor,
        orderedDescriptor: WindowOrderDescriptor
    ) -> Int? {
        let windowFrame = windowDescriptor.frame
        let orderedFrame = orderedDescriptor.frame

        if
            let windowID = windowDescriptor.windowID,
            let orderedWindowID = orderedDescriptor.windowID,
            windowID == orderedWindowID
        {
            return frameMatchScore(
                windowFrame,
                orderedFrame,
                baseScore: 1_000_000
            )
        }

        if framesAreClose(windowFrame, orderedFrame) {
            return frameMatchScore(
                windowFrame,
                orderedFrame,
                baseScore: 100_000
            )
        }

        guard sizesAreClose(windowFrame, orderedFrame) else {
            return nil
        }

        let distance = centerDistance(windowFrame, orderedFrame)
        guard distance <= centerTolerance else {
            return nil
        }

        return 10_000 - Int(distance.rounded(.down))
    }

    private func frameMatchScore(_ lhs: CGRect, _ rhs: CGRect, baseScore: Int) -> Int {
        baseScore - Int(frameDelta(lhs, rhs).rounded(.down))
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

        let baseOrder = if shouldContinueSession(
            for: processIdentifier,
            currentWindow: currentWindow,
            now: now
        ), let session {
            mergedOrder(
                rememberedOrder: session.orderedWindows,
                liveOrder: liveOrder
            )
        } else {
            liveOrder
        }

        guard baseOrder.count > 1 else {
            invalidate(for: processIdentifier)
            return nil
        }

        let currentIndex = currentWindow.flatMap { currentWindow in
            firstIndex(of: currentWindow, in: baseOrder)
        } ?? 0
        let targetIndex = (currentIndex + direction.indexOffset + baseOrder.count) % baseOrder.count

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
        guard
            let session,
            session.processIdentifier == processIdentifier,
            now.timeIntervalSince(session.updatedAt) <= expirationInterval,
            let currentWindow
        else {
            return false
        }

        return areEqual(currentWindow, session.lastTarget)
    }

    private func mergedOrder(
        rememberedOrder: [Item],
        liveOrder: [Item]
    ) -> [Item] {
        let retainedWindows = rememberedOrder.filter { rememberedWindow in
            liveOrder.contains { areEqual($0, rememberedWindow) }
        }
        let newWindows = liveOrder.filter { liveWindow in
            !retainedWindows.contains { areEqual($0, liveWindow) }
        }
        return retainedWindows + newWindows
    }

    private func firstIndex(of candidate: Item, in windows: [Item]) -> Int? {
        windows.firstIndex { areEqual($0, candidate) }
    }
}

private extension WindowCycleDirection {
    var indexOffset: Int {
        switch self {
        case .forward:
            return 1
        case .backward:
            return -1
        }
    }
}
