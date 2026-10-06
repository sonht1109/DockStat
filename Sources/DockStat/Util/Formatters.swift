import Foundation

/// Allocation-light formatters. No `String(format:)`, no `NumberFormatter`.
enum Formatters {
    /// `27.4` -> `"27%"`
    static func percent(_ value: Double) -> String {
        "\(clampedInt(value))%"
    }

    static func clampedInt(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(value.rounded())
    }

    /// `44_800_000_000` -> `"41.7 GB"`. One decimal, binary-free (SI-ish, matches Finder).
    static func bytes(_ bytes: UInt64) -> String {
        let kb = 1_000.0
        let mb = kb * 1_000
        let gb = mb * 1_000
        let tb = gb * 1_000

        let value: Double
        let unit: String
        switch Double(bytes) {
        case tb...: (value, unit) = (Double(bytes) / tb, "TB")
        case gb...: (value, unit) = (Double(bytes) / gb, "GB")
        case mb...: (value, unit) = (Double(bytes) / mb, "MB")
        default: (value, unit) = (Double(bytes) / kb, "KB")
        }

        // Tenths via integer math: avoids Float formatting machinery.
        let tenths = UInt64((value * 10).rounded())
        return "\(tenths / 10).\(tenths % 10) \(unit)"
    }

    /// `1.5` -> `"1.5s"`, `60` -> `"60s"`.
    static func seconds(_ value: Double) -> String {
        if value < 1 { return "\(Int((value * 1000).rounded()))ms" }
        if value == value.rounded() { return "\(Int(value))s" }
        let tenths = UInt64((value * 10).rounded())
        return "\(tenths / 10).\(tenths % 10)s"
    }
}
