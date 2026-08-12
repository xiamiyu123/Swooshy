import CoreGraphics
import Foundation

enum GestureHUDPosition: String, CaseIterable, Codable, Identifiable, Sendable {
    case followPointer
    case topCenter
    case customOffset

    var id: Self { self }

    var storageValue: String {
        rawValue
    }

    init(storageValue: String?) {
        self = switch storageValue {
        case Self.topCenter.storageValue:
            .topCenter
        case Self.customOffset.storageValue:
            .customOffset
        default:
            .followPointer
        }
    }

    func title(
        localeIdentifier: String? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let localizationKey = switch self {
        case .followPointer:
            "settings.gesture_hud.position.follow_pointer"
        case .topCenter:
            "settings.gesture_hud.position.top_center"
        case .customOffset:
            "settings.gesture_hud.position.custom_offset"
        }

        return L10n.string(
            localizationKey,
            localeIdentifier: localeIdentifier,
            preferredLanguages: preferredLanguages
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = GestureHUDPosition(storageValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageValue)
    }
}

struct GestureHUDPlacement: Equatable, Sendable {
    let position: GestureHUDPosition
    let horizontalOffset: CGFloat
    let verticalOffset: CGFloat

    init(
        position: GestureHUDPosition,
        horizontalOffset: CGFloat = 0,
        verticalOffset: CGFloat = 0
    ) {
        self.position = position
        self.horizontalOffset = horizontalOffset
        self.verticalOffset = verticalOffset
    }
}

enum GestureHUDPlacementResolver {
    static let pointerVerticalGap: CGFloat = 18
    static let sideMargin: CGFloat = 10

    static func frame(
        anchorPoint: CGPoint,
        visibleFrame: CGRect,
        panelSize: CGSize,
        placement: GestureHUDPlacement
    ) -> CGRect {
        let desiredOrigin: CGPoint

        switch placement.position {
        case .followPointer:
            desiredOrigin = pointerOrigin(for: anchorPoint, panelSize: panelSize)
        case .topCenter:
            desiredOrigin = CGPoint(
                x: visibleFrame.midX - panelSize.width / 2,
                y: visibleFrame.maxY - panelSize.height - sideMargin
            )
        case .customOffset:
            let pointerOrigin = pointerOrigin(for: anchorPoint, panelSize: panelSize)
            desiredOrigin = CGPoint(
                x: pointerOrigin.x + placement.horizontalOffset,
                y: pointerOrigin.y + placement.verticalOffset
            )
        }

        let desiredFrame = CGRect(origin: desiredOrigin, size: panelSize)
        return clamp(desiredFrame, to: visibleFrame)
    }

    private static func pointerOrigin(for anchorPoint: CGPoint, panelSize: CGSize) -> CGPoint {
        CGPoint(
            x: anchorPoint.x - panelSize.width / 2,
            y: anchorPoint.y + pointerVerticalGap
        )
    }

    private static func clamp(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        guard !visibleFrame.isNull, !visibleFrame.isEmpty else {
            return frame
        }

        let minimumX = visibleFrame.minX + sideMargin
        let maximumX = visibleFrame.maxX - frame.width - sideMargin
        let minimumY = visibleFrame.minY + sideMargin
        let maximumY = visibleFrame.maxY - frame.height - sideMargin

        let originX = clamped(frame.minX, minimum: minimumX, maximum: maximumX)
        let originY = clamped(frame.minY, minimum: minimumY, maximum: maximumY)

        return CGRect(x: originX, y: originY, width: frame.width, height: frame.height)
    }

    private static func clamped(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        guard minimum <= maximum else {
            return (minimum + maximum) / 2
        }

        return min(max(value, minimum), maximum)
    }
}
