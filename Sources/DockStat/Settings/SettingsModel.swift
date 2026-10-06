import Foundation
import Observation

/// How a metric is rendered in the menu bar.
///
/// Either the bare number, or the number with a second line underneath naming
/// the metric — as a text label or its SF Symbol. Only text leaves you guessing
/// which number belongs to which metric.
enum BarStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case percent      // 27%
    case stackedText  // 27% over CPU
    case stackedIcon  // 27% over <icon>

    var id: String { rawValue }

    /// Older releases stored the label beside the number (`suffix`, `prefix`,
    /// `iconSuffix`, `iconPrefix`); fold them into the stacked equivalents so an
    /// upgrade keeps a sensible look instead of resetting to number-only.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "suffix", "prefix": self = .stackedText
        case "iconSuffix", "iconPrefix": self = .stackedIcon
        default: self = BarStyle(rawValue: raw) ?? .percent
        }
    }

    var title: String {
        switch self {
        case .percent: "Number only"
        case .stackedText: "Number + text below"
        case .stackedIcon: "Number + icon below"
        }
    }

    /// Literal preview shown next to the title in Preferences.
    var example: String {
        switch self {
        case .percent: "27%"
        case .stackedText: "27% over CPU"
        case .stackedIcon: "27% over ▣"
        }
    }

    /// Whether the second line is drawn at all.
    var isStacked: Bool { self != .percent }

    var usesIcon: Bool { self == .stackedIcon }

    /// One-line rendering, used by the headless preview and the cache key.
    func plainText(value: String, label: String) -> String {
        switch self {
        case .percent: value
        case .stackedText, .stackedIcon: value + " " + label
        }
    }
}

/// One line of the Dock icon.
enum IconLine: Codable, Sendable, Equatable, Hashable {
    case value(StatKind)
    case label(StatKind)
    case none

    var title: String {
        switch self {
        case .value(let kind): "\(kind.title) value"
        case .label(let kind): "\(kind.title) label"
        case .none: "Empty"
        }
    }

    var kind: StatKind? {
        switch self {
        case .value(let kind), .label(let kind): kind
        case .none: nil
        }
    }

    static let all: [IconLine] = [.none]
        + StatKind.allCases.map { IconLine.value($0) }
        + StatKind.allCases.map { IconLine.label($0) }
}

/// Single source of truth for user preferences. Persisted as JSON in UserDefaults.
///
/// Properties are plain stored observable values; `StatsStore` watches the whole
/// model with `withObservationTracking` and calls `save()` on any change.
@MainActor
@Observable
final class SettingsModel {
    static let storageKey = "dockstat.settings.v1"

    private var isLoading = true

    // Menu bar
    var barStats: [StatKind] = [.cpu, .mem, .disk]
    var barStyle: BarStyle = .percent
    var barSeparator: String = "  "
    var showMenuBarIcon: Bool = true
    var useCustomColors: Bool = false
    var cpuColor: RGBAColor = .white
    var memColor: RGBAColor = .white
    var diskColor: RGBAColor = .white

    // Polling
    var interval: TimeInterval = 2
    var adaptivePolling: Bool = true
    var adaptiveMultiplier: Double = 3
    var pauseOnDisplaySleep: Bool = true

    // Dock icon
    var dockIconEnabled: Bool = true
    var iconBackground: RGBAColor = .iconBackground
    var iconBorder: RGBAColor = .iconBorder
    var iconText: RGBAColor = .iconText
    var iconBorderWidth: Double = 0.035
    var iconLine1: IconLine = .value(.cpu)
    var iconLine2: IconLine = .label(.cpu)
    /// Use `dockTile.contentView` instead of `applicationIconImage`.
    /// Default: the content view is ~10x cheaper to update (0.25 ms vs 2 ms at
    /// 256 pt) and cannot be missed by the Dock's icon cache.
    var useDockTileView: Bool = true

    // Dock badge
    var badgeEnabled: Bool = false
    var badgeStat: StatKind = .cpu

    // Disk
    var volumePath: String = "/"
    var diskShowFree: Bool = true

    // Behaviour
    var thresholds = Thresholds()
    var launchAtLogin: Bool = false
    var bounceOnCritical: Bool = false

    init() {
        load()
        isLoading = false
    }

    // MARK: - Derived

    func color(for kind: StatKind) -> RGBAColor {
        switch kind {
        case .cpu: cpuColor
        case .mem: memColor
        case .disk: diskColor
        }
    }

    func setColor(_ color: RGBAColor, for kind: StatKind) {
        switch kind {
        case .cpu: cpuColor = color
        case .mem: memColor = color
        case .disk: diskColor = color
        }
    }

    func isShown(_ kind: StatKind) -> Bool { barStats.contains(kind) }

    func toggle(_ kind: StatKind, shown: Bool) {
        if shown {
            guard !barStats.contains(kind) else { return }
            barStats.append(kind)
        } else {
            barStats.removeAll { $0 == kind }
        }
    }

    func move(_ kind: StatKind, by offset: Int) {
        guard let index = barStats.firstIndex(of: kind) else { return }
        let target = index + offset
        guard barStats.indices.contains(target) else { return }
        barStats.swapAt(index, target)
    }

    // MARK: - Persistence

    struct Payload: Codable, Equatable {
        var barStats: [StatKind]
        var barStyle: BarStyle
        var barSeparator: String
        var showMenuBarIcon: Bool
        var useCustomColors: Bool
        var cpuColor: RGBAColor
        var memColor: RGBAColor
        var diskColor: RGBAColor
        var interval: TimeInterval
        var adaptivePolling: Bool
        var adaptiveMultiplier: Double
        var pauseOnDisplaySleep: Bool
        var dockIconEnabled: Bool
        var iconBackground: RGBAColor
        var iconBorder: RGBAColor
        var iconText: RGBAColor
        var iconBorderWidth: Double
        var iconLine1: IconLine
        var iconLine2: IconLine
        var useDockTileView: Bool
        var badgeEnabled: Bool
        var badgeStat: StatKind
        var volumePath: String
        var diskShowFree: Bool
        var thresholds: Thresholds
        var launchAtLogin: Bool
        var bounceOnCritical: Bool
    }

    /// Reads every property — used to register observation of the whole model.
    func payload() -> Payload {
        Payload(
            barStats: barStats,
            barStyle: barStyle,
            barSeparator: barSeparator,
            showMenuBarIcon: showMenuBarIcon,
            useCustomColors: useCustomColors,
            cpuColor: cpuColor,
            memColor: memColor,
            diskColor: diskColor,
            interval: interval,
            adaptivePolling: adaptivePolling,
            adaptiveMultiplier: adaptiveMultiplier,
            pauseOnDisplaySleep: pauseOnDisplaySleep,
            dockIconEnabled: dockIconEnabled,
            iconBackground: iconBackground,
            iconBorder: iconBorder,
            iconText: iconText,
            iconBorderWidth: iconBorderWidth,
            iconLine1: iconLine1,
            iconLine2: iconLine2,
            useDockTileView: useDockTileView,
            badgeEnabled: badgeEnabled,
            badgeStat: badgeStat,
            volumePath: volumePath,
            diskShowFree: diskShowFree,
            thresholds: thresholds,
            launchAtLogin: launchAtLogin,
            bounceOnCritical: bounceOnCritical
        )
    }

    func save() {
        guard !isLoading else { return }
        guard let data = try? JSONEncoder().encode(payload()) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    /// Called after every persisted change, one runloop hop after the mutation.
    var onChange: (@MainActor () -> Void)?

    /// Watches the whole model: persists and notifies on any change.
    /// `withObservationTracking` fires on `willSet`, so the work is deferred one
    /// hop to read the settled values, then observation is re-armed.
    func startObserving() {
        withObservationTracking {
            _ = self.payload()
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.save()
                    self.onChange?()
                    self.startObserving()
                }
            }
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(Payload.self, from: data)
        else { return }
        apply(stored)
    }

    private func apply(_ stored: Payload) {
        barStats = stored.barStats
        barStyle = stored.barStyle
        barSeparator = stored.barSeparator
        showMenuBarIcon = stored.showMenuBarIcon
        useCustomColors = stored.useCustomColors
        cpuColor = stored.cpuColor
        memColor = stored.memColor
        diskColor = stored.diskColor
        interval = stored.interval
        adaptivePolling = stored.adaptivePolling
        adaptiveMultiplier = stored.adaptiveMultiplier
        pauseOnDisplaySleep = stored.pauseOnDisplaySleep
        dockIconEnabled = stored.dockIconEnabled
        iconBackground = stored.iconBackground
        iconBorder = stored.iconBorder
        iconText = stored.iconText
        iconBorderWidth = stored.iconBorderWidth
        iconLine1 = stored.iconLine1
        iconLine2 = stored.iconLine2
        useDockTileView = stored.useDockTileView
        badgeEnabled = stored.badgeEnabled
        badgeStat = stored.badgeStat
        volumePath = stored.volumePath
        diskShowFree = stored.diskShowFree
        thresholds = stored.thresholds
        bounceOnCritical = stored.bounceOnCritical
        // launchAtLogin is owned by the system, not by the JSON blob.
    }

    func resetToDefaults() {
        var defaults = Payload(
            barStats: [.cpu, .mem, .disk],
            barStyle: .percent,
            barSeparator: "  ",
            showMenuBarIcon: true,
            useCustomColors: false,
            cpuColor: .white,
            memColor: .white,
            diskColor: .white,
            interval: 2,
            adaptivePolling: true,
            adaptiveMultiplier: 3,
            pauseOnDisplaySleep: true,
            dockIconEnabled: true,
            iconBackground: .iconBackground,
            iconBorder: .iconBorder,
            iconText: .iconText,
            iconBorderWidth: 0.035,
            iconLine1: .value(.cpu),
            iconLine2: .label(.cpu),
            useDockTileView: true,
            badgeEnabled: false,
            badgeStat: .cpu,
            volumePath: "/",
            diskShowFree: true,
            thresholds: Thresholds(),
            launchAtLogin: launchAtLogin,
            bounceOnCritical: false
        )
        defaults.launchAtLogin = launchAtLogin
        apply(defaults)
        save()
    }
}

/// Missing keys decode to the supplied default, so adding a setting never
/// wipes an existing configuration.
private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)).flatMap { $0 } ?? fallback
    }
}

extension SettingsModel.Payload {
    /// Missing keys decode to a default, so adding a setting never wipes an
    /// existing configuration.
    init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            barStats = c.value(.barStats, [.cpu, .mem, .disk])
            barStyle = c.value(.barStyle, .percent)
            barSeparator = c.value(.barSeparator, "  ")
            showMenuBarIcon = c.value(.showMenuBarIcon, true)
            useCustomColors = c.value(.useCustomColors, false)
            cpuColor = c.value(.cpuColor, .white)
            memColor = c.value(.memColor, .white)
            diskColor = c.value(.diskColor, .white)
            interval = c.value(.interval, 2)
            adaptivePolling = c.value(.adaptivePolling, true)
            adaptiveMultiplier = c.value(.adaptiveMultiplier, 3)
            pauseOnDisplaySleep = c.value(.pauseOnDisplaySleep, true)
            dockIconEnabled = c.value(.dockIconEnabled, true)
            iconBackground = c.value(.iconBackground, .iconBackground)
            iconBorder = c.value(.iconBorder, .iconBorder)
            iconText = c.value(.iconText, .iconText)
            iconBorderWidth = c.value(.iconBorderWidth, 0.035)
            iconLine1 = c.value(.iconLine1, .value(.cpu))
            iconLine2 = c.value(.iconLine2, .label(.cpu))
            useDockTileView = c.value(.useDockTileView, true)
            badgeEnabled = c.value(.badgeEnabled, false)
            badgeStat = c.value(.badgeStat, .cpu)
            volumePath = c.value(.volumePath, "/")
            diskShowFree = c.value(.diskShowFree, true)
            thresholds = c.value(.thresholds, Thresholds())
            launchAtLogin = c.value(.launchAtLogin, false)
            bounceOnCritical = c.value(.bounceOnCritical, false)
        }
}
