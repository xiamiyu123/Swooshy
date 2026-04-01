import AppKit
import Foundation

@MainActor
protocol GestureFeedbackPresenting {
    func show(
        glyph: GestureHUDGlyph,
        gestureTitle: String,
        actionTitle: String,
        anchor: CGPoint?,
        persistent: Bool,
        preview: WindowActionPreview?
    )
    func dismiss()
    func scheduleDismiss()
}

extension GestureFeedbackPresenting {
    func show(
        gesture: DockGestureKind,
        gestureTitle: String,
        actionTitle: String,
        anchor: CGPoint? = nil,
        persistent: Bool = false,
        preview: WindowActionPreview? = nil
    ) {
        show(
            glyph: .gesture(gesture),
            gestureTitle: gestureTitle,
            actionTitle: actionTitle,
            anchor: anchor,
            persistent: persistent,
            preview: preview
        )
    }
}

enum GestureHUDGlyph: Equatable {
    enum DiagonalDirection: Equatable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    case gesture(DockGestureKind)
    case diagonal(DiagonalDirection)
    case cornerMode
}

struct GestureHUDRenderModel: Equatable {
    let style: GestureHUDStyle
    let glyph: GestureHUDGlyph
    let gestureTitle: String
    let actionTitle: String
}

struct GestureHUDStyleConfiguration {
    let panelSize: NSSize
    let cornerRadius: CGFloat
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let backgroundColor: NSColor
    let borderColor: NSColor
    let borderWidth: CGFloat
    let titleFontSize: CGFloat
    let glyphColor: NSColor
    let glyphSecondaryColor: NSColor
    let glyphLineWidth: CGFloat
    let glyphGlowLineWidth: CGFloat
    let glyphBadgeBackgroundColor: NSColor
    let glyphBadgeBorderColor: NSColor
    let glyphBadgeBorderWidth: CGFloat
    let glyphBadgeCornerRadius: CGFloat
}

func gestureHUDStyleConfiguration(for style: GestureHUDStyle) -> GestureHUDStyleConfiguration {
    switch style {
    case .classic:
        return GestureHUDStyleConfiguration(
            panelSize: NSSize(width: 208, height: 42),
            cornerRadius: 14,
            material: .hudWindow,
            blendingMode: .behindWindow,
            backgroundColor: .clear,
            borderColor: .clear,
            borderWidth: 0,
            titleFontSize: 13,
            glyphColor: NSColor.labelColor.withAlphaComponent(0.9),
            glyphSecondaryColor: NSColor.labelColor.withAlphaComponent(0.16),
            glyphLineWidth: 2.2,
            glyphGlowLineWidth: 0,
            glyphBadgeBackgroundColor: .clear,
            glyphBadgeBorderColor: .clear,
            glyphBadgeBorderWidth: 0,
            glyphBadgeCornerRadius: 0
        )
    case .elegant:
        return GestureHUDStyleConfiguration(
            panelSize: NSSize(width: 182, height: 40),
            cornerRadius: 12,
            material: .hudWindow,
            blendingMode: .behindWindow,
            backgroundColor: .clear,
            borderColor: .clear,
            borderWidth: 0,
            titleFontSize: 12,
            glyphColor: NSColor.white.withAlphaComponent(0.95),
            glyphSecondaryColor: NSColor.labelColor.withAlphaComponent(0.16),
            glyphLineWidth: 2.2,
            glyphGlowLineWidth: 4.8,
            glyphBadgeBackgroundColor: .clear,
            glyphBadgeBorderColor: .clear,
            glyphBadgeBorderWidth: 0,
            glyphBadgeCornerRadius: 8
        )
    case .minimal:
        return GestureHUDStyleConfiguration(
            panelSize: NSSize(width: 40, height: 40),
            cornerRadius: 10,
            material: .hudWindow,
            blendingMode: .behindWindow,
            backgroundColor: .clear,
            borderColor: .clear,
            borderWidth: 0,
            titleFontSize: 13,
            glyphColor: NSColor.white.withAlphaComponent(0.95),
            glyphSecondaryColor: NSColor.labelColor.withAlphaComponent(0.16),
            glyphLineWidth: 2.2,
            glyphGlowLineWidth: 4.8,
            glyphBadgeBackgroundColor: .clear,
            glyphBadgeBorderColor: .clear,
            glyphBadgeBorderWidth: 0,
            glyphBadgeCornerRadius: 8
        )
    }
}

@MainActor
final class GestureHUDRenderView: NSVisualEffectView {
    private let messageLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let glyphView = GestureGlyphView(frame: .zero)
    private let glyphBadgeView = NSView(frame: .zero)
    private var currentStyle: GestureHUDStyle?

    static func panelSize(for style: GestureHUDStyle) -> NSSize {
        gestureHUDStyleConfiguration(for: style).panelSize
    }

    var currentPanelSize: NSSize {
        GestureHUDRenderView.panelSize(for: currentStyle ?? .elegant)
    }

    override var intrinsicContentSize: NSSize {
        currentPanelSize
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func render(model: GestureHUDRenderModel) {
        if currentStyle != model.style || subviews.isEmpty {
            rebuild(for: model.style)
        }

        glyphView.glyph = model.glyph
        messageLabel.stringValue = "\(model.gestureTitle) · \(model.actionTitle)"
        titleLabel.stringValue = model.actionTitle
    }

    private func rebuild(for style: GestureHUDStyle) {
        let configuration = gestureHUDStyleConfiguration(for: style)
        currentStyle = style
        frame = NSRect(origin: .zero, size: configuration.panelSize)
        material = configuration.material
        blendingMode = configuration.blendingMode
        state = .active
        wantsLayer = true
        layer?.cornerRadius = configuration.cornerRadius
        layer?.masksToBounds = true
        layer?.backgroundColor = configuration.backgroundColor.cgColor
        layer?.borderColor = configuration.borderColor.cgColor
        layer?.borderWidth = configuration.borderWidth

        subviews.forEach { $0.removeFromSuperview() }

        messageLabel.font = .systemFont(ofSize: 12, weight: .medium)
        messageLabel.textColor = .labelColor
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 1
        messageLabel.lineBreakMode = .byTruncatingMiddle
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: configuration.titleFontSize, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        glyphView.translatesAutoresizingMaskIntoConstraints = false
        glyphView.glyphStyle = .minimal
        glyphView.primaryColor = configuration.glyphColor
        glyphView.secondaryColor = configuration.glyphSecondaryColor
        glyphView.lineWidth = configuration.glyphLineWidth
        glyphView.glowLineWidth = configuration.glyphGlowLineWidth

        glyphBadgeView.translatesAutoresizingMaskIntoConstraints = false
        glyphBadgeView.wantsLayer = true
        glyphBadgeView.layer?.cornerRadius = configuration.glyphBadgeCornerRadius
        glyphBadgeView.layer?.masksToBounds = true
        glyphBadgeView.layer?.backgroundColor = configuration.glyphBadgeBackgroundColor.cgColor
        glyphBadgeView.layer?.borderColor = configuration.glyphBadgeBorderColor.cgColor
        glyphBadgeView.layer?.borderWidth = configuration.glyphBadgeBorderWidth
        glyphBadgeView.subviews.forEach { $0.removeFromSuperview() }

        switch style {
        case .classic:
            addSubview(messageLabel)
            NSLayoutConstraint.activate([
                messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
                messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            ])
        case .elegant:
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 10
            row.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
            row.alignment = .centerY
            row.translatesAutoresizingMaskIntoConstraints = false

            let textStack = NSStackView(views: [titleLabel])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.translatesAutoresizingMaskIntoConstraints = false

            glyphBadgeView.addSubview(glyphView)
            row.addArrangedSubview(glyphBadgeView)
            row.addArrangedSubview(textStack)
            addSubview(row)

            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: leadingAnchor),
                row.trailingAnchor.constraint(equalTo: trailingAnchor),
                row.topAnchor.constraint(equalTo: topAnchor),
                row.bottomAnchor.constraint(equalTo: bottomAnchor),
                glyphBadgeView.widthAnchor.constraint(equalToConstant: 24),
                glyphBadgeView.heightAnchor.constraint(equalToConstant: 24),
                glyphView.centerXAnchor.constraint(equalTo: glyphBadgeView.centerXAnchor),
                glyphView.centerYAnchor.constraint(equalTo: glyphBadgeView.centerYAnchor),
                glyphView.widthAnchor.constraint(equalToConstant: 22),
                glyphView.heightAnchor.constraint(equalToConstant: 22),
            ])
        case .minimal:
            glyphBadgeView.addSubview(glyphView)
            addSubview(glyphBadgeView)

            NSLayoutConstraint.activate([
                glyphBadgeView.centerXAnchor.constraint(equalTo: centerXAnchor),
                glyphBadgeView.centerYAnchor.constraint(equalTo: centerYAnchor),
                glyphBadgeView.widthAnchor.constraint(equalToConstant: 20),
                glyphBadgeView.heightAnchor.constraint(equalToConstant: 20),
                glyphView.centerXAnchor.constraint(equalTo: glyphBadgeView.centerXAnchor),
                glyphView.centerYAnchor.constraint(equalTo: glyphBadgeView.centerYAnchor),
                glyphView.widthAnchor.constraint(equalToConstant: 18),
                glyphView.heightAnchor.constraint(equalToConstant: 18),
            ])
        }
    }
}

@MainActor
final class GestureFeedbackController: GestureFeedbackPresenting {
    private let settingsStore: SettingsStore
    private let panel: NSPanel
    private let previewPanel: NSPanel
    private let renderView = GestureHUDRenderView(frame: .zero)
    private let previewView = GestureSnapPreviewView(frame: .zero)
    private var dismissTask: Task<Void, Never>?
    private var hideGeneration: UInt64 = 0
    private var currentPanelSize = GestureHUDRenderView.panelSize(for: .elegant)

    private let verticalOffset: CGFloat = 18
    private let sideMargin: CGFloat = 10
    private let dismissalDelay: UInt64 = 700_000_000

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: currentPanelSize),
            styleMask: [.nonactivatingPanel, .hudWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        renderView.render(
            model: GestureHUDRenderModel(
                style: settingsStore.gestureHUDStyle,
                glyph: .gesture(.swipeUp),
                gestureTitle: "",
                actionTitle: ""
            )
        )
        currentPanelSize = renderView.currentPanelSize
        panel.setContentSize(currentPanelSize)
        panel.contentView = renderView
        panel.hasShadow = settingsStore.gestureHUDStyle != .minimal
        panel.alphaValue = 0

        previewPanel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        previewPanel.level = .statusBar
        previewPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        previewPanel.backgroundColor = .clear
        previewPanel.isOpaque = false
        previewPanel.hasShadow = false
        previewPanel.isReleasedWhenClosed = false
        previewPanel.hidesOnDeactivate = false
        previewPanel.ignoresMouseEvents = true
        previewPanel.titleVisibility = .hidden
        previewPanel.titlebarAppearsTransparent = true
        previewPanel.contentView = previewView
        previewPanel.alphaValue = 0
    }

    func show(
        glyph: GestureHUDGlyph,
        gestureTitle: String,
        actionTitle: String,
        anchor: CGPoint? = nil,
        persistent: Bool = false,
        preview: WindowActionPreview? = nil
    ) {
        let style = settingsStore.gestureHUDStyle
        renderView.render(
            model: GestureHUDRenderModel(
                style: style,
                glyph: glyph,
                gestureTitle: gestureTitle,
                actionTitle: actionTitle
            )
        )
        currentPanelSize = renderView.currentPanelSize
        panel.hasShadow = style != .minimal
        panel.setContentSize(currentPanelSize)

        let anchorPoint = anchor ?? NSEvent.mouseLocation
        panel.setFrame(frame(for: anchorPoint), display: false)
        updatePreview(preview: persistent ? preview : nil)

        hideGeneration &+= 1
        dismissTask?.cancel()
        if preview != nil, persistent {
            previewPanel.orderFrontRegardless()
        }
        panel.orderFrontRegardless()

        previewPanel.animator().alphaValue = preview != nil && persistent ? 1 : 0
        panel.animator().alphaValue = 1

        guard persistent == false else {
            // In persistent mode the HUD stays visible until dismiss() is called.
            return
        }

        let delay = self.dismissalDelay
        let generation = hideGeneration

        dismissTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch is CancellationError {
                return
            } catch {
                DebugLog.debug(DebugLog.dock, "HUD dismiss delay task failed unexpectedly: \(error.localizedDescription)")
                return
            }
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.hide(expectedGeneration: generation)
            }
        }
    }

    private func frame(for anchorPoint: CGPoint) -> NSRect {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorPoint) }) ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let width = currentPanelSize.width
        let height = currentPanelSize.height
        let desiredX = anchorPoint.x - (width / 2)
        let desiredY = anchorPoint.y + verticalOffset

        let minX = visibleFrame.minX + sideMargin
        let maxX = visibleFrame.maxX - width - sideMargin
        let minY = visibleFrame.minY + sideMargin
        let maxY = visibleFrame.maxY - height - sideMargin

        let clampedX = min(max(desiredX, minX), maxX)
        let clampedY = min(max(desiredY, minY), maxY)

        return NSRect(x: clampedX, y: clampedY, width: width, height: height)
    }

    private func hide(expectedGeneration: UInt64) {
        guard expectedGeneration == hideGeneration else { return }

        dismissTask?.cancel()
        dismissTask = nil

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            previewPanel.animator().alphaValue = 0
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard expectedGeneration == self.hideGeneration else { return }
                self.previewPanel.orderOut(nil)
                self.panel.orderOut(nil)
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        hideGeneration &+= 1
        previewPanel.animator().alphaValue = 0
        panel.animator().alphaValue = 0
        let gen = hideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, gen == self.hideGeneration else { return }
                self.previewPanel.orderOut(nil)
                self.panel.orderOut(nil)
            }
        }
    }

    func scheduleDismiss() {
        dismissTask?.cancel()
        let delay = self.dismissalDelay
        let generation = hideGeneration

        dismissTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.hide(expectedGeneration: generation)
            }
        }
    }

    private func updatePreview(preview: WindowActionPreview?) {
        guard let preview else {
            previewPanel.alphaValue = 0
            previewPanel.orderOut(nil)
            return
        }

        previewView.preview = preview
        previewPanel.setFrame(preview.frame, display: true)
    }
}

@MainActor
private final class GestureSnapPreviewView: NSView {
    var preview: WindowActionPreview? {
        didSet { needsDisplay = true }
    }

    private let cornerRadius: CGFloat = 18
    private let strokeWidth: CGFloat = 1.5

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

        guard let preview else { return }
        let previewRect = bounds.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)
        guard previewRect.isEmpty == false else { return }

        switch preview.style {
        case .area:
            drawAreaPreview(in: previewRect)
        }
    }

    private func drawAreaPreview(in previewRect: NSRect) {
        let path = NSBezierPath(roundedRect: previewRect, xRadius: cornerRadius, yRadius: cornerRadius)

        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        path.fill()

        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(
            roundedRect: NSRect(
                x: previewRect.minX + 1,
                y: previewRect.midY,
                width: max(0, previewRect.width - 2),
                height: max(0, (previewRect.height / 2) - 1)
            ),
            xRadius: max(0, cornerRadius - 3),
            yRadius: max(0, cornerRadius - 3)
        ).fill()

        NSColor.controlAccentColor.withAlphaComponent(0.62).setStroke()
        path.lineWidth = strokeWidth
        path.stroke()
    }
}

private final class GestureGlyphView: NSView {
    enum Style {
        case minimal
        case trackpad
    }

    var glyph: GestureHUDGlyph = .gesture(.swipeLeft) {
        didSet { needsDisplay = true }
    }

    var glyphStyle: Style = .minimal {
        didSet { needsDisplay = true }
    }

    var primaryColor: NSColor = NSColor.labelColor.withAlphaComponent(0.9) {
        didSet { needsDisplay = true }
    }

    var secondaryColor: NSColor = NSColor.labelColor.withAlphaComponent(0.16) {
        didSet { needsDisplay = true }
    }

    var lineWidth: CGFloat = 2.2 {
        didSet { needsDisplay = true }
    }

    var glowLineWidth: CGFloat = 4.8 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        defer { context.restoreGState() }

        switch glyphStyle {
        case .minimal:
            drawMinimalGlyph(in: bounds)
        case .trackpad:
            drawTrackpadGlyph(in: bounds)
        }
    }

    private func drawMinimalGlyph(in rect: NSRect) {
        let strokePadding = max(glowLineWidth, lineWidth) / 2
        let glyphRect = sanitizedRect(
            from: rect.insetBy(dx: strokePadding + 0.5, dy: strokePadding + 0.5),
            minimumSize: 8
        )
        guard glyphRect.isEmpty == false else { return }

        if secondaryColor.alphaComponent > 0.01, glowLineWidth > lineWidth {
            let glowPath = gestureArrowPath(in: glyphRect, lineWidth: glowLineWidth)
            secondaryColor.setStroke()
            glowPath.stroke()
        }

        let path = gestureArrowPath(in: glyphRect, lineWidth: lineWidth)
        primaryColor.setStroke()
        path.stroke()
    }

    private func drawTrackpadGlyph(in rect: NSRect) {
        let trackpadRect = sanitizedRect(from: rect.insetBy(dx: 3, dy: 5), minimumSize: 18)
        guard trackpadRect.isEmpty == false else { return }

        let platePath = NSBezierPath(roundedRect: trackpadRect, xRadius: 8, yRadius: 8)
        secondaryColor.setFill()
        platePath.fill()

        secondaryColor.withAlphaComponent(0.85).setStroke()
        platePath.lineWidth = 1
        platePath.stroke()

        let arrowRect = sanitizedRect(from: trackpadRect.insetBy(dx: 4, dy: 4), minimumSize: 10)
        guard arrowRect.isEmpty == false else { return }

        let arrow = gestureArrowPath(in: arrowRect, lineWidth: 2.3)
        primaryColor.setStroke()
        arrow.stroke()
    }

    private func gestureArrowPath(in rect: NSRect, lineWidth: CGFloat) -> NSBezierPath {
        let rect = rect.standardized
        let path = CGMutablePath()

        switch glyph {
        case .gesture(let gesture):
            switch gesture {
            case .swipeLeft:
                addArrow(
                    to: path,
                    from: point(in: rect, x: 0.84, y: 0.5),
                    to: point(in: rect, x: 0.18, y: 0.5),
                    wingA: point(in: rect, x: 0.42, y: 0.26),
                    wingB: point(in: rect, x: 0.42, y: 0.74)
                )
            case .swipeRight:
                addArrow(
                    to: path,
                    from: point(in: rect, x: 0.16, y: 0.5),
                    to: point(in: rect, x: 0.82, y: 0.5),
                    wingA: point(in: rect, x: 0.58, y: 0.26),
                    wingB: point(in: rect, x: 0.58, y: 0.74)
                )
            case .swipeUp:
                addArrow(
                    to: path,
                    from: point(in: rect, x: 0.5, y: 0.84),
                    to: point(in: rect, x: 0.5, y: 0.18),
                    wingA: point(in: rect, x: 0.26, y: 0.42),
                    wingB: point(in: rect, x: 0.74, y: 0.42)
                )
            case .swipeDown:
                addArrow(
                    to: path,
                    from: point(in: rect, x: 0.5, y: 0.16),
                    to: point(in: rect, x: 0.5, y: 0.82),
                    wingA: point(in: rect, x: 0.26, y: 0.58),
                    wingB: point(in: rect, x: 0.74, y: 0.58)
                )
            case .pinchIn:
                addLine(to: path, from: point(in: rect, x: 0.12, y: 0.18), to: point(in: rect, x: 0.38, y: 0.4))
                addLine(to: path, from: point(in: rect, x: 0.88, y: 0.18), to: point(in: rect, x: 0.62, y: 0.4))
                addLine(to: path, from: point(in: rect, x: 0.12, y: 0.82), to: point(in: rect, x: 0.38, y: 0.6))
                addLine(to: path, from: point(in: rect, x: 0.88, y: 0.82), to: point(in: rect, x: 0.62, y: 0.6))
            case .pinchOut:
                addArrow(
                    to: path,
                    from: point(in: rect, x: 0.42, y: 0.5),
                    to: point(in: rect, x: 0.16, y: 0.5),
                    wingA: point(in: rect, x: 0.34, y: 0.36),
                    wingB: point(in: rect, x: 0.34, y: 0.64)
                )
                addArrow(
                    to: path,
                    from: point(in: rect, x: 0.58, y: 0.5),
                    to: point(in: rect, x: 0.84, y: 0.5),
                    wingA: point(in: rect, x: 0.66, y: 0.36),
                    wingB: point(in: rect, x: 0.66, y: 0.64)
                )
            }
        case .diagonal(let direction):
            switch direction {
            case .topLeft:
                addArrow(
                    to: path,
                    from: point(in: rect, x: 0.82, y: 0.82),
                    to: point(in: rect, x: 0.2, y: 0.2),
                    wingA: point(in: rect, x: 0.5, y: 0.2),
                    wingB: point(in: rect, x: 0.2, y: 0.5)
                )
            case .topRight:
                addArrow(
                    to: path,
                    from: point(in: rect, x: 0.18, y: 0.82),
                    to: point(in: rect, x: 0.8, y: 0.2),
                    wingA: point(in: rect, x: 0.5, y: 0.2),
                    wingB: point(in: rect, x: 0.8, y: 0.5)
                )
            case .bottomLeft:
                addArrow(
                    to: path,
                    from: point(in: rect, x: 0.82, y: 0.18),
                    to: point(in: rect, x: 0.2, y: 0.8),
                    wingA: point(in: rect, x: 0.2, y: 0.5),
                    wingB: point(in: rect, x: 0.5, y: 0.8)
                )
            case .bottomRight:
                addArrow(
                    to: path,
                    from: point(in: rect, x: 0.18, y: 0.18),
                    to: point(in: rect, x: 0.8, y: 0.8),
                    wingA: point(in: rect, x: 0.5, y: 0.8),
                    wingB: point(in: rect, x: 0.8, y: 0.5)
                )
            }
        case .cornerMode:
            addArrow(
                to: path,
                from: point(in: rect, x: 0.46, y: 0.46),
                to: point(in: rect, x: 0.16, y: 0.16),
                wingA: point(in: rect, x: 0.32, y: 0.16),
                wingB: point(in: rect, x: 0.16, y: 0.32)
            )
            addArrow(
                to: path,
                from: point(in: rect, x: 0.54, y: 0.46),
                to: point(in: rect, x: 0.84, y: 0.16),
                wingA: point(in: rect, x: 0.68, y: 0.16),
                wingB: point(in: rect, x: 0.84, y: 0.32)
            )
            addArrow(
                to: path,
                from: point(in: rect, x: 0.46, y: 0.54),
                to: point(in: rect, x: 0.16, y: 0.84),
                wingA: point(in: rect, x: 0.16, y: 0.68),
                wingB: point(in: rect, x: 0.32, y: 0.84)
            )
            addArrow(
                to: path,
                from: point(in: rect, x: 0.54, y: 0.54),
                to: point(in: rect, x: 0.84, y: 0.84),
                wingA: point(in: rect, x: 0.68, y: 0.84),
                wingB: point(in: rect, x: 0.84, y: 0.68)
            )
        }

        let bezierPath = NSBezierPath(cgPath: path)
        bezierPath.lineCapStyle = .round
        bezierPath.lineJoinStyle = .round
        bezierPath.lineWidth = lineWidth

        let pathBounds = bezierPath.bounds
        guard pathBounds.isEmpty == false else { return bezierPath }

        let transform = AffineTransform(
            translationByX: rect.midX - pathBounds.midX,
            byY: rect.midY - pathBounds.midY
        )
        bezierPath.transform(using: transform)
        return bezierPath
    }

    private func sanitizedRect(from rect: NSRect, minimumSize: CGFloat) -> NSRect {
        guard
            rect.origin.x.isFinite,
            rect.origin.y.isFinite,
            rect.size.width.isFinite,
            rect.size.height.isFinite
        else {
            return .zero
        }

        let standardized = rect.standardized
        guard standardized.width >= minimumSize, standardized.height >= minimumSize else {
            return .zero
        }

        return standardized
    }

    private func addLine(to path: CGMutablePath, from start: CGPoint, to end: CGPoint) {
        guard
            start.x.isFinite,
            start.y.isFinite,
            end.x.isFinite,
            end.y.isFinite
        else {
            return
        }

        path.move(to: start)
        path.addLine(to: end)
    }

    private func addArrow(
        to path: CGMutablePath,
        from tail: CGPoint,
        to tip: CGPoint,
        wingA: CGPoint,
        wingB: CGPoint
    ) {
        addLine(to: path, from: tail, to: tip)
        addLine(to: path, from: tip, to: wingA)
        addLine(to: path, from: tip, to: wingB)
    }

    private func point(in rect: NSRect, x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(
            x: rect.minX + (rect.width * x),
            y: rect.minY + (rect.height * y)
        )
    }
}
