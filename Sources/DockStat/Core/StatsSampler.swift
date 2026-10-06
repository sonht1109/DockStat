import Foundation

/// Fans out to the three samplers. Runs on the polling queue only.
final class StatsSampler: @unchecked Sendable {
    struct Config: Sendable, Equatable {
        var volumePath: String = "/"
        var collectCPU = true
        var collectMemory = true
        var collectDisk = true
    }

    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let disk = DiskSampler()
    private let lock = NSLock()
    private var _config = Config()

    /// `statfs` is a syscall and free space moves slowly: refresh the disk on
    /// every Nth tick instead of every tick.
    private let diskRefreshEvery = 5
    private var diskTick = 0
    private var lastDisk: (free: UInt64, total: UInt64)?

    var config: Config {
        get { lock.withLock { _config } }
        set { lock.withLock { _config = newValue } }
    }

    /// Warm up CPU deltas so the first delivered sample is real, not since-boot.
    func warmUp() {
        _ = cpu.sample()
    }

    func sample() -> Sample {
        let config = self.config
        var sample = Sample()

        autoreleasepool {
            if config.collectCPU {
                sample.cpu = cpu.sample()
            }
            if config.collectMemory {
                sample.mem = memory.sample()
            }
            if config.collectDisk {
                diskTick += 1
                if lastDisk == nil || diskTick % diskRefreshEvery == 0 {
                    lastDisk = disk.sample(path: config.volumePath)
                }
                sample.diskFree = lastDisk?.free
                sample.diskTotal = lastDisk?.total
            }
        }
        return sample
    }

    func invalidateDisk() {
        lastDisk = nil
        diskTick = 0
    }
}
