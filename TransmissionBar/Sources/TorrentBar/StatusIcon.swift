import AppKit

// A template image lets macOS tint the border and mark for either menu-bar
// appearance. Everything between them stays transparent, including at Retina scale.
enum StatusIcon {
    static func make() -> NSImage { image }

    private static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let border = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 16, height: 16),
                                      xRadius: 3, yRadius: 3)
            border.lineWidth = 1.2
            border.stroke()

            // Simplify the reference's vertical arrows and horizontal handle so
            // they remain legible at the menu bar's actual 18-point size.
            let upperArrow = NSBezierPath()
            upperArrow.move(to: NSPoint(x: 9, y: 3.3))
            upperArrow.line(to: NSPoint(x: 12, y: 6.9))
            upperArrow.line(to: NSPoint(x: 10, y: 6.9))
            upperArrow.line(to: NSPoint(x: 10, y: 7.2))
            upperArrow.line(to: NSPoint(x: 8, y: 7.2))
            upperArrow.line(to: NSPoint(x: 8, y: 6.9))
            upperArrow.line(to: NSPoint(x: 6, y: 6.9))
            upperArrow.close()
            upperArrow.fill()

            NSBezierPath(roundedRect: NSRect(x: 4.5, y: 8, width: 9, height: 2),
                         xRadius: 1, yRadius: 1).fill()

            let lowerArrow = NSBezierPath()
            lowerArrow.move(to: NSPoint(x: 8, y: 10.8))
            lowerArrow.line(to: NSPoint(x: 10, y: 10.8))
            lowerArrow.line(to: NSPoint(x: 10, y: 11.1))
            lowerArrow.line(to: NSPoint(x: 12, y: 11.1))
            lowerArrow.line(to: NSPoint(x: 9, y: 14.7))
            lowerArrow.line(to: NSPoint(x: 6, y: 11.1))
            lowerArrow.line(to: NSPoint(x: 8, y: 11.1))
            lowerArrow.close()
            lowerArrow.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
