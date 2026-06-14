import AppKit

@MainActor
final class UserFacingWindowPresenter {
    static let shared = UserFacingWindowPresenter()

    private let activationCoordinator: UserFacingWindowActivationCoordinator<ObjectIdentifier>
    private let activateApplication: () -> Void

    init(
        setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Bool = {
            NSApplication.shared.setActivationPolicy($0)
        },
        activateApplication: @escaping () -> Void = {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    ) {
        self.activationCoordinator = UserFacingWindowActivationCoordinator(
            setActivationPolicy: setActivationPolicy
        )
        self.activateApplication = activateApplication
    }

    func present(window: NSWindow?, showWindow: () -> Void) {
        if let window {
            activationCoordinator.presentWindow(id: ObjectIdentifier(window))
        } else {
            activationCoordinator.prepareForUserFacingWindow()
        }

        showWindow()
        activateApplication()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowDidClose(_ window: NSWindow?) {
        guard let window else { return }

        activationCoordinator.closeWindow(id: ObjectIdentifier(window))
    }
}

@MainActor
final class UserFacingWindowActivationCoordinator<WindowID: Hashable> {
    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Bool
    private var visibleWindowIDs: Set<WindowID> = []

    init(setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Bool) {
        self.setActivationPolicy = setActivationPolicy
    }

    func prepareForUserFacingWindow() {
        _ = setActivationPolicy(.regular)
    }

    func presentWindow(id: WindowID) {
        visibleWindowIDs.insert(id)
        prepareForUserFacingWindow()
    }

    func closeWindow(id: WindowID) {
        guard visibleWindowIDs.remove(id) != nil else {
            return
        }

        if visibleWindowIDs.isEmpty {
            _ = setActivationPolicy(.accessory)
        }
    }
}
