import AppKit
import Carbon.HIToolbox
import SwiftUI
import Observation

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settingsStore: SettingsStore
    private let onPointerInsideChanged: (Bool) -> Void
    private var settingsObserver: NSObjectProtocol?
    private var pointerTrackingArea: NSTrackingArea?
    private var isPointerInsideContentView = false

    init(
        settingsStore: SettingsStore,
        onPointerInsideChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.settingsStore = settingsStore
        self.onPointerInsideChanged = onPointerInsideChanged

        let rootView = SettingsView(settingsStore: settingsStore)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)

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

private struct SettingsView: View {
    @Bindable var settingsStore: SettingsStore
    @State private var launchAtLoginController = LaunchAtLoginController()
    @State private var selectedPage: SettingsPage? = .general

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(
                selection: $selectedPage,
                settingsStore: settingsStore
            )
        } detail: {
            SettingsDetailPage(
                page: selectedPage ?? .general,
                settingsStore: settingsStore,
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

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case gestures
    case dockGestures
    case titleBarGestures
    case shortcuts
    case advanced

    var id: Self { self }

    var localizationKey: String {
        switch self {
        case .general:
            return "settings.section.general"
        case .gestures:
            return "settings.section.gestures"
        case .dockGestures:
            return "settings.section.dock_gestures"
        case .titleBarGestures:
            return "settings.section.title_bar_gestures"
        case .shortcuts:
            return "settings.section.shortcuts"
        case .advanced:
            return "settings.section.advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .gestures:
            return "hand.draw"
        case .dockGestures:
            return "rectangle.bottomthird.inset.filled"
        case .titleBarGestures:
            return "rectangle.topthird.inset.filled"
        case .shortcuts:
            return "command"
        case .advanced:
            return "gearshape.2"
        }
    }

    func title(localize: (String) -> String) -> String {
        localize(localizationKey)
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPage?
    @Bindable var settingsStore: SettingsStore

    var body: some View {
        List(selection: $selection) {
            ForEach(SettingsPage.allCases) { page in
                Label(page.title(localize: settingsStore.localized), systemImage: page.systemImage)
                    .tag(Optional(page))
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 210)
    }
}

private struct SettingsDetailPage: View {
    let page: SettingsPage
    @Bindable var settingsStore: SettingsStore
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
                GestureSettingsPage(settingsStore: settingsStore)
            case .dockGestures:
                DockGestureMappingsPage(settingsStore: settingsStore)
            case .titleBarGestures:
                TitleBarGestureMappingsPage(settingsStore: settingsStore)
            case .shortcuts:
                HotKeysSettingsPage(settingsStore: settingsStore)
            case .advanced:
                AdvancedSettingsPage(settingsStore: settingsStore)
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
            SettingsPickerOption(value: language, title: languageTitle(for: language))
        }
    }

    private var statusItemIconOptions: [SettingsPickerOption<StatusItemIcon>] {
        StatusItemIcon.allCases.map { icon in
            SettingsPickerOption(
                value: icon,
                title: icon.title(preferredLanguages: preferredLanguages),
                systemImage: icon.symbolName,
                image: icon.symbolName == nil
                    ? icon.makeImage(accessibilityDescription: icon.title(preferredLanguages: preferredLanguages))
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
        }
    }

    private func languageTitle(for language: AppLanguage) -> String {
        switch language {
        case .system:
            return settingsStore.localized("settings.language.system")
        case .english:
            return settingsStore.localized("settings.language.english")
        case .simplifiedChinese:
            return settingsStore.localized("settings.language.simplified_chinese")
        }
    }
}

private struct GestureSettingsPage: View {
    @Bindable var settingsStore: SettingsStore

    private var preferredLanguages: [String] {
        settingsStore.preferredLanguages
    }

    private var gestureHUDStyleOptions: [SettingsPickerOption<GestureHUDStyle>] {
        GestureHUDStyle.allCases.map { style in
            SettingsPickerOption(value: style, title: style.title(preferredLanguages: preferredLanguages))
        }
    }

    private var gesturePreviewItems: [GestureHUDPreviewItem] {
        [
            GestureHUDPreviewItem(
                style: settingsStore.gestureHUDStyle,
                gesture: .pinchIn,
                gestureTitle: DockGestureKind.pinchIn.title(preferredLanguages: preferredLanguages),
                actionTitle: settingsStore.dockGestureAction(for: .pinchIn).title(preferredLanguages: preferredLanguages)
            ),
            GestureHUDPreviewItem(
                style: settingsStore.gestureHUDStyle,
                gesture: .swipeUp,
                gestureTitle: DockGestureKind.swipeUp.title(preferredLanguages: preferredLanguages),
                actionTitle: settingsStore.dockGestureAction(for: .swipeUp).title(preferredLanguages: preferredLanguages)
            ),
        ]
    }

    var body: some View {
        SettingsPageContainer {
            GestureSettingsSection(
                settingsStore: settingsStore,
                gestureHUDStyleOptions: gestureHUDStyleOptions,
                previewItems: gesturePreviewItems
            )
        }
    }
}

private struct DockGestureMappingsPage: View {
    @Bindable var settingsStore: SettingsStore

    private var preferredLanguages: [String] {
        settingsStore.preferredLanguages
    }

    private var rows: [GestureActionRowModel<DockGestureKind, DockGestureAction>] {
        DockGestureKind.allCases.map { gesture in
            GestureActionRowModel(
                gesture: gesture,
                title: gesture.title(preferredLanguages: preferredLanguages),
                isEnabled: settingsStore.dockGestureIsEnabled(for: gesture),
                selectedAction: settingsStore.dockGestureAction(for: gesture),
                availableActions: DockGestureAction.allCases.map {
                    SettingsPickerOption(
                        value: $0,
                        title: $0.title(preferredLanguages: preferredLanguages),
                        isDisabled: $0 == .closeTab && settingsStore.experimentalBrowserTabCloseEnabled == false
                    )
                }
            )
        }
    }

    var body: some View {
        SettingsPageContainer {
            DockGestureMappingsSection(
                settingsStore: settingsStore,
                rows: rows
            )
        }
    }
}

private struct TitleBarGestureMappingsPage: View {
    @Bindable var settingsStore: SettingsStore

    private var preferredLanguages: [String] {
        settingsStore.preferredLanguages
    }

    private var rows: [GestureActionRowModel<DockGestureKind, WindowAction>] {
        TitleBarGestureBindings.supportedGestures.map { gesture in
            GestureActionRowModel(
                gesture: gesture,
                title: gesture.title(preferredLanguages: preferredLanguages),
                isEnabled: settingsStore.titleBarGestureIsEnabled(for: gesture),
                selectedAction: settingsStore.titleBarGestureAction(for: gesture)
                    ?? TitleBarGestureBindings.fallbackBinding(for: gesture).action,
                availableActions: WindowAction.gestureCases.map {
                    SettingsPickerOption(
                        value: $0,
                        title: $0.title(preferredLanguages: preferredLanguages),
                        isDisabled: $0 == .closeTab && settingsStore.experimentalBrowserTabCloseEnabled == false
                    )
                }
            )
        }
    }

    var body: some View {
        SettingsPageContainer {
            TitleBarGestureMappingsSection(
                settingsStore: settingsStore,
                rows: rows
            )
        }
    }
}

private struct HotKeysSettingsPage: View {
    @Bindable var settingsStore: SettingsStore

    private var preferredLanguages: [String] {
        settingsStore.preferredLanguages
    }

    private var rows: [HotKeyRowModel] {
        WindowAction.allCases.map { action in
            HotKeyRowModel(
                action: action,
                title: action.title(preferredLanguages: preferredLanguages),
                binding: settingsStore.hotKeyBinding(for: action)
            )
        }
    }

    var body: some View {
        SettingsPageContainer {
            HotKeysSection(
                settingsStore: settingsStore,
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

private struct GestureHUDPreviewItem: Identifiable, Equatable {
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

private struct HotKeyRowModel: Identifiable {
    let action: WindowAction
    let title: String
    let binding: HotKeyBinding

    var id: WindowAction { action }
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
                   statusMessage.isEmpty == false {
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
                .disabled(settingsStore.titleBarGesturesEnabled == false)

                DurationSlider(
                    label: settingsStore.localized("settings.advanced.corner_drag_hold_duration.label"),
                    value: $settingsStore.titleBarCornerDragHoldDuration,
                    range: SettingsStore.minimumTitleBarCornerDragHoldDuration ... SettingsStore.maximumTitleBarCornerDragHoldDuration,
                    step: 0.1
                )
                .disabled(
                    (settingsStore.dockGesturesEnabled == false || settingsStore.dockCornerDragSnapEnabled == false) &&
                        (settingsStore.titleBarGesturesEnabled == false || settingsStore.titleBarCornerDragSnapEnabled == false)
                )
            }

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
                .disabled(settingsStore.reverseCancelEnabled == false)

                SettingsHintGroup {
                    Text(settingsStore.localized("settings.advanced.reverse_cancel.footer"))
                }
            }

            SettingsCardSection(title: settingsStore.localized("settings.advanced.section.other")) {
                Toggle(
                    settingsStore.localized("settings.advanced.title_bar_overlay_protection.enabled"),
                    isOn: $settingsStore.titleBarOverlayProtectionEnabled
                )
                .disabled(settingsStore.titleBarGesturesEnabled == false)

                SettingsHintGroup {
                    Text(settingsStore.localized("settings.advanced.title_bar_overlay_protection.footer"))
                }

                Toggle(
                    settingsStore.localized("settings.advanced.smart_pinch_exit_full_screen.enabled"),
                    isOn: $settingsStore.smartPinchExitFullScreenEnabled
                )
                .disabled(settingsStore.titleBarGesturesEnabled == false)

                SettingsHintGroup {
                    Text(settingsStore.localized("settings.advanced.smart_pinch_exit_full_screen.footer"))
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
                .disabled(settingsStore.experimentalBrowserTabCloseEnabled == false)

                SettingsHintGroup {
                    Text(settingsStore.localized("settings.experimental.smart_browser_tab_close.footer"))
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
            .disabled(settingsStore.dockGesturesEnabled == false)

            SettingsMappingCard {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    DockGestureActionRow(
                        row: row,
                        isSectionEnabled: settingsStore.dockGesturesEnabled,
                        toggleBinding: Binding(
                            get: { settingsStore.dockGestureIsEnabled(for: row.gesture) },
                            set: { settingsStore.updateDockGestureEnabled($0, for: row.gesture) }
                        ),
                        actionBinding: Binding(
                            get: { settingsStore.dockGestureAction(for: row.gesture) },
                            set: { settingsStore.updateDockGestureAction($0, for: row.gesture) }
                        )
                    )

                    if index < rows.count - 1 {
                        Divider()
                    }
                }
            }

            Button(settingsStore.localized("settings.dock_gestures.reset")) {
                settingsStore.resetDockGestureActionsToDefaults()
            }
            .disabled(settingsStore.dockGesturesEnabled == false)
            .padding(.top, 2)

            Text(settingsStore.localized("settings.dock_gestures.footer"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
            .disabled(settingsStore.titleBarGesturesEnabled == false)

            SettingsMappingCard {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    TitleBarGestureActionRow(
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
                        )
                    )

                    if index < rows.count - 1 {
                        Divider()
                    }
                }
            }

            Button(settingsStore.localized("settings.title_bar_gestures.reset")) {
                settingsStore.resetTitleBarGestureActionsToDefaults()
            }
            .disabled(settingsStore.titleBarGesturesEnabled == false)
            .padding(.top, 2)

            Text(settingsStore.localized("settings.title_bar_gestures.footer"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 10)
    }
}

private struct GestureHUDPreviewStrip: View {
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

private struct DockGestureActionRow: View {
    let row: GestureActionRowModel<DockGestureKind, DockGestureAction>
    let isSectionEnabled: Bool
    let toggleBinding: Binding<Bool>
    let actionBinding: Binding<DockGestureAction>

    var body: some View {
        HStack(spacing: 20) {
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
            .frame(width: 220)
            .disabled(isSectionEnabled == false || row.isEnabled == false)
        }
        .disabled(isSectionEnabled == false)
        .padding(.vertical, 14)
    }
}

private struct TitleBarGestureActionRow: View {
    let row: GestureActionRowModel<DockGestureKind, WindowAction>
    let isSectionEnabled: Bool
    let toggleBinding: Binding<Bool>
    let actionBinding: Binding<WindowAction>

    var body: some View {
        HStack(spacing: 20) {
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
            .frame(width: 220)
            .disabled(isSectionEnabled == false || row.isEnabled == false)
        }
        .disabled(isSectionEnabled == false)
        .padding(.vertical, 14)
    }
}

private struct HotKeysSection: View {
    @Bindable var settingsStore: SettingsStore
    let rows: [HotKeyRowModel]

    var body: some View {
        SettingsCardSection(title: settingsStore.localized("settings.section.shortcuts")) {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(rows) { row in
                    HotKeyEditorRow(
                        row: row,
                        placeholder: settingsStore.localized("settings.shortcuts.recorder_placeholder"),
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
    let onChange: (HotKeyBinding) -> Void

    var body: some View {
        HStack {
            Text(row.title)
            Spacer()
            ShortcutRecorderField(
                binding: row.binding,
                placeholder: placeholder,
                onChange: onChange
            )
            .frame(width: 160, height: 28)
        }
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
