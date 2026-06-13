import Foundation

enum GestureExclusionSurface: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case dock
    case titleBar

    var id: String { rawValue }
}

enum GestureExclusionGesture: String, Codable, Hashable, Identifiable, Sendable {
    case swipeLeft
    case swipeRight
    case swipeDown
    case swipeUp
    case pinchIn
    case pinchOut
    case cornerDrag

    init(_ gesture: DockGestureKind) {
        self = switch gesture {
        case .swipeLeft:
            .swipeLeft
        case .swipeRight:
            .swipeRight
        case .swipeDown:
            .swipeDown
        case .swipeUp:
            .swipeUp
        case .pinchIn:
            .pinchIn
        case .pinchOut:
            .pinchOut
        }
    }

    var id: String { rawValue }
}

struct GestureExclusionSelection: Codable, Hashable, Identifiable, Sendable {
    let surface: GestureExclusionSurface
    let gesture: GestureExclusionGesture

    var id: String {
        "\(surface.rawValue).\(gesture.rawValue)"
    }

    static func standard(_ gesture: DockGestureKind, on surface: GestureExclusionSurface) -> Self {
        GestureExclusionSelection(surface: surface, gesture: GestureExclusionGesture(gesture))
    }

    static func cornerDrag(on surface: GestureExclusionSurface) -> Self {
        GestureExclusionSelection(surface: surface, gesture: .cornerDrag)
    }
}

enum GestureExclusionMode: Codable, Hashable, Sendable {
    case all
    case selected(Set<GestureExclusionSelection>)

    private enum CodingKeys: String, CodingKey {
        case type
        case disabledGestures
    }

    private enum StorageType: String, Codable {
        case all
        case selected
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StorageType.self, forKey: .type)

        switch type {
        case .all:
            self = .all
        case .selected:
            let gestures = try container.decodeIfPresent(Set<GestureExclusionSelection>.self, forKey: .disabledGestures)
            self = .selected(gestures ?? [])
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .all:
            try container.encode(StorageType.all, forKey: .type)
        case .selected(let gestures):
            try container.encode(StorageType.selected, forKey: .type)
            try container.encode(gestures, forKey: .disabledGestures)
        }
    }

    func disables(_ selection: GestureExclusionSelection) -> Bool {
        switch self {
        case .all:
            true
        case .selected(let disabledGestures):
            disabledGestures.contains(selection)
        }
    }
}

struct GestureExcludedApplication: Codable, Hashable, Identifiable, Sendable {
    var bundleURL: URL
    var bundleIdentifier: String?
    var displayName: String

    var id: String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }

        return bundleURL.path
    }

    init(
        bundleURL: URL,
        bundleIdentifier: String?,
        displayName: String
    ) {
        let canonicalBundleURL = AppIdentity.canonicalBundleURL(from: bundleURL)
        self.bundleURL = canonicalBundleURL
        self.bundleIdentifier = bundleIdentifier?.isEmpty == false ? bundleIdentifier : nil
        self.displayName = displayName.isEmpty
            ? canonicalBundleURL.deletingPathExtension().lastPathComponent
            : displayName
    }

    init(_ appIdentity: AppIdentity) {
        self.init(
            bundleURL: appIdentity.bundleURL,
            bundleIdentifier: appIdentity.bundleIdentifier,
            displayName: appIdentity.localizedName
        )
    }

    func matches(_ appIdentity: AppIdentity) -> Bool {
        if
            let bundleIdentifier,
            let otherBundleIdentifier = appIdentity.bundleIdentifier,
            !bundleIdentifier.isEmpty,
            !otherBundleIdentifier.isEmpty
        {
            return bundleIdentifier == otherBundleIdentifier
        }

        return bundleURL == appIdentity.bundleURL
    }

    func matches(_ application: GestureExcludedApplication) -> Bool {
        if
            let bundleIdentifier,
            let otherBundleIdentifier = application.bundleIdentifier,
            !bundleIdentifier.isEmpty,
            !otherBundleIdentifier.isEmpty
        {
            return bundleIdentifier == otherBundleIdentifier
        }

        return bundleURL == application.bundleURL
    }
}

struct GestureExclusionRule: Codable, Hashable, Identifiable, Sendable {
    var application: GestureExcludedApplication
    var mode: GestureExclusionMode

    var id: String {
        application.id
    }

    func matches(_ appIdentity: AppIdentity) -> Bool {
        application.matches(appIdentity)
    }

    func disablesStandardGesture(
        _ gesture: DockGestureKind,
        on surface: GestureExclusionSurface
    ) -> Bool {
        mode.disables(.standard(gesture, on: surface))
    }

    func disablesCornerDrag(on surface: GestureExclusionSurface) -> Bool {
        mode.disables(.cornerDrag(on: surface))
    }
}
