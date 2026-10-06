import AppKit

/// Codable colour. Lives in settings, converts on demand.
struct RGBAColor: Codable, Sendable, Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r.clamped01
        self.g = g.clamped01
        self.b = b.clamped01
        self.a = a.clamped01
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        self.init(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent), a: Double(c.alphaComponent))
    }

    /// Accepts `#RRGGBB`, `RRGGBB`, `#RRGGBBAA`, `#RGB`.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            self.init(r: Double((value >> 16) & 0xFF) / 255,
                      g: Double((value >> 8) & 0xFF) / 255,
                      b: Double(value & 0xFF) / 255)
        } else {
            self.init(r: Double((value >> 24) & 0xFF) / 255,
                      g: Double((value >> 16) & 0xFF) / 255,
                      b: Double((value >> 8) & 0xFF) / 255,
                      a: Double(value & 0xFF) / 255)
        }
    }

    var hex: String {
        let ri = Int((r * 255).rounded()), gi = Int((g * 255).rounded()), bi = Int((b * 255).rounded())
        if a >= 0.999 { return String(format: "#%02X%02X%02X", ri, gi, bi) }
        return String(format: "#%02X%02X%02X%02X", ri, gi, bi, Int((a * 255).rounded()))
    }

    var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    var cgColor: CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    func withAlpha(_ alpha: Double) -> RGBAColor {
        RGBAColor(r: r, g: g, b: b, a: alpha)
    }

    // Defaults from the reference screenshot.
    static let iconBackground = RGBAColor(hex: "#0D2510")!
    static let iconBorder = RGBAColor(hex: "#000000")!
    static let iconText = RGBAColor(hex: "#04E518")!
    static let black = RGBAColor(r: 0, g: 0, b: 0)
    static let white = RGBAColor(r: 1, g: 1, b: 1)
}

private extension Double {
    var clamped01: Double { Swift.min(Swift.max(self, 0), 1) }
}
