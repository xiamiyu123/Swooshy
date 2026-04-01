import AppKit
import Carbon.HIToolbox
import SwiftUI
import Observation

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settingsStore: SettingsStore
    private var settingsObserver: NSObjectProtocol?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore

        let rootView = SettingsView(settingsStore: settingsStore)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)

        window.setContentSize(NSSize(width: 560, height: 640))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        self.window?.delegate = self
        updateWindowTitle()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: settingsStore,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateWindowTitle()
            }
        }
    }

    func shutdown() {
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
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func updateWindowTitle() {
        window?.title = settingsStore.localized("settings.window.title")
    }
}

private struct SettingsView: View {
    @Bindable var settingsStore: SettingsStore
    @State private var launchAtLoginController = LaunchAtLoginController()
    @State private var showingAdvancedSettings = false

    var body: some View {
        Form {
            Section {
                Picker(
                    settingsStore.localized("settings.language.label"),
                    selection: $settingsStore.languageOverride
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(title(for: language)).tag(language)
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
                    ForEach(StatusItemIcon.allCases) { icon in
                        statusItemIconLabel(for: icon).tag(icon)
                    }
                }
                .pickerStyle(.menu)

                #if DEBUG
                Toggle(
                    settingsStore.localized("settings.debug_logging.enabled"),
                    isOn: $settingsStore.debugLoggingEnabled
                )
                #endif
            } header: {
                Text(settingsStore.localized("settings.section.general"))
            }

            Section {
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
                    ForEach(GestureHUDStyle.allCases) { style in
                        Text(style.title(preferredLanguages: settingsStore.preferredLanguages)).tag(style)
                    }
                }
                .pickerStyle(.menu)

                SettingsHintGroup {
                    Text(settingsStore.localized("settings.gesture_hud.footer"))
                    Text(settingsStore.localized("settings.gesture_execute_on_release.footer"))
                }

                GestureHUDPreviewStrip(settingsStore: settingsStore)
            } header: {
                Text(settingsStore.localized("settings.section.gestures"))
            } footer: {
                Text(settingsStore.localized("settings.gestures.footer"))
            }

            DockGestureMappingsSection(settingsStore: settingsStore)

            TitleBarGestureMappingsSection(settingsStore: settingsStore)

            Section {
                ForEach(WindowAction.allCases, id: \.self) { action in
                    HotKeyEditorRow(settingsStore: settingsStore, action: action)
                }

                Button(settingsStore.localized("settings.shortcuts.reset")) {
                    settingsStore.resetHotKeysToDefaults()
                }
            } header: {
                Text(settingsStore.localized("settings.section.shortcuts"))
            }

            Section {
                Button {
                    showingAdvancedSettings = true
                } label: {
                    Text(settingsStore.localized("settings.advanced.open"))
                }
            } footer: {
                Text(settingsStore.localized("settings.advanced.footer"))
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 500, minHeight: 520)
        .onAppear {
            launchAtLoginController.refresh(localize: settingsStore.localized)
        }
        .sheet(isPresented: $showingAdvancedSettings) {
            AdvancedSettingsSheet(settingsStore: settingsStore)
        }
    }

    private func title(for language: AppLanguage) -> String {
        switch language {
        case .system:
            return settingsStore.localized("settings.language.system")
        case .english:
            return settingsStore.localized("settings.language.english")
        case .simplifiedChinese:
            return settingsStore.localized("settings.language.simplified_chinese")
        }
    }

    @ViewBuilder
    private func statusItemIconLabel(for icon: StatusItemIcon) -> some View {
        let title = icon.title(preferredLanguages: settingsStore.preferredLanguages)

        if let symbolName = icon.symbolName {
            Label(title, systemImage: symbolName)
        } else if let image = icon.makeImage(accessibilityDescription: title) {
            Label {
                Text(title)
            } icon: {
                Image(nsImage: image)
                    .renderingMode(.template)
            }
        } else {
            Text(title)
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

private struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

private struct AdvancedSettingsSheet: View {
    @Bindable var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text(settingsStore.localized("settings.advanced.title"))
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Form {
                Section {
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
                } header: {
                    Text(settingsStore.localized("settings.advanced.section.sensitivity"))
                }

                Section {
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
                } header: {
                    Text(settingsStore.localized("settings.advanced.section.cancel"))
                }

                Section {
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
                } header: {
                    Text(settingsStore.localized("settings.advanced.section.other"))
                }

                Section {
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
                } header: {
                    Text(settingsStore.localized("settings.experimental.section"))
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(settingsStore.localized("settings.advanced.reset_defaults")) {
                    settingsStore.resetAdvancedSettingsToDefaults()
                }

                Spacer()

                Button(settingsStore.localized("settings.advanced.done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 8)
        }
        .frame(width: 480, height: 520)
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


private struct SettingsMappingCard<Rows: View>: View {
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(spacing: 0) {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSectionHeader(title: settingsStore.localized("settings.section.dock_gestures"))

            SettingsMappingCard {
                ForEach(Array(DockGestureKind.allCases.enumerated()), id: \.element) { index, gesture in
                    DockGestureActionRow(settingsStore: settingsStore, gesture: gesture)
                        .disabled(settingsStore.dockGesturesEnabled == false)

                    if index < DockGestureKind.allCases.count - 1 {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSectionHeader(title: settingsStore.localized("settings.section.title_bar_gestures"))

            SettingsMappingCard {
                ForEach(Array(TitleBarGestureBindings.supportedGestures.enumerated()), id: \.element) { index, gesture in
                    TitleBarGestureActionRow(settingsStore: settingsStore, gesture: gesture)
                        .disabled(settingsStore.titleBarGesturesEnabled == false)

                    if index < TitleBarGestureBindings.supportedGestures.count - 1 {
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
    @Bindable var settingsStore: SettingsStore

    var body: some View {
        let previewStyle = settingsStore.gestureHUDStyle

        VStack(alignment: .leading, spacing: 10) {
            GestureHUDPreviewCard(
                style: previewStyle,
                gesture: .pinchIn,
                gestureTitle: DockGestureKind.pinchIn.title(preferredLanguages: settingsStore.preferredLanguages),
                actionTitle: settingsStore.dockGestureAction(for: .pinchIn).title(
                    preferredLanguages: settingsStore.preferredLanguages
                )
            )

            GestureHUDPreviewCard(
                style: previewStyle,
                gesture: .swipeUp,
                gestureTitle: DockGestureKind.swipeUp.title(preferredLanguages: settingsStore.preferredLanguages),
                actionTitle: settingsStore.dockGestureAction(for: .swipeUp).title(
                    preferredLanguages: settingsStore.preferredLanguages
                )
            )
        }
        .padding(.top, 4)
    }
}

private struct GestureHUDPreviewCard: View {
    let style: GestureHUDStyle
    let gesture: DockGestureKind
    let gestureTitle: String
    let actionTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(gestureTitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            GestureHUDRenderHost(
                model: GestureHUDRenderModel(
                    style: style,
                    gesture: gesture,
                    gestureTitle: gestureTitle,
                    actionTitle: actionTitle
                )
            )
            .frame(
                width: GestureHUDRenderView.panelSize(for: style).width,
                height: GestureHUDRenderView.panelSize(for: style).height,
                alignment: .leading
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GestureHUDRenderHost: NSViewRepresentable {
    let model: GestureHUDRenderModel

    func makeNSView(context: Context) -> GestureHUDRenderView {
        let view = GestureHUDRenderView(frame: NSRect(origin: .zero, size: GestureHUDRenderView.panelSize(for: model.style)))
        view.render(model: model)
        return view
    }

    func updateNSView(_ nsView: GestureHUDRenderView, context: Context) {
        nsView.render(model: model)
    }
}

private struct DockGestureActionRow: View {
    @Bindable var settingsStore: SettingsStore
    let gesture: DockGestureKind

    var body: some View {
        HStack(spacing: 20) {
            Toggle(
                gesture.title(preferredLanguages: settingsStore.preferredLanguages),
                isOn: Binding(
                    get: { settingsStore.dockGestureIsEnabled(for: gesture) },
                    set: { settingsStore.updateDockGestureEnabled($0, for: gesture) }
                )
            )
            .toggleStyle(.switch)
            .frame(maxWidth: .infinity, alignment: .leading)
            Picker(
                "",
                selection: Binding(
                    get: { settingsStore.dockGestureAction(for: gesture) },
                    set: { settingsStore.updateDockGestureAction($0, for: gesture) }
                )
            ) {
                ForEach(DockGestureAction.allCases) { action in
                    Text(action.title(preferredLanguages: settingsStore.preferredLanguages))
                        .tag(action)
                        .disabled(action == .closeTab && settingsStore.experimentalBrowserTabCloseEnabled == false)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 220)
            .disabled(settingsStore.dockGestureIsEnabled(for: gesture) == false)
        }
        .padding(.vertical, 14)
    }
}

private struct TitleBarGestureActionRow: View {
    @Bindable var settingsStore: SettingsStore
    let gesture: DockGestureKind

    var body: some View {
        HStack(spacing: 20) {
            Toggle(
                gesture.title(preferredLanguages: settingsStore.preferredLanguages),
                isOn: Binding(
                    get: { settingsStore.titleBarGestureIsEnabled(for: gesture) },
                    set: { settingsStore.updateTitleBarGestureEnabled($0, for: gesture) }
                )
            )
            .toggleStyle(.switch)
            .frame(maxWidth: .infinity, alignment: .leading)
            Picker(
                "",
                selection: Binding(
                    get: {
                        settingsStore.titleBarGestureAction(for: gesture)
                        ?? TitleBarGestureBindings.fallbackBinding(for: gesture).action
                    },
                    set: { settingsStore.updateTitleBarGestureAction($0, for: gesture) }
                )
            ) {
                ForEach(WindowAction.allCases, id: \.self) { action in
                    Text(action.title(preferredLanguages: settingsStore.preferredLanguages))
                        .tag(action)
                        .disabled(action == .closeTab && settingsStore.experimentalBrowserTabCloseEnabled == false)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 220)
            .disabled(settingsStore.titleBarGestureIsEnabled(for: gesture) == false)
        }
        .padding(.vertical, 14)
    }
}

private struct HotKeyEditorRow: View {
    @Bindable var settingsStore: SettingsStore
    let action: WindowAction

    var body: some View {
        HStack {
            Text(action.title(preferredLanguages: settingsStore.preferredLanguages))
            Spacer()
            ShortcutRecorderField(
                binding: settingsStore.hotKeyBinding(for: action),
                placeholder: settingsStore.localized("settings.shortcuts.recorder_placeholder"),
                onChange: { settingsStore.updateHotKeyBinding($0) }
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
        nsView.placeholder = placeholder
        nsView.binding = binding
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
