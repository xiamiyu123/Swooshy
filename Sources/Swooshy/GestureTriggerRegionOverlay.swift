import AppKit
import Foundation

struct GestureTriggerRegionOverlayItem: Equatable, Identifiable {
    enum Kind: Equatable {
        case dock
        case titleBar
    }

    let id: UUID
    let kind: Kind
    let frame: CGRect
    let title: String
    let detail: String

    init(
        id: UUID = UUID(),
        kind: Kind,
        frame: CGRect,
        title: String,
        detail: String
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame.integral
        self.title = title
        self.detail = detail
    }
}

enum GestureTriggerRegionOverlayLayout {
    @MainActor
    static func titleBarRegion(
        forWindowFrame windowFrame: CGRect,
        titleBarHeight: Double
    ) -> CGRect? {
        let height = CGFloat(SettingsStore.clampTitleBarTriggerHeight(titleBarHeight))
        guard windowFrame.width >= 120, windowFrame.height >= 80 else {
            return nil
        }

        let clampedHeight = min(height, windowFrame.height)
        let region = CGRect(
            x: windowFrame.minX,
            y: windowFrame.maxY - clampedHeight,
            width: windowFrame.width,
            height: clampedHeight
        ).integral

        return region.isEmpty ? nil : region
    }

    static func localFrame(
        for frame: CGRect,
        onScreen screenFrame: CGRect
    ) -> CGRect? {
        let clippedFrame = frame.intersection(screenFrame).integral
        guard !clippedFrame.isNull, !clippedFrame.isEmpty else {
            return nil
        }

        return clippedFrame
            .offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
            .integral
    }
}

@MainActor
final class GestureTriggerRegionOverlayController {
    private final class OverlayPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private struct ActivePanel {
        let panel: NSPanel
        let view: GestureTriggerRegionOverlayView
    }

    private var activePanels: [ActivePanel] = []
    private var dismissTask: Task<Void, Never>?
    private var hideGeneration: UInt64 = 0
    private let displayDurationNanoseconds: UInt64 = 3_000_000_000
    private let fadeDuration: TimeInterval = 0.16

    func show(items: [GestureTriggerRegionOverlayItem], localized: (String) -> String) {
        hideGeneration &+= 1
        dismissTask?.cancel()
        dismissExistingPanels()

        guard !items.isEmpty else {
            showEmptyHint(localized: localized)
            return
        }

        DebugLog.debug(
            DebugLog.dock,
            "Showing gesture trigger regions: \(items.map { "\($0.kind.logDescription)=\(NSStringFromRect($0.frame))" }.joined(separator: ", "))"
        )

        activePanels = NSScreen.screens.compactMap { screen in
            let screenItems = items.compactMap { item -> GestureTriggerRegionOverlayView.Item? in
                guard let localFrame = GestureTriggerRegionOverlayLayout.localFrame(
                    for: item.frame,
                    onScreen: screen.frame
                ) else {
                    return nil
                }

                return GestureTriggerRegionOverlayView.Item(
                    kind: item.kind,
                    frame: localFrame,
                    title: item.title,
                    detail: item.detail
                )
            }
            guard !screenItems.isEmpty else {
                return nil
            }

            let view = GestureTriggerRegionOverlayView(
                frame: NSRect(origin: .zero, size: screen.frame.size)
            )
            view.items = screenItems
            DebugLog.debug(
                DebugLog.dock,
                "Gesture trigger overlay screen \(NSStringFromRect(screen.frame)) local regions: \(screenItems.map { "\($0.kind.logDescription)=\(NSStringFromRect($0.frame))" }.joined(separator: ", "))"
            )

            let panel = makePanel(frame: screen.frame, contentView: view)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            panel.animator().alphaValue = 1
            return ActivePanel(panel: panel, view: view)
        }

        scheduleDismiss()
    }

    func dismiss() {
        hideGeneration &+= 1
        dismissTask?.cancel()
        dismissTask = nil
        hidePanels(orderOutAfterFade: true, expectedGeneration: hideGeneration)
    }

    private func showEmptyHint(localized: (String) -> String) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let item = GestureTriggerRegionOverlayItem(
            kind: .titleBar,
            frame: CGRect(
                x: screen.frame.midX - 190,
                y: screen.frame.midY - 34,
                width: 380,
                height: 68
            ),
            title: localized("settings.trigger_regions.empty.title"),
            detail: localized("settings.trigger_regions.empty.detail")
        )

        show(items: [item], localized: localized)
    }

    private func makePanel(frame: CGRect, contentView: NSView) -> NSPanel {
        let panel = OverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = contentView
        return panel
    }

    private func scheduleDismiss() {
        let generation = hideGeneration
        dismissTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.displayDurationNanoseconds ?? 0)
            } catch is CancellationError {
                return
            } catch {
                return
            }

            self?.hidePanels(orderOutAfterFade: true, expectedGeneration: generation)
        }
    }

    private func hidePanels(orderOutAfterFade: Bool, expectedGeneration: UInt64) {
        guard !activePanels.isEmpty else {
            return
        }

        let panels = activePanels.map(\.panel)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for panel in panels {
                panel.animator().alphaValue = 0
            }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, expectedGeneration == self.hideGeneration else {
                    return
                }

                if orderOutAfterFade {
                    for panel in panels {
                        panel.orderOut(nil)
                    }
                    self.activePanels = []
                    self.dismissTask = nil
                }
            }
        }
    }

    private func dismissExistingPanels() {
        for activePanel in activePanels {
            activePanel.panel.orderOut(nil)
        }
        activePanels = []
    }
}

private extension GestureTriggerRegionOverlayItem.Kind {
    var logDescription: String {
        switch self {
        case .dock:
            return "dock"
        case .titleBar:
            return "title-bar"
        }
    }
}

@MainActor
private final class GestureTriggerRegionOverlayView: NSView {
    struct Item: Equatable {
        let kind: GestureTriggerRegionOverlayItem.Kind
        let frame: CGRect
        let title: String
        let detail: String
    }

    var items: [Item] = [] {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        context.setFillColor(NSColor.black.withAlphaComponent(0.08).cgColor)
        context.fill(bounds)

        for item in items {
            draw(item)
        }
    }

    private func draw(_ item: Item) {
        let rect = item.frame.intersection(bounds).insetBy(dx: 1, dy: 1)
        guard !rect.isEmpty else {
            return
        }

        let color = color(for: item.kind)
        let cornerRadius = min(rect.height / 2, item.kind == .dock ? 18 : 10)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

        color.withAlphaComponent(0.20).setFill()
        path.fill()

        color.withAlphaComponent(0.78).setStroke()
        path.lineWidth = 2
        path.stroke()

        drawLabel(for: item, color: color, near: rect)
    }

    private func drawLabel(for item: Item, color: NSColor, near rect: CGRect) {
        guard !item.title.isEmpty || !item.detail.isEmpty else {
            return
        }

        let labelPadding = CGSize(width: 12, height: 8)
        let maxWidth: CGFloat = 320
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let title = item.title.isEmpty ? nil : NSAttributedString(string: item.title, attributes: titleAttributes)
        let detail = item.detail.isEmpty ? nil : NSAttributedString(string: item.detail, attributes: detailAttributes)
        let titleSize = title.map {
            $0.boundingRect(
                with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).size
        } ?? .zero
        let detailSize = detail.map {
            $0.boundingRect(
                with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).size
        } ?? .zero
        let labelWidth = min(
            max(max(titleSize.width, detailSize.width) + labelPadding.width * 2, 160),
            maxWidth + labelPadding.width * 2
        )
        let textGap: CGFloat = title != nil && detail != nil ? 3 : 0
        let labelHeight = titleSize.height + detailSize.height + labelPadding.height * 2 + textGap
        let labelFrame = clampedLabelFrame(
            near: rect,
            size: CGSize(width: labelWidth, height: labelHeight)
        )

        let labelPath = NSBezierPath(
            roundedRect: labelFrame,
            xRadius: 14,
            yRadius: 14
        )
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        labelPath.fill()
        color.withAlphaComponent(0.42).setStroke()
        labelPath.lineWidth = 1
        labelPath.stroke()

        let textX = labelFrame.minX + labelPadding.width
        var textY = labelFrame.maxY - labelPadding.height - titleSize.height
        if let title {
            title.draw(
                with: CGRect(x: textX, y: textY, width: labelWidth - labelPadding.width * 2, height: titleSize.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            textY -= textGap
        }
        if let detail {
            textY -= detailSize.height
            detail.draw(
                with: CGRect(x: textX, y: textY, width: labelWidth - labelPadding.width * 2, height: detailSize.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
        }
    }

    private func clampedLabelFrame(near rect: CGRect, size: CGSize) -> CGRect {
        let margin: CGFloat = 18
        let preferredAbove = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.maxY + 10,
            width: size.width,
            height: size.height
        )
        let preferredBelow = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.minY - size.height - 10,
            width: size.width,
            height: size.height
        )
        let chosen = preferredAbove.maxY <= bounds.maxY - margin ? preferredAbove : preferredBelow
        let x = min(max(chosen.minX, bounds.minX + margin), bounds.maxX - size.width - margin)
        let y = min(max(chosen.minY, bounds.minY + margin), bounds.maxY - size.height - margin)
        return CGRect(x: x, y: y, width: size.width, height: size.height).integral
    }

    private func color(for kind: GestureTriggerRegionOverlayItem.Kind) -> NSColor {
        switch kind {
        case .dock:
            return NSColor.systemTeal
        case .titleBar:
            return NSColor.systemOrange
        }
    }
}
