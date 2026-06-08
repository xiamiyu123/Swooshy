import AppKit
import Foundation

/// Normalizes the different names macOS exposes for the same app so Dock hits,
/// AX windows, and running processes can still be matched reliably.
enum RunningApplicationIdentity {
    private static let helperNameMarkers = [
        "helper",
        "notification service",
    ]
    private static let helperBundleIdentifierMarkers = [
        ".framework.",
        ".helper",
    ]
    private static let helperBundlePathMarkers = [
        "/frameworks/",
        "/helpers/",
        ".appex/",
    ]
    static func isLikelyHelperProcess(_ application: NSRunningApplication) -> Bool {
        isLikelyHelperProcess(
            localizedName: application.localizedName,
            bundleIdentifier: application.bundleIdentifier,
            bundlePath: application.bundleURL?.path
        )
    }

    static func isLikelyHelperProcess(
        localizedName: String?,
        bundleIdentifier: String?,
        bundlePath: String?
    ) -> Bool {
        containsAnyMarker(helperNameMarkers, in: localizedName) ||
            containsAnyMarker(helperBundleIdentifierMarkers, in: bundleIdentifier) ||
            containsAnyMarker(helperBundlePathMarkers, in: bundlePath)
    }

    private static func containsAnyMarker(_ markers: [String], in value: String?) -> Bool {
        guard let value else {
            return false
        }

        let normalizedValue = value.lowercased()
        return markers.contains { normalizedValue.contains($0) }
    }
}
