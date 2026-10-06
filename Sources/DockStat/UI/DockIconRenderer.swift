import AppKit
import CoreText

/// Specification of what the Dock icon should show.
struct IconSpec: Equatable, Sendable {
    var line1: String = ""
    var line2: String = ""
    var background: RGBAColor = .iconBackground
    var border: RGBAColor = .iconBorder
    var text: RGBAColor = .iconText
    var borderWidth: Double = 0.035
    /// 256 pt @2x = 512 px: twice what the Dock can display, and the image path
    /// costs roughly linearly in pixels when assigned to `applicationIconImage`.
    var size: CGFloat = 256

    var cacheKey: String {
        "\(line1)|\(line2)|\(background.hex)|\(border.hex)|\(text.hex)|\(borderWidth)|\(size)"
    }
}

/// Draws the squircle icon. Images and text lines are cached; a repaint only
/// happens when the rendered strings or colours actually change.
@MainActor
final class DockIconRenderer {
    private var imageCache: [String: NSImage] = [:]
    private var lineCache: [String: CTLine] = [:]

    func image(for spec: IconSpec) -> NSImage {
        if let cached = imageCache[spec.cacheKey] { return cached }

        let image = render(spec)
        // A 512pt @2x bitmap is ~4 MB, so keep the cache tiny: only the
        // currently displayed icon matters.
        if imageCache.count >= 2 { imageCache.removeAll(keepingCapacity: true) }
        imageCache[spec.cacheKey] = image
        return image
    }

    private func render(_ spec: IconSpec) -> NSImage {
        let size = spec.size
        let pixels = Int(size * 2)

        let image = NSImage(size: NSSize(width: size, height: size))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return image }
        rep.size = NSSize(width: size, height: size)
        image.addRepresentation(rep)

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            Self.draw(in: context.cgContext, size: size, spec: spec, lines: layout(spec))
            context.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()

        return image
    }

    // MARK: - Text

    /// A laid-out line: the CTLine plus its width, ready to draw.
    struct LaidOutLine {
        var line: CTLine
        var width: CGFloat
        var fontSize: CGFloat
    }

    func layout(_ spec: IconSpec) -> [LaidOutLine] {
        let hasSecond = !spec.line2.isEmpty
        let firstSize = spec.size * (hasSecond ? 0.30 : 0.38)
        // The bottom line stays clearly subordinate to the top one, but big
        // enough to read at the Dock's ~128pt tile.
        let secondSize = spec.size * 0.195
        return [
            make(spec.line1, size: firstSize, color: spec.text),
            hasSecond ? make(spec.line2, size: secondSize, color: spec.text) : nil
        ].compactMap { $0 }
    }

    private func make(_ text: String, size fontSize: CGFloat, color: RGBAColor) -> LaidOutLine? {
        guard !text.isEmpty else { return nil }
        let key = "\(text)|\(Int(fontSize))|\(color.hex)"
        if let cached = lineCache[key] {
            return LaidOutLine(line: cached, width: CTLineGetTypographicBounds(cached, nil, nil, nil), fontSize: fontSize)
        }
        let font = CTFontCreateWithName("SFMono-Bold" as CFString, fontSize, nil)
        // CoreText ignores the context fill colour unless the colour comes from
        // the attributes, so bake it in (and key the cache on it).
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color.cgColor
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        if lineCache.count > 32 { lineCache.removeAll(keepingCapacity: true) }
        lineCache[key] = line
        return LaidOutLine(line: line, width: CTLineGetTypographicBounds(line, nil, nil, nil), fontSize: fontSize)
    }

    // MARK: - Drawing

    /// macOS app icons leave a transparent margin around the squircle: the
    /// shape is 824 of the 1024pt icon grid, i.e. 100pt on each side. Drawing
    /// edge to edge makes the tile read larger than its Dock neighbours.
    static let contentMargin: CGFloat = 100.0 / 1024.0

    static func draw(in cg: CGContext, size: CGFloat, spec: IconSpec, lines: [LaidOutLine]) {
        // Scale everything — squircle, border, text, separator — into the
        // content box, so the icon matches the system grid at any size.
        let margin = size * contentMargin
        let content = size - margin * 2
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.translateBy(x: margin, y: margin)
        cg.scaleBy(x: content / size, y: content / size)

        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let radius = size * 0.2237

        cg.setShouldAntialias(true)
        cg.setAllowsAntialiasing(true)

        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        cg.addPath(path)
        cg.setFillColor(spec.background.cgColor)
        cg.fillPath()

        let lineWidth = max(size * spec.borderWidth, 1)
        let stroke = CGPath(
            roundedRect: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
        cg.addPath(stroke)
        cg.setStrokeColor(spec.border.cgColor)
        cg.setLineWidth(lineWidth)
        cg.strokePath()

        guard !lines.isEmpty else { return }
        cg.setFillColor(spec.text.cgColor)
        cg.textMatrix = .identity

        if lines.count == 1 {
            drawCentered(lines[0], in: cg, size: size, centerY: size * 0.50)
        } else {
            drawCentered(lines[0], in: cg, size: size, centerY: size * 0.635)
            drawCentered(lines[1], in: cg, size: size, centerY: size * 0.275)

            // Hairline separator, as in the reference icon.
            let inset = size * 0.20
            cg.setStrokeColor(spec.text.cgColor.copy(alpha: 0.55) ?? spec.text.cgColor)
            cg.setLineWidth(max(size * 0.008, 1))
            cg.move(to: CGPoint(x: inset, y: size * 0.455))
            cg.addLine(to: CGPoint(x: size - inset, y: size * 0.455))
            cg.strokePath()
        }
    }

    private static func drawCentered(_ laid: LaidOutLine, in cg: CGContext, size: CGFloat, centerY: CGFloat) {
        let x = (size - laid.width) / 2
        let baseline = centerY - laid.fontSize * 0.35
        cg.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(laid.line, cg)
    }
}

/// Live `NSView` for the Dock tile. This is the default renderer: the Dock
/// draws it directly, so a repaint cannot be swallowed by an icon cache, and
/// updating it costs a fraction of reassigning `applicationIconImage`.
@MainActor
final class DockTileView: NSView {
    var spec: IconSpec = IconSpec() {
        didSet { if spec != oldValue { needsDisplay = true } }
    }
    private let renderer = DockIconRenderer()

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext, bounds.width > 0 else { return }
        var sized = spec
        sized.size = bounds.width
        let laid = renderer.layout(sized)
        DockIconRenderer.draw(in: cg, size: bounds.width, spec: sized, lines: laid)
    }
}
