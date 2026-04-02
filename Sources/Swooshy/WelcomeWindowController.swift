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
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reloadLocalizedContent(preservingPageIndex: self.viewModel.currentPageIndex)
            }
        }
    }

    func shutdown() {
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
    }
}

@MainActor
struct WelcomeGuideContent {
    struct Page: Identifiable, Equatable {
        let id: Int
        let kind: WelcomeGuideViewModel.PageKind
        let title: String
        let message: String
        let bullets: [String]
        let imageName: String?
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
        [
            Page(
                id: 0,
                kind: .welcome,
                title: settingsStore.localized("welcome.title"),
                message: settingsStore.localized("welcome.message"),
                bullets: [],
                imageName: nil
            ),
            Page(
                id: 1,
                kind: .tutorial,
                title: settingsStore.localized("guide.page.dock_switch.title"),
                message: settingsStore.localized("guide.page.dock_switch.message"),
                bullets: [
                    settingsStore.localized("guide.page.dock_switch.bullet1"),
                    settingsStore.localized("guide.page.dock_switch.bullet2"),
                ],
                imageName: "step1"
            ),
            Page(
                id: 2,
                kind: .tutorial,
                title: settingsStore.localized("guide.page.dock_visibility.title"),
                message: settingsStore.localized("guide.page.dock_visibility.message"),
                bullets: [
                    settingsStore.localized("guide.page.dock_visibility.bullet1"),
                    settingsStore.localized("guide.page.dock_visibility.bullet2"),
                ],
                imageName: "step4"
            ),
            Page(
                id: 3,
                kind: .tutorial,
                title: settingsStore.localized("guide.page.dock_quit.title"),
                message: settingsStore.localized("guide.page.dock_quit.message"),
                bullets: [
                    settingsStore.localized("guide.page.dock_quit.bullet1"),
                    settingsStore.localized("guide.page.dock_quit.bullet2"),
                    settingsStore.localized("guide.page.dock_quit.bullet3"),
                ],
                imageName: "step5"
            ),
            Page(
                id: 4,
                kind: .tutorial,
                title: settingsStore.localized("guide.page.titlebar_vertical.title"),
                message: settingsStore.localized("guide.page.titlebar_vertical.message"),
                bullets: [
                    settingsStore.localized("guide.page.titlebar_vertical.bullet1"),
                    settingsStore.localized("guide.page.titlebar_vertical.bullet2"),
                    settingsStore.localized("guide.page.titlebar_vertical.bullet3"),
                ],
                imageName: "step2"
            ),
            Page(
                id: 5,
                kind: .tutorial,
                title: settingsStore.localized("guide.page.titlebar_horizontal.title"),
                message: settingsStore.localized("guide.page.titlebar_horizontal.message"),
                bullets: [
                    settingsStore.localized("guide.page.titlebar_horizontal.bullet1"),
                    settingsStore.localized("guide.page.titlebar_horizontal.bullet2"),
                    settingsStore.localized("guide.page.titlebar_horizontal.bullet3"),
                ],
                imageName: "step3"
            ),
            Page(
                id: 6,
                kind: .tutorial,
                title: settingsStore.localized("guide.page.corner_snap.title"),
                message: settingsStore.localized("guide.page.corner_snap.message"),
                bullets: [
                    settingsStore.localized("guide.page.corner_snap.bullet1"),
                    settingsStore.localized("guide.page.corner_snap.bullet2"),
                    settingsStore.localized("guide.page.corner_snap.bullet3"),
                ],
                imageName: "corner-snap-mode"
            ),
            Page(
                id: 7,
                kind: .preference,
                title: settingsStore.localized("guide.page.interaction.title"),
                message: settingsStore.localized("guide.page.interaction.message"),
                bullets: [],
                imageName: nil
            ),
            Page(
                id: 8,
                kind: .tutorial,
                title: settingsStore.localized("guide.page.shortcuts.title"),
                message: settingsStore.localized("guide.page.shortcuts.message"),
                bullets: [
                    settingsStore.localized("guide.page.shortcuts.bullet1"),
                    settingsStore.localized("guide.page.shortcuts.bullet2"),
                    settingsStore.localized("guide.page.shortcuts.bullet3"),
                    settingsStore.localized("guide.page.shortcuts.bullet4"),
                    settingsStore.localized("guide.page.shortcuts.bullet5"),
                    settingsStore.localized("guide.page.shortcuts.bullet6"),
                ],
                imageName: nil
            ),
            Page(
                id: 9,
                kind: .experimental,
                title: settingsStore.localized("guide.page.experimental.title"),
                message: settingsStore.localized("guide.page.experimental.message"),
                bullets: [
                    settingsStore.localized("guide.page.experimental.bullet1"),
                    settingsStore.localized("guide.page.experimental.bullet2"),
                    settingsStore.localized("guide.page.experimental.bullet3"),
                ],
                imageName: nil
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

    var executeGestureOnRelease: Bool {
        get { settingsStore.executeGestureOnRelease }
        set { settingsStore.executeGestureOnRelease = newValue }
    }

    var smartBrowserTabCloseEnabled: Bool {
        get { settingsStore.smartBrowserTabCloseEnabled }
        set { settingsStore.smartBrowserTabCloseEnabled = newValue }
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
        permissionGranted
    }

    var pageIndicatorText: String {
        let pageNumber = currentPageIndex + 1
        return String(format: pageFormat, pageNumber, pages.count)
    }

    func presentWelcome() {
        refreshPermissionState()
        currentPageIndex = 0
    }

    func presentGuide() {
        refreshPermissionState()
        currentPageIndex = min(1, pages.count - 1)
    }

    func goToNextPage() {
        guard isLastPage == false else { return }
        currentPageIndex += 1
    }

    func goToPreviousPage() {
        guard isFirstPage == false else { return }
        currentPageIndex -= 1
    }

    func requestPermission() {
        permissionGranted = permissionManager.isTrusted(promptIfNeeded: true)
        refreshPermissionState()
    }

    func refreshPermissionState() {
        permissionGranted = permissionManager.isTrusted(promptIfNeeded: false)
    }

    func dismiss() {
        onDismiss()
    }

    func openSettings() {
        onOpenSettings()
        onDismiss()
    }

    func localized(_ key: String) -> String {
        settingsStore.localized(key)
    }
}

private struct WelcomeGuideView: View {
    @ObservedObject var viewModel: WelcomeGuideViewModel
    @State private var launchAtLoginController = LaunchAtLoginController()

    private let permissionRefreshTimer = Timer
        .publish(every: 1.0, on: .main, in: .common)
        .autoconnect()

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
        .onReceive(permissionRefreshTimer) { _ in
            guard viewModel.currentPage.kind == .welcome else { return }
            viewModel.refreshPermissionState()
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

            permissionStatus
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

            Spacer(minLength: 0)
        }
    }

    private func experimentalContent(page: WelcomeGuideContent.Page) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(page.message)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(
                    viewModel.localized("settings.experimental.smart_browser_tab_close.enabled"),
                    isOn: $viewModel.smartBrowserTabCloseEnabled
                )
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .padding(.vertical, 8)

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

    private func tutorialContent(page: WelcomeGuideContent.Page) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(page.message)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if let imageName = page.imageName {
                    GuideImageCard(imageName: imageName)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(page.bullets.enumerated()), id: \.offset) { _, bullet in
                        bulletRow(text: bullet)
                    }
                }

                if page.id == 6 {
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
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
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
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
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
               statusMessage.isEmpty == false {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
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
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var footer: some View {
        HStack {
            Button(viewModel.closeActionTitle) {
                viewModel.dismiss()
            }

            Spacer()

            if viewModel.isFirstPage == false {
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
                .disabled(viewModel.canOpenSettings == false)
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
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: maxImageWidth, maxHeight: maxImageHeight)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            } else {
                Text(imageName)
                    .foregroundStyle(.secondary)
                    .frame(width: maxImageWidth, height: 180)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
    private static let supportedExtensions = ["gif", "jpg", "jpeg", "png"]

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
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
