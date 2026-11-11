enum DockingAnimationSpeed: Double, CaseIterable, Identifiable, Sendable {
    case slow = 400
    case relaxed = 320
    case standard = 240
    case quick = 180
    case fast = 120

    var id: Self { self }

    var localizationKey: String {
        switch self {
        case .slow: "settings.animation_speed.slow"
        case .relaxed: "settings.animation_speed.relaxed"
        case .standard: "settings.animation_speed.standard"
        case .quick: "settings.animation_speed.quick"
        case .fast: "settings.animation_speed.fast"
        }
    }
}
