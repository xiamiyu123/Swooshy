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
        onPointerInsideChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.settingsStore = settingsStore
        self.gestureTargetCaptureController = gestureTargetCaptureController
        self.hotKeyRegistrationStatusStore = hotKeyRegistrationStatusStore
        self.onPointerInsideChanged = onPointerInsideChanged

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
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
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

private struct SettingsView: View {
    @Bindable var settingsStore: SettingsStore
    @Bindable var gestureTargetCaptureController: GestureTargetCaptureController
    @Bindable var hotKeyRegistrationStatusStore: HotKeyRegistrationStatusStore
    let aboutPageModel: AboutPageModel
    let showGestureTriggerRegions: () -> Void
    let startGestureTargetCapture: () -> Void
    let cancelGestureTargetCapture: () -> Void
    @Bindable var navigationState: SettingsNavigationState
    @State private var launchAtLoginController = LaunchAtLoginController()

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(
                selection: $navigationState.selectedPage,
                settingsStore: settingsStore,
                hotKeyRegistrationStatusStore: hotKeyRegistrationStatusStore
            )
        } detail: {
            SettingsDetailPage(
                page: navigationState.selectedPage ?? .general,
                settingsStore: settingsStore,
                gestureTargetCaptureController: gestureTargetCaptureController,
                hotKeyRegistrationStatusStore: hotKeyRegistrationStatusStore,
                aboutPageModel: aboutPageModel,
                showGestureTriggerRegions: showGestureTriggerRegions,
                startGestureTargetCapture: startGestureTargetCapture,
                cancelGestureTargetCapture: cancelGestureTargetCapture,
                launchAtLoginController: $launchAtLoginController
            )
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            launchAtLoginController.refresh(localize: settingsStore.localized)
        }
    }
}

@MainActor
@Observable
private final class SettingsNavigationState {
    var selectedPage: SettingsPage? = .general
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case gestures
    case dockGestures
    case titleBarGestures
    case shortcuts
    case advanced
    case about

    var id: Self { self }

    var localizationKey: String {
        switch self {
        case .general:
            "settings.section.general"
        case .gestures:
            "settings.section.gestures"
        case .dockGestures:
            "settings.section.dock_gestures"
        case .titleBarGestures:
            "settings.section.title_bar_gestures"
        case .shortcuts:
            "settings.section.shortcuts"
        case .advanced:
            "settings.section.advanced"
        case .about:
            "settings.section.about"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .gestures:
            "hand.draw"
        case .dockGestures:
            "rectangle.bottomthird.inset.filled"
        case .titleBarGestures:
            "rectangle.topthird.inset.filled"
        case .shortcuts:
            "command"
        case .advanced:
            "gearshape.2"
        case .about:
            "info.circle"
        }
    }

    func title(localize: (String) -> String) -> String {
        localize(localizationKey)
    }
}

private struct SettingsSidebar: View {
    private static let width: CGFloat = 210

    @Binding var selection: SettingsPage?
    @Bindable var settingsStore: SettingsStore
    @Bindable var hotKeyRegistrationStatusStore: HotKeyRegistrationStatusStore

    var body: some View {
        List(selection: $selection) {
            ForEach(SettingsPage.allCases) { page in
                SettingsSidebarRow(
                    page: page,
                    title: page.title(localize: settingsStore.localized),
                    showsWarning: page == .shortcuts && hotKeyRegistrationStatusStore.hasIssue,
                    warningTooltip: settingsStore.localized("settings.shortcuts.registration_issue.tooltip")
                )
                    .tag(Optional(page))
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: Self.width, ideal: Self.width, max: Self.width)
    }
}

private struct SettingsSidebarRow: View {
    let page: SettingsPage
    let title: String
    let showsWarning: Bool
    let warningTooltip: String

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: page.systemImage)

            Spacer(minLength: 4)

            if showsWarning {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .help(warningTooltip)
                    .accessibilityLabel(warningTooltip)
            }
        }
    }
}

private struct SettingsDetailPage: View {
    let page: SettingsPage
    @Bindable var settingsStore: SettingsStore
    @Bindable var gestureTargetCaptureController: GestureTargetCaptureController
    @Bindable var hotKeyRegistrationStatusStore: HotKeyRegistrationStatusStore
    let aboutPageModel: AboutPageModel
    let showGestureTriggerRegions: () -> Void
    let startGestureTargetCapture: () -> Void
    let cancelGestureTargetCapture: () -> Void
    @Binding var launchAtLoginController: LaunchAtLoginController

    var body: some View {
        Group {
            switch page {
            case .general:
                GeneralSettingsPage(
                    settingsStore: settingsStore,
                    launchAtLoginController: $launchAtLoginController
                )
            case .gestures:
                GestureSettingsPage(
                    settingsStore: settingsStore,
                    gestureTargetCaptureController: gestureTargetCaptureController,
                    startGestureTargetCapture: startGestureTargetCapture,
                    cancelGestureTargetCapture: cancelGestureTargetCapture,
                    showGestureTriggerRegions: showGestureTriggerRegions
                )
            case .dockGestures:
                DockGestureMappingsPage(
                    settingsStore: settingsStore,
                    showGestureTriggerRegions: showGestureTriggerRegions
                )
            case .titleBarGestures:
                TitleBarGestureMappingsPage(
                    settingsStore: settingsStore,
                    showGestureTriggerRegions: showGestureTriggerRegions
                )
            case .shortcuts:
                HotKeysSettingsPage(
                    settingsStore: settingsStore,
                    hotKeyRegistrationStatusStore: hotKeyRegistrationStatusStore
                )
            case .advanced:
                AdvancedSettingsPage(settingsStore: settingsStore)
            case .about:
                AboutSettingsPage(
                    settingsStore: settingsStore,
                    model: aboutPageModel
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsPageContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct GeneralSettingsPage: View {
    @Bindable var settingsStore: SettingsStore
    @Binding var launchAtLoginController: LaunchAtLoginController

    private var preferredLanguages: [String] {
        settingsStore.preferredLanguages
    }

    private var languageOptions: [SettingsPickerOption<AppLanguage>] {
        AppLanguage.allCases.map { language in
            SettingsPickerOption(
                value: language,
                title: language.title(preferredLanguages: preferredLanguages)
            )
        }
    }

    private var statusItemIconOptions: [SettingsPickerOption<StatusItemIcon>] {
        StatusItemIcon.allCases.map { icon in
            let title = icon.title(preferredLanguages: preferredLanguages)
            return SettingsPickerOption(
                value: icon,
                title: title,
                systemImage: icon.symbolName,
                image: icon.symbolName == nil
                    ? icon.makeImage(accessibilityDescription: title)
                    : nil
            )
        }
    }

    var body: some View {
        SettingsPageContainer {
            GeneralSettingsSection(
                settingsStore: settingsStore,
                launchAtLoginController: $launchAtLoginController,
                languageOptions: languageOptions,
                statusItemIconOptions: statusItemIconOptions
            )

            GeneralGestureBehaviorSection(settingsStore: settingsStore)
        }
    }

}

private struct GestureSettingsPage: View {
    @Bindable var settingsStore: SettingsStore
    @Bindable var gestureTargetCaptureController: GestureTargetCaptureController
    let startGestureTargetCapture: () -> Void
    let cancelGestureTargetCapture: () -> Void
    let showGestureTriggerRegions: () -> Void

    private var preferredLanguages: [String] {
        settingsStore.preferredLanguages
    }

    private var gestureHUDStyleOptions: [SettingsPickerOption<GestureHUDStyle>] {
        GestureHUDStyle.allCases.map { style in
            SettingsPickerOption(value: style, title: style.title(preferredLanguages: preferredLanguages))
        }
    }

    private var gesturePreviewItems: [GestureHUDPreviewItem] {
        [DockGestureKind.pinchIn, .swipeUp].map { gesture in
            GestureHUDPreviewItem(
                style: settingsStore.gestureHUDStyle,
                gesture: gesture,
                gestureTitle: gesture.title(preferredLanguages: preferredLanguages),
                actionTitle: settingsStore.dockGestureAction(for: gesture).title(preferredLanguages: preferredLanguages)
            )
        }
    }

    var body: some View {
        SettingsPageContainer {
            GestureTriggerRegionsSection(
                settingsStore: settingsStore,
                showGestureTriggerRegions: showGestureTriggerRegions
            )

            GestureSettingsSection(
                settingsStore: settingsStore,
                gestureHUDStyleOptions: gestureHUDStyleOptions,
                previewItems: gesturePreviewItems
            )

            GestureExclusionsSection(
                settingsStore: settingsStore,
                gestureTargetCaptureController: gestureTargetCaptureController,
                startGestureTargetCapture: startGestureTargetCapture,
                cancelGestureTargetCapture: cancelGestureTargetCapture
            )
        }
    }
}

private struct DockGestureMappingsPage: View {
    @Bindable var settingsStore: SettingsStore
    let showGestureTriggerRegions: () -> Void

    private var preferredLanguages: [String] {
        settingsStore.preferredLanguages
    }

    private var rows: [GestureActionRowModel<DockGestureKind, DockGestureAction>] {
        let availableActions = settingsStore.availableDockGestureActions.map { action in
            SettingsPickerOption(
                value: action,
                title: action.title(preferredLanguages: preferredLanguages),
                isDisabled: action == .closeTab && !settingsStore.experimentalBrowserTabCloseEnabled
            )
        }

        return DockGestureKind.allCases.map { gesture in
            GestureActionRowModel(
                gesture: gesture,
                title: gesture.title(preferredLanguages: preferredLanguages),
                isEnabled: settingsStore.dockGestureIsEnabled(for: gesture),
                selectedAction: settingsStore.dockGestureAction(for: gesture),
                availableActions: availableActions
            )
        }
    }

    var body: some View {
        SettingsPageContainer {
            GestureTriggerRegionsSection(
                settingsStore: settingsStore,
                showGestureTriggerRegions: showGestureTriggerRegions
            )

            DockGestureMappingsSection(
                settingsStore: settingsStore,
                rows: rows
            )
        }
    }
}

private struct TitleBarGestureMappingsPage: View {
    @Bindable var settingsStore: SettingsStore
    let showGestureTriggerRegions: () -> Void

    private var preferredLanguages: [String] {
        settingsStore.preferredLanguages
    }

    private var rows: [GestureActionRowModel<DockGestureKind, WindowAction>] {
        let availableActions = settingsStore.availableWindowGestureActions.map { action in
            SettingsPickerOption(
                value: action,
                title: action.title(preferredLanguages: preferredLanguages),
                isDisabled: action == .closeTab && !settingsStore.experimentalBrowserTabCloseEnabled
            )
        }

        return TitleBarGestureBindings.supportedGestures.map { gesture in
            GestureActionRowModel(
                gesture: gesture,
                title: gesture.title(preferredLanguages: preferredLanguages),
                isEnabled: settingsStore.titleBarGestureIsEnabled(for: gesture),
                selectedAction: settingsStore.titleBarGestureAction(for: gesture)
                    ?? TitleBarGestureBindings.fallbackBinding(for: gesture).action,
                availableActions: availableActions
            )
        }
    }

    var body: some View {
        SettingsPageContainer {
            GestureTriggerRegionsSection(
                settingsStore: settingsStore,
                showGestureTriggerRegions: showGestureTriggerRegions
            )

            TitleBarGestureMappingsSection(
                settingsStore: settingsStore,
                rows: rows
            )
        }
    }
}

private struct HotKeysSettingsPage: View {
    @Bindable var settingsStore: SettingsStore
    @Bindable var hotKeyRegistrationStatusStore: HotKeyRegistrationStatusStore

    private var rows: [HotKeyRowModel] {
        HotKeySettingsRowFactory.rows(
            settingsStore: settingsStore,
            registrationStatusStore: hotKeyRegistrationStatusStore
        )
    }

    var body: some View {
        SettingsPageContainer {
            HotKeysSection(
                settingsStore: settingsStore,
                registrationStatusStore: hotKeyRegistrationStatusStore,
                rows: rows
            )
        }
    }
}

private struct SettingsPickerOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var systemImage: String? = nil
    var image: NSImage? = nil
    var isDisabled = false

    var id: Value { value }
}

struct GestureHUDPreviewItem: Identifiable, Equatable {
    let style: GestureHUDStyle
    let gesture: DockGestureKind
    let gestureTitle: String
    let actionTitle: String

    var id: DockGestureKind { gesture }
}

private struct GestureActionRowModel<Gesture: Hashable & Identifiable, Action: Hashable>: Identifiable {
    let gesture: Gesture
    let title: String
    let isEnabled: Bool
    let selectedAction: Action
    let availableActions: [SettingsPickerOption<Action>]

    var id: Gesture { gesture }
}

struct HotKeyRowModel: Identifiable {
    let action: WindowAction
    let title: String
    let binding: HotKeyBinding
    let registrationFailure: HotKeyRegistrationFailure?

    var id: WindowAction { action }
}

enum HotKeySettingsRowFactory {
    @MainActor
    static func rows(
        settingsStore: SettingsStore,
        registrationStatusStore: HotKeyRegistrationStatusStore
    ) -> [HotKeyRowModel] {
        let preferredLanguages = settingsStore.preferredLanguages
        return settingsStore.availableWindowActions.map { action in
            HotKeyRowModel(
                action: action,
                title: action.title(preferredLanguages: preferredLanguages),
                binding: settingsStore.hotKeyBinding(for: action),
                registrationFailure: registrationStatusStore.failure(for: action)
            )
        }
    }
}

private struct GeneralSettingsSection: View {
    @Bindable var settingsStore: SettingsStore
    @Binding var launchAtLoginController: LaunchAtLoginController
    let languageOptions: [SettingsPickerOption<AppLanguage>]
    let statusItemIconOptions: [SettingsPickerOption<StatusItemIcon>]

    var body: some View {
        SettingsCardSection(title: settingsStore.localized("settings.section.general")) {
            Picker(
                settingsStore.localized("settings.language.label"),
                selection: $settingsStore.languageOverride
            ) {
                ForEach(languageOptions) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.menu)

            Toggle(
                settingsStore.localized("settings.hotkeys.enabled"),
                isOn: $settingsStore.hotKeysEnabled
            )

            Toggle(
                settingsStore.localized("settings.launch_at_login.enabled"),
                isOn: Binding(
                    get: { launchAtLoginController.isEnabled },
                    set: { launchAtLoginController.setEnabled($0, localize: settingsStore.localized) }
                )
            )

            SettingsHintGroup {
                Text(settingsStore.localized("settings.launch_at_login.footer"))

                if let statusMessage = launchAtLoginController.statusMessage,
                   !statusMessage.isEmpty {
                    Text(statusMessage)
                }
            }

            Picker(
                settingsStore.localized("settings.status_item_icon.label"),
                selection: $settingsStore.statusItemIcon
            ) {
                ForEach(statusItemIconOptions) { option in
                    SettingsPickerOptionLabel(option: option)
                        .tag(option.value)
                }
            }
            .pickerStyle(.menu)

            Toggle(
                settingsStore.localized("settings.status_item_window_actions_collapsed.enabled"),
                isOn: $settingsStore.collapseStatusItemWindowActions
            )

            SettingsHintGroup {
                Text(settingsStore.localized("settings.status_item_window_actions_collapsed.footer"))
            }
        }
    }
}

private struct GeneralGestureBehaviorSection: View {
    @Bindable var settingsStore: SettingsStore

    var body: some View {
        SettingsCardSection(title: settingsStore.localized("settings.advanced.section.other")) {
            Toggle(
                settingsStore.localized("settings.advanced.title_bar_overlay_protection.enabled"),
                isOn: $settingsStore.titleBarOverlayProtectionEnabled
            )
            .disabled(!settingsStore.titleBarGesturesEnabled)

            SettingsHintGroup {
                Text(settingsStore.localized("settings.advanced.title_bar_overlay_protection.footer"))
            }

            Toggle(
                settingsStore.localized("settings.advanced.smart_pinch_exit_full_screen.enabled"),
                isOn: $settingsStore.smartPinchExitFullScreenEnabled
            )
            .disabled(!settingsStore.titleBarGesturesEnabled)

            SettingsHintGroup {
                Text(settingsStore.localized("settings.advanced.smart_pinch_exit_full_screen.footer"))
            }

            Toggle(
                settingsStore.localized("settings.danger_gesture_confirmation.title"),
                isOn: $settingsStore.dangerGestureConfirmationEnabled
            )

            SettingsHintGroup {
                Text(
                    settingsStore.dangerGestureConfirmationEnabled
                        ? settingsStore.localized("settings.danger_gesture_confirmation.inline_footer")
                        : settingsStore.localized("settings.danger_gesture_confirmation.footer")
                )
            }
        }
    }
}

private struct GestureSettingsSection: View {
    @Bindable var settingsStore: SettingsStore
    let gestureHUDStyleOptions: [SettingsPickerOption<GestureHUDStyle>]
    let previewItems: [GestureHUDPreviewItem]

    var body: some View {
        SettingsCardSection(
            title: settingsStore.localized("settings.section.gestures")
        ) {
            Toggle(
                settingsStore.localized("settings.dock_gestures.enabled"),
                isOn: $settingsStore.dockGesturesEnabled
            )
            Toggle(
                settingsStore.localized("settings.title_bar_gestures.enabled"),
                isOn: $settingsStore.titleBarGesturesEnabled
            )

            // Deprecated: this selector still exposes the legacy preview-mode
            // flow because gesture execution and cancellation still branch on
            // SettingsStore.executeGestureOnRelease.
            VStack(alignment: .leading, spacing: 12) {
                Text(settingsStore.localized("guide.page.interaction.title"))
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 12) {
                    CompactInteractionStyleCard(
                        title: settingsStore.localized("guide.page.interaction.immediate.title"),
                        description: settingsStore.localized("guide.page.interaction.immediate.description"),
                        systemImage: "bolt.fill",
                        isSelected: !settingsStore.executeGestureOnRelease,
                        action: { settingsStore.executeGestureOnRelease = false }
                    )

                    CompactInteractionStyleCard(
                        title: settingsStore.localized("guide.page.interaction.on_release.title"),
                        description: settingsStore.localized("guide.page.interaction.on_release.description"),
                        systemImage: "hand.raised.fill",
                        isSelected: settingsStore.executeGestureOnRelease,
                        action: { settingsStore.executeGestureOnRelease = true }
                    )
                }
            }
            .padding(.vertical, 4)

            Picker(
                settingsStore.localized("settings.gesture_hud.style.label"),
                selection: $settingsStore.gestureHUDStyle
            ) {
                ForEach(gestureHUDStyleOptions) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.menu)

            SettingsHintGroup {
                Text(settingsStore.localized("settings.gesture_hud.footer"))
                Text(settingsStore.localized("settings.gesture_execute_on_release.footer"))
            }

            GestureHUDPreviewStrip(items: previewItems)
        } footer: {
            Text(settingsStore.localized("settings.gestures.footer"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct GestureTriggerRegionsSection: View {
    @Bindable var settingsStore: SettingsStore
    let showGestureTriggerRegions: () -> Void

    private var isEnabled: Bool {
        settingsStore.dockGesturesEnabled || settingsStore.titleBarGesturesEnabled
    }

    var body: some View {
        SettingsCardSection(title: settingsStore.localized("settings.trigger_regions.title")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(settingsStore.localized("settings.trigger_regions.description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showGestureTriggerRegions()
                } label: {
                    Label(
                        settingsStore.localized("settings.trigger_regions.show"),
                        systemImage: "rectangle.dashed.badge.record"
                    )
                }
                .disabled(!isEnabled)
            }
        }
    }
}

private struct GestureExclusionsSection: View {
    @Bindable var settingsStore: SettingsStore
    @Bindable var gestureTargetCaptureController: GestureTargetCaptureController
    let startGestureTargetCapture: () -> Void
    let cancelGestureTargetCapture: () -> Void
    @State private var isShowingRunningApplicationPicker = false
    @State private var editedRule: GestureExclusionRuleDraft?

    var body: some View {
        SettingsCardSection(title: settingsStore.localized("settings.gesture_exclusions.title")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(settingsStore.localized("settings.gesture_exclusions.description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        isShowingRunningApplicationPicker = true
                    } label: {
                        Label(
                            settingsStore.localized("settings.gesture_exclusions.add_running"),
                            systemImage: "app.badge"
                        )
                    }

                    Button {
                        chooseApplicationBundle()
                    } label: {
                        Label(
                            settingsStore.localized("settings.gesture_exclusions.choose_app"),
                            systemImage: "folder"
                        )
                    }

                    if gestureTargetCaptureController.isCapturing {
                        Button(role: .cancel) {
                            cancelGestureTargetCapture()
                        } label: {
                            Label(
                                settingsStore.localized("settings.gesture_exclusions.capture.cancel"),
                                systemImage: "xmark.circle"
                            )
                        }
                    } else {
                        Button {
                            startGestureTargetCapture()
                        } label: {
                            Label(
                                settingsStore.localized("settings.gesture_exclusions.capture.start"),
                                systemImage: "hand.pinch"
                            )
                        }
                    }
                }

                captureStatusView

                Divider()

                if settingsStore.gestureExclusionRules.isEmpty {
                    Text(settingsStore.localized("settings.gesture_exclusions.empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(settingsStore.gestureExclusionRules.enumerated()), id: \.element.id) { index, rule in
                            GestureExclusionRuleRow(
                                rule: rule,
                                summary: summary(for: rule),
                                editLabel: settingsStore.localized("settings.gesture_exclusions.edit"),
                                removeLabel: settingsStore.localized("settings.gesture_exclusions.remove"),
                                onEdit: { edit(rule.application) },
                                onRemove: { settingsStore.removeGestureExclusionRule(id: rule.id) }
                            )

                            if index < settingsStore.gestureExclusionRules.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingRunningApplicationPicker) {
            RunningApplicationPickerSheet(
                settingsStore: settingsStore,
                onSelect: { application in
                    isShowingRunningApplicationPicker = false
                    edit(application)
                },
                onCancel: {
                    isShowingRunningApplicationPicker = false
                }
            )
        }
        .sheet(item: $editedRule) { draft in
            GestureExclusionRuleEditorSheet(
                settingsStore: settingsStore,
                draft: draft,
                onSave: { rule in
                    settingsStore.updateGestureExclusionRule(rule)
                    editedRule = nil
                },
                onCancel: {
                    editedRule = nil
                }
            )
        }
        .onChange(of: gestureTargetCaptureController.capturedApplication) { _, capturedApplication in
            guard let capturedApplication else { return }
            edit(capturedApplication)
            gestureTargetCaptureController.clearResult()
        }
    }

    @ViewBuilder
    private var captureStatusView: some View {
        if gestureTargetCaptureController.isCapturing {
            SettingsHintGroup {
                Text(settingsStore.localized("settings.gesture_exclusions.capture.waiting"))
            }
        } else if gestureTargetCaptureController.didTimeout {
            SettingsHintGroup {
                Text(settingsStore.localized("settings.gesture_exclusions.capture.timeout"))
            }
        } else if gestureTargetCaptureController.didMiss {
            SettingsHintGroup {
                Text(settingsStore.localized("settings.gesture_exclusions.capture.miss"))
            }
        }
    }

    private func edit(_ application: GestureExcludedApplication) {
        let existingRule = settingsStore.gestureExclusionRules.first {
            $0.application.matches(application)
        }
        editedRule = GestureExclusionRuleDraft(
            application: application,
            mode: existingRule?.mode ?? .all
        )
    }

    private func summary(for rule: GestureExclusionRule) -> String {
        switch rule.mode {
        case .all:
            settingsStore.localized("settings.gesture_exclusions.summary.all")
        case .selected(let selections):
            if selections.isEmpty {
                settingsStore.localized("settings.gesture_exclusions.summary.none")
            } else {
                String(
                    format: settingsStore.localized("settings.gesture_exclusions.summary.selected_format"),
                    selections.count
                )
            }
        }
    }

    private func chooseApplicationBundle() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        edit(GestureExcludedApplication(bundleURL: url, bundleIdentifier: Bundle(url: url)?.bundleIdentifier, displayName: applicationDisplayName(for: url)))
    }
}

private struct GestureExclusionRuleDraft: Identifiable {
    let application: GestureExcludedApplication
    let mode: GestureExclusionMode

    var id: String { application.id }
}

private struct GestureExclusionRuleRow: View {
    let rule: GestureExclusionRule
    let summary: String
    let editLabel: String
    let removeLabel: String
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ApplicationIcon(application: rule.application, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.application.displayName)
                    .font(.subheadline.weight(.medium))

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help(editLabel)
            .accessibilityLabel(editLabel)

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(removeLabel)
            .accessibilityLabel(removeLabel)
        }
        .padding(.vertical, 10)
    }
}

private struct RunningApplicationPickerSheet: View {
    let settingsStore: SettingsStore
    let onSelect: (GestureExcludedApplication) -> Void
    let onCancel: () -> Void
    @State private var searchText = ""
    @State private var applications: [GestureExcludedApplication] = []

    private var filteredApplications: [GestureExcludedApplication] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return applications
        }

        return applications.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
                ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(settingsStore.localized("settings.gesture_exclusions.running_picker.title"))
                .font(.headline)

            TextField(
                settingsStore.localized("settings.gesture_exclusions.running_picker.search"),
                text: $searchText
            )
            .textFieldStyle(.roundedBorder)

            if filteredApplications.isEmpty {
                Text(settingsStore.localized("settings.gesture_exclusions.running_picker.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            } else {
                List(filteredApplications) { application in
                    Button {
                        onSelect(application)
                    } label: {
                        HStack(spacing: 10) {
                            ApplicationIcon(application: application, size: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(application.displayName)
                                    .font(.subheadline.weight(.medium))
                                if let bundleIdentifier = application.bundleIdentifier {
                                    Text(bundleIdentifier)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 260)
            }

            HStack {
                Spacer()
                Button(settingsStore.localized("settings.gesture_exclusions.editor.cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 390)
        .onAppear {
            applications = Self.runningApplications()
        }
    }

    private static func runningApplications() -> [GestureExcludedApplication] {
        var seenIDs = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { application -> GestureExcludedApplication? in
            guard
                !application.isTerminated,
                application.activationPolicy != .prohibited,
                !RunningApplicationIdentity.isLikelyHelperProcess(application),
                let appIdentity = AppIdentity(application: application)
            else {
                return nil
            }

            let excludedApplication = GestureExcludedApplication(appIdentity)
            guard seenIDs.insert(excludedApplication.id).inserted else {
                return nil
            }
            return excludedApplication
        }
        .sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}

private struct GestureExclusionRuleEditorSheet: View {
    let settingsStore: SettingsStore
    let draft: GestureExclusionRuleDraft
    let onSave: (GestureExclusionRule) -> Void
    let onCancel: () -> Void
    @State private var editorMode: GestureExclusionEditorMode
    @State private var disabledSelections: Set<GestureExclusionSelection>

    init(
        settingsStore: SettingsStore,
        draft: GestureExclusionRuleDraft,
        onSave: @escaping (GestureExclusionRule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.draft = draft
        self.onSave = onSave
        self.onCancel = onCancel

        switch draft.mode {
        case .all:
            _editorMode = State(initialValue: .all)
            _disabledSelections = State(initialValue: [])
        case .selected(let selections):
            _editorMode = State(initialValue: .selected)
            _disabledSelections = State(initialValue: selections)
        }
    }

    private var saveDisabled: Bool {
        editorMode == .selected && disabledSelections.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ApplicationIcon(application: draft.application, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.application.displayName)
                        .font(.headline)

                    Text(settingsStore.localized("settings.gesture_exclusions.editor.title"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("", selection: $editorMode) {
                Text(settingsStore.localized("settings.gesture_exclusions.mode.all"))
                    .tag(GestureExclusionEditorMode.all)
                Text(settingsStore.localized("settings.gesture_exclusions.mode.selected"))
                    .tag(GestureExclusionEditorMode.selected)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if editorMode == .selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        gestureSelectionGroup(
                            title: settingsStore.localized("settings.gesture_exclusions.surface.dock"),
                            surface: .dock,
                            gestures: DockGestureKind.allCases
                        )

                        gestureSelectionGroup(
                            title: settingsStore.localized("settings.gesture_exclusions.surface.title_bar"),
                            surface: .titleBar,
                            gestures: TitleBarGestureBindings.supportedGestures
                        )

                        if disabledSelections.isEmpty {
                            Text(settingsStore.localized("settings.gesture_exclusions.editor.empty_selection"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 260)
            } else {
                Text(settingsStore.localized("settings.gesture_exclusions.editor.all_footer"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(settingsStore.localized("settings.gesture_exclusions.editor.cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(settingsStore.localized("settings.gesture_exclusions.editor.save")) {
                    onSave(
                        GestureExclusionRule(
                            application: draft.application,
                            mode: editorMode == .all ? .all : .selected(disabledSelections)
                        )
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(saveDisabled)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func gestureSelectionGroup(
        title: String,
        surface: GestureExclusionSurface,
        gestures: [DockGestureKind]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(gestures) { gesture in
                    Toggle(
                        gesture.title(preferredLanguages: settingsStore.preferredLanguages),
                        isOn: selectionBinding(.standard(gesture, on: surface))
                    )
                }

                Toggle(
                    settingsStore.localized("settings.gesture_exclusions.corner_drag"),
                    isOn: selectionBinding(.cornerDrag(on: surface))
                )
            }
        }
    }

    private func selectionBinding(_ selection: GestureExclusionSelection) -> Binding<Bool> {
        Binding(
            get: { disabledSelections.contains(selection) },
            set: { isSelected in
                if isSelected {
                    disabledSelections.insert(selection)
                } else {
                    disabledSelections.remove(selection)
                }
            }
        )
    }
}

private enum GestureExclusionEditorMode: String, CaseIterable, Identifiable {
    case all
    case selected

    var id: String { rawValue }
}

private struct ApplicationIcon: View {
    let application: GestureExcludedApplication
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: application.bundleURL.path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private func applicationDisplayName(for bundleURL: URL) -> String {
    let bundle = Bundle(url: bundleURL)
    if let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
       !displayName.isEmpty {
        return displayName
    }
    if let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
       !bundleName.isEmpty {
        return bundleName
    }

    return bundleURL.deletingPathExtension().lastPathComponent
}

private struct SettingsHintGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

private struct SettingsCardSection<Content: View, Footer: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.title = title
        self.content = content()
        self.footer = EmptyView()
    }

    init(
        title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: title)

            SettingsCard {
                content
            }

            footer
        }
    }
}

private struct AdvancedSettingsPage: View {
    @Bindable var settingsStore: SettingsStore

    var body: some View {
        SettingsPageContainer {
            SettingsCardSection(title: settingsStore.localized("settings.advanced.section.sensitivity")) {
                SensitivitySlider(
                    label: settingsStore.localized("settings.advanced.swipe_sensitivity.label"),
                    value: $settingsStore.swipeSensitivity,
                    lowLabel: settingsStore.localized("settings.advanced.sensitivity.low"),
                    highLabel: settingsStore.localized("settings.advanced.sensitivity.high")
                )

                SensitivitySlider(
                    label: settingsStore.localized("settings.advanced.pinch_sensitivity.label"),
                    value: $settingsStore.pinchSensitivity,
                    lowLabel: settingsStore.localized("settings.advanced.sensitivity.low"),
                    highLabel: settingsStore.localized("settings.advanced.sensitivity.high")
                )

                PixelSlider(
                    label: settingsStore.localized("settings.advanced.title_bar_trigger_height.label"),
                    value: $settingsStore.titleBarTriggerHeight,
                    range: SettingsStore.minimumTitleBarTriggerHeight ... SettingsStore.maximumTitleBarTriggerHeight,
                    step: 1
                )
                .disabled(!settingsStore.titleBarGesturesEnabled)

                DurationSlider(
                    label: settingsStore.localized("settings.advanced.corner_drag_hold_duration.label"),
                    value: $settingsStore.titleBarCornerDragHoldDuration,
                    range: SettingsStore.minimumTitleBarCornerDragHoldDuration ... SettingsStore.maximumTitleBarCornerDragHoldDuration,
                    step: 0.1
                )
                .disabled(
                    (!settingsStore.dockGesturesEnabled || !settingsStore.dockCornerDragSnapEnabled) &&
                        (!settingsStore.titleBarGesturesEnabled || !settingsStore.titleBarCornerDragSnapEnabled)
                )
            }

            // Deprecated: reverse-cancel controls only affect the same legacy
            // preview-mode flow retained above.
            SettingsCardSection(title: settingsStore.localized("settings.advanced.section.cancel")) {
                Toggle(
                    settingsStore.localized("settings.advanced.reverse_cancel.enabled"),
                    isOn: $settingsStore.reverseCancelEnabled
                )

                SensitivitySlider(
                    label: settingsStore.localized("settings.advanced.reverse_cancel_sensitivity.label"),
                    value: $settingsStore.reverseCancelSensitivity,
                    lowLabel: settingsStore.localized("settings.advanced.sensitivity.low"),
                    highLabel: settingsStore.localized("settings.advanced.sensitivity.high")
                )
                .disabled(!settingsStore.reverseCancelEnabled)

                SettingsHintGroup {
                    Text(settingsStore.localized("settings.advanced.reverse_cancel.footer"))
                }
            }

            SettingsCardSection(title: settingsStore.localized("settings.advanced.section.logging")) {
                Toggle(
                    settingsStore.localized("settings.debug_logging.enabled"),
                    isOn: $settingsStore.debugLoggingEnabled
                )

                if settingsStore.debugLoggingEnabled {
                    SettingsHintGroup {
                        Text(
                            String(
                                format: settingsStore.localized("settings.advanced.debug_logging.footer"),
                                DebugLog.logFilePathDescription
                            )
                        )
                    }
                }
            }

            SettingsCardSection(title: settingsStore.localized("settings.experimental.section")) {
                Toggle(
                    settingsStore.localized("settings.experimental.display_move_actions.enabled"),
                    isOn: $settingsStore.experimentalDisplayMoveActionsEnabled
                )

                SettingsHintGroup {
                    Text(settingsStore.localized("settings.experimental.display_move_actions.footer"))
                }

                Toggle(
                    settingsStore.localized("settings.experimental.browser_tab_close.enabled"),
                    isOn: $settingsStore.experimentalBrowserTabCloseEnabled
                )

                SettingsHintGroup {
                    Text(settingsStore.localized("settings.experimental.browser_tab_close.footer"))
                }

                Toggle(
                    settingsStore.localized("settings.experimental.smart_browser_tab_close.enabled"),
                    isOn: $settingsStore.smartBrowserTabCloseEnabled
                )
                .disabled(!settingsStore.experimentalBrowserTabCloseEnabled)

                SettingsHintGroup {
                    Text(settingsStore.localized("settings.experimental.smart_browser_tab_close.footer"))
                }

                Toggle(
                    settingsStore.localized("settings.experimental.pinch_close_confirmation.enabled"),
                    isOn: $settingsStore.pinchCloseConfirmationEnabled
                )
                .disabled(!settingsStore.experimentalBrowserTabCloseEnabled)

                SettingsHintGroup {
                    Text(settingsStore.localized("settings.experimental.pinch_close_confirmation.footer"))
                    Text(settingsStore.localized("settings.experimental.opt_in_persistence.footer"))
                }
            }

            SettingsCardSection(title: settingsStore.localized("settings.section.advanced")) {
                Button(settingsStore.localized("settings.advanced.reset_defaults")) {
                    settingsStore.resetAdvancedSettingsToDefaults()
                }
            }
        }
    }
}

private struct AboutSettingsPage: View {
    @Bindable var settingsStore: SettingsStore
    let model: AboutPageModel
    @State private var updateState = AboutUpdateState.manualCheck

    var body: some View {
        SettingsPageContainer {
            SettingsCardSection(title: settingsStore.localized("settings.section.about")) {
                HStack(alignment: .center, spacing: 14) {
                    Image(nsImage: StatusItemIcon.gale.makeImage(accessibilityDescription: model.appName) ?? NSImage())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.appName)
                            .font(.title3.weight(.semibold))

                        Text(
                            String(
                                format: settingsStore.localized("settings.about.version_format"),
                                model.versionText
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                AboutLinkButton(
                    title: settingsStore.localized("settings.about.github.title"),
                    subtitle: settingsStore.localized("settings.about.github.subtitle"),
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    url: model.repositoryURL
                )

                AboutLinkButton(
                    title: settingsStore.localized("settings.about.license.title"),
                    subtitle: settingsStore.localized("settings.about.license.subtitle"),
                    systemImage: "doc.text",
                    url: model.licenseURL
                )

                AboutLinkButton(
                    title: settingsStore.localized("settings.about.attribution.title"),
                    subtitle: settingsStore.localized("settings.about.attribution.subtitle"),
                    systemImage: "list.bullet.rectangle",
                    url: model.attributionURL
                )
            }

            SettingsCardSection(title: settingsStore.localized("settings.about.update.section")) {
                AboutUpdateStatusView(
                    model: model,
                    updateState: updateState,
                    localize: settingsStore.localized
                ) {
                    checkForUpdates()
                }
            }
        }
        .onAppear {
            if model.updateState == .updateAvailable {
                updateState = .updateAvailable
            }
        }
    }

    private func checkForUpdates() {
        updateState = .checking
        Task {
            let nextState = await AboutUpdateChecker.checkLatestRelease(
                currentVersion: model.currentVersion
            )
            await MainActor.run {
                updateState = nextState
            }
        }
    }
}

private struct AboutUpdateStatusView: View {
    let model: AboutPageModel
    let updateState: AboutUpdateState
    let localize: (String) -> String
    let checkForUpdates: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    if opensLatestRelease {
                        NSWorkspace.shared.open(model.latestReleaseURL)
                    } else {
                        checkForUpdates()
                    }
                } label: {
                    Label(buttonTitle, systemImage: buttonSystemImage)
                }
                .padding(.top, 4)
                .disabled(updateState == .checking)

                if opensLatestRelease == false {
                    Button {
                        NSWorkspace.shared.open(model.latestReleaseURL)
                    } label: {
                        Label(localize("settings.about.open_releases.button"), systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.link)
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        switch updateState {
        case .manualCheck:
            localize("settings.about.update.manual.title")
        case .checking:
            localize("settings.about.update.checking.title")
        case .upToDate:
            localize("settings.about.update.up_to_date.title")
        case .updateAvailable:
            localize("settings.about.update.available.title")
        case .sourceBuild:
            localize("settings.about.update.source_build.title")
        case .checkFailed:
            localize("settings.about.update.failed.title")
        }
    }

    private var message: String {
        switch updateState {
        case .manualCheck:
            localize("settings.about.update.manual.message")
        case .checking:
            localize("settings.about.update.checking.message")
        case .upToDate:
            localize("settings.about.update.up_to_date.message")
        case .updateAvailable:
            localize("settings.about.update.available.message")
        case .sourceBuild:
            localize("settings.about.update.source_build.message")
        case .checkFailed:
            localize("settings.about.update.failed.message")
        }
    }

    private var systemImage: String {
        switch updateState {
        case .manualCheck:
            "arrow.triangle.2.circlepath"
        case .checking:
            "clock.arrow.circlepath"
        case .upToDate:
            "checkmark.circle.fill"
        case .updateAvailable:
            "sparkles"
        case .sourceBuild:
            "hammer.fill"
        case .checkFailed:
            "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch updateState {
        case .manualCheck:
            Color(nsColor: .controlAccentColor)
        case .checking:
            Color(nsColor: .controlAccentColor)
        case .upToDate:
            Color(nsColor: .systemGreen)
        case .updateAvailable:
            Color(nsColor: .systemGreen)
        case .sourceBuild:
            Color(nsColor: .systemOrange)
        case .checkFailed:
            Color(nsColor: .systemOrange)
        }
    }

    private var buttonTitle: String {
        switch updateState {
        case .updateAvailable:
            localize("settings.about.download_update.button")
        case .checking:
            localize("settings.about.checking_updates.button")
        case .sourceBuild:
            localize("settings.about.open_releases.button")
        case .manualCheck, .upToDate, .checkFailed:
            localize("settings.about.check_updates.button")
        }
    }

    private var buttonSystemImage: String {
        switch updateState {
        case .updateAvailable:
            "square.and.arrow.down"
        case .sourceBuild:
            "arrow.up.right"
        case .manualCheck, .checking, .upToDate, .checkFailed:
            "arrow.triangle.2.circlepath"
        }
    }

    private var opensLatestRelease: Bool {
        switch updateState {
        case .updateAvailable, .sourceBuild:
            true
        case .manualCheck, .checking, .upToDate, .checkFailed:
            false
        }
    }
}

private struct AboutLinkButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(url.absoluteString)
    }
}

private struct SensitivitySlider: View {
    let label: String
    @Binding var value: Double
    let lowLabel: String
    let highLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.body)

            HStack(spacing: 8) {
                Text(lowLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)

                Slider(value: $value, in: 0...1, step: 0.05)

                Text(highLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PixelSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.body)

                Spacer()

                Text("\(Int(value.rounded())) px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: $value, in: range, step: step)
        }
        .padding(.vertical, 4)
    }
}

private struct DurationSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.body)

                Spacer()

                Text(String(format: "%.1f s", value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: $value, in: range, step: step)
        }
        .padding(.vertical, 4)
    }
}


private struct SettingsMappingCard<Rows: View>: View {
    @ViewBuilder let rows: Rows

    var body: some View {
        LazyVStack(spacing: 0) {
            rows
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.08), lineWidth: 1)
        )
    }
}

private struct DockGestureMappingsSection: View {
    @Bindable var settingsStore: SettingsStore
    let rows: [GestureActionRowModel<DockGestureKind, DockGestureAction>]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSectionHeader(title: settingsStore.localized("settings.section.dock_gestures"))

            Toggle(
                settingsStore.localized("settings.dock_gestures.corner_drag.enabled"),
                isOn: $settingsStore.dockCornerDragSnapEnabled
            )
            .disabled(!settingsStore.dockGesturesEnabled)

            SettingsMappingCard {
                GestureMappingColumnHeader(
                    actionTitle: settingsStore.localized("settings.gesture_mappings.column.action"),
                    confirmationTitle: settingsStore.dangerGestureConfirmationEnabled
                        ? settingsStore.localized("settings.gesture_mappings.column.confirmation")
                        : nil
                )

                Divider()

                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    GestureActionRow(
                        row: row,
                        isSectionEnabled: settingsStore.dockGesturesEnabled,
                        toggleBinding: Binding(
                            get: { settingsStore.dockGestureIsEnabled(for: row.gesture) },
                            set: { settingsStore.updateDockGestureEnabled($0, for: row.gesture) }
                        ),
                        actionBinding: Binding(
                            get: { settingsStore.dockGestureAction(for: row.gesture) },
                            set: { settingsStore.updateDockGestureAction($0, for: row.gesture) }
                        ),
                        confirmationBinding: settingsStore.dangerGestureConfirmationEnabled
                            ? Binding(
                                get: { settingsStore.requiresDangerGestureConfirmation(row.gesture, on: .dock) },
                                set: { settingsStore.updateDangerGestureConfirmation($0, for: row.gesture, on: .dock) }
                            )
                            : nil,
                        confirmationHelp: settingsStore.localized("settings.danger_gesture_confirmation.toggle.help")
                    )

                    if index < rows.count - 1 {
                        Divider()
                    }
                }
            }

            Button(settingsStore.localized("settings.dock_gestures.reset")) {
                settingsStore.resetDockGestureActionsToDefaults()
            }
            .disabled(!settingsStore.dockGesturesEnabled)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(settingsStore.localized("settings.dock_gestures.footer"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                DangerGestureConfirmationDisabledHint(settingsStore: settingsStore)
            }
        }
        .padding(.bottom, 10)
    }
}

private struct TitleBarGestureMappingsSection: View {
    @Bindable var settingsStore: SettingsStore
    let rows: [GestureActionRowModel<DockGestureKind, WindowAction>]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSectionHeader(title: settingsStore.localized("settings.section.title_bar_gestures"))

            Toggle(
                settingsStore.localized("settings.title_bar_gestures.corner_drag.enabled"),
                isOn: $settingsStore.titleBarCornerDragSnapEnabled
            )
            .disabled(!settingsStore.titleBarGesturesEnabled)

            SettingsMappingCard {
                GestureMappingColumnHeader(
                    actionTitle: settingsStore.localized("settings.gesture_mappings.column.action"),
                    confirmationTitle: settingsStore.dangerGestureConfirmationEnabled
                        ? settingsStore.localized("settings.gesture_mappings.column.confirmation")
                        : nil
                )

                Divider()

                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    GestureActionRow(
                        row: row,
                        isSectionEnabled: settingsStore.titleBarGesturesEnabled,
                        toggleBinding: Binding(
                            get: { settingsStore.titleBarGestureIsEnabled(for: row.gesture) },
                            set: { settingsStore.updateTitleBarGestureEnabled($0, for: row.gesture) }
                        ),
                        actionBinding: Binding(
                            get: {
                                settingsStore.titleBarGestureAction(for: row.gesture)
                                ?? TitleBarGestureBindings.fallbackBinding(for: row.gesture).action
                            },
                            set: { settingsStore.updateTitleBarGestureAction($0, for: row.gesture) }
                        ),
                        confirmationBinding: settingsStore.dangerGestureConfirmationEnabled
                            ? Binding(
                                get: { settingsStore.requiresDangerGestureConfirmation(row.gesture, on: .titleBar) },
                                set: { settingsStore.updateDangerGestureConfirmation($0, for: row.gesture, on: .titleBar) }
                            )
                            : nil,
                        confirmationHelp: settingsStore.localized("settings.danger_gesture_confirmation.toggle.help")
                    )

                    if index < rows.count - 1 {
                        Divider()
                    }
                }
            }

            Button(settingsStore.localized("settings.title_bar_gestures.reset")) {
                settingsStore.resetTitleBarGestureActionsToDefaults()
            }
            .disabled(!settingsStore.titleBarGesturesEnabled)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(settingsStore.localized("settings.title_bar_gestures.footer"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                DangerGestureConfirmationDisabledHint(settingsStore: settingsStore)
            }
        }
        .padding(.bottom, 10)
    }
}

struct GestureHUDPreviewStrip: View {
    let items: [GestureHUDPreviewItem]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                GestureHUDPreviewCard(item: item)
            }
        }
        .padding(.top, 4)
    }
}

private struct GestureHUDPreviewCard: View {
    let item: GestureHUDPreviewItem

    private var model: GestureHUDRenderModel {
        GestureHUDRenderModel(
            style: item.style,
            glyph: .gesture(item.gesture),
            gestureTitle: item.gestureTitle,
            actionTitle: item.actionTitle
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.gestureTitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            GestureHUDPreviewSnapshot(model: model)
                .frame(
                    width: GestureHUDRenderView.panelSize(for: item.style).width,
                    height: GestureHUDRenderView.panelSize(for: item.style).height,
                    alignment: .leading
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
private struct GestureHUDPreviewSnapshot: View {
    let model: GestureHUDRenderModel
    @State private var snapshot: NSImage?

    var body: some View {
        Group {
            if let snapshot {
                Image(nsImage: snapshot)
            } else {
                Color.clear
            }
        }
        .task(id: model) {
            snapshot = Self.cachedSnapshot(for: model)
        }
    }

    private static func cachedSnapshot(for model: GestureHUDRenderModel) -> NSImage? {
        if let snapshot = GestureHUDPreviewSnapshotCache.shared.snapshot(for: model) {
            return snapshot
        }

        let snapshot = makeSnapshot(for: model)
        if let snapshot {
            GestureHUDPreviewSnapshotCache.shared.store(snapshot, for: model)
        }
        return snapshot
    }

    private static func makeSnapshot(for model: GestureHUDRenderModel) -> NSImage? {
        let size = GestureHUDRenderView.panelSize(for: model.style)
        let renderView = GestureHUDRenderView(frame: NSRect(origin: .zero, size: size))
        renderView.render(model: model)
        renderView.layoutSubtreeIfNeeded()

        guard let bitmap = renderView.bitmapImageRepForCachingDisplay(in: renderView.bounds) else {
            return nil
        }

        renderView.cacheDisplay(in: renderView.bounds, to: bitmap)

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }
}

@MainActor
private final class GestureHUDPreviewSnapshotCache {
    static let shared = GestureHUDPreviewSnapshotCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {}

    func snapshot(for model: GestureHUDRenderModel) -> NSImage? {
        cache.object(forKey: cacheKey(for: model) as NSString)
    }

    func store(_ image: NSImage, for model: GestureHUDRenderModel) {
        cache.setObject(image, forKey: cacheKey(for: model) as NSString)
    }

    private func cacheKey(for model: GestureHUDRenderModel) -> String {
        "\(model.style.storageValue)|\(String(describing: model.glyph))|\(model.gestureTitle)|\(model.actionTitle)"
    }
}

private struct DangerGestureConfirmationToggle: View {
    @Bindable var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                settingsStore.localized("settings.danger_gesture_confirmation.title"),
                isOn: $settingsStore.dangerGestureConfirmationEnabled
            )

            Text(
                settingsStore.dangerGestureConfirmationEnabled
                    ? settingsStore.localized("settings.danger_gesture_confirmation.inline_footer")
                    : settingsStore.localized("settings.danger_gesture_confirmation.footer")
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Shown on the gesture mapping pages while the danger-confirmation master
/// switch is off, so users understand why the shield column is hidden and
/// where to turn the feature on (it lives in General now, not here).
private struct DangerGestureConfirmationDisabledHint: View {
    @Bindable var settingsStore: SettingsStore

    var body: some View {
        if !settingsStore.dangerGestureConfirmationEnabled {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "shield")
                    .foregroundStyle(.secondary)
                Text(settingsStore.localized("settings.danger_gesture_confirmation.mapping_hint"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private enum GestureMappingColumnLayout {
    static let actionWidth: CGFloat = 220
    static let confirmationWidth: CGFloat = 28
    static let columnSpacing: CGFloat = 12
}

private struct GestureMappingColumnHeader: View {
    let actionTitle: String
    var confirmationTitle: String? = nil

    var body: some View {
        HStack(spacing: GestureMappingColumnLayout.columnSpacing) {
            Spacer(minLength: 0)

            Text(actionTitle)
                .frame(width: GestureMappingColumnLayout.actionWidth, alignment: .leading)

            if let confirmationTitle {
                Text(confirmationTitle)
                    .frame(width: GestureMappingColumnLayout.confirmationWidth, alignment: .center)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.bottom, 2)
    }
}

private struct GestureActionRow<Action: Hashable>: View {
    let row: GestureActionRowModel<DockGestureKind, Action>
    let isSectionEnabled: Bool
    let toggleBinding: Binding<Bool>
    let actionBinding: Binding<Action>
    var confirmationBinding: Binding<Bool>? = nil
    var confirmationHelp: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Toggle(row.title, isOn: toggleBinding)
                .toggleStyle(.switch)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: actionBinding) {
                ForEach(row.availableActions) { option in
                    Text(option.title)
                        .tag(option.value)
                        .disabled(option.isDisabled)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: GestureMappingColumnLayout.actionWidth)
            .disabled(!isSectionEnabled || !row.isEnabled)

            if let confirmationBinding {
                DangerGestureConfirmationButton(
                    isOn: confirmationBinding,
                    help: confirmationHelp ?? ""
                )
                .frame(width: GestureMappingColumnLayout.confirmationWidth)
                .disabled(!isSectionEnabled || !row.isEnabled)
            }
        }
        .disabled(!isSectionEnabled)
        .padding(.vertical, 14)
    }
}

private struct DangerGestureConfirmationButton: View {
    @Binding var isOn: Bool
    let help: String

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: isOn ? "shield.fill" : "shield")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isOn ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct HotKeysSection: View {
    @Bindable var settingsStore: SettingsStore
    @Bindable var registrationStatusStore: HotKeyRegistrationStatusStore
    let rows: [HotKeyRowModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeaderWithBadge(
                title: settingsStore.localized("settings.section.shortcuts"),
                showsWarning: registrationStatusStore.hasIssue,
                warningTooltip: settingsStore.localized("settings.shortcuts.registration_issue.tooltip")
            )

            SettingsCard {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if registrationStatusStore.handlerUnavailable {
                        HotKeyRegistrationNotice(
                            title: settingsStore.localized(
                                "settings.shortcuts.handler_unavailable.title"
                            ),
                            message: settingsStore.localized(
                                "settings.shortcuts.handler_unavailable.message"
                            )
                        )

                        Divider()
                    }

                    ForEach(rows) { row in
                        HotKeyEditorRow(
                            row: row,
                            placeholder: settingsStore.localized("settings.shortcuts.recorder_placeholder"),
                            registrationFailureTooltip: settingsStore.localized(
                                "settings.shortcuts.registration_failed.tooltip"
                            ),
                            registrationFailureAccessibilityLabel: settingsStore.localized(
                                "settings.shortcuts.registration_failed.accessibility_label"
                            ),
                            onChange: { settingsStore.updateHotKeyBinding($0) }
                        )
                    }

                    Button(settingsStore.localized("settings.shortcuts.reset")) {
                        settingsStore.resetHotKeysToDefaults()
                    }
                }
            }
        }
    }
}

private struct SettingsSectionHeaderWithBadge: View {
    let title: String
    let showsWarning: Bool
    let warningTooltip: String

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.headline)

            if showsWarning {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .help(warningTooltip)
                    .accessibilityLabel(warningTooltip)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

private struct HotKeyRegistrationNotice: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemRed))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsPickerOptionLabel<Value: Hashable>: View {
    let option: SettingsPickerOption<Value>

    var body: some View {
        if let systemImage = option.systemImage {
            Label(option.title, systemImage: systemImage)
        } else if let image = option.image {
            Label {
                Text(option.title)
            } icon: {
                Image(nsImage: image)
                    .renderingMode(.template)
            }
        } else {
            Text(option.title)
        }
    }
}

private struct HotKeyEditorRow: View {
    let row: HotKeyRowModel
    let placeholder: String
    let registrationFailureTooltip: String
    let registrationFailureAccessibilityLabel: String
    let onChange: (HotKeyBinding) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(row.title)
            Spacer()
            HStack(spacing: 6) {
                ShortcutRecorderField(
                    binding: row.binding,
                    placeholder: placeholder,
                    onChange: onChange
                )
                .frame(width: 160, height: 28)

                HotKeyRegistrationFailureIndicator(
                    failure: row.registrationFailure,
                    tooltip: registrationFailureTooltip,
                    accessibilityLabel: registrationFailureAccessibilityLabel
                )
            }
        }
    }
}

private struct HotKeyRegistrationFailureIndicator: View {
    let failure: HotKeyRegistrationFailure?
    let tooltip: String
    let accessibilityLabel: String
    @State private var isShowingDetails = false

    var body: some View {
        Group {
            if failure != nil {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .frame(width: 16, height: 28)
                    .contentShape(Rectangle())
                    .help(tooltip)
                    .onHover { isHovering in
                        isShowingDetails = isHovering
                    }
                    .popover(
                        isPresented: $isShowingDetails,
                        arrowEdge: .trailing
                    ) {
                        HotKeyRegistrationFailurePopover(
                            title: accessibilityLabel,
                            message: tooltip
                        )
                    }
                    .accessibilityLabel(accessibilityLabel)
            } else {
                Color.clear
                    .frame(width: 16, height: 28)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct HotKeyRegistrationFailurePopover: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemRed))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 280, alignment: .leading)
        .padding(12)
    }
}

private enum HotKeyDisplayFormatter {
    static func description(for binding: HotKeyBinding) -> String {
        description(for: binding.modifiers) + binding.menuDisplayKey
    }

    static func description(for modifiers: ShortcutModifierSet) -> String {
        modifiers.displayString
    }

    static func description(for key: ShortcutKey) -> String {
        key.displayKey
    }
}

private struct ShortcutRecorderField: NSViewRepresentable {
    let binding: HotKeyBinding
    let placeholder: String
    let onChange: (HotKeyBinding) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl()
        control.onChange = { key, modifiers in
            onChange(
                HotKeyBinding(
                    action: binding.action,
                    key: key,
                    modifiers: modifiers
                )
            )
        }
        return control
    }

    func updateNSView(_ nsView: ShortcutRecorderControl, context: Context) {
        if nsView.placeholder != placeholder {
            nsView.placeholder = placeholder
        }
        if nsView.binding != binding {
            nsView.binding = binding
        }
        nsView.onChange = { key, modifiers in
            onChange(
                HotKeyBinding(
                    action: binding.action,
                    key: key,
                    modifiers: modifiers
                )
            )
        }
    }
}

private final class ShortcutRecorderControl: NSControl {
    var binding: HotKeyBinding? {
        didSet {
            guard !isRecording else { return }
            updateDisplay()
        }
    }

    var placeholder = ""
    var onChange: ((ShortcutKey, ShortcutModifierSet) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var isRecording = false {
        didSet {
            updateAppearance()
            updateDisplay()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAppearance()
        updateDisplay()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
        updateDisplay()
        needsDisplay = true
        label.needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return
        }

        guard let key = ShortcutKey(keyCode: event.keyCode) else {
            NSSound.beep()
            return
        }

        guard let modifiers = ShortcutModifierSet(
            eventFlags: event.modifierFlags
        ) else {
            NSSound.beep()
            return
        }

        onChange?(key, modifiers)
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        isRecording = false
        return didResign
    }

    private func cancelRecording() {
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    private func updateDisplay() {
        if isRecording {
            label.stringValue = placeholder
            label.textColor = .controlAccentColor
            return
        }

        if let binding {
            label.stringValue = HotKeyDisplayFormatter.description(for: binding)
            label.textColor = .labelColor
        } else {
            label.stringValue = placeholder
            label.textColor = .secondaryLabelColor
        }
    }

    private func updateAppearance() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }
}

private struct CompactInteractionStyleCard: View {
    let title: String
    let description: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Circle()
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            .frame(width: 14, height: 14)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .primary : .secondary)

                    Text(description)
                        .font(.system(size: 11))
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
