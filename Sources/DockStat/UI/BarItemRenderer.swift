import AppKit

/// Draws the *content* of the menu bar status item.
///
/// Extracted from `StatsStore` so the offscreen `--demo` renderer draws the very
/// same art the live item shows: a README picture that cannot drift from the
/// code. Everything the drawing depends on is passed in, so nothing here reads
/// the running user's settings.
@MainActor
struct BarItemRenderer {
    /// Metrics to show, in order.
    var stats: [StatKind]
    var style: BarStyle
    /// Drawn between metrics.
    var separator: String
    /// Formatted value for a metric.
    var text: (StatKind) -> String
    /// Colour for a metric, already escalated for its severity.
    var color: (StatKind) -> NSColor
    /// Colour of the separators.
    var separatorColor: NSColor
    /// `!` / `⚠` suffix, empty when the metric is normal.
    var marker: (StatKind) -> String

    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    /// Stacked styles have to fit two lines into one menu bar row.
    private static let stackedValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    private static let stackedLabelFont = NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .medium)

    /// Plain-text form of the item: the store's cache key, and the accessibility
    /// label of the rendered item.
    func plainTitle() -> String {
        stats
            .map { style.plainText(value: text($0), label: $0.label) + marker($0) }
            .joined(separator: separator)
    }

    func attributedTitle() -> NSAttributedString {
        let result = NSMutableAttributedString()

        for (index, kind) in stats.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(
                    string: separator,
                    attributes: [.font: Self.valueFont, .foregroundColor: separatorColor]
                ))
            }
            result.append(NSAttributedString(
                string: text(kind) + marker(kind),
                attributes: [.font: Self.valueFont, .foregroundColor: color(kind)]
            ))
        }
        return result
    }

    /// Two lines per metric — the number on top, the metric's identity (label or
    /// symbol) underneath. Drawn as one image because a status item title is a
    /// single text line, so it cannot stack blocks side by side.
    func image() -> NSImage? {
        guard style.isStacked, !stats.isEmpty else { return nil }

        // The separator text is drawn between the blocks, so the gap is its own
        // width — same rule as the single-line title, where it is concatenated.
        let separator = NSAttributedString(
            string: separator,
            attributes: [.font: Self.stackedValueFont, .foregroundColor: separatorColor]
        )
        let gap = separator.size().width

        struct Block {
            let value: NSAttributedString
            let label: NSAttributedString?
            let icon: NSImage?
            let width: CGFloat
        }

        let blocks: [Block] = stats.map { kind in
            let color = color(kind)
            let value = NSAttributedString(
                string: text(kind) + marker(kind),
                attributes: [.font: Self.stackedValueFont, .foregroundColor: color]
            )
            let label = style.usesIcon ? nil : NSAttributedString(
                string: kind.label,
                attributes: [.font: Self.stackedLabelFont, .foregroundColor: color]
            )
            let icon = style.usesIcon
                ? SymbolImage.menuBar(kind.symbol, pointSize: 8, color: color)
                : nil
            let bottom = icon?.size.width ?? label?.size().width ?? 0
            return Block(value: value, label: label, icon: icon, width: ceil(max(value.size().width, bottom)))
        }

        let width = blocks.reduce(0) { $0 + $1.width } + gap * CGFloat(blocks.count - 1)
        let valueHeight = ceil(Self.stackedValueFont.ascender - Self.stackedValueFont.descender)
        let bottomHeight = style.usesIcon
            ? ceil(blocks.compactMap(\.icon?.size.height).max() ?? 0)
            : ceil(Self.stackedLabelFont.ascender - Self.stackedLabelFont.descender)
        let size = NSSize(width: ceil(width), height: valueHeight + bottomHeight)

        return NSImage(size: size, flipped: false) { rect in
            var x: CGFloat = 0
            for (index, block) in blocks.enumerated() {
                if index > 0 {
                    let separatorSize = separator.size()
                    separator.draw(at: NSPoint(
                        x: x + (gap - separatorSize.width) / 2,
                        y: rect.midY - separatorSize.height / 2
                    ))
                    x += gap
                }

                let valueSize = block.value.size()
                block.value.draw(at: NSPoint(
                    x: x + (block.width - valueSize.width) / 2,
                    y: rect.maxY - valueSize.height
                ))

                if let icon = block.icon {
                    icon.draw(in: NSRect(
                        x: x + (block.width - icon.size.width) / 2,
                        y: rect.minY,
                        width: icon.size.width,
                        height: icon.size.height
                    ))
                } else if let label = block.label {
                    let labelSize = label.size()
                    label.draw(at: NSPoint(
                        x: x + (block.width - labelSize.width) / 2,
                        y: rect.minY
                    ))
                }

                x += block.width
            }
            return true
        }
    }
}
