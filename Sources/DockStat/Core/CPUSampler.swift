import Darwin

/// CPU utilisation from `host_statistics(HOST_CPU_LOAD_INFO)` tick deltas.
///
/// Not thread-safe by design: only the polling queue touches it.
final class CPUSampler: @unchecked Sendable {
    private var previous: (user: UInt64, system: UInt64, nice: UInt64, idle: UInt64)?

    /// Returns busy percent (0…100), or `nil` for the first (since-boot) sample.
    func sample() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let ticks = info.cpu_ticks
        let user = UInt64(ticks.0)
        let system = UInt64(ticks.1)
        let idle = UInt64(ticks.2)
        let nice = UInt64(ticks.3)

        defer { previous = (user, system, nice, idle) }
        guard let last = previous else { return nil }

        // Wrapping arithmetic handles the 32-bit tick counters rolling over.
        let busy = (user &- last.user) &+ (system &- last.system) &+ (nice &- last.nice)
        let total = busy &+ (idle &- last.idle)
        guard total > 0 else { return nil }

        return Double(busy) / Double(total) * 100
    }

    func reset() { previous = nil }
}
