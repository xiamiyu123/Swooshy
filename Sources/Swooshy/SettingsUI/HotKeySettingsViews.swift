import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HotKeysSection: View {
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

struct SettingsSectionHeaderWithBadge: View {
    let title: String
    let showsWarning: Bool
    let warningTooltip: String

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Text(title)
                .font(SettingsDesign.Typography.sectionTitle)
                .lineLimit(1)

            if showsWarning {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .help(warningTooltip)
                    .accessibilityLabel(warningTooltip)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .padding(.top, 6)
    }
}

struct HotKeyRegistrationNotice: View {
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

struct SettingsPickerOptionLabel<Value: Hashable>: View {
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

struct HotKeyEditorRow: View {
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

struct HotKeyRegistrationFailureIndicator: View {
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

struct HotKeyRegistrationFailurePopover: View {
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

enum HotKeyDisplayFormatter {
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

struct ShortcutRecorderField: NSViewRepresentable {
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

final class ShortcutRecorderControl: NSControl {
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
