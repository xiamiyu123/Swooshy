import SwiftUI
import Observation

struct SettingsView: View {
    @Bindable var settingsStore: SettingsStore
    @Bindable var gestureTargetCaptureController: GestureTargetCaptureController
    @Bindable var hotKeyRegistrationStatusStore: HotKeyRegistrationStatusStore
    let aboutPageModel: AboutPageModel
    let showGestureTriggerRegions: () -> Void
    let startGestureTargetCapture: () -> Void
    let cancelGestureTargetCapture: () -> Void
    @Bindable var navigationState: SettingsNavigationState
    @State private var launchAtLoginController = LaunchAtLoginController()

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(
                selection: $navigationState.selectedPage,
                settingsStore: settingsStore,
                hotKeyRegistrationStatusStore: hotKeyRegistrationStatusStore
            )
        } detail: {
            SettingsDetailPage(
                page: navigationState.selectedPage ?? .general,
                settingsStore: settingsStore,
                gestureTargetCaptureController: gestureTargetCaptureController,
                hotKeyRegistrationStatusStore: hotKeyRegistrationStatusStore,
                aboutPageModel: aboutPageModel,
                showGestureTriggerRegions: showGestureTriggerRegions,
                startGestureTargetCapture: startGestureTargetCapture,
                cancelGestureTargetCapture: cancelGestureTargetCapture,
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

@MainActor
@Observable
final class SettingsNavigationState {
    var selectedPage: SettingsPage? = .general
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case gestures
    case dockGestures
    case titleBarGestures
    case shortcuts
    case advanced
    case about

    var id: Self { self }

    var localizationKey: String {
        switch self {
        case .general:
            "settings.section.general"
        case .gestures:
            "settings.section.gestures"
        case .dockGestures:
            "settings.section.dock_gestures"
        case .titleBarGestures:
            "settings.section.title_bar_gestures"
        case .shortcuts:
            "settings.section.shortcuts"
        case .advanced:
            "settings.section.advanced"
        case .about:
            "settings.section.about"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape.fill"
        case .gestures:
            "hand.draw.fill"
        case .dockGestures:
            "rectangle.bottomthird.inset.filled"
        case .titleBarGestures:
            "rectangle.topthird.inset.filled"
        case .shortcuts:
            "command.square.fill"
        case .advanced:
            "slider.horizontal.3"
        case .about:
            "info.circle.fill"
        }
    }

    /// Background tint for the sidebar icon tile (the system-settings style
    /// rounded colored square). Distinct hues make rows easy to scan.
    var iconTint: Color {
        switch self {
        case .general:
            Color(nsColor: .systemGray)
        case .gestures:
            Color(nsColor: .systemIndigo)
        case .dockGestures:
            Color(nsColor: .systemBlue)
        case .titleBarGestures:
            Color(nsColor: .systemTeal)
        case .shortcuts:
            Color(nsColor: .systemPurple)
        case .advanced:
            Color(nsColor: .systemOrange)
        case .about:
            Color(nsColor: .systemPink)
        }
    }

    func title(localize: (String) -> String) -> String {
        localize(localizationKey)
    }
}

struct SettingsSidebar: View {
    private static let width = SettingsDesign.Sidebar.width

    @Binding var selection: SettingsPage?
    @Bindable var settingsStore: SettingsStore
    @Bindable var hotKeyRegistrationStatusStore: HotKeyRegistrationStatusStore

    var body: some View {
        List(selection: $selection) {
            ForEach(SettingsPage.allCases) { page in
                SettingsSidebarRow(
                    page: page,
                    title: page.title(localize: settingsStore.localized),
                    showsWarning: page == .shortcuts && hotKeyRegistrationStatusStore.hasIssue,
                    warningTooltip: settingsStore.localized("settings.shortcuts.registration_issue.tooltip")
                )
                    .tag(Optional(page))
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: Self.width, ideal: Self.width, max: Self.width)
    }
}

/// System-settings style rounded colored icon tile.
struct SidebarIconTile: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: SettingsDesign.Radius.iconTile, style: .continuous)
            .fill(tint.gradient)
            .frame(
                width: SettingsDesign.Sidebar.iconTileSize,
                height: SettingsDesign.Sidebar.iconTileSize
            )
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: SettingsDesign.Sidebar.iconGlyphSize, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

struct SettingsSidebarRow: View {
    let page: SettingsPage
    let title: String
    let showsWarning: Bool
    let warningTooltip: String

    var body: some View {
        HStack(alignment: .center, spacing: SettingsDesign.Spacing.inlineIcon) {
            SidebarIconTile(systemImage: page.systemImage, tint: page.iconTint)

            Text(title)
                .font(.body)
                .lineLimit(1)
                .frame(maxHeight: .infinity, alignment: .center)

            Spacer(minLength: 4)

            if showsWarning {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .frame(width: 14, height: SettingsDesign.Sidebar.rowHeight)
                    .help(warningTooltip)
                    .accessibilityLabel(warningTooltip)
            }
        }
        .frame(height: SettingsDesign.Sidebar.rowHeight, alignment: .center)
        .contentShape(Rectangle())
    }
}

struct SettingsDetailPage: View {
    let page: SettingsPage
    @Bindable var settingsStore: SettingsStore
    @Bindable var gestureTargetCaptureController: GestureTargetCaptureController
    @Bindable var hotKeyRegistrationStatusStore: HotKeyRegistrationStatusStore
    let aboutPageModel: AboutPageModel
    let showGestureTriggerRegions: () -> Void
    let startGestureTargetCapture: () -> Void
    let cancelGestureTargetCapture: () -> Void
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
                GestureSettingsPage(
                    settingsStore: settingsStore,
                    gestureTargetCaptureController: gestureTargetCaptureController,
                    startGestureTargetCapture: startGestureTargetCapture,
                    cancelGestureTargetCapture: cancelGestureTargetCapture,
                    showGestureTriggerRegions: showGestureTriggerRegions
                )
            case .dockGestures:
                DockGestureMappingsPage(
                    settingsStore: settingsStore,
                    showGestureTriggerRegions: showGestureTriggerRegions
                )
            case .titleBarGestures:
                TitleBarGestureMappingsPage(
                    settingsStore: settingsStore,
                    showGestureTriggerRegions: showGestureTriggerRegions
                )
            case .shortcuts:
                HotKeysSettingsPage(
                    settingsStore: settingsStore,
                    hotKeyRegistrationStatusStore: hotKeyRegistrationStatusStore
                )
            case .advanced:
                AdvancedSettingsPage(settingsStore: settingsStore)
            case .about:
                AboutSettingsPage(
                    settingsStore: settingsStore,
                    model: aboutPageModel
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SettingsPageContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            GlassGroup(spacing: SettingsDesign.Spacing.section) {
                LazyVStack(alignment: .leading, spacing: SettingsDesign.Spacing.section) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(SettingsDesign.Spacing.page)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
