import Foundation

struct StatusMenuEntry: Equatable {
    enum Kind: Equatable {
        case title
        case permission
        case refresh
        case windowAction(WindowAction)
        case windowActionGroup
        case settings
        case help
        case quit
        case separator
    }

    let kind: Kind
    let title: String
    let isEnabled: Bool
    let hotKeyIssue: HotKeyRegistrationIssueKind?

    static let separator = StatusMenuEntry(
        kind: .separator,
        title: "",
        isEnabled: false
    )

    init(
        kind: Kind,
        title: String,
        isEnabled: Bool,
        hotKeyIssue: HotKeyRegistrationIssueKind? = nil
    ) {
        self.kind = kind
        self.title = title
        self.isEnabled = isEnabled
        self.hotKeyIssue = hotKeyIssue
    }
}

struct StatusMenuContentBuilder {
    func makeEntries(
        permissionGranted: Bool,
        collapseWindowActions: Bool = false,
        windowActions: [WindowAction] = WindowAction.allCases,
        localeIdentifier: String? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages,
        hotKeyIssueForAction: (WindowAction) -> HotKeyRegistrationIssueKind? = { _ in nil }
    ) -> [StatusMenuEntry] {
        let permissionMissing = !permissionGranted
        let localized: (String) -> String = { key in
            L10n.string(
                key,
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        }
        func entry(
            kind: StatusMenuEntry.Kind,
            titleKey: String,
            isEnabled: Bool,
            hotKeyIssue: HotKeyRegistrationIssueKind? = nil
        ) -> StatusMenuEntry {
            StatusMenuEntry(
                kind: kind,
                title: localized(titleKey),
                isEnabled: isEnabled,
                hotKeyIssue: hotKeyIssue
            )
        }
        let actionEntries = if collapseWindowActions {
            [
                entry(
                    kind: .windowActionGroup,
                    titleKey: "menu.window_actions",
                    isEnabled: permissionGranted,
                    hotKeyIssue: firstHotKeyIssue(
                        for: windowActions,
                        hotKeyIssueForAction: hotKeyIssueForAction
                    )
                )
            ]
        } else {
            makeWindowActionEntries(
                permissionGranted: permissionGranted,
                windowActions: windowActions,
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages,
                hotKeyIssueForAction: hotKeyIssueForAction
            )
        }

        return [
            entry(
                kind: .title,
                titleKey: "menu.app_name",
                isEnabled: false
            ),
            entry(
                kind: .permission,
                titleKey: permissionGranted ? "menu.permission.ready" : "menu.permission.grant",
                isEnabled: permissionMissing
            ),
            entry(
                kind: .refresh,
                titleKey: "menu.permission.refresh",
                isEnabled: true
            ),
            .separator,
        ] + actionEntries + [
            .separator,
            entry(
                kind: .settings,
                titleKey: "menu.settings",
                isEnabled: true
            ),
            .separator,
            entry(
                kind: .help,
                titleKey: "menu.help",
                isEnabled: true
            ),
            entry(
                kind: .quit,
                titleKey: "menu.quit",
                isEnabled: true
            ),
        ]
    }

    func makeWindowActionEntries(
        permissionGranted: Bool,
        windowActions: [WindowAction] = WindowAction.allCases,
        localeIdentifier: String? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages,
        hotKeyIssueForAction: (WindowAction) -> HotKeyRegistrationIssueKind? = { _ in nil }
    ) -> [StatusMenuEntry] {
        windowActions.map { action in
            StatusMenuEntry(
                kind: .windowAction(action),
                title: action.title(
                    localeIdentifier: localeIdentifier,
                    preferredLanguages: preferredLanguages
                ),
                isEnabled: permissionGranted,
                hotKeyIssue: hotKeyIssueForAction(action)
            )
        }
    }

    private func firstHotKeyIssue(
        for windowActions: [WindowAction],
        hotKeyIssueForAction: (WindowAction) -> HotKeyRegistrationIssueKind?
    ) -> HotKeyRegistrationIssueKind? {
        for action in windowActions {
            if let issue = hotKeyIssueForAction(action) {
                return issue
            }
        }

        return nil
    }
}
