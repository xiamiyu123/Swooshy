import AppKit
import Combine
import SwiftUI

@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: WelcomeGuideViewModel

    init(
        settingsStore: SettingsStore,
        permissionManager: AccessibilityPermissionManaging,
        onOpenSettings: @escaping () -> Void
    ) {
        var windowReference: NSWindow?
        let viewModel = WelcomeGuideViewModel(
            settingsStore: settingsStore,
            permissionManager: permissionManager,
            onOpenSettings: onOpenSettings,
            onDismiss: {
                windowReference?.close()
            }
        )
        self.viewModel = viewModel

        let hostingController = NSHostingController(
            rootView: WelcomeGuideView(viewModel: viewModel)
        )
        let window = NSWindow(contentViewController: hostingController)
        windowReference = window

        window.setContentSize(NSSize(width: 760, height: 720))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.title = settingsStore.localized("welcome.window.title")

        super.init(window: window)
        self.window?.delegate = self
    }

    func shutdown() {
        window?.delegate = nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func show() {
        viewModel.presentWelcome()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func showGuide() {
        viewModel.presentGuide()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class WelcomeGuideViewModel: ObservableObject {
    enum PageKind {
        case welcome
        case tutorial
    }

    struct Page: Identifiable {
        let id: Int
        let kind: PageKind
        let title: String
        let message: String
        let bullets: [String]
        let imageName: String?
    }

    @Published var currentPageIndex: Int = 0
    @Published var permissionGranted: Bool

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
        self.windowTitle = settingsStore.localized("welcome.window.title")
        self.welcomeTitle = settingsStore.localized("welcome.title")
        self.welcomeMessage = settingsStore.localized("welcome.message")
        self.permissionStep = settingsStore.localized("welcome.step.permission")
        self.settingsStep = settingsStore.localized("welcome.step.settings")
        self.permissionGrantedText = settingsStore.localized("welcome.permission.granted")
        self.permissionMissingText = settingsStore.localized("welcome.permission.missing")
        self.permissionTroubleshootingText = settingsStore.localized("welcome.permission.troubleshooting")
        self.grantPermissionActionTitle = settingsStore.localized("welcome.grant_permission_action")
        self.refreshPermissionActionTitle = settingsStore.localized("welcome.refresh_permission_action")
        self.openSettingsActionTitle = settingsStore.localized("welcome.open_settings_action")
        self.nextActionTitle = settingsStore.localized("guide.next_action")
        self.previousActionTitle = settingsStore.localized("guide.previous_action")
        self.closeActionTitle = settingsStore.localized("guide.close_action")
        self.pageFormat = settingsStore.localized("guide.page_format")
        self.guideTitle = settingsStore.localized("menu.help")
        self.nextPreviewTitle = settingsStore.localized("guide.next_preview")
        self.permissionManager = permissionManager
        self.onOpenSettings = onOpenSettings
        self.onDismiss = onDismiss
        self.permissionGranted = permissionManager.isTrusted(promptIfNeeded: false)
        self.pages = Self.makePages(settingsStore: settingsStore)
    }

    var currentPage: Page {
        pages[currentPageIndex]
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
                ],
                imageName: "step3"
            ),
            Page(
                id: 6,
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
        ]
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

    private func tutorialContent(page: WelcomeGuideViewModel.Page) -> some View {
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

    private var cache: [String: NSImage] = [:]

    func image(named name: String) -> NSImage? {
        if let cached = cache[name] {
            return cached
        }

        guard let url = Bundle.appResources.url(forResource: name, withExtension: "jpg") else {
            return nil
        }

        guard let image = NSImage(contentsOf: url) else {
            return nil
        }

        cache[name] = image
        return image
    }
}
