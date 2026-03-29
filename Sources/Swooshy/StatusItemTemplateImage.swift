import AppKit

enum StatusItemTemplateImage {
    private static let canvasSize = NSSize(width: 18, height: 18)

    static func loadTemplateImage(
        named name: String,
        accessibilityDescription: String
    ) -> NSImage? {
        let resourceURL = preferredResourceURL(named: name)

        guard
            let resourceURL,
            let image = NSImage(contentsOf: resourceURL)
        else {
            return nil
        }

        image.size = NSSize(width: 22, height: 22)
        image.accessibilityDescription = accessibilityDescription
        image.isTemplate = true
        return image
    }

    private static func preferredResourceURL(named name: String) -> URL? {
        let candidates: [(String, String?)] = [
            ("png", "StatusItem"),
            ("png", nil),
            ("pdf", "StatusItem"),
            ("pdf", nil),
        ]

        for (fileExtension, subdirectory) in candidates {
            let url: URL?

            if let subdirectory {
                url = Bundle.module.url(
                    forResource: name,
                    withExtension: fileExtension,
                    subdirectory: subdirectory
                )
            } else {
                url = Bundle.module.url(forResource: name, withExtension: fileExtension)
            }

            if let url {
                return url
            }
        }

        return nil
    }

    static func makeGaleTemplateImage() -> NSImage {
        let image = NSImage(size: canvasSize, flipped: false) { bounds in
            drawGale(in: bounds)
            return true
        }

        image.size = canvasSize
        image.isTemplate = true
        return image
    }

    private static func drawGale(in bounds: NSRect) {
        NSColor.black.setStroke()

        let windowRect = NSRect(x: 2.1, y: 3.25, width: 10.9, height: 8.85)
        let windowOutline = NSBezierPath(
            roundedRect: windowRect,
            xRadius: 2.45,
            yRadius: 2.45
        )
        windowOutline.lineWidth = 1.2
        windowOutline.lineJoinStyle = .round
        windowOutline.stroke()

        let header = NSBezierPath()
        header.move(to: NSPoint(x: windowRect.minX + 1.0, y: windowRect.maxY - 2.8))
        header.line(to: NSPoint(x: windowRect.maxX - 1.0, y: windowRect.maxY - 2.8))
        header.lineWidth = 1.0
        header.lineCapStyle = .round
        header.stroke()

        let swoosh = NSBezierPath()
        swoosh.move(to: NSPoint(x: bounds.maxX - 5.2, y: bounds.maxY - 2.45))
        swoosh.curve(
            to: NSPoint(x: 11.15, y: 12.05),
            controlPoint1: NSPoint(x: 14.8, y: 15.0),
            controlPoint2: NSPoint(x: 12.85, y: 13.45)
        )
        swoosh.curve(
            to: NSPoint(x: 9.45, y: 10.05),
            controlPoint1: NSPoint(x: 10.25, y: 11.35),
            controlPoint2: NSPoint(x: 9.75, y: 10.85)
        )
        swoosh.curve(
            to: NSPoint(x: 11.65, y: 7.55),
            controlPoint1: NSPoint(x: 9.45, y: 9.1),
            controlPoint2: NSPoint(x: 11.4, y: 8.75)
        )
        swoosh.curve(
            to: NSPoint(x: 10.45, y: 4.35),
            controlPoint1: NSPoint(x: 12.2, y: 6.45),
            controlPoint2: NSPoint(x: 11.7, y: 5.0)
        )
        swoosh.lineWidth = 2.25
        swoosh.lineCapStyle = .round
        swoosh.lineJoinStyle = .round
        swoosh.stroke()

        let lowerCurl = NSBezierPath()
        lowerCurl.move(to: NSPoint(x: 10.45, y: 5.55))
        lowerCurl.curve(
            to: NSPoint(x: 8.8, y: 6.6),
            controlPoint1: NSPoint(x: 9.75, y: 5.15),
            controlPoint2: NSPoint(x: 9.0, y: 5.65)
        )
        lowerCurl.lineWidth = 1.25
        lowerCurl.lineCapStyle = .round
        lowerCurl.stroke()

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 12.3, y: 5.25))
        tail.curve(
            to: NSPoint(x: 13.45, y: 6.05),
            controlPoint1: NSPoint(x: 12.75, y: 5.25),
            controlPoint2: NSPoint(x: 13.15, y: 5.55)
        )
        tail.lineWidth = 1.0
        tail.lineCapStyle = .round
        tail.stroke()
    }
}
