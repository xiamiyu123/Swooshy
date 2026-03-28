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

        window.setContentSize(NSSize(width: 460, height: 340))
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
            Task { @MainActor in
                self?.updateWindowTitle()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
            Section(settingsStore.localized("settings.section.general")) {
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
                    settingsStore.localized("settings.dock_gestures.enabled"),
                    isOn: $settingsStore.dockGesturesEnabled
                )
            }

            Section(settingsStore.localized("settings.section.shortcuts")) {
                ForEach(WindowAction.allCases, id: \.self) { action in
                    HotKeyEditorRow(settingsStore: settingsStore, action: action)
                }

                Button(settingsStore.localized("settings.shortcuts.reset")) {
                    settingsStore.resetHotKeysToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 420, minHeight: 320)
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
        fatalError("init(coder:) has not been implemented")
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
