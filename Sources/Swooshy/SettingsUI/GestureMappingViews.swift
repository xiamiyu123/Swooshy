import AppKit
import SwiftUI

struct SettingsMappingCard<Rows: View>: View {
    @ViewBuilder let rows: Rows

    var body: some View {
        LazyVStack(spacing: 0) {
            rows
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: SettingsDesign.Radius.card, padding: nil)
    }
}

struct DockGestureMappingsSection: View {
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

struct TitleBarGestureMappingsSection: View {
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

struct GestureHUDPreviewCard: View {
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
struct GestureHUDPreviewSnapshot: View {
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
final class GestureHUDPreviewSnapshotCache {
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

struct DangerGestureConfirmationToggle: View {
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
struct DangerGestureConfirmationDisabledHint: View {
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

enum GestureMappingColumnLayout {
    static let actionWidth: CGFloat = 220
    static let confirmationWidth: CGFloat = 28
    static let columnSpacing: CGFloat = 12
}

struct GestureMappingRowLayout<Leading: View, Action: View, Confirmation: View>: View {
    let showsConfirmation: Bool
    @ViewBuilder let leading: Leading
    @ViewBuilder let action: Action
    @ViewBuilder let confirmation: Confirmation

    var body: some View {
        HStack(spacing: GestureMappingColumnLayout.columnSpacing) {
            leading
                .frame(maxWidth: .infinity, alignment: .leading)

            action
                .frame(width: GestureMappingColumnLayout.actionWidth, alignment: .center)

            if showsConfirmation {
                confirmation
                    .frame(width: GestureMappingColumnLayout.confirmationWidth, alignment: .center)
            }
        }
    }
}

struct GestureMappingColumnHeader: View {
    let actionTitle: String
    var confirmationTitle: String? = nil

    var body: some View {
        GestureMappingRowLayout(showsConfirmation: confirmationTitle != nil) {
            Color.clear
        } action: {
            Text(actionTitle)
        } confirmation: {
            if let confirmationTitle {
                Text(confirmationTitle)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.bottom, 2)
    }
}

struct GestureActionRow<Action: Hashable>: View {
    let row: GestureActionRowModel<DockGestureKind, Action>
    let isSectionEnabled: Bool
    let toggleBinding: Binding<Bool>
    let actionBinding: Binding<Action>
    var confirmationBinding: Binding<Bool>? = nil
    var confirmationHelp: String? = nil

    var body: some View {
        GestureMappingRowLayout(showsConfirmation: confirmationBinding != nil) {
            Toggle(row.title, isOn: toggleBinding)
                .toggleStyle(.switch)
        } action: {
            Picker("", selection: actionBinding) {
                ForEach(row.availableActions) { option in
                    Text(option.title)
                        .tag(option.value)
                        .disabled(option.isDisabled)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .disabled(!isSectionEnabled || !row.isEnabled)
        } confirmation: {
            if let confirmationBinding {
                DangerGestureConfirmationButton(
                    isOn: confirmationBinding,
                    help: confirmationHelp ?? ""
                )
                .disabled(!isSectionEnabled || !row.isEnabled)
            }
        }
        .disabled(!isSectionEnabled)
        .padding(.vertical, 14)
    }
}

struct DangerGestureConfirmationButton: View {
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
