import SwiftUI

struct GeneralSettingsSection: View {
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

struct GeneralGestureBehaviorSection: View {
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

            if settingsStore.dangerGestureConfirmationEnabled {
                DurationSlider(
                    label: settingsStore.localized("settings.danger_gesture_confirmation.duration.label"),
                    value: $settingsStore.dangerGestureConfirmationDuration,
                    range: SettingsStore.minimumDangerGestureConfirmationDuration ... SettingsStore.maximumDangerGestureConfirmationDuration,
                    step: 0.5
                )
            }

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

struct GestureSettingsSection: View {
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
