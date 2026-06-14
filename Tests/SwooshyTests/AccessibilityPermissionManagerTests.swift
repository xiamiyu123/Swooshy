import Foundation
import Testing
@testable import Swooshy

@MainActor
struct AccessibilityPermissionManagerTests {
    @Test
    func requestAccessPromptsAndOpensAccessibilitySettingsWhenPermissionIsMissing() {
        var promptRequests: [Bool] = []
        var openedURLs: [URL] = []
        let manager = AccessibilityPermissionManager(
            trustChecker: { promptIfNeeded in
                promptRequests.append(promptIfNeeded)
                return false
            },
            openURL: { url in
                openedURLs.append(url)
            }
        )

        #expect(!manager.requestAccess())
        #expect(promptRequests == [true])
        #expect(openedURLs == [AccessibilityPermissionManager.accessibilitySettingsURL])
    }

    @Test
    func requestAccessDoesNotOpenSettingsWhenPermissionIsAlreadyGranted() {
        var promptRequests: [Bool] = []
        var openedURLs: [URL] = []
        let manager = AccessibilityPermissionManager(
            trustChecker: { promptIfNeeded in
                promptRequests.append(promptIfNeeded)
                return true
            },
            openURL: { url in
                openedURLs.append(url)
            }
        )

        #expect(manager.requestAccess())
        #expect(promptRequests == [true])
        #expect(openedURLs.isEmpty)
    }
}
