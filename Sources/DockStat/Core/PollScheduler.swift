import Foundation
import IOKit.ps

/// Drives sampling. All mutable state lives on `queue`; the public API is
/// async fire-and-forget so callers never block.
final class PollScheduler: @unchecked Sendable {
    struct Config: Sendable, Equatable {
        var interval: TimeInterval = 2
        var adaptive: Bool = true
        /// Multiplier applied on battery or Low Power Mode.
        var multiplier: Double = 3
    }

    private let queue = DispatchQueue(label: "dev.sonht.dockstat.timer", qos: .userInitiated)
    private let onTick: @Sendable () -> Void

    private var timer: DispatchSourceTimer?
    private var config = Config()
    private var appliedInterval: TimeInterval = 0
    private var suspended = false

    init(onTick: @escaping @Sendable () -> Void) {
        self.onTick = onTick
    }

    func start() {
        queue.async { [self] in
            guard timer == nil, !suspended else { return }
            schedule(desiredInterval())
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            appliedInterval = 0
        }
    }

    func update(_ newConfig: Config) {
        queue.async { [self] in
            let previous = config
            config = newConfig
            guard !suspended else { return }
            let desired = desiredInterval()
            guard desired != appliedInterval || previous.interval != newConfig.interval else { return }
            schedule(desired)
        }
    }

    /// Suspend on display sleep / screen lock, resume with an immediate sample.
    func setSuspended(_ value: Bool) {
        queue.async { [self] in
            guard suspended != value else { return }
            suspended = value
            if value {
                timer?.cancel()
                timer = nil
                appliedInterval = 0
            } else {
                schedule(desiredInterval())
                onTick()
            }
        }
    }

    func fireNow() {
        queue.async { [self] in
            guard !suspended else { return }
            onTick()
        }
    }

    // MARK: - queue-confined

    private func schedule(_ interval: TimeInterval) {
        timer?.cancel()

        let source = DispatchSource.makeTimerSource(queue: queue)
        let leeway = DispatchTimeInterval.milliseconds(max(Int(interval * 100), 50))
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: leeway)
        source.setEventHandler { [self] in tick() }
        source.resume()

        timer = source
        appliedInterval = interval
    }

    private func tick() {
        // Power state can change without a notification we see (charger pulled
        // while asleep); re-evaluate cheaply on every tick.
        let desired = desiredInterval()
        if abs(desired - appliedInterval) > 0.001 {
            schedule(desired)
        }
        onTick()
    }

    private func desiredInterval() -> TimeInterval {
        let base = max(config.interval, 0.5)
        guard config.adaptive, isThrottled() else { return base }
        return base * max(config.multiplier, 1)
    }

    private func isThrottled() -> Bool {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return true }
        return Self.isOnBattery()
    }

    static func isOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return false }
        return (type as String) == (kIOPSBatteryPowerValue as String)
    }
}
