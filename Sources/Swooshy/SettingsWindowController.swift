import AppKit
import Carbon.HIToolbox
import SwiftUI
import Observation
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settingsStore: SettingsStore
    private let gestureTargetCaptureController: GestureTargetCaptureController
    private let hotKeyRegistrationStatusStore: HotKeyRegistrationStatusStore
    private let navigationState = SettingsNavigationState()
    private let onPointerInsideChanged: (Bool) -> Void
    private let windowPresenter: UserFacingWindowPresenter
    private var settingsObserver: NSObjectProtocol?
    private var pointerTrackingArea: NSTrackingArea?
    private var isPointerInsideContentView = false

    init(
        settingsStore: SettingsStore,
        hotKeyRegistrationStatusStore: HotKeyRegistrationStatusStore = HotKeyRegistrationStatusStore(),
        gestureTargetCaptureController: GestureTargetCaptureController = GestureTargetCaptureController(),
        previewUpdateAvailable: Bool = false,
        showGestureTriggerRegions: @escaping (CGRect?) -> Void = { _ in },
        startGestureTargetCapture: @escaping () -> Void = {},
        cancelGestureTargetCapture: @escaping () -> Void = {},
        onPointerInsideChanged: @escaping (Bool) -> Void = { _ in },
        windowPresenter: UserFacingWindowPresenter = .shared
    ) {
        self.settingsStore = settingsStore
        self.gestureTargetCaptureController = gestureTargetCaptureController
        self.hotKeyRegistrationStatusStore = hotKeyRegistrationStatusStore
        self.onPointerInsideChanged = onPointerInsideChanged
        self.windowPresenter = windowPresenter

        let windowReference = WeakWindowReference()
        let rootView = SettingsView(
            settingsStore: settingsStore,
            gestureTargetCaptureController: gestureTargetCaptureController,
            hotKeyRegistrationStatusStore: hotKeyRegistrationStatusStore,
            aboutPageModel: AboutPageModel(previewUpdateAvailable: previewUpdateAvailable),
            showGestureTriggerRegions: {
                showGestureTriggerRegions(windowReference.window?.frame)
            },
            startGestureTargetCapture: startGestureTargetCapture,
            cancelGestureTargetCapture: cancelGestureTargetCapture,
            navigationState: navigationState
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        windowReference.window = window

        window.setContentSize(NSSize(width: 860, height: 640))
        window.minSize = NSSize(width: 760, height: 560)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        self.window?.delegate = self
        installPointerTrackingIfNeeded()
        updatePointerInsideContentViewState()
        updateWindowTitle()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: settingsStore,
            queue: .main
        ) { [weak self] notification in
            let categories = notification.settingsChangeCategories
            MainActor.assumeIsolated {
                guard categories.contains(.localization) else {
                    return
                }
                self?.updateWindowTitle()
            }
        }
    }

    deinit {
        // deinit is not guaranteed to run on the main thread; assumeIsolated
        // would crash there. AppDelegate calls shutdown() explicitly, so this
        // is only a best-effort fallback when deallocated on the main thread.
        guard Thread.isMainThread else {
            assertionFailure("SettingsWindowController deallocated off the main thread without shutdown()")
            return
        }

        MainActor.assumeIsolated {
            shutdown()
        }
    }

    func shutdown() {
        setPointerInsideContentView(false)
        removePointerTracking()

        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }

        window?.delegate = nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func show() {
        updateWindowTitle()
        installPointerTrackingIfNeeded()
        windowPresenter.present(window: window) {
            showWindow(nil)
        }
        updatePointerInsideContentViewState()
    }

    func showShortcuts() {
        navigationState.selectedPage = .shortcuts
        show()
    }

    func showAbout() {
        navigationState.selectedPage = .about
        show()
    }

    private func updateWindowTitle() {
        window?.title = settingsStore.localized("settings.window.title")
    }

    override func mouseEntered(with event: NSEvent) {
        setPointerInsideContentView(true)
    }

    override func mouseExited(with event: NSEvent) {
        setPointerInsideContentView(false)
    }

    func windowWillClose(_ notification: Notification) {
        setPointerInsideContentView(false)
        windowPresenter.windowDidClose(window)
    }

    private func installPointerTrackingIfNeeded() {
        guard let contentView = window?.contentView else {
            return
        }

        if let pointerTrackingArea {
            contentView.removeTrackingArea(pointerTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView.addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
    }

    private func removePointerTracking() {
        guard
            let pointerTrackingArea,
            let contentView = window?.contentView
        else {
            self.pointerTrackingArea = nil
            return
        }

        contentView.removeTrackingArea(pointerTrackingArea)
        self.pointerTrackingArea = nil
    }

    private func updatePointerInsideContentViewState() {
        guard
            let window,
            let contentView = window.contentView,
            window.isVisible
        else {
            setPointerInsideContentView(false)
            return
        }

        let windowPoint = window.mouseLocationOutsideOfEventStream
        let contentPoint = contentView.convert(windowPoint, from: nil)
        setPointerInsideContentView(contentView.bounds.contains(contentPoint))
    }

    private func setPointerInsideContentView(_ isInside: Bool) {
        guard isPointerInsideContentView != isInside else {
            return
        }

        isPointerInsideContentView = isInside
        onPointerInsideChanged(isInside)
    }
}

private final class WeakWindowReference {
    weak var window: NSWindow?
}
