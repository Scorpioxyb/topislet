import AppKit

@MainActor
enum BrandIdentity {
    // A single-color optical master of the approved wraparound visor.
    // AppKit tints the template for both light and dark menu bars.
    static func visorPath() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0.4, y: 8))
        path.curve(to: NSPoint(x: 3, y: 7.6),
                   controlPoint1: NSPoint(x: 1.2, y: 7.6),
                   controlPoint2: NSPoint(x: 2, y: 7.6))
        path.line(to: NSPoint(x: 17, y: 7.6))
        path.curve(to: NSPoint(x: 19.6, y: 8),
                   controlPoint1: NSPoint(x: 18, y: 7.6),
                   controlPoint2: NSPoint(x: 18.8, y: 7.6))
        path.curve(to: NSPoint(x: 15, y: 0.6),
                   controlPoint1: NSPoint(x: 20, y: 3),
                   controlPoint2: NSPoint(x: 18, y: 0.6))
        path.curve(to: NSPoint(x: 11.5, y: 2),
                   controlPoint1: NSPoint(x: 12.5, y: 0.6),
                   controlPoint2: NSPoint(x: 12.2, y: 0.6))
        path.curve(to: NSPoint(x: 10, y: 2.7),
                   controlPoint1: NSPoint(x: 11, y: 2.6),
                   controlPoint2: NSPoint(x: 10.5, y: 2.7))
        path.curve(to: NSPoint(x: 8.5, y: 2),
                   controlPoint1: NSPoint(x: 9.5, y: 2.7),
                   controlPoint2: NSPoint(x: 9, y: 2.6))
        path.curve(to: NSPoint(x: 5, y: 0.6),
                   controlPoint1: NSPoint(x: 7.8, y: 0.6),
                   controlPoint2: NSPoint(x: 7.5, y: 0.6))
        path.curve(to: NSPoint(x: 0.4, y: 8),
                   controlPoint1: NSPoint(x: 2, y: 0.6),
                   controlPoint2: NSPoint(x: 0, y: 3))
        path.close()
        return path
    }

    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 8), flipped: false) { _ in
            NSColor.black.setFill()
            visorPath().fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "顶屿"
        return image
    }

    static func applicationImage() -> NSImage {
        if let url = Bundle.main.url(forResource: "IslandAppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return menuBarImage()
    }
}
