import CoreGraphics
import Foundation
import Testing
@testable import Swooshy

struct CGWindowOrderingSnapshotCacheTests {
    private func windowInfo(
        ownerProcessIdentifier: pid_t,
        windowIdentifier: CGWindowID,
        frame: CGRect
    ) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: ownerProcessIdentifier),
            kCGWindowNumber as String: NSNumber(value: windowIdentifier),
            kCGWindowBounds as String: [
                "X": frame.origin.x,
                "Y": frame.origin.y,
                "Width": frame.width,
                "Height": frame.height,
            ] as NSDictionary,
        ]
    }

    @MainActor
    @Test
    func reusesLoadedWindowInfoWithinTTL() {
        var loadCount = 0
        var currentDate = Date(timeIntervalSinceReferenceDate: 10)
        let cache = CGWindowOrderingSnapshotCache(
            ttl: 0.1,
            now: { currentDate },
            loadWindowInfoList: {
                loadCount += 1
                return [
                    windowInfo(
                        ownerProcessIdentifier: 42,
                        windowIdentifier: 701,
                        frame: CGRect(x: 0, y: 0, width: 800, height: 600)
                    ),
                    windowInfo(
                        ownerProcessIdentifier: 77,
                        windowIdentifier: 702,
                        frame: CGRect(x: 40, y: 40, width: 400, height: 300)
                    ),
                ]
            }
        )

        let first = cache.frontToBackWindowDescriptors(forOwnerProcessIdentifier: 42)
        let second = cache.frontToBackWindowDescriptors(forOwnerProcessIdentifier: 42)

        #expect(loadCount == 1)
        #expect(
            first == [
                WindowOrderDescriptor(
                    windowID: 701,
                    frame: CGRect(x: 0, y: 0, width: 800, height: 600)
                ),
            ]
        )
        #expect(second == first)

        currentDate = currentDate.addingTimeInterval(0.11)
        _ = cache.frontToBackWindowDescriptors(forOwnerProcessIdentifier: 42)

        #expect(loadCount == 2)
    }

    @MainActor
    @Test
    func reusesEmptySnapshotWithinTTL() {
        var loadCount = 0
        let cache = CGWindowOrderingSnapshotCache(
            ttl: 0.1,
            now: { Date(timeIntervalSinceReferenceDate: 20) },
            loadWindowInfoList: {
                loadCount += 1
                return nil
            }
        )

        #expect(cache.frontToBackWindowDescriptors(forOwnerProcessIdentifier: 42).isEmpty)
        #expect(cache.frontToBackWindowDescriptors(forOwnerProcessIdentifier: 42).isEmpty)
        #expect(loadCount == 1)
    }
}
