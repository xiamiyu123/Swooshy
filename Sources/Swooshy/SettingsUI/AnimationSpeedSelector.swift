import SwiftUI

struct AnimationSpeedSelector: View {
    @Bindable var settingsStore: SettingsStore
    @Namespace private var segmentNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(settingsStore.localized("settings.animation_speed.label"))
                    .font(.body)

                Spacer()

                Text("\(Int(settingsStore.dockingAnimationDurationMilliseconds)) ms")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 2) {
                ForEach(DockingAnimationSpeed.allCases) { speed in
                    let isSelected = settingsStore.dockingAnimationDurationMilliseconds == speed.rawValue
                    let title = settingsStore.localized(speed.localizationKey)
                    let isStandard = speed == .standard

                    SpeedSegmentButton(
                        title: title,
                        isSelected: isSelected,
                        isStandard: isStandard,
                        speedMilliseconds: Int(speed.rawValue),
                        namespace: segmentNamespace
                    ) {
                        withAnimation(.snappy(duration: 0.2)) {
                            settingsStore.dockingAnimationDurationMilliseconds = speed.rawValue
                        }
                    }
                }
            }
            .padding(2)
            .background(
                Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .padding(.vertical, 2)
    }
}

private struct SpeedSegmentButton: View {
    let title: String
    let isSelected: Bool
    let isStandard: Bool
    let speedMilliseconds: Int
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                if isStandard {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.10), radius: 1.5, x: 0, y: 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                        .matchedGeometryEffect(id: "selected_speed_pill", in: namespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(speedMilliseconds) ms")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
