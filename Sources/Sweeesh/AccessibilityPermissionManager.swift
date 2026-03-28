import ApplicationServices

@MainActor
protocol AccessibilityPermissionManaging {
    func isTrusted(promptIfNeeded: Bool) -> Bool
}

@MainActor
struct AccessibilityPermissionManager: AccessibilityPermissionManaging {
    func isTrusted(promptIfNeeded: Bool) -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": promptIfNeeded,
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }
}
