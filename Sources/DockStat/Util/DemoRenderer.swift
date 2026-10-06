import AppKit

/// Offscreen previews for the README (`--demo`, `make demo`).
///
/// The two things the app actually draws — the status item and the Dock tile —
/// come from its own renderers (`BarItemRenderer`, `DockIconRenderer`), laid out
/// on a synthetic menu bar and Dock. The pictures therefore cannot drift from
/// what the app draws, and no screen recording permission is involved.
///
/// Everything is deterministic: the inputs are fixed here rather than read from
/// `SettingsModel`, so `make demo` renders the same files on any machine.
@MainActor
enum DemoRenderer {
    // MARK: - Canonical demo state

    private static let sample = Sample(
        cpu: 27,
        mem: 73,
        diskFree: 41_500_000_000,
        diskTotal: 245_100_000_000
    )
    private static let stats: [StatKind] = [.cpu, .mem, .disk]
    private static let separator = "  "

    /// 2× so the PNGs stay sharp wherever they are scaled.
    private static let scale: CGFloat = 2

    private static let textColor = NSColor(white: 1, alpha: 0.92)
    private static let secondaryColor = NSColor(white: 1, alpha: 0.72)
    private static let captionColor = NSColor(white: 1, alpha: 0.55)
    private static let hairlineColor = NSColor(white: 1, alpha: 0.14)

    // MARK: - Entry points

    static func writeAll(into directory: String) {
        let images: [(name: String, image: NSImage)] = [
            ("demo.png", heroImage()),
            ("menu-bar.png", menuBarImage()),
            ("dock-icon.png", dockIconImage()),
        ]
        for (name, image) in images {
            let path = (directory as NSString).appendingPathComponent(name)
            write(image, to: path)
            print("wrote \(path) (\(Int(image.size.width))×\(Int(image.size.height)) pt)")
        }
    }

    /// A macOS desktop with the status item in the menu bar and the Dock tile in
    /// the Dock: where the app lives, in one picture.
    static func heroImage() -> NSImage {
        let width: CGFloat = 820
        let height: CGFloat = 232
        let barHeight: CGFloat = 24
        let shelfHeight: CGFloat = 64
        let shelf = NSRect(
            x: (width - dockShelfWidth()) / 2,
            y: height - 10 - shelfHeight,
            width: dockShelfWidth(),
            height: shelfHeight
        )

        return canvas(width: width, height: height) {
            drawDesktop(in: NSRect(x: 0, y: 0, width: width, height: height))

            NSColor(white: 0, alpha: 0.35).setFill()
            NSRect(x: 0, y: 0, width: width, height: barHeight).fill()
            hairline(from: CGPoint(x: 0, y: barHeight), to: CGPoint(x: width, y: barHeight))
            drawMenuBar(in: NSRect(x: 0, y: 0, width: width, height: barHeight))

            let path = NSBezierPath(roundedRect: shelf, xRadius: 16, yRadius: 16)
            NSColor(white: 1, alpha: 0.13).setFill()
            path.fill()
            NSColor(white: 1, alpha: 0.18).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            drawDock(in: shelf)
        }
    }

    /// The three menu bar styles side by side, each labelled — the setting users
    /// pick between.
    static func menuBarImage() -> NSImage {
        let captionFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let gapBetweenGroups: CGFloat = 26
        let gapInsideGroup: CGFloat = 12
        let padding: CGFloat = 18

        let items = BarStyle.allCases.map { style in
            (
                style: style,
                image: art(for: barItem(style: style)),
                caption: style.title
            )
        }
        let width = padding * 2
            + items.reduce(0) { $0 + $1.image.size.width + gapInsideGroup + captionWidth($1.caption, font: captionFont) }
            + gapBetweenGroups * CGFloat(items.count - 1)
        let contentHeight = items.map(\.image.size.height).max() ?? 0
        let height = ceil(contentHeight) + 34

        return canvas(width: ceil(width), height: height) {
            let board = NSRect(x: 0.5, y: 0.5, width: ceil(width) - 1, height: height - 1)
            let path = NSBezierPath(roundedRect: board, xRadius: 12, yRadius: 12)
            NSColor(srgbRed: 0.05, green: 0.06, blue: 0.08, alpha: 1).setFill()
            path.fill()
            NSColor(white: 1, alpha: 0.12).setStroke()
            path.lineWidth = 1
            path.stroke()

            var x = padding
            for (index, item) in items.enumerated() {
                if index > 0 { x += gapBetweenGroups }
                let size = item.image.size
                item.image.draw(in: NSRect(x: x, y: (height - size.height) / 2, width: size.width, height: size.height))
                x += size.width + gapInsideGroup
                label(item.caption, at: x, midY: height / 2, font: captionFont, color: captionColor)
                x += captionWidth(item.caption, font: captionFont)
            }
        }
    }

    /// Just the Dock tile, large, for the Dock icon section.
    static func dockIconImage() -> NSImage {
        let tile: CGFloat = 256
        let side: CGFloat = 320
        return canvas(width: side, height: side) {
            let context = NSGraphicsContext.current?.cgContext
            context?.setShadow(
                offset: CGSize(width: 0, height: -10),
                blur: 16,
                color: NSColor(white: 0, alpha: 0.4).cgColor
            )
            dockTile(size: tile).draw(in: NSRect(
                x: (side - tile) / 2,
                y: (side - tile) / 2,
                width: tile,
                height: tile
            ))
            context?.setShadow(offset: .zero, blur: 0, color: nil)
        }
    }

    // MARK: - The app's own art

    /// The status item's content, as the live one draws it: the stacked styles
    /// are an image, the plain one an attributed title.
    private static func art(for item: BarItemRenderer) -> NSImage {
        if let stacked = item.image() { return stacked }

        let title = item.attributedTitle()
        let size = title.size()
        return NSImage(size: size, flipped: false) { _ in
            title.draw(at: .zero)
            return true
        }
    }

    private static func dockTile(size: CGFloat) -> NSImage {
        DockIconRenderer().image(for: IconSpec(
            line1: Formatters.percent(sample.cpu ?? 0),
            line2: StatKind.cpu.label,
            background: .iconBackground,
            border: .iconBorder,
            text: .iconText,
            borderWidth: 0.035,
            size: size
        ))
    }

    private static func barItem(style: BarStyle) -> BarItemRenderer {
        BarItemRenderer(
            stats: stats,
            style: style,
            separator: separator,
            text: { kind in
                switch kind {
                case .cpu: Formatters.percent(sample.cpu ?? 0)
                case .mem: Formatters.percent(sample.mem ?? 0)
                case .disk: Formatters.bytes(sample.diskFree ?? 0)
                }
            },
            color: { _ in textColor },
            separatorColor: NSColor(white: 1, alpha: 0.85),
            marker: { _ in "" }
        )
    }

    // MARK: - Desktop chrome

    private static func drawDesktop(in rect: NSRect) {
        NSGradient(colors: [
            NSColor(srgbRed: 0.10, green: 0.15, blue: 0.22, alpha: 1),
            NSColor(srgbRed: 0.03, green: 0.05, blue: 0.08, alpha: 1),
        ])?.draw(in: rect, angle: -90)

        // Soft light, so the wallpaper does not read as a flat fill.
        let center = NSPoint(x: rect.midX, y: rect.midY + rect.height * 0.12)
        NSGradient(colors: [
            NSColor(white: 1, alpha: 0.10),
            NSColor(white: 1, alpha: 0),
        ])?.draw(fromCenter: center, radius: 0, toCenter: center, radius: rect.width * 0.5, options: [])
    }

    private static func drawMenuBar(in rect: NSRect) {
        let midY = rect.midY
        var x: CGFloat = 14

        if let logo = SymbolImage.menuBar("apple.logo", pointSize: 13, color: textColor) {
            let size = logo.size
            logo.draw(in: NSRect(x: x, y: midY - size.height / 2, width: size.width, height: size.height))
            x += size.width + 11
        }
        x += label("DockStat", at: x, midY: midY, font: .systemFont(ofSize: 12.5, weight: .semibold), color: textColor) + 14
        for menu in ["File", "Edit", "View", "Window", "Help"] {
            x += label(menu, at: x, midY: midY, font: .systemFont(ofSize: 12.5), color: secondaryColor) + 13
        }

        // Right to left: clock, then the system icons, then our own item.
        var right = rect.maxX - 14
        let clock = attributed("Mon 9:41 AM", font: .systemFont(ofSize: 12.5, weight: .semibold), color: textColor)
        let clockSize = clock.size()
        clock.draw(at: NSPoint(x: right - clockSize.width, y: midY - clockSize.height / 2))
        right -= clockSize.width + 14

        for symbol in ["switch.2", "battery.100percent", "wifi"] {
            guard let image = SymbolImage.menuBar(symbol, pointSize: 12, color: textColor) else { continue }
            let size = image.size
            image.draw(in: NSRect(x: right - size.width, y: midY - size.height / 2, width: size.width, height: size.height))
            right -= size.width + 12
        }

        let item = art(for: barItem(style: .percent))
        let size = item.size
        item.draw(in: NSRect(
            x: right - 16 - size.width,
            y: midY - size.height / 2,
            width: size.width,
            height: size.height
        ))
    }

    private enum DockEntry {
        case app(String)
        case dockStat
        case divider
    }

    /// Real system icons when they are installed (they read instantly as "the
    /// Dock"); the layout does not depend on which ones exist.
    private static let dockEntries: [DockEntry] = [
        .app("/System/Library/CoreServices/Finder.app"),
        .app("/Applications/Safari.app"),
        .app("/System/Applications/Utilities/Terminal.app"),
        .divider,
        .dockStat,
    ]

    private static let tileSize: CGFloat = 44
    private static let tileGap: CGFloat = 8

    private static func dockShelfWidth() -> CGFloat {
        var width: CGFloat = 24
        var isFirstTile = true
        for entry in dockEntries {
            switch entry {
            case .divider:
                width += 21
                isFirstTile = true
            case .app, .dockStat:
                if !isFirstTile { width += tileGap }
                width += tileSize
                isFirstTile = false
            }
        }
        return width
    }

    private static func drawDock(in shelf: NSRect) {
        var x = shelf.minX + 12
        var isFirstTile = true

        for entry in dockEntries {
            switch entry {
            case .divider:
                NSColor(white: 1, alpha: 0.25).setFill()
                NSRect(x: x + 10, y: shelf.midY - 18, width: 0.5, height: 36).fill()
                x += 21
                isFirstTile = true

            case .app(let path):
                if !isFirstTile { x += tileGap }
                let rect = NSRect(x: x, y: shelf.midY - tileSize / 2, width: tileSize, height: tileSize)
                appIcon(at: path).draw(in: rect)
                x += tileSize
                isFirstTile = false

            case .dockStat:
                if !isFirstTile { x += tileGap }
                let rect = NSRect(x: x, y: shelf.midY - tileSize / 2, width: tileSize, height: tileSize)
                dockTile(size: tileSize).draw(in: rect)
                // Running indicator, as the Dock draws it.
                NSColor(white: 1, alpha: 0.75).setFill()
                NSBezierPath(ovalIn: NSRect(
                    x: rect.midX - 1.75,
                    y: shelf.maxY - 7,
                    width: 3.5,
                    height: 3.5
                )).fill()
                x += tileSize
                isFirstTile = false
            }
        }
    }

    private static func appIcon(at path: String) -> NSImage {
        // Resolve first: `/Applications/Safari.app` is a symlink, and the Finder
        // icon for a symlink carries an alias badge.
        let resolved = (path as NSString).resolvingSymlinksInPath
        guard FileManager.default.fileExists(atPath: resolved) else { return placeholderTile() }
        let icon = NSWorkspace.shared.icon(forFile: resolved)
        icon.size = NSSize(width: tileSize, height: tileSize)
        return icon
    }

    private static func placeholderTile() -> NSImage {
        let size = NSSize(width: tileSize, height: tileSize)
        return NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: tileSize * 0.23, yRadius: tileSize * 0.23)
            NSGradient(
                starting: NSColor(white: 0.45, alpha: 1),
                ending: NSColor(white: 0.24, alpha: 1)
            )?.draw(in: path, angle: -90)

            if let glyph = SymbolImage.menuBar("app.fill", pointSize: tileSize * 0.42, color: NSColor(white: 1, alpha: 0.9)) {
                let glyphSize = glyph.size
                glyph.draw(in: NSRect(
                    x: rect.midX - glyphSize.width / 2,
                    y: rect.midY - glyphSize.height / 2,
                    width: glyphSize.width,
                    height: glyphSize.height
                ))
            }
            return true
        }
    }

    // MARK: - Drawing helpers

    /// Flipped canvas: the layout code below reads top-down, like the screen.
    private static func canvas(width: CGFloat, height: CGFloat, body: @escaping () -> Void) -> NSImage {
        let logical = NSSize(width: width, height: height)
        let image = NSImage(size: logical)

        if let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width * scale),
            pixelsHigh: Int(height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) {
            rep.size = logical
            image.addRepresentation(rep)

            NSGraphicsContext.saveGraphicsState()
            if let context = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = context
                NSImage(size: logical, flipped: true, drawingHandler: { _ in
                    body()
                    return true
                }).draw(in: NSRect(origin: .zero, size: logical))
                context.flushGraphics()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        return image
    }

    private static func attributed(_ string: String, font: NSFont, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    }

    /// Draws a single line with its box centred on `midY`; returns its width.
    @discardableResult
    private static func label(_ string: String, at x: CGFloat, midY: CGFloat, font: NSFont, color: NSColor) -> CGFloat {
        let text = attributed(string, font: font, color: color)
        let size = text.size()
        text.draw(at: NSPoint(x: x, y: midY - size.height / 2))
        return size.width
    }

    private static func captionWidth(_ string: String, font: NSFont) -> CGFloat {
        attributed(string, font: font, color: captionColor).size().width
    }

    private static func hairline(from: CGPoint, to: CGPoint) {
        let path = NSBezierPath()
        path.move(to: from)
        path.line(to: to)
        path.lineWidth = 0.5
        hairlineColor.setStroke()
        path.stroke()
    }

    private static func write(_ image: NSImage, to path: String) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            print("demo render failed: \(path)")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
