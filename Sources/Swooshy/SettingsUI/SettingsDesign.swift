import SwiftUI

/// Single source of truth for spacing, corner radii, and typography across the
/// rebuilt Settings and Welcome surfaces. Replaces the magic numbers that were
/// scattered through the old hand-drawn card system so both windows share one
/// visual rhythm.
enum SettingsDesign {
    /// Spacing tokens (points). Names describe intent, not raw size, so the
    /// scale can be retuned in one place.
    enum Spacing {
        /// Gap between major page sections.
        static let section: CGFloat = 20
        /// Padding inside a card / panel.
        static let cardPadding: CGFloat = 16
        /// Vertical gap between a control and its caption/footer.
        static let captionGap: CGFloat = 4
        /// Gap between sibling controls within a card.
        static let control: CGFloat = 12
        /// Tight gap for icon + label rows.
        static let inlineIcon: CGFloat = 8
        /// Outer page padding for non-Form scroll containers.
        static let page: CGFloat = 20
    }

    /// Corner radius tokens (points). Aligned closer to the system settings
    /// look than the old 18pt cards.
    enum Radius {
        /// Standard card / panel.
        static let card: CGFloat = 12
        /// Small inline chips and badges.
        static let chip: CGFloat = 8
        /// Large hero / preview surfaces.
        static let hero: CGFloat = 20
        /// Sidebar icon tile.
        static let iconTile: CGFloat = 7
    }

    /// Typography helpers so footers and captions are consistent everywhere
    /// (the old code mixed `.caption` and `.subheadline` for the same role).
    enum Typography {
        static let sectionTitle: Font = .headline
        static let rowTitle: Font = .body
        static let caption: Font = .footnote
    }

    /// Sidebar icon tile dimensions.
    enum Sidebar {
        static let iconTileSize: CGFloat = 22
        static let iconGlyphSize: CGFloat = 13
        static let rowHeight: CGFloat = 28
        static let width: CGFloat = 215
    }
}

extension View {
    /// Standard secondary caption/footer styling used under controls.
    func settingsCaption() -> some View {
        font(SettingsDesign.Typography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
