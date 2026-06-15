import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GestureTriggerRegionsSection: View {
    @Bindable var settingsStore: SettingsStore
    let showGestureTriggerRegions: () -> Void

    private var isEnabled: Bool {
        settingsStore.dockGesturesEnabled || settingsStore.titleBarGesturesEnabled
    }

    var body: some View {
        SettingsCardSection(title: settingsStore.localized("settings.trigger_regions.title")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(settingsStore.localized("settings.trigger_regions.description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showGestureTriggerRegions()
                } label: {
                    Label(
                        settingsStore.localized("settings.trigger_regions.show"),
                        systemImage: "rectangle.dashed.badge.record"
                    )
                }
                .disabled(!isEnabled)
            }
        }
    }
}

struct GestureExclusionsSection: View {
    @Bindable var settingsStore: SettingsStore
    @Bindable var gestureTargetCaptureController: GestureTargetCaptureController
    let startGestureTargetCapture: () -> Void
    let cancelGestureTargetCapture: () -> Void
    @State private var isShowingRunningApplicationPicker = false
    @State private var editedRule: GestureExclusionRuleDraft?

    var body: some View {
        SettingsCardSection(title: settingsStore.localized("settings.gesture_exclusions.title")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(settingsStore.localized("settings.gesture_exclusions.description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        isShowingRunningApplicationPicker = true
                    } label: {
                        Label(
                            settingsStore.localized("settings.gesture_exclusions.add_running"),
                            systemImage: "app.badge"
                        )
                    }

                    Button {
                        chooseApplicationBundle()
                    } label: {
                        Label(
                            settingsStore.localized("settings.gesture_exclusions.choose_app"),
                            systemImage: "folder"
                        )
                    }

                    if gestureTargetCaptureController.isCapturing {
                        Button(role: .cancel) {
                            cancelGestureTargetCapture()
                        } label: {
                            Label(
                                settingsStore.localized("settings.gesture_exclusions.capture.cancel"),
                                systemImage: "xmark.circle"
                            )
                        }
                    } else {
                        Button {
                            startGestureTargetCapture()
                        } label: {
                            Label(
                                settingsStore.localized("settings.gesture_exclusions.capture.start"),
                                systemImage: "hand.pinch"
                            )
                        }
                    }
                }

                captureStatusView

                Divider()

                if settingsStore.gestureExclusionRules.isEmpty {
                    Text(settingsStore.localized("settings.gesture_exclusions.empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(settingsStore.gestureExclusionRules.enumerated()), id: \.element.id) { index, rule in
                            GestureExclusionRuleRow(
                                rule: rule,
                                summary: summary(for: rule),
                                editLabel: settingsStore.localized("settings.gesture_exclusions.edit"),
                                removeLabel: settingsStore.localized("settings.gesture_exclusions.remove"),
                                onEdit: { edit(rule.application) },
                                onRemove: { settingsStore.removeGestureExclusionRule(id: rule.id) }
                            )

                            if index < settingsStore.gestureExclusionRules.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingRunningApplicationPicker) {
            RunningApplicationPickerSheet(
                settingsStore: settingsStore,
                onSelect: { application in
                    isShowingRunningApplicationPicker = false
                    edit(application)
                },
                onCancel: {
                    isShowingRunningApplicationPicker = false
                }
            )
        }
        .sheet(item: $editedRule) { draft in
            GestureExclusionRuleEditorSheet(
                settingsStore: settingsStore,
                draft: draft,
                onSave: { rule in
                    settingsStore.updateGestureExclusionRule(rule)
                    editedRule = nil
                },
                onCancel: {
                    editedRule = nil
                }
            )
        }
        .onChange(of: gestureTargetCaptureController.capturedApplication) { _, capturedApplication in
            guard let capturedApplication else { return }
            edit(capturedApplication)
            gestureTargetCaptureController.clearResult()
        }
    }

    @ViewBuilder
    private var captureStatusView: some View {
        if gestureTargetCaptureController.isCapturing {
            SettingsHintGroup {
                Text(settingsStore.localized("settings.gesture_exclusions.capture.waiting"))
            }
        } else if gestureTargetCaptureController.didTimeout {
            SettingsHintGroup {
                Text(settingsStore.localized("settings.gesture_exclusions.capture.timeout"))
            }
        } else if gestureTargetCaptureController.didMiss {
            SettingsHintGroup {
                Text(settingsStore.localized("settings.gesture_exclusions.capture.miss"))
            }
        }
    }

    private func edit(_ application: GestureExcludedApplication) {
        let existingRule = settingsStore.gestureExclusionRules.first {
            $0.application.matches(application)
        }
        editedRule = GestureExclusionRuleDraft(
            application: application,
            mode: existingRule?.mode ?? .all
        )
    }

    private func summary(for rule: GestureExclusionRule) -> String {
        switch rule.mode {
        case .all:
            settingsStore.localized("settings.gesture_exclusions.summary.all")
        case .selected(let selections):
            if selections.isEmpty {
                settingsStore.localized("settings.gesture_exclusions.summary.none")
            } else {
                String(
                    format: settingsStore.localized("settings.gesture_exclusions.summary.selected_format"),
                    selections.count
                )
            }
        }
    }

    private func chooseApplicationBundle() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        edit(GestureExcludedApplication(bundleURL: url, bundleIdentifier: Bundle(url: url)?.bundleIdentifier, displayName: applicationDisplayName(for: url)))
    }
}

struct GestureExclusionRuleDraft: Identifiable {
    let application: GestureExcludedApplication
    let mode: GestureExclusionMode

    var id: String { application.id }
}

struct GestureExclusionRuleRow: View {
    let rule: GestureExclusionRule
    let summary: String
    let editLabel: String
    let removeLabel: String
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ApplicationIcon(application: rule.application, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.application.displayName)
                    .font(.subheadline.weight(.medium))

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help(editLabel)
            .accessibilityLabel(editLabel)

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(removeLabel)
            .accessibilityLabel(removeLabel)
        }
        .padding(.vertical, 10)
    }
}

struct RunningApplicationPickerSheet: View {
    let settingsStore: SettingsStore
    let onSelect: (GestureExcludedApplication) -> Void
    let onCancel: () -> Void
    @State private var searchText = ""
    @State private var applications: [GestureExcludedApplication] = []

    private var filteredApplications: [GestureExcludedApplication] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return applications
        }

        return applications.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
                ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(settingsStore.localized("settings.gesture_exclusions.running_picker.title"))
                .font(.headline)

            TextField(
                settingsStore.localized("settings.gesture_exclusions.running_picker.search"),
                text: $searchText
            )
            .textFieldStyle(.roundedBorder)

            if filteredApplications.isEmpty {
                Text(settingsStore.localized("settings.gesture_exclusions.running_picker.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            } else {
                List(filteredApplications) { application in
                    Button {
                        onSelect(application)
                    } label: {
                        HStack(spacing: 10) {
                            ApplicationIcon(application: application, size: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(application.displayName)
                                    .font(.subheadline.weight(.medium))
                                if let bundleIdentifier = application.bundleIdentifier {
                                    Text(bundleIdentifier)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 260)
            }

            HStack {
                Spacer()
                Button(settingsStore.localized("settings.gesture_exclusions.editor.cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 390)
        .onAppear {
            applications = Self.runningApplications()
        }
    }

    private static func runningApplications() -> [GestureExcludedApplication] {
        var seenIDs = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { application -> GestureExcludedApplication? in
            guard
                !application.isTerminated,
                application.activationPolicy != .prohibited,
                !RunningApplicationIdentity.isLikelyHelperProcess(application),
                let appIdentity = AppIdentity(application: application)
            else {
                return nil
            }

            let excludedApplication = GestureExcludedApplication(appIdentity)
            guard seenIDs.insert(excludedApplication.id).inserted else {
                return nil
            }
            return excludedApplication
        }
        .sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}

struct GestureExclusionRuleEditorSheet: View {
    let settingsStore: SettingsStore
    let draft: GestureExclusionRuleDraft
    let onSave: (GestureExclusionRule) -> Void
    let onCancel: () -> Void
    @State private var editorMode: GestureExclusionEditorMode
    @State private var disabledSelections: Set<GestureExclusionSelection>

    init(
        settingsStore: SettingsStore,
        draft: GestureExclusionRuleDraft,
        onSave: @escaping (GestureExclusionRule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.draft = draft
        self.onSave = onSave
        self.onCancel = onCancel

        switch draft.mode {
        case .all:
            _editorMode = State(initialValue: .all)
            _disabledSelections = State(initialValue: [])
        case .selected(let selections):
            _editorMode = State(initialValue: .selected)
            _disabledSelections = State(initialValue: selections)
        }
    }

    private var saveDisabled: Bool {
        editorMode == .selected && disabledSelections.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ApplicationIcon(application: draft.application, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.application.displayName)
                        .font(.headline)

                    Text(settingsStore.localized("settings.gesture_exclusions.editor.title"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("", selection: $editorMode) {
                Text(settingsStore.localized("settings.gesture_exclusions.mode.all"))
                    .tag(GestureExclusionEditorMode.all)
                Text(settingsStore.localized("settings.gesture_exclusions.mode.selected"))
                    .tag(GestureExclusionEditorMode.selected)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if editorMode == .selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        gestureSelectionGroup(
                            title: settingsStore.localized("settings.gesture_exclusions.surface.dock"),
                            surface: .dock,
                            gestures: DockGestureKind.allCases
                        )

                        gestureSelectionGroup(
                            title: settingsStore.localized("settings.gesture_exclusions.surface.title_bar"),
                            surface: .titleBar,
                            gestures: TitleBarGestureBindings.supportedGestures
                        )

                        if disabledSelections.isEmpty {
                            Text(settingsStore.localized("settings.gesture_exclusions.editor.empty_selection"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 260)
            } else {
                Text(settingsStore.localized("settings.gesture_exclusions.editor.all_footer"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(settingsStore.localized("settings.gesture_exclusions.editor.cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(settingsStore.localized("settings.gesture_exclusions.editor.save")) {
                    onSave(
                        GestureExclusionRule(
                            application: draft.application,
                            mode: editorMode == .all ? .all : .selected(disabledSelections)
                        )
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(saveDisabled)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func gestureSelectionGroup(
        title: String,
        surface: GestureExclusionSurface,
        gestures: [DockGestureKind]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(gestures) { gesture in
                    Toggle(
                        gesture.title(preferredLanguages: settingsStore.preferredLanguages),
                        isOn: selectionBinding(.standard(gesture, on: surface))
                    )
                }

                Toggle(
                    settingsStore.localized("settings.gesture_exclusions.corner_drag"),
                    isOn: selectionBinding(.cornerDrag(on: surface))
                )
            }
        }
    }

    private func selectionBinding(_ selection: GestureExclusionSelection) -> Binding<Bool> {
        Binding(
            get: { disabledSelections.contains(selection) },
            set: { isSelected in
                if isSelected {
                    disabledSelections.insert(selection)
                } else {
                    disabledSelections.remove(selection)
                }
            }
        )
    }
}

enum GestureExclusionEditorMode: String, CaseIterable, Identifiable {
    case all
    case selected

    var id: String { rawValue }
}

struct ApplicationIcon: View {
    let application: GestureExcludedApplication
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: application.bundleURL.path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private func applicationDisplayName(for bundleURL: URL) -> String {
    let bundle = Bundle(url: bundleURL)
    if let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
       !displayName.isEmpty {
        return displayName
    }
    if let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
       !bundleName.isEmpty {
        return bundleName
    }

    return bundleURL.deletingPathExtension().lastPathComponent
}
