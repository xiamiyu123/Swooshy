import Foundation

/// Identifies a class of windows within one app so learned size constraints can
/// be reused across windows that behave the same without leaking between apps.
struct WindowConstraintObservationScope: Equatable {
    let applicationKey: String
    let role: String
    let subrole: String
    let title: String

    var storageKey: String {
        [
            applicationKey,
            "role=\(role)",
            "subrole=\(subrole)",
            "title=\(title)"
        ].joined(separator: "|")
    }

    init(
        applicationKey: String,
        role: String?,
        subrole: String?,
        title: String?
    ) {
        self.applicationKey = applicationKey
        self.role = Self.normalizedComponent(role, fallback: "AXWindow")
        self.subrole = Self.normalizedComponent(subrole, fallback: "<none>")
        self.title = Self.normalizedTitleComponent(title)
    }

    private static func normalizedComponent(_ value: String?, fallback: String) -> String {
        let collapsed = collapsedWhitespace(value)
        return collapsed.isEmpty ? fallback : collapsed
    }

    private static func normalizedTitleComponent(_ value: String?) -> String {
        let collapsed = collapsedWhitespace(value)
        guard !collapsed.isEmpty else {
            return "<untitled>"
        }

        return String(collapsed.prefix(80))
    }

    private static func collapsedWhitespace(_ value: String?) -> String {
        guard let value else {
            return ""
        }

        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        return folded
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
