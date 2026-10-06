import Darwin
import Foundation

/// Memory pressure as Activity Monitor's "Memory Used":
/// `(active + wired + compressed) / physicalMemory`.
final class MemorySampler: @unchecked Sendable {
    private let physicalMemory: UInt64
    private let pageSize: UInt64

    init() {
        physicalMemory = ProcessInfo.processInfo.physicalMemory

        // `vm_kernel_page_size` is not concurrency-safe; host_page_size is.
        var size: vm_size_t = 0
        if host_page_size(mach_host_self(), &size) == KERN_SUCCESS, size > 0 {
            pageSize = UInt64(size)
        } else {
            pageSize = 4096
        }
    }

    /// Returns used percent (0…100).
    func sample() -> Double? {
        guard physicalMemory > 0 else { return nil }

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pages = UInt64(stats.active_count)
            &+ UInt64(stats.wire_count)
            &+ UInt64(stats.compressor_page_count)
        let used = pages &* pageSize

        return min(Double(used) / Double(physicalMemory) * 100, 100)
    }

    var totalBytes: UInt64 { physicalMemory }
}
