import Foundation

/// One of the three metrics DockStat can display.
enum StatKind: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case cpu
    case mem
    case disk

    var id: String { rawValue }

    /// Short label, used in the menu bar and the Dock icon.
    var label: String {
        switch self {
        case .cpu: "CPU"
        case .mem: "MEM"
        case .disk: "DISK"
        }
    }

    /// Long label, used in the UI.
    var title: String {
        switch self {
        case .cpu: "CPU"
        case .mem: "Memory"
        case .disk: "Disk"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .mem: "memorychip"
        case .disk: "internaldrive"
        }
    }
}

/// Visual escalation level for a metric.
enum Severity: Int, Codable, Sendable, Comparable, Hashable {
    case normal = 0
    case warning = 1
    case critical = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A single immutable snapshot of every metric.
struct Sample: Sendable, Equatable {
    var cpu: Double?
    var mem: Double?
    var diskFree: UInt64?
    var diskTotal: UInt64?

    /// Used fraction of the selected volume, in percent.
    var diskUsedPercent: Double? {
        guard let free = diskFree, let total = diskTotal, total > 0 else { return nil }
        return Double(total - free) / Double(total) * 100
    }

    static let empty = Sample()

    var isEmpty: Bool { cpu == nil && mem == nil && diskFree == nil }
}
