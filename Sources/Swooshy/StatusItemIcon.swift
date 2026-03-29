import AppKit

enum StatusItemIcon: String, CaseIterable, Codable, Identifiable, Sendable {
    case swooshy = "swooshy"
    case gale = "gale"
    case groupedWindows = "grouped_windows"
    case splitView = "split_view"
    case stackedWindows = "stacked_windows"
    case focusedWindow = "focused_window"
    case windowGrid = "window_grid"

    var id: Self { self }

    init(storageValue: String?) {
        self = StatusItemIcon(rawValue: storageValue ?? "") ?? .groupedWindows
    }

    var storageValue: String {
        rawValue
    }

    var symbolName: String? {
        switch self {
        case .swooshy, .gale:
            return nil
        case .groupedWindows:
            return "rectangle.3.group"
        case .splitView:
            return "rectangle.split.2x1"
        case .stackedWindows:
            return "rectangle.on.rectangle"
        case .focusedWindow:
            return "macwindow.on.rectangle"
        case .windowGrid:
            return "square.grid.2x2"
        }
    }

    func title(
        localeIdentifier: String? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        L10n.string(
            "settings.status_item_icon.\(storageValue)",
            localeIdentifier: localeIdentifier,
            preferredLanguages: preferredLanguages
        )
    }

    func makeImage(accessibilityDescription: String) -> NSImage? {
        switch self {
        case .swooshy:
            return StatusItemTemplateImage.loadTemplateImage(
                named: "SwooshyStatusTemplate",
                accessibilityDescription: accessibilityDescription
            )
        case .gale:
            if let image = StatusItemTemplateImage.loadTemplateImage(
                named: "GaleStatusTemplate",
                accessibilityDescription: accessibilityDescription
            ) {
                return image
            }

            return StatusItemTemplateImage.makeGaleTemplateImage()
        case .groupedWindows, .splitView, .stackedWindows, .focusedWindow, .windowGrid:
            guard
                let symbolName,
                let image = NSImage(
                    systemSymbolName: symbolName,
                    accessibilityDescription: accessibilityDescription
                )
            else {
                return nil
            }

            image.isTemplate = true
            return image
        }
    }
}
