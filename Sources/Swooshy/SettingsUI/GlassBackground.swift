import SwiftUI

/// Centralizes the card and panel treatment so Settings and the Welcome guide
/// go through one surface implementation that builds with the current project
/// SDK.
///
/// Usage: `someView.glassCard()` for content cards, `.glassPanel()` for larger
/// hero/preview surfaces with a bigger radius.
extension View {
    /// Card-level glass surface (standard radius).
    func glassCard(
        cornerRadius: CGFloat = SettingsDesign.Radius.card,
        padding: CGFloat? = SettingsDesign.Spacing.cardPadding
    ) -> some View {
        modifier(
            GlassSurfaceModifier(cornerRadius: cornerRadius, padding: padding)
        )
    }

    /// Larger hero/preview glass surface.
    func glassPanel(
        cornerRadius: CGFloat = SettingsDesign.Radius.hero,
        padding: CGFloat? = SettingsDesign.Spacing.cardPadding
    ) -> some View {
        modifier(
            GlassSurfaceModifier(cornerRadius: cornerRadius, padding: padding)
        )
    }
}

private struct GlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat?

    func body(content: Content) -> some View {
        let padded = content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding ?? 0)

        padded
            .standardCardSurface(cornerRadius: cornerRadius)
    }
}

extension View {
    /// Background-only glass treatment for views that already manage their own
    /// padding and frame (e.g. the Welcome guide cards). Replaces the repeated
    /// `.background(RoundedRectangle.fill).overlay(stroke)` pair so the surface
    /// matches the rest of the rebuilt UI without changing the view's layout.
    func glassCardBackground(
        cornerRadius: CGFloat = SettingsDesign.Radius.card
    ) -> some View {
        modifier(GlassCardBackgroundModifier(cornerRadius: cornerRadius))
    }
}

private struct GlassCardBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .standardCardSurface(cornerRadius: cornerRadius)
    }
}

extension View {
    /// Background for selectable cards (e.g. the interaction-style pickers).
    /// The selected state keeps an accent tint + ring so the choice stays
    /// obvious; the unselected state uses the standard card surface.
    func selectableCardBackground(
        isSelected: Bool,
        cornerRadius: CGFloat = SettingsDesign.Radius.card
    ) -> some View {
        modifier(
            SelectableCardBackgroundModifier(
                isSelected: isSelected,
                cornerRadius: cornerRadius
            )
        )
    }
}

private struct SelectableCardBackgroundModifier: ViewModifier {
    let isSelected: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if isSelected {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.4), lineWidth: 2)
                )
        } else {
            content
                .standardCardSurface(cornerRadius: cornerRadius)
        }
    }
}

private extension View {
    func standardCardSurface(cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.12), lineWidth: 1)
        )
    }
}

/// Keeps a single grouping type for settings surfaces.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = SettingsDesign.Spacing.control, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        content
    }
}
