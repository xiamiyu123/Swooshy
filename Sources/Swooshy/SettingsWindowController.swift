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
            } footer: {
                let footerText = settingsStore.localized("settings.status_item_icon.footer")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if footerText.isEmpty == false {
                    Text(footerText)
                }
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
                Picker(
                    settingsStore.localized("settings.gesture_hud.style.label"),
                    selection: $settingsStore.gestureHUDStyle
                ) {
                    ForEach(GestureHUDStyle.allCases) { style in
                        Text(style.title(preferredLanguages: settingsStore.preferredLanguages)).tag(style)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text(settingsStore.localized("settings.section.gestures"))
            } footer: {
                Text(settingsStore.localized("settings.gesture_hud.footer"))
            }

            Section {
                ForEach(DockGestureKind.allCases) { gesture in
                    DockGestureActionRow(settingsStore: settingsStore, gesture: gesture)
                        .disabled(settingsStore.dockGesturesEnabled == false)
                }

                Button(settingsStore.localized("settings.dock_gestures.reset")) {
                    settingsStore.resetDockGestureActionsToDefaults()
                }
                .disabled(settingsStore.dockGesturesEnabled == false)
            } header: {
                Text(settingsStore.localized("settings.section.dock_gestures"))
            } footer: {
                Text(settingsStore.localized("settings.dock_gestures.footer"))
            }

            Section {
                ForEach(TitleBarGestureBindings.supportedGestures) { gesture in
                    TitleBarGestureActionRow(settingsStore: settingsStore, gesture: gesture)
                        .disabled(settingsStore.titleBarGesturesEnabled == false)
                }

                Button(settingsStore.localized("settings.title_bar_gestures.reset")) {
                    settingsStore.resetTitleBarGestureActionsToDefaults()
                }
                .disabled(settingsStore.titleBarGesturesEnabled == false)
            } header: {
                Text(settingsStore.localized("settings.section.title_bar_gestures"))
            } footer: {
                Text(settingsStore.localized("settings.title_bar_gestures.footer"))
            }

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
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 500, minHeight: 520)
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

private struct DockGestureActionRow: View {
    @Bindable var settingsStore: SettingsStore
    let gesture: DockGestureKind

    var body: some View {
        HStack {
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
                    Text(action.title(preferredLanguages: settingsStore.preferredLanguages)).tag(action)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 220)
            .disabled(settingsStore.dockGestureIsEnabled(for: gesture) == false)
        }
    }
}

private struct TitleBarGestureActionRow: View {
    @Bindable var settingsStore: SettingsStore
    let gesture: DockGestureKind

    var body: some View {
        HStack {
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
                    Text(action.title(preferredLanguages: settingsStore.preferredLanguages)).tag(action)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 220)
            .disabled(settingsStore.titleBarGestureIsEnabled(for: gesture) == false)
        }
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
