import CoreGraphics
import Foundation

struct WindowOrderDescriptor: Equatable, Sendable {
    let title: String
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
        var unmatchedWindowIndices = Array(windows.indices)
        var orderedWindowIndices: [Int] = []
        orderedWindowIndices.reserveCapacity(windows.count)

        for orderedDescriptor in orderedDescriptors {
            guard let bestMatch = bestMatchingWindowIndex(
                among: unmatchedWindowIndices,
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
        among unmatchedWindowIndices: [Int],
        windowDescriptors: [WindowOrderDescriptor],
        orderedDescriptor: WindowOrderDescriptor
    ) -> Int? {
        var bestMatchIndex: Int?
        var bestScore = Int.min

        for windowIndex in unmatchedWindowIndices {
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
        let normalizedWindowTitle = normalizedTitle(windowDescriptor.title)
        let normalizedOrderedTitle = normalizedTitle(orderedDescriptor.title)
        let titlesMatch = normalizedWindowTitle.isEmpty == false &&
            normalizedWindowTitle == normalizedOrderedTitle

        if framesAreClose(windowDescriptor.frame, orderedDescriptor.frame) {
            let delta = frameDelta(windowDescriptor.frame, orderedDescriptor.frame)
            let titleBonus = titlesMatch ? 10_000 : 0
            return 100_000 + titleBonus - Int(delta.rounded(.down))
        }

        guard titlesMatch else {
            return nil
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

    private func normalizedTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
    }
}

@MainActor
final class WindowCycleSessionStore {
    private struct Session {
        let processIdentifier: pid_t
        let orderedWindows: [WindowOrderDescriptor]
        let lastTarget: WindowOrderDescriptor
        let updatedAt: Date
    }

    private let expirationInterval: TimeInterval = 5
    private var session: Session?

    func nextTarget(
        for processIdentifier: pid_t,
        liveOrder: [WindowOrderDescriptor],
        currentWindow: WindowOrderDescriptor?,
        direction: WindowCycleDirection,
        now: Date = Date()
    ) -> WindowOrderDescriptor? {
        guard liveOrder.count > 1 else {
            invalidate(for: processIdentifier)
            return nil
        }

        let baseOrder: [WindowOrderDescriptor]
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

        let referenceWindow = currentWindow.flatMap { currentWindow in
            baseOrder.first(where: { $0 == currentWindow })
        } ?? baseOrder[baseOrder.startIndex]
        let currentIndex = baseOrder.firstIndex(of: referenceWindow) ?? 0
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
        currentWindow: WindowOrderDescriptor?,
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

        return currentWindow == session.lastTarget
    }

    private func mergedOrder(
        rememberedOrder: [WindowOrderDescriptor],
        liveOrder: [WindowOrderDescriptor]
    ) -> [WindowOrderDescriptor] {
        let retainedWindows = rememberedOrder.filter { liveOrder.contains($0) }
        let newWindows = liveOrder.filter { retainedWindows.contains($0) == false }
        return retainedWindows + newWindows
    }
}
