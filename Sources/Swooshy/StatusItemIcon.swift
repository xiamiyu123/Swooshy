import AppKit

enum StatusItemIcon: String, CaseIterable, Codable, Identifiable, Sendable {
    case swooshy
    case gale
    case groupedWindows = "grouped_windows"
    case splitView = "split_view"
    case stackedWindows = "stacked_windows"
    case focusedWindow = "focused_window"
    case windowGrid = "window_grid"

    var id: Self { self }

    @MainActor
    private static let imageCache = NSCache<NSString, NSImage>()

    init(storageValue: String?) {
        self = StatusItemIcon(rawValue: storageValue ?? "") ?? .gale
    }

    var storageValue: String {
        rawValue
    }

    var symbolName: String? {
        switch self {
        case .swooshy, .gale:
            nil
        case .groupedWindows:
            "rectangle.3.group"
        case .splitView:
            "rectangle.split.2x1"
        case .stackedWindows:
            "rectangle.on.rectangle"
        case .focusedWindow:
            "macwindow.on.rectangle"
        case .windowGrid:
            "square.grid.2x2"
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

    @MainActor
    func makeImage(accessibilityDescription: String) -> NSImage? {
        let cacheKey = "\(storageValue)|\(accessibilityDescription)" as NSString
        if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        let image = switch self {
        case .swooshy:
            StatusItemTemplateImage.loadTemplateImage(
                named: "SwooshyStatusTemplate",
                accessibilityDescription: accessibilityDescription
            )
        case .gale:
            StatusItemTemplateImage.loadTemplateImage(
                named: "GaleStatusTemplate",
                accessibilityDescription: accessibilityDescription
            ) ?? StatusItemTemplateImage.makeGaleTemplateImage()
        case .groupedWindows, .splitView, .stackedWindows, .focusedWindow, .windowGrid:
            makeSymbolImage(accessibilityDescription: accessibilityDescription)
        }

        guard let image else {
            return nil
        }

        Self.imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    @MainActor
    private func makeSymbolImage(accessibilityDescription: String) -> NSImage? {
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
