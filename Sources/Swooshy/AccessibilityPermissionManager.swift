import AppKit
import ApplicationServices

@MainActor
protocol AccessibilityPermissionManaging {
    func isTrusted(promptIfNeeded: Bool) -> Bool
    func requestAccess() -> Bool
}

extension AccessibilityPermissionManaging {
    func requestAccess() -> Bool {
        isTrusted(promptIfNeeded: true)
    }
}

@MainActor
struct AccessibilityPermissionManager: AccessibilityPermissionManaging {
    static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    private let trustChecker: @MainActor (Bool) -> Bool
    private let openURL: @MainActor (URL) -> Void

    init(
        trustChecker: @escaping @MainActor (Bool) -> Bool = AccessibilityPermissionManager.checkTrust,
        openURL: @escaping @MainActor (URL) -> Void = { url in
            NSWorkspace.shared.open(url)
        }
    ) {
        self.trustChecker = trustChecker
        self.openURL = openURL
    }

    func isTrusted(promptIfNeeded: Bool) -> Bool {
        trustChecker(promptIfNeeded)
    }

    func requestAccess() -> Bool {
        let granted = isTrusted(promptIfNeeded: true)
        if !granted {
            openURL(Self.accessibilitySettingsURL)
        }

        return granted
    }

    private static func checkTrust(promptIfNeeded: Bool) -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": promptIfNeeded,
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }
}
