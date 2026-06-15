import AppKit
import SwiftUI

struct AdvancedSettingsPage: View {
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

                SettingsHintGroup {
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

struct AboutSettingsPage: View {
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

struct AboutUpdateStatusView: View {
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

struct AboutLinkButton: View {
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
