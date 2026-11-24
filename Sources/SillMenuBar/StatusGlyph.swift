import AppKit

/// The status item's image: iOSClient/Sill.icon reduced to a menu bar template. The icon's back pane is
/// solid and its front pane an outline over it, cut free by a gap, and the state shows in the front pane:
/// empty (idle), the icon's three dots (a device is connected), the dots and the icon's three lines
/// (streaming), or a badge at the lower right (Sill needs attention).
///
/// Drawn in code from the icon's own coordinates (its 1024 grid), so there is no asset to keep in sync,
/// and marked as a template so the menu bar tints it for light and dark bars and highlights it when the
/// menu is open. `symbolFallback` (SF Symbol rectangle.on.rectangle) is the stand-in if this drawing is
/// ever dropped; the previews render both side by side.
enum StatusGlyph {
    enum State: Equatable, CaseIterable { case idle, connected, streaming, attention }

    /// 18 pt tall: 16 pt of drawing and a point above and below, like the system's own items.
    static let size = NSSize(width: 21, height: 18)

    static let symbolFallback: NSImage? = {
        let image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Sill")
        image?.isTemplate = true
        return image
    }()

    static func image(_ state: State) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(state, in: ctx)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Sill"
        return image
    }

    // MARK: Geometry, in Sill.icon units (1024 grid)

    /// The panes as Sill.icon draws them (portal-frame.svg, glass-pane.svg) and the span they cover.
    private static let back = CGRect(x: 128, y: 186, width: 644, height: 532)
    private static let front = CGRect(x: 252, y: 306, width: 644, height: 532)
    private static let paneRadius: CGFloat = 112
    private static let span = back.union(front)

    /// Units → points: the panes' 652-unit height in 16 pt, centred in the image.
    private static let scale: CGFloat = 16 / span.height
    private static let origin = CGPoint(x: span.midX - size.width / 2 / scale, y: span.midY - size.height / 2 / scale)

    private static func rect(_ r: CGRect) -> CGRect {
        CGRect(x: (r.minX - origin.x) * scale, y: (r.minY - origin.y) * scale, width: r.width * scale, height: r.height * scale)
    }

    private static func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        let box = rect(r)
        let corner = min(radius * scale, box.width / 2, box.height / 2)
        return CGPath(roundedRect: box, cornerWidth: corner, cornerHeight: corner, transform: nil)
    }

    private static func draw(_ state: State, in ctx: CGContext) {
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setStrokeColor(NSColor.black.cgColor)

        let stroke: CGFloat = 61                              // 1.5 pt
        let gap: CGFloat = 51                                 // 1.25 pt

        ctx.addPath(rounded(back, paneRadius))
        ctx.fillPath()
        ctx.setBlendMode(.clear)
        ctx.addPath(rounded(front.insetBy(dx: -gap, dy: -gap), paneRadius + gap))
        ctx.fillPath()
        ctx.setBlendMode(.normal)

        ctx.setLineWidth(stroke * scale)
        ctx.addPath(rounded(front.insetBy(dx: stroke / 2, dy: stroke / 2), paneRadius - stroke / 2))
        ctx.strokePath()

        let dot: CGFloat = 72
        let dots = (0..<3).map { CGRect(x: 360 + CGFloat($0) * 104, y: 392, width: dot, height: dot) }
        let lines = [CGRect(x: 360, y: 548, width: 440, height: 64), CGRect(x: 360, y: 676, width: 288, height: 64)]
        switch state {
        case .connected:
            dots.forEach { ctx.fillEllipse(in: rect($0)) }
        case .streaming:
            dots.forEach { ctx.fillEllipse(in: rect($0)) }
            lines.forEach { ctx.addPath(rounded($0, $0.height / 2)) }
            ctx.fillPath()
        case .idle, .attention:
            break
        }

        if state == .attention {
            let d = size.height * 0.42
            let badge = CGRect(x: size.width - d, y: size.height - d, width: d, height: d)
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: badge.insetBy(dx: -1.5, dy: -1.5))
            ctx.setBlendMode(.normal)
            ctx.fillEllipse(in: badge)
        }
    }
}
