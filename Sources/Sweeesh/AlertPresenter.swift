import AppKit

@MainActor
protocol AlertPresenting {
    func show(title: String, message: String)
}

@MainActor
struct AppAlertPresenter: AlertPresenting {
    func show(title: String, message: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
