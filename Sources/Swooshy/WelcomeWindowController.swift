import AppKit
import Combine
import SwiftUI

@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let settingsStore: SettingsStore
    private let permissionManager: AccessibilityPermissionManaging
    private let onOpenSettings: () -> Void
    private let hostingController: NSHostingController<WelcomeGuideView>
    private var settingsObserver: NSObjectProtocol?
    private var viewModel: WelcomeGuideViewModel

    init(
        settingsStore: SettingsStore,
        permissionManager: AccessibilityPermissionManaging,
        onOpenSettings: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.permissionManager = permissionManager
        self.onOpenSettings = onOpenSettings

        let viewModel = WelcomeGuideViewModel(
            settingsStore: settingsStore,
            permissionManager: permissionManager,
            onOpenSettings: onOpenSettings,
            onDismiss: {}
        )
        self.viewModel = viewModel
        self.hostingController = NSHostingController(
            rootView: WelcomeGuideView(viewModel: viewModel)
        )
        let window = NSWindow(contentViewController: hostingController)

        window.setContentSize(NSSize(width: 760, height: 720))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.title = viewModel.windowTitle

        super.init(window: window)
        self.window?.delegate = self

        reloadLocalizedContent(preservingPageIndex: 0)
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: settingsStore,
            queue: .main
        ) { [weak self] notification in
            let categories = notification.settingsChangeCategories
            MainActor.assumeIsolated {
                guard let self else { return }
                guard categories.contains(.localization) else {
                    return
                }
                self.reloadLocalizedContent(preservingPageIndex: self.viewModel.currentPageIndex)
            }
        }
    }

    func shutdown() {
        viewModel.endPresentation()
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
        reloadLocalizedContent(preservingPageIndex: 0)
        viewModel.presentWelcome()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func showGuide() {
        reloadLocalizedContent(preservingPageIndex: 1)
        viewModel.presentGuide()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func reloadLocalizedContent(preservingPageIndex: Int? = nil) {
        viewModel.endPresentation()
        let viewModel = WelcomeGuideViewModel(
            settingsStore: settingsStore,
            permissionManager: permissionManager,
            onOpenSettings: onOpenSettings,
            onDismiss: { [weak self] in
                self?.window?.close()
            }
        )
        if let preservingPageIndex {
            viewModel.currentPageIndex = min(preservingPageIndex, viewModel.pages.count - 1)
        }

        self.viewModel = viewModel
        hostingController.rootView = WelcomeGuideView(viewModel: viewModel)
        window?.title = viewModel.windowTitle
        if window?.isVisible == true {
            viewModel.resumePresentation()
        }
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.endPresentation()
    }
}

@MainActor
struct WelcomeGuideContent {
    struct Page: Identifiable, Equatable {
        enum Visual: Equatable {
            case none
            case image(String)
            case cornerSnapGesturePreview
        }

        let id: Int
        let kind: WelcomeGuideViewModel.PageKind
        let title: String
        let message: String
        let bullets: [String]
        let visual: Visual
        let showsPermissionStatus: Bool
    }

    let windowTitle: String
    let welcomeTitle: String
    let welcomeMessage: String
    let permissionStep: String
    let settingsStep: String
    let permissionGrantedText: String
    let permissionMissingText: String
    let permissionTroubleshootingText: String
    let grantPermissionActionTitle: String
    let refreshPermissionActionTitle: String
    let openSettingsActionTitle: String
    let nextActionTitle: String
    let previousActionTitle: String
    let closeActionTitle: String
    let pageFormat: String
    let guideTitle: String
    let nextPreviewTitle: String
    let pages: [Page]

    static func make(settingsStore: SettingsStore) -> Self {
        Self(
            windowTitle: settingsStore.localized("welcome.window.title"),
            welcomeTitle: settingsStore.localized("welcome.title"),
            welcomeMessage: settingsStore.localized("welcome.message"),
            permissionStep: settingsStore.localized("welcome.step.permission"),
            settingsStep: settingsStore.localized("welcome.step.settings"),
            permissionGrantedText: settingsStore.localized("welcome.permission.granted"),
            permissionMissingText: settingsStore.localized("welcome.permission.missing"),
            permissionTroubleshootingText: settingsStore.localized("welcome.permission.troubleshooting"),
            grantPermissionActionTitle: settingsStore.localized("welcome.grant_permission_action"),
            refreshPermissionActionTitle: settingsStore.localized("welcome.refresh_permission_action"),
            openSettingsActionTitle: settingsStore.localized("welcome.open_settings_action"),
            nextActionTitle: settingsStore.localized("guide.next_action"),
            previousActionTitle: settingsStore.localized("guide.previous_action"),
            closeActionTitle: settingsStore.localized("guide.close_action"),
            pageFormat: settingsStore.localized("guide.page_format"),
            guideTitle: settingsStore.localized("menu.help"),
            nextPreviewTitle: settingsStore.localized("guide.next_preview"),
            pages: makePages(settingsStore: settingsStore)
        )
    }

    private static func makePages(settingsStore: SettingsStore) -> [Page] {
        func localized(_ key: String) -> String {
            settingsStore.localized(key)
        }

        func guidePage(
            id: Int,
            kind: WelcomeGuideViewModel.PageKind,
            key: String,
            bulletCount: Int = 0,
            visual: Page.Visual = .none
        ) -> Page {
            let localizationKey = "guide.page.\(key)"
            return Page(
                id: id,
                kind: kind,
                title: localized("\(localizationKey).title"),
                message: localized("\(localizationKey).message"),
                bullets: (0..<bulletCount).map { localized("\(localizationKey).bullet\($0 + 1)") },
                visual: visual,
                showsPermissionStatus: false
            )
        }

        return [
            Page(
                id: 0,
                kind: .welcome,
                title: localized("welcome.title"),
                message: localized("welcome.message"),
                bullets: [],
                visual: .none,
                showsPermissionStatus: true
            ),
            guidePage(
                id: 1,
                kind: .tutorial,
                key: "dock_switch",
                bulletCount: 2,
                visual: .image("step1")
            ),
            guidePage(
                id: 2,
                kind: .tutorial,
                key: "dock_visibility",
                bulletCount: 2,
                visual: .image("step4")
            ),
            guidePage(
                id: 3,
                kind: .tutorial,
                key: "dock_quit",
                bulletCount: 3,
                visual: .image("step5")
            ),
            guidePage(
                id: 4,
                kind: .tutorial,
                key: "titlebar_vertical",
                bulletCount: 3,
                visual: .image("step2")
            ),
            guidePage(
                id: 5,
                kind: .tutorial,
                key: "titlebar_horizontal",
                bulletCount: 3,
                visual: .image("step3")
            ),
            guidePage(
                id: 6,
                kind: .tutorial,
                key: "corner_snap",
                bulletCount: 3,
                visual: .cornerSnapGesturePreview
            ),
            guidePage(
                id: 7,
                kind: .preference,
                key: "interaction"
            ),
            guidePage(
                id: 8,
                kind: .tutorial,
                key: "shortcuts",
                bulletCount: 7
            ),
            guidePage(
                id: 9,
                kind: .tutorial,
                key: "danger_confirmation",
                bulletCount: 4
            ),
            guidePage(
                id: 10,
                kind: .experimental,
                key: "experimental",
                bulletCount: 4
            ),
        ]
    }
}

@MainActor
final class WelcomeGuideViewModel: ObservableObject {
    enum PageKind {
        case welcome
        case tutorial
        case preference
        case experimental
    }

    @Published var currentPageIndex: Int = 0
    @Published var permissionGranted: Bool

    let content: WelcomeGuideContent

    private let settingsStore: SettingsStore
    private let permissionManager: AccessibilityPermissionManaging
    private let onOpenSettings: () -> Void
    private let onDismiss: () -> Void
    private var isPresented = false
    private var permissionRefreshTask: Task<Void, Never>?

    init(
        settingsStore: SettingsStore,
        permissionManager: AccessibilityPermissionManaging,
        onOpenSettings: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.content = WelcomeGuideContent.make(settingsStore: settingsStore)
        self.permissionManager = permissionManager
        self.onOpenSettings = onOpenSettings
        self.onDismiss = onDismiss
        self.permissionGranted = permissionManager.isTrusted(promptIfNeeded: false)
    }

    deinit {
        permissionRefreshTask?.cancel()
    }

    // Deprecated: onboarding still proxies the legacy preview-mode toggle until
    // the release-deferred gesture path is removed from runtime settings.
    var executeGestureOnRelease: Bool {
        get { settingsStore.executeGestureOnRelease }
        set {
            guard settingsStore.executeGestureOnRelease != newValue else { return }
            objectWillChange.send()
            settingsStore.executeGestureOnRelease = newValue
        }
    }

    var gestureHUDStyle: GestureHUDStyle {
        get { settingsStore.gestureHUDStyle }
        set {
            guard settingsStore.gestureHUDStyle != newValue else { return }
            objectWillChange.send()
            settingsStore.gestureHUDStyle = newValue
        }
    }

    var experimentalBrowserTabCloseEnabled: Bool {
        get { settingsStore.experimentalBrowserTabCloseEnabled }
        set {
            guard settingsStore.experimentalBrowserTabCloseEnabled != newValue else { return }
            objectWillChange.send()
            settingsStore.experimentalBrowserTabCloseEnabled = newValue
        }
    }

    var experimentalDisplayMoveActionsEnabled: Bool {
        get { settingsStore.experimentalDisplayMoveActionsEnabled }
        set {
            guard settingsStore.experimentalDisplayMoveActionsEnabled != newValue else { return }
            objectWillChange.send()
            settingsStore.experimentalDisplayMoveActionsEnabled = newValue
        }
    }

    var smartBrowserTabCloseEnabled: Bool {
        get { settingsStore.smartBrowserTabCloseEnabled }
        set {
            guard settingsStore.smartBrowserTabCloseEnabled != newValue else { return }
            objectWillChange.send()
            settingsStore.smartBrowserTabCloseEnabled = newValue
        }
    }

    var windowTitle: String { content.windowTitle }
    var welcomeTitle: String { content.welcomeTitle }
    var welcomeMessage: String { content.welcomeMessage }
    var permissionStep: String { content.permissionStep }
    var settingsStep: String { content.settingsStep }
    var permissionGrantedText: String { content.permissionGrantedText }
    var permissionMissingText: String { content.permissionMissingText }
    var permissionTroubleshootingText: String { content.permissionTroubleshootingText }
    var grantPermissionActionTitle: String { content.grantPermissionActionTitle }
    var refreshPermissionActionTitle: String { content.refreshPermissionActionTitle }
    var openSettingsActionTitle: String { content.openSettingsActionTitle }
    var nextActionTitle: String { content.nextActionTitle }
    var previousActionTitle: String { content.previousActionTitle }
    var closeActionTitle: String { content.closeActionTitle }
    var pageFormat: String { content.pageFormat }
    var guideTitle: String { content.guideTitle }
    var nextPreviewTitle: String { content.nextPreviewTitle }
    var pages: [WelcomeGuideContent.Page] { content.pages }

    var currentPage: WelcomeGuideContent.Page {
        content.pages[currentPageIndex]
    }

    var isFirstPage: Bool {
        currentPageIndex == 0
    }

    var isLastPage: Bool {
        currentPageIndex == pages.count - 1
    }

    var canOpenSettings: Bool {
        true
    }

    var pageIndicatorText: String {
        let pageNumber = currentPageIndex + 1
        return String(format: pageFormat, pageNumber, pages.count)
    }

    func presentWelcome() {
        isPresented = true
        currentPageIndex = 0
        refreshPermissionState()
        syncPermissionPolling()
    }

    func presentGuide() {
        isPresented = true
        currentPageIndex = min(1, pages.count - 1)
        refreshPermissionState()
        syncPermissionPolling()
    }

    func goToNextPage() {
        guard !isLastPage else { return }
        currentPageIndex += 1
        syncPermissionPolling()
    }

    func goToPreviousPage() {
        guard !isFirstPage else { return }
        currentPageIndex -= 1
        syncPermissionPolling()
    }

    func requestPermission() {
        permissionGranted = permissionManager.requestAccess()
        refreshPermissionState()
    }

    func refreshPermissionState() {
        let nextPermissionGranted = permissionManager.isTrusted(promptIfNeeded: false)
        guard permissionGranted != nextPermissionGranted else { return }
        permissionGranted = nextPermissionGranted
    }

    func dismiss() {
        endPresentation()
        onDismiss()
    }

    func openSettings() {
        endPresentation()
        onOpenSettings()
        onDismiss()
    }

    func resumePresentation() {
        isPresented = true
        refreshPermissionState()
        syncPermissionPolling()
    }

    func endPresentation() {
        isPresented = false
        stopPermissionPolling()
    }

    private func syncPermissionPolling() {
        guard isPresented, currentPage.kind == .welcome else {
            stopPermissionPolling()
            return
        }

        startPermissionPollingIfNeeded()
    }

    private func startPermissionPollingIfNeeded() {
        guard permissionRefreshTask == nil else {
            return
        }

        permissionRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }

                guard let self else {
                    return
                }
                guard self.isPresented, self.currentPage.kind == .welcome else {
                    self.stopPermissionPolling()
                    return
                }
                self.refreshPermissionState()
            }
        }
    }

    private func stopPermissionPolling() {
        permissionRefreshTask?.cancel()
        permissionRefreshTask = nil
    }

    func localized(_ key: String) -> String {
        settingsStore.localized(key)
    }

    func title(for gestureHUDStyle: GestureHUDStyle) -> String {
        gestureHUDStyle.title(preferredLanguages: settingsStore.preferredLanguages)
    }

    var gesturePreviewItems: [GestureHUDPreviewItem] {
        [DockGestureKind.pinchIn, .swipeUp].map { gesture in
            GestureHUDPreviewItem(
                style: gestureHUDStyle,
                gesture: gesture,
                gestureTitle: gesture.title(preferredLanguages: settingsStore.preferredLanguages),
                actionTitle: settingsStore.dockGestureAction(for: gesture)
                    .title(preferredLanguages: settingsStore.preferredLanguages)
            )
        }
    }
}

private struct WelcomeGuideView: View {
    @ObservedObject var viewModel: WelcomeGuideViewModel
    @State private var launchAtLoginController = LaunchAtLoginController()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Group {
                switch viewModel.currentPage.kind {
                case .welcome:
                    welcomeContent
                case .tutorial:
                    tutorialContent(page: viewModel.currentPage)
                case .preference:
                    preferenceContent
                case .experimental:
                    experimentalContent(page: viewModel.currentPage)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            footer
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: viewModel.refreshPermissionState)
        .onAppear {
            launchAtLoginController.refresh(localize: viewModel.localized)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.currentPage.title)
                    .font(.system(size: 28, weight: .semibold))
                Text(viewModel.currentPage.kind == .welcome ? viewModel.windowTitle : viewModel.guideTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(viewModel.pageIndicatorText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(viewModel.welcomeMessage)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                stepRow(index: 1, text: viewModel.permissionStep)
                stepRow(index: 2, text: viewModel.settingsStep)
                stepRow(index: 3, text: viewModel.nextActionTitle)
            }

            if viewModel.currentPage.showsPermissionStatus {
                permissionStatus
            }
            permissionTroubleshootingNotice
            launchAtLoginSection

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            tutorialPreview
        }
    }

    private var preferenceContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(viewModel.currentPage.message)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            // Deprecated: keep this onboarding choice in sync with the legacy
            // preview-mode setting until the runtime path is fully deleted.
            HStack(spacing: 20) {
                InteractionStyleCard(
                    title: viewModel.localized("guide.page.interaction.immediate.title"),
                    description: viewModel.localized("guide.page.interaction.immediate.description"),
                    systemImage: "bolt.fill",
                    isSelected: !viewModel.executeGestureOnRelease,
                    action: { viewModel.executeGestureOnRelease = false }
                )

                InteractionStyleCard(
                    title: viewModel.localized("guide.page.interaction.on_release.title"),
                    description: viewModel.localized("guide.page.interaction.on_release.description"),
                    systemImage: "hand.raised.fill",
                    isSelected: viewModel.executeGestureOnRelease,
                    action: { viewModel.executeGestureOnRelease = true }
                )
            }
            .frame(maxWidth: .infinity)

            hudStyleSection

            Spacer(minLength: 0)
        }
    }

    private var hudStyleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.localized("settings.gesture_hud.style.label"))
                .font(.headline)

            Picker(
                viewModel.localized("settings.gesture_hud.style.label"),
                selection: Binding(
                    get: { viewModel.gestureHUDStyle },
                    set: { viewModel.gestureHUDStyle = $0 }
                )
            ) {
                ForEach(GestureHUDStyle.allCases) { style in
                    Text(viewModel.title(for: style)).tag(style)
                }
            }
            .pickerStyle(.menu)

            Text(viewModel.localized("settings.gesture_hud.footer"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GestureHUDPreviewStrip(items: viewModel.gesturePreviewItems)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardBackground(cornerRadius: 14)
    }

    private func experimentalContent(page: WelcomeGuideContent.Page) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(page.message)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    experimentalToggleCard(
                        title: viewModel.localized("settings.experimental.display_move_actions.enabled"),
                        isOn: $viewModel.experimentalDisplayMoveActionsEnabled,
                        footer: viewModel.localized("settings.experimental.display_move_actions.footer")
                    )

                    experimentalToggleCard(
                        title: viewModel.localized("settings.experimental.browser_tab_close.enabled"),
                        isOn: $viewModel.experimentalBrowserTabCloseEnabled,
                        footer: viewModel.localized("settings.experimental.browser_tab_close.footer")
                    )

                    experimentalToggleCard(
                        title: viewModel.localized("settings.experimental.smart_browser_tab_close.enabled"),
                        isOn: $viewModel.smartBrowserTabCloseEnabled,
                        footer: viewModel.localized("settings.experimental.smart_browser_tab_close.footer"),
                        isEnabled: viewModel.experimentalBrowserTabCloseEnabled
                    )

                }

                Text(viewModel.localized("settings.experimental.opt_in_persistence.footer"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(page.bullets.enumerated()), id: \.offset) { _, bullet in
                        bulletRow(text: bullet)
                    }
                }
            }
            .padding(.trailing, 10)
        }
    }

    private func experimentalToggleCard(
        title: String,
        isOn: Binding<Bool>,
        footer: String,
        isEnabled: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(title, isOn: isOn)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardBackground(cornerRadius: 12)
        .opacity(isEnabled ? 1 : 0.65)
        .disabled(!isEnabled)
    }

    private func tutorialContent(page: WelcomeGuideContent.Page) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(page.message)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                switch page.visual {
                case .cornerSnapGesturePreview:
                    CornerSnapGesturePreviewCard(localized: viewModel.localized)
                case .image(let imageName):
                    GuideImageCard(imageName: imageName)
                case .none:
                    EmptyView()
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(page.bullets.enumerated()), id: \.offset) { _, bullet in
                        bulletRow(text: bullet)
                    }
                }

                if page.showsPermissionStatus {
                    permissionStatus
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 4)
        }
    }

    private var tutorialPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.nextPreviewTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(viewModel.guideTitle)
                .font(.headline)

            Text(viewModel.currentPage.kind == .welcome ? viewModel.pages[1].message : "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(["step1", "step2"], id: \.self) { imageName in
                    GuideThumbnail(imageName: imageName)
                }
            }
        }
        .padding(16)
        .frame(width: 228, alignment: .leading)
        .glassCardBackground(cornerRadius: 16)
        .padding(.trailing, 12)
        .padding(.bottom, 12)
    }

    private var permissionStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.permissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(viewModel.permissionGranted ? Color.green : Color.orange)
            Text(viewModel.permissionGranted ? viewModel.permissionGrantedText : viewModel.permissionMissingText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(viewModel.refreshPermissionActionTitle) {
                viewModel.refreshPermissionState()
            }
            .controlSize(.small)
        }
        .padding(14)
        .glassCardBackground(cornerRadius: 14)
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                viewModel.localized("settings.launch_at_login.enabled"),
                isOn: Binding(
                    get: { launchAtLoginController.isEnabled },
                    set: { launchAtLoginController.setEnabled($0, localize: viewModel.localized) }
                )
            )

            Text(viewModel.localized("settings.launch_at_login.footer"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let statusMessage = launchAtLoginController.statusMessage,
               !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassCardBackground(cornerRadius: 14)
    }

    private var permissionTroubleshootingNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Text(viewModel.permissionTroubleshootingText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .glassCardBackground(cornerRadius: 14)
    }

    private var footer: some View {
        HStack {
            Button(viewModel.closeActionTitle) {
                viewModel.dismiss()
            }

            Spacer()

            if !viewModel.isFirstPage {
                Button(viewModel.previousActionTitle) {
                    viewModel.goToPreviousPage()
                }
            }

            if viewModel.currentPage.kind == .welcome {
                Button(viewModel.grantPermissionActionTitle) {
                    viewModel.requestPermission()
                }
                .disabled(viewModel.permissionGranted)
            }

            if viewModel.isLastPage {
                Button(viewModel.openSettingsActionTitle) {
                    viewModel.openSettings()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canOpenSettings)
            } else {
                Button(viewModel.nextActionTitle) {
                    viewModel.goToNextPage()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func stepRow(index: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index).")
                .font(.headline)
                .frame(width: 22, alignment: .leading)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func bulletRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .padding(.top, 7)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct GuideImageCard: View {
    let imageName: String
    private let maxImageWidth: CGFloat = 360
    private let maxImageHeight: CGFloat = 260

    var body: some View {
        Group {
            if let image = guideImage(named: imageName) {
                let displaySize = fittedSize(for: image)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: displaySize.width, height: displaySize.height)
            } else {
                Text(imageName)
                    .foregroundStyle(.secondary)
                    .frame(width: maxImageWidth, height: 180)
            }
        }
        .padding(12)
        .glassCardBackground(cornerRadius: 16)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func fittedSize(for image: NSImage) -> CGSize {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: maxImageWidth, height: 180)
        }

        let scale = min(maxImageWidth / imageSize.width, maxImageHeight / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

private struct CornerSnapGesturePreviewCard: View {
    let localized: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.08))

                windowPreview
                dockPreview
                gesturePath
                cornerTargets
                instructionBadge
            }
            .frame(width: 420, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            HStack(spacing: 10) {
                previewLegendItem(index: 1, text: localized("guide.page.corner_snap.preview.hover"))
                previewLegendItem(index: 2, text: localized("guide.page.corner_snap.preview.hold"))
                previewLegendItem(index: 3, text: localized("guide.page.corner_snap.preview.drag"))
            }
            .frame(width: 420, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var windowPreview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(.red.opacity(0.85)).frame(width: 7, height: 7)
                Circle().fill(.yellow.opacity(0.9)).frame(width: 7, height: 7)
                Circle().fill(.green.opacity(0.85)).frame(width: 7, height: 7)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.13))
                    .frame(width: 150, height: 8)
                    .padding(.leading, 6)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color(red: 0.92, green: 0.95, blue: 0.99))

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.black.opacity(0.14))
                    .frame(width: 180, height: 12)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 250, height: 10)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 220, height: 10)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white)
        }
        .frame(width: 300, height: 166)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .offset(x: -34, y: -20)
    }

    private var dockPreview: some View {
        HStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(index == 2 ? Color.white.opacity(0.24) : Color.white.opacity(0.13))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: index == 2 ? "cursorarrow.motionlines" : "app.dashed")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(index == 2 ? 0.92 : 0.54))
                    )
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .offset(x: 72, y: 78)
    }

    private var gesturePath: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 210, y: 34))
                path.addQuadCurve(to: CGPoint(x: 316, y: 44), control: CGPoint(x: 258, y: 18))
            }
            .stroke(
                Color.white.opacity(0.82),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [8, 8])
            )

            Image(systemName: "arrow.up.right")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.9))
                .position(x: 320, y: 42)

            HStack(spacing: 8) {
                touchDot
                touchDot
            }
            .position(x: 210, y: 34)

            Text("0.2s")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.5), in: Capsule())
                .position(x: 210, y: 58)
        }
    }

    private var cornerTargets: some View {
        ZStack {
            ForEach(Array(cornerTargetOffsets.enumerated()), id: \.offset) { _, offset in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.38), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(width: 74, height: 54)
                    .offset(x: offset.x, y: offset.y)
            }
        }
    }

    private var cornerTargetOffsets: [CGPoint] {
        [
            CGPoint(x: 134, y: -78),
            CGPoint(x: 134, y: 78),
            CGPoint(x: -134, y: -78),
            CGPoint(x: -134, y: 78),
        ]
    }

    private var instructionBadge: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(localized("guide.page.corner_snap.preview.hold"), systemImage: "hand.point.up.left.fill")
            Label(localized("guide.page.corner_snap.preview.drag"), systemImage: "arrow.up.right")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.white.opacity(0.88))
        .padding(10)
        .background(Color.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .offset(x: 88, y: -16)
    }

    private var touchDot: some View {
        Circle()
            .fill(Color.white.opacity(0.92))
            .frame(width: 16, height: 16)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 5)
    }

    private func previewLegendItem(index: Int, text: String) -> some View {
        HStack(spacing: 6) {
            Text("\(index)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.primary.opacity(0.72)))

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct GuideThumbnail: View {
    let imageName: String
    private let width: CGFloat = 94
    private let height: CGFloat = 58

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))

            if let image = guideImage(named: imageName) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: width - 10, maxHeight: height - 10)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

@MainActor
private func guideImage(named name: String) -> NSImage? {
    GuideImageCache.shared.image(named: name)
}

@MainActor
private final class GuideImageCache {
    static let shared = GuideImageCache()
    private static let supportedExtensions = ["jpg", "jpeg", "png"]

    private var cache: [String: NSImage] = [:]

    func image(named name: String) -> NSImage? {
        if let cached = cache[name] {
            return cached
        }

        for fileExtension in Self.supportedExtensions {
            guard let url = Bundle.appResources.url(forResource: name, withExtension: fileExtension) else {
                continue
            }

            guard let image = NSImage(contentsOf: url) else {
                continue
            }

            cache[name] = image
            return image
        }
        return nil
    }
}

private struct InteractionStyleCard: View {
    let title: String
    let description: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Circle()
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            .frame(width: 20, height: 20)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(18)
            .selectableCardBackground(isSelected: isSelected, cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
