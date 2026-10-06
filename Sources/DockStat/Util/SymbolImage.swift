import AppKit

/// SF Symbols for the menu bar title, drawn as text attachments.
@MainActor
enum SymbolImage {
    /// Renders `name` at `pointSize`, tinted with `color`.
    ///
    /// The image draws lazily through a handler, so a dynamic colour such as
    /// `.labelColor` resolves against the current appearance at draw time —
    /// a light/dark switch needs no re-render.
    static func menuBar(_ name: String, pointSize: CGFloat = 11, color: NSColor) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
              let symbol = base.withSymbolConfiguration(
                  NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
              )
        else { return nil }

        let size = symbol.size
        return NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
