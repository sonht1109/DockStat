import Foundation

/// Owns the samplers and the timer. Everything here is off the main actor;
/// samples are handed back to `sink` on the main actor.
final class SamplingEngine: @unchecked Sendable {
    private let sampler = StatsSampler()
    private let scheduler: PollScheduler

    init(sink: @escaping @MainActor @Sendable (Sample) -> Void) {
        // Captured by value: `self` is not needed on the polling queue.
        let sampler = self.sampler
        self.scheduler = PollScheduler {
            let sample = sampler.sample()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { sink(sample) }
            }
        }
    }

    func start(config: PollScheduler.Config, samplerConfig: StatsSampler.Config) {
        sampler.config = samplerConfig
        sampler.warmUp()
        scheduler.update(config)
        scheduler.start()
        scheduler.fireNow()
    }

    func update(config: PollScheduler.Config) {
        scheduler.update(config)
    }

    func update(samplerConfig: StatsSampler.Config) {
        if sampler.config.volumePath != samplerConfig.volumePath {
            sampler.invalidateDisk()
        }
        sampler.config = samplerConfig
    }

    func setSuspended(_ suspended: Bool) {
        scheduler.setSuspended(suspended)
    }

    func fireNow() {
        scheduler.fireNow()
    }
}
