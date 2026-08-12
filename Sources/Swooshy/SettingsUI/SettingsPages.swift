import SwiftUI

struct GeneralSettingsPage: View {
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

struct GestureSettingsPage: View {
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

    private var gestureHUDPositionOptions: [SettingsPickerOption<GestureHUDPosition>] {
        GestureHUDPosition.allCases.map { position in
            SettingsPickerOption(value: position, title: position.title(preferredLanguages: preferredLanguages))
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
                gestureHUDPositionOptions: gestureHUDPositionOptions,
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

struct DockGestureMappingsPage: View {
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

struct TitleBarGestureMappingsPage: View {
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

struct HotKeysSettingsPage: View {
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
