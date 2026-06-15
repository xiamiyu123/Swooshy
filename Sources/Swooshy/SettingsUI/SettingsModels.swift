import AppKit
import Foundation

struct SettingsPickerOption<Value: Hashable>: Identifiable {
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

struct GestureActionRowModel<Gesture: Hashable & Identifiable, Action: Hashable>: Identifiable {
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
