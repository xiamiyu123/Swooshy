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
}

struct StatusMenuContentBuilder {
    func makeEntries(
        permissionGranted: Bool,
        collapseWindowActions: Bool = false,
        localeIdentifier: String? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> [StatusMenuEntry] {
        let permissionMissing = permissionGranted == false
        let localized: (String) -> String = { key in
            L10n.string(
                key,
                localeIdentifier: localeIdentifier,
                preferredLanguages: preferredLanguages
            )
        }

        let actionEntries: [StatusMenuEntry]
        if collapseWindowActions {
            actionEntries = [
                StatusMenuEntry(
                    kind: .windowActionGroup,
                    title: localized("menu.window_actions"),
                    isEnabled: permissionGranted
                )
            ]
        } else {
            actionEntries = WindowAction.allCases.map { action in
                StatusMenuEntry(
                    kind: .windowAction(action),
                    title: action.title(
                        localeIdentifier: localeIdentifier,
                        preferredLanguages: preferredLanguages
                    ),
                    isEnabled: permissionGranted
                )
            }
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
                isEnabled: permissionMissing
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
            )
        ] + actionEntries + [
            StatusMenuEntry(
                kind: .separator,
                title: "",
                isEnabled: false
            ),
            StatusMenuEntry(
                kind: .settings,
                title: localized("menu.settings"),
                isEnabled: permissionGranted
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
                isEnabled: permissionGranted
            ),
        ]
    }
}
