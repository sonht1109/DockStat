import AppKit
import Observation

/// Single source of truth for the app: current sample, severities and the
/// derived menu bar title / Dock icon.
@MainActor
@Observable
final class StatsStore {
    let settings = SettingsModel()

    private(set) var sample = Sample.empty
    private(set) var cpuSeverity: Severity = .normal
    private(set) var memSeverity: Severity = .normal
    private(set) var diskSeverity: Severity = .normal

    private var engine: SamplingEngine?
    private var bar: MenuBarController?
    private let iconRenderer = DockIconRenderer()
    private let badge = DockBadgeController()
    private var dockTileView: DockTileView?

    private var lastBarTitle = ""
    private var lastIconKey = ""
    private var observers: [NSObjectProtocol] = []

    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    // MARK: - Lifecycle

    func start() {
        let engine = SamplingEngine { [weak self] sample in
            self?.apply(sample)
        }
        self.engine = engine

        let bar = MenuBarController(store: self)
        bar.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
        bar.onQuit = { [weak self] in self?.onQuit?() }
        self.bar = bar

        engine.start(config: schedulerConfig, samplerConfig: samplerConfig)
        bar.setVisible(settings.showMenuBarIcon)
        // Login items are owned by the system, so adopt the system's answer
        // before wiring the change handler (otherwise a stale `false` would
        // switch off an existing login item).
        settings.launchAtLogin = LaunchAtLogin.isEnabled
        settings.onChange = { [weak self] in self?.settingsChanged() }
        settings.startObserving()
        observeWorkspace()
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    // MARK: - Configuration

    private var schedulerConfig: PollScheduler.Config {
        PollScheduler.Config(
            interval: settings.interval,
            adaptive: settings.adaptivePolling,
            multiplier: settings.adaptiveMultiplier
        )
    }

    private var samplerConfig: StatsSampler.Config {
        StatsSampler.Config(
            volumePath: settings.volumePath,
            collectCPU: settings.isShown(.cpu) || iconUses(.cpu) || settings.badgeStat == .cpu,
            collectMemory: settings.isShown(.mem) || iconUses(.mem) || settings.badgeStat == .mem,
            collectDisk: settings.isShown(.disk) || iconUses(.disk) || settings.badgeStat == .disk
        )
    }

    private func iconUses(_ kind: StatKind) -> Bool {
        guard settings.dockIconEnabled else { return false }
        return settings.iconLine1.kind == kind || settings.iconLine2.kind == kind
    }

    func settingsChanged() {
        engine?.update(config: schedulerConfig)
        engine?.update(samplerConfig: samplerConfig)
        bar?.setVisible(settings.showMenuBarIcon)
        applyLaunchAtLoginState()
        lastBarTitle = ""
        lastIconKey = ""
        updateBar(force: true)
        updateDockIcon(force: true)
        updateBadge(force: true)
    }

    func refreshNow() {
        engine?.fireNow()
    }

    /// Injects one snapshot for offscreen rendering (`--panel`). No sampling and
    /// no menu bar / Dock side effects: only the panel's values are set.
    func showPreview(_ sample: Sample, critical: Bool = false) {
        self.sample = sample
        let thresholds = settings.thresholds
        cpuSeverity = thresholds.severity(.cpu, metric: sample.cpu ?? 0, previous: .normal)
        memSeverity = thresholds.severity(.mem, metric: sample.mem ?? 0, previous: .normal)
        diskSeverity = critical
            ? .critical
            : thresholds.severity(.disk, metric: sample.diskUsedPercent ?? 0, previous: .normal)
    }

    func applyLaunchAtLoginState() {
        guard LaunchAtLogin.isEnabled != settings.launchAtLogin else { return }
        if let reason = LaunchAtLogin.set(settings.launchAtLogin) {
            NSLog("DockStat: launch at login: %@", reason)
            // Reflect what actually happened instead of leaving the toggle lying.
            settings.launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    // MARK: - Sampling

    private func apply(_ sample: Sample) {
        guard !sample.isEmpty else { return }
        self.sample = sample

        let thresholds = settings.thresholds
        if let value = sample.cpu {
            cpuSeverity = thresholds.severity(.cpu, metric: value, previous: cpuSeverity)
        }
        if let value = sample.mem {
            memSeverity = thresholds.severity(.mem, metric: value, previous: memSeverity)
        }
        if let value = sample.diskUsedPercent {
            diskSeverity = thresholds.severity(.disk, metric: value, previous: diskSeverity)
        }

        if Self.trace { traceParts.removeAll(keepingCapacity: true) }
        stage("bar") { updateBar() }
        stage("icon") { updateDockIcon() }
        stage("badge") { updateBadge() }
        escalateIfNeeded()
        if Self.trace {
            let line = traceParts.joined(separator: " ") + "\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    /// Per-tick timing breakdown, enabled with `DOCKSTAT_TRACE=1`.
    static let trace = ProcessInfo.processInfo.environment["DOCKSTAT_TRACE"] != nil
    private var traceParts: [String] = []

    private func stage(_ label: String, _ body: () -> Void) {
        guard Self.trace else { return body() }
        let start = ProcessInfo.processInfo.systemUptime
        body()
        let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
        traceParts.append(String(format: "%@=%.2fms", label, ms))
    }

    func severity(for kind: StatKind) -> Severity {
        switch kind {
        case .cpu: cpuSeverity
        case .mem: memSeverity
        case .disk: diskSeverity
        }
    }

    /// Value driving threshold evaluation (disk uses *used* percent).
    func metric(for kind: StatKind) -> Double? {
        switch kind {
        case .cpu: sample.cpu
        case .mem: sample.mem
        case .disk: sample.diskUsedPercent
        }
    }

    /// Value as shown (disk is free space by default).
    func displayText(for kind: StatKind) -> String {
        switch kind {
        case .cpu:
            sample.cpu.map(Formatters.percent) ?? "--"
        case .mem:
            sample.mem.map(Formatters.percent) ?? "--"
        case .disk:
            if settings.diskShowFree {
                sample.diskFree.map(Formatters.bytes) ?? "--"
            } else {
                sample.diskUsedPercent.map(Formatters.percent) ?? "--"
            }
        }
    }

    var anyCritical: Bool { cpuSeverity == .critical || memSeverity == .critical || diskSeverity == .critical }
    var anyWarning: Bool { cpuSeverity >= .warning || memSeverity >= .warning || diskSeverity >= .warning }

    // MARK: - Menu bar

    private func updateBar(force: Bool = false) {
        let title = barTitle()
        guard force || title != lastBarTitle else {
            // Colour escalation also depends on severity, so compare the string
            // including markers — it already covers that.
            return
        }
        lastBarTitle = title
        if settings.barStyle.isStacked {
            bar?.setImage(stackedBarImage(), accessibilityLabel: title)
        } else {
            bar?.setTitle(singleLineBarTitle(), accessibilityLabel: title)
        }
    }

    /// Plain-text form of the current title: the cache key, and the
    /// accessibility label of the rendered item.
    private func barTitle() -> String {
        settings.barStats
            .map { settings.barStyle.plainText(value: displayText(for: $0), label: $0.label) + marker(for: $0) }
            .joined(separator: settings.barSeparator)
    }

    private func marker(for kind: StatKind) -> String {
        switch severity(for: kind) {
        case .normal: ""
        case .warning: "!"
        case .critical: "⚠"
        }
    }

    private func singleLineBarTitle() -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let result = NSMutableAttributedString()

        for (index, kind) in settings.barStats.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(
                    string: settings.barSeparator,
                    attributes: [.font: font, .foregroundColor: NSColor.labelColor]
                ))
            }
            result.append(NSAttributedString(
                string: displayText(for: kind) + marker(for: kind),
                attributes: [.font: font, .foregroundColor: color(for: kind)]
            ))
        }
        return result
    }

    /// Two lines per metric — the number on top, the metric's identity (label or
    /// symbol) underneath. Drawn as one image because a status item title is a
    /// single text line, so it cannot stack blocks side by side.
    private func stackedBarImage() -> NSImage? {
        guard settings.barStyle.isStacked, !settings.barStats.isEmpty else { return nil }

        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .medium)
        // The separator text is drawn between the blocks, so the gap is its own
        // width — same rule as the single-line title, where it is concatenated.
        let separator = NSAttributedString(
            string: settings.barSeparator,
            attributes: [.font: valueFont, .foregroundColor: NSColor.labelColor]
        )
        let gap = separator.size().width

        struct Block {
            let value: NSAttributedString
            let label: NSAttributedString?
            let icon: NSImage?
            let width: CGFloat
        }

        let blocks: [Block] = settings.barStats.map { kind in
            let color = color(for: kind)
            let value = NSAttributedString(
                string: displayText(for: kind) + marker(for: kind),
                attributes: [.font: valueFont, .foregroundColor: color]
            )
            let label = settings.barStyle.usesIcon ? nil : NSAttributedString(
                string: kind.label,
                attributes: [.font: labelFont, .foregroundColor: color]
            )
            let icon = settings.barStyle.usesIcon
                ? SymbolImage.menuBar(kind.symbol, pointSize: 8, color: color)
                : nil
            let bottom = icon?.size.width ?? label?.size().width ?? 0
            return Block(value: value, label: label, icon: icon, width: ceil(max(value.size().width, bottom)))
        }

        let width = blocks.reduce(0) { $0 + $1.width } + gap * CGFloat(blocks.count - 1)
        let valueHeight = ceil(valueFont.ascender - valueFont.descender)
        let bottomHeight = settings.barStyle.usesIcon
            ? ceil(blocks.compactMap(\.icon?.size.height).max() ?? 0)
            : ceil(labelFont.ascender - labelFont.descender)
        let size = NSSize(width: ceil(width), height: valueHeight + bottomHeight)

        return NSImage(size: size, flipped: false) { rect in
            var x: CGFloat = 0
            for (index, block) in blocks.enumerated() {
                if index > 0 {
                    let separatorSize = separator.size()
                    separator.draw(at: NSPoint(
                        x: x + (gap - separatorSize.width) / 2,
                        y: rect.midY - separatorSize.height / 2
                    ))
                    x += gap
                }

                let valueSize = block.value.size()
                block.value.draw(at: NSPoint(
                    x: x + (block.width - valueSize.width) / 2,
                    y: rect.maxY - valueSize.height
                ))

                if let icon = block.icon {
                    icon.draw(in: NSRect(
                        x: x + (block.width - icon.size.width) / 2,
                        y: rect.minY,
                        width: icon.size.width,
                        height: icon.size.height
                    ))
                } else if let label = block.label {
                    let labelSize = label.size()
                    label.draw(at: NSPoint(
                        x: x + (block.width - labelSize.width) / 2,
                        y: rect.minY
                    ))
                }

                x += block.width
            }
            return true
        }
    }

    private func color(for kind: StatKind) -> NSColor {
        switch severity(for: kind) {
        case .critical: return .systemRed
        case .warning: return .systemOrange
        case .normal:
            guard settings.useCustomColors else { return .labelColor }
            return settings.color(for: kind).nsColor
        }
    }

    // MARK: - Dock

    private func updateDockIcon(force: Bool = false) {
        guard settings.dockIconEnabled else {
            if force || !lastIconKey.isEmpty {
                lastIconKey = ""
                NSApp.dockTile.contentView = nil
                dockTileView = nil
                NSApp.applicationIconImage = nil
                NSApp.dockTile.display()
            }
            return
        }

        let spec = IconSpec(
            line1: iconText(for: settings.iconLine1),
            line2: iconText(for: settings.iconLine2),
            background: settings.iconBackground,
            border: settings.iconBorder,
            text: iconColor(),
            borderWidth: settings.iconBorderWidth,
            size: 256
        )

        guard force || spec.cacheKey != lastIconKey else { return }
        lastIconKey = spec.cacheKey

        if settings.useDockTileView {
            // Default path: draw straight into the tile's content view.
            let view = dockTileView ?? DockTileView()
            view.frame = NSRect(x: 0, y: 0, width: 128, height: 128)
            view.spec = spec
            NSApp.dockTile.contentView = view
            dockTileView = view
        } else {
            if dockTileView != nil {
                NSApp.dockTile.contentView = nil
                dockTileView = nil
            }
            NSApp.applicationIconImage = iconRenderer.image(for: spec)
        }
        NSApp.dockTile.display()
    }

    private func iconText(for line: IconLine) -> String {
        switch line {
        case .none: ""
        case .label(let kind): kind.label
        case .value(let kind): displayText(for: kind)
        }
    }

    /// Text colour escalates with severity, otherwise uses the configured colour.
    private func iconColor() -> RGBAColor {
        let severity = [cpuSeverity, memSeverity, diskSeverity].max() ?? .normal
        switch severity {
        case .critical: return RGBAColor(r: 1, g: 0.27, b: 0.23)
        case .warning: return RGBAColor(r: 1, g: 0.62, b: 0.04)
        case .normal: return settings.iconText
        }
    }

    // MARK: - Badge

    private func updateBadge(force: Bool = false) {
        guard settings.badgeEnabled else {
            if force { badge.update(nil) }
            return
        }
        let text: String
        switch settings.badgeStat {
        case .cpu: text = sample.cpu.map(Formatters.percent) ?? ""
        case .mem: text = sample.mem.map(Formatters.percent) ?? ""
        case .disk: text = sample.diskUsedPercent.map(Formatters.percent) ?? ""
        }
        badge.update(text.isEmpty ? nil : text)
    }

    // MARK: - Escalation

    private var lastCritical: Severity = .normal

    private func escalateIfNeeded() {
        let current: Severity = anyCritical ? .critical : (anyWarning ? .warning : .normal)
        defer { lastCritical = current }
        guard settings.bounceOnCritical, current > lastCritical else { return }
        if current == .warning || current == .critical {
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    // MARK: - Workspace

    private func observeWorkspace() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter

        func on(_ name: Notification.Name, _ center: NotificationCenter, _ body: @escaping @MainActor () -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { body() }
            }
            observers.append(token)
        }

        on(NSWorkspace.screensDidSleepNotification, workspace) { [weak self] in
            guard let self, settings.pauseOnDisplaySleep else { return }
            engine?.setSuspended(true)
        }
        on(NSWorkspace.screensDidWakeNotification, workspace) { [weak self] in
            guard let self, settings.pauseOnDisplaySleep else { return }
            engine?.setSuspended(false)
        }
        on(NSWorkspace.didWakeNotification, workspace) { [weak self] in
            self?.engine?.fireNow()
        }
        on(Notification.Name.NSProcessInfoPowerStateDidChange, center) { [weak self] in
            guard let self else { return }
            engine?.update(config: schedulerConfig)
            engine?.fireNow()
        }
        on(NSApplication.didBecomeActiveNotification, center) { [weak self] in
            // Re-assert the Dock icon: the Dock forgets it across logins/updates.
            self?.updateDockIcon(force: true)
        }
    }
}
