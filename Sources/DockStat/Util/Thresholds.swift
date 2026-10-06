import Foundation

/// Warn / critical limits per metric, with hysteresis on the way down.
struct Thresholds: Codable, Sendable, Equatable {
    var cpuWarn: Double = 80
    var cpuCrit: Double = 95
    var memWarn: Double = 85
    var memCrit: Double = 95
    /// Disk limits are expressed on *used* percent (low free space = critical).
    var diskWarn: Double = 85
    var diskCrit: Double = 95
    /// Percentage points a value has to fall below a limit before it clears.
    var hysteresis: Double = 5

    func warn(_ kind: StatKind) -> Double {
        switch kind {
        case .cpu: cpuWarn
        case .mem: memWarn
        case .disk: diskWarn
        }
    }

    func crit(_ kind: StatKind) -> Double {
        switch kind {
        case .cpu: cpuCrit
        case .mem: memCrit
        case .disk: diskCrit
        }
    }

    mutating func setWarn(_ kind: StatKind, _ value: Double) {
        switch kind {
        case .cpu: cpuWarn = value
        case .mem: memWarn = value
        case .disk: diskWarn = value
        }
    }

    mutating func setCrit(_ kind: StatKind, _ value: Double) {
        switch kind {
        case .cpu: cpuCrit = value
        case .mem: memCrit = value
        case .disk: diskCrit = value
        }
    }

    /// Escalate immediately, de-escalate only after `hysteresis` points of headroom.
    func severity(_ kind: StatKind, metric: Double, previous: Severity) -> Severity {
        let crit = crit(kind)
        let warn = warn(kind)
        let margin = hysteresis

        if metric >= crit { return .critical }
        if previous == .critical, metric >= crit - margin { return .critical }
        if metric >= warn { return .warning }
        if previous >= .warning, metric >= warn - margin { return .warning }
        return .normal
    }
}
