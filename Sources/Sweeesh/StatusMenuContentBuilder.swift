import Foundation

struct StatusMenuEntry: Equatable {
    enum Kind: Equatable {
        case title
        case permission
        case refresh
        case windowAction(WindowAction)
        case settings
        case help
        case quit
        case separator
    }

    let kind: Kind
    let title: String
    let isEnabled: Bool
}

struct StatusMenuContentBuilder {
    func makeEntries(
        permissionGranted: Bool,
        localeIdentifier: String? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> [StatusMenuEntry] {
        let localized: (String) -> String = { key in
            L10n.string(
                key,
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        }

        let actions = WindowAction.allCases.map { action in
            StatusMenuEntry(
                kind: .windowAction(action),
                title: action.title(
                    localeIdentifier: localeIdentifier,
                    preferredLanguages: preferredLanguages
                ),
                isEnabled: permissionGranted
            )
        }

        return [
            StatusMenuEntry(
                kind: .title,
                title: localized("menu.app_name"),
                isEnabled: false
            ),
            StatusMenuEntry(
                kind: .permission,
                title: localized(
                    permissionGranted ? "menu.permission.ready" : "menu.permission.grant"
                ),
                isEnabled: !permissionGranted
            ),
            StatusMenuEntry(
                kind: .refresh,
                title: localized("menu.permission.refresh"),
                isEnabled: true
            ),
            StatusMenuEntry(
                kind: .separator,
                title: "",
                isEnabled: false
            ),
        ] + actions + [
            StatusMenuEntry(
                kind: .separator,
                title: "",
                isEnabled: false
            ),
            StatusMenuEntry(
                kind: .settings,
                title: localized("menu.settings"),
                isEnabled: true
            ),
            StatusMenuEntry(
                kind: .separator,
                title: "",
                isEnabled: false
            ),
            StatusMenuEntry(
                kind: .help,
                title: localized("menu.help"),
                isEnabled: true
            ),
            StatusMenuEntry(
                kind: .quit,
                title: localized("menu.quit"),
                isEnabled: true
            ),
        ]
    }
}
