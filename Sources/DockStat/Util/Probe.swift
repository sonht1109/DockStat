import AppKit
import Foundation
import ServiceManagement
import SwiftUI

/// Headless self-check, used by `make verify`. Not part of the normal UI path.
///
///   dockstat --probe [seconds]     sample the three metrics and print them
///   dockstat --render <path>       render the default Dock icon to a PNG
///   dockstat --self-test           formatters, thresholds, settings round-trip
enum Probe {
    @MainActor
    static func run(arguments: [String]) -> Bool {
        if let index = arguments.firstIndex(of: "--probe") {
            let seconds = arguments.count > index + 1 ? Double(arguments[index + 1]) ?? 4 : 4
            sample(seconds: seconds)
            return true
        }
        if arguments.contains("--login-status") {
            print("SMAppService.mainApp.status = \(SMAppService.mainApp.status.rawValue) (0=notRegistered 1=enabled 2=requiresApproval 3=notFound)")
            print("LaunchAtLogin.isEnabled       = \(LaunchAtLogin.isEnabled)")
            print("agent plist                   = \(LaunchAtLogin.agentURL.path)")
            if arguments.contains("--on") {
                print("set(true) -> \(LaunchAtLogin.set(true) ?? "ok")")
                print("now enabled = \(LaunchAtLogin.isEnabled)")
            }
            if arguments.contains("--off") {
                try? SMAppService.mainApp.unregister()
                print("set(false) -> \(LaunchAtLogin.set(false) ?? "ok")")
                print("now enabled = \(LaunchAtLogin.isEnabled)")
                print("agent exists = \(FileManager.default.fileExists(atPath: LaunchAtLogin.agentURL.path))")
            }
            return true
        }
        if arguments.contains("--self-test") {
            selfTest()
            return true
        }
        if arguments.contains("--bench") {
            bench()
            return true
        }
        if let index = arguments.firstIndex(of: "--render") {
            let path = arguments.count > index + 1 ? arguments[index + 1] : "/tmp/dockstat-icon.png"
            renderIcon(to: path)
            return true
        }
        if let index = arguments.firstIndex(of: "--panel") {
            let path = arguments.count > index + 1 ? arguments[index + 1] : "/tmp/dockstat-panel.png"
            renderPanel(to: path)
            return true
        }
        return false
    }

    private static func sample(seconds: Double) {
        let sampler = StatsSampler()
        sampler.warmUp()
        let settings = MainActor.assumeIsolated { SettingsModel() }

        print("DockStat probe — \(Int(seconds))s")
        print("  t      cpu%     mem%            free           total")

        var last = Sample.empty
        let ticks = max(Int(seconds), 1)
        for tick in 1...ticks {
            Thread.sleep(forTimeInterval: 1)
            let sample = sampler.sample()
            last = sample
            let cpu = sample.cpu.map { String(format: "%.1f", $0) } ?? "-"
            let mem = sample.mem.map { String(format: "%.1f", $0) } ?? "-"
            let free = sample.diskFree.map(Formatters.bytes) ?? "-"
            let total = sample.diskTotal.map(Formatters.bytes) ?? "-"
            print("  \(tick)  \(cpu.padded(6)) \(mem.padded(6)) \(free.padded(14)) \(total.padded(14))")
        }

        MainActor.assumeIsolated {
            let store = DisplayPreview(sample: last, settings: settings)
            print("\nderived display state")
            for kind in StatKind.allCases {
                print("  \(kind.label.padded(5)) \(store.displayText(for: kind))")
            }
            print("  menu bar  : \"\(store.barTitle)\"")
            print("  icon line1: \"\(store.iconLine1)\"")
            print("  icon line2: \"\(store.iconLine2)\"")
        }
    }

    private static func renderIcon(to path: String) {
        MainActor.assumeIsolated {
            let renderer = DockIconRenderer()
            let settings = SettingsModel()
            let spec = IconSpec(
                line1: "27%",
                line2: settings.iconLine2 == .none ? "" : "CPU",
                background: settings.iconBackground,
                border: settings.iconBorder,
                text: settings.iconText,
                borderWidth: settings.iconBorderWidth
            )
            let image = renderer.image(for: spec)
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else {
                print("render failed")
                return
            }
            try? png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) (\(Int(image.size.width))×\(Int(image.size.height)) pt)")
        }
    }
}

extension Probe {
    /// Offscreen render of the menu bar panel, so a change to it can be looked at
    /// without opening the app. Native controls the renderer cannot draw (the
    /// interval popup) come out blank; everything else is to scale.
    @MainActor
    static func renderPanel(to path: String) {
        let store = StatsStore()
        store.showPreview(
            Sample(cpu: 42, mem: 68, diskFree: 35_800_000_000, diskTotal: 494_300_000_000)
        )
        let view = PanelView(store: store, onOpenSettings: {}, onQuit: {}, vibrancy: false)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            print("panel render failed")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(Int(image.size.width))×\(Int(image.size.height)) pt)")
    }
}

/// Mirrors the display logic of `StatsStore` without touching AppKit.
@MainActor
private struct DisplayPreview {
    let sample: Sample
    let settings: SettingsModel

    func displayText(for kind: StatKind) -> String {
        switch kind {
        case .cpu: sample.cpu.map(Formatters.percent) ?? "--"
        case .mem: sample.mem.map(Formatters.percent) ?? "--"
        case .disk:
            settings.diskShowFree
                ? (sample.diskFree.map(Formatters.bytes) ?? "--")
                : (sample.diskUsedPercent.map(Formatters.percent) ?? "--")
        }
    }

    var barTitle: String {
        settings.barStats
            .map { settings.barStyle.plainText(value: displayText(for: $0), label: $0.label) }
            .joined(separator: settings.barSeparator)
    }

    var iconLine1: String {
        switch settings.iconLine1 {
        case .none: ""
        case .label(let kind): kind.label
        case .value(let kind): displayText(for: kind)
        }
    }

    var iconLine2: String {
        switch settings.iconLine2 {
        case .none: ""
        case .label(let kind): kind.label
        case .value(let kind): displayText(for: kind)
        }
    }
}

private extension String {
    func padded(_ width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}

extension Probe {
    /// Deterministic checks for the pure logic: formatters, thresholds and the
    /// settings persistence round-trip (including observation-driven saves).
    @MainActor
    static func selfTest() {
        let defaults = UserDefaults.standard
        let key = SettingsModel.storageKey
        let backup = defaults.data(forKey: key)
        defaults.removeObject(forKey: key)

        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            print("  \(ok ? "ok  " : "FAIL") \(name)")
            if !ok { failures += 1 }
        }

        print("formatters")
        check("percent(27.4) == 27%", Formatters.percent(27.4) == "27%")
        check("percent clamps garbage", Formatters.percent(.nan) == "0%")
        check("bytes(41.5GB)", Formatters.bytes(41_500_000_000) == "41.5 GB")
        check("bytes(2TB)", Formatters.bytes(2_000_000_000_000) == "2.0 TB")
        check("seconds(0.5) == 500ms", Formatters.seconds(0.5) == "500ms")

        print("colour")
        check("hex round-trip", RGBAColor(hex: "#04E518")?.hex == "#04E518")
        check("short hex expands", RGBAColor(hex: "0f0")?.hex == "#00FF00")
        check("bad hex rejected", RGBAColor(hex: "zz") == nil)

        print("thresholds (hysteresis 5pp)")
        let t = Thresholds()
        check("below warn is normal", t.severity(.cpu, metric: 40, previous: .normal) == .normal)
        check("at warn escalates", t.severity(.cpu, metric: 81, previous: .normal) == .warning)
        check("at crit escalates", t.severity(.cpu, metric: 96, previous: .warning) == .critical)
        check("critical holds at 90", t.severity(.cpu, metric: 90, previous: .critical) == .critical)
        check("critical drops to warning at 89", t.severity(.cpu, metric: 89, previous: .critical) == .warning)
        check("warning holds at 75", t.severity(.cpu, metric: 75, previous: .warning) == .warning)
        check("warning clears at 74", t.severity(.cpu, metric: 74, previous: .warning) == .normal)

        MainActor.assumeIsolated {
            print("settings model")
            let a = SettingsModel()
            check("default interval", a.interval == 2)
            check("default bar stats", a.barStats == [.cpu, .mem, .disk])
            check("launchAtLogin defaults to off", a.launchAtLogin == false)

            var notified = 0
            a.onChange = { notified += 1 }
            a.startObserving()
            a.interval = 7
            a.barStyle = .stackedIcon
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))

            check("change was observed", notified > 0)
            let stored = defaults.data(forKey: key)
                .flatMap { try? JSONDecoder().decode(SettingsModel.Payload.self, from: $0) }
            check("interval saved", stored?.interval == 7)
            check("style saved", stored?.barStyle == .stackedIcon)

            let reloaded = SettingsModel()
            check("reload restores interval", reloaded.interval == 7)
            check("reload restores style", reloaded.barStyle == .stackedIcon)

            print("bar style")
            check("number only drops the label",
                  BarStyle.percent.plainText(value: "27%", label: "CPU") == "27%")
            check("stacked text keeps the label",
                  BarStyle.stackedText.plainText(value: "27%", label: "CPU") == "27% CPU")
            check("stacked styles flagged",
                  BarStyle.stackedText.isStacked && BarStyle.stackedIcon.isStacked
                      && BarStyle.stackedIcon.usesIcon && !BarStyle.stackedText.usesIcon
                      && !BarStyle.percent.isStacked)
            check("metric symbol renders",
                  SymbolImage.menuBar(StatKind.cpu.symbol, color: .labelColor) != nil)
            for legacy in ["suffix", "prefix", "iconSuffix", "iconPrefix", "bogus"] {
                let data = "\"\(legacy)\"".data(using: .utf8)!
                let style = try? JSONDecoder().decode(BarStyle.self, from: data)
                let expected: BarStyle = legacy.hasPrefix("icon") ? .stackedIcon
                    : (legacy == "bogus" ? .percent : .stackedText)
                check("legacy style \(legacy) maps to \(expected.rawValue)", style == expected)
            }
            check("styles round-trip", BarStyle.allCases.allSatisfy {
                (try? JSONDecoder().decode(BarStyle.self, from: JSONEncoder().encode($0))) == $0
            })

            // Old payloads lacking newer keys must still decode.
            let partial = #"{"interval":5}"#.data(using: .utf8)!
            let decoded = try? JSONDecoder().decode(SettingsModel.Payload.self, from: partial)
            check("partial payload decodes", decoded?.interval == 5)
            check("missing keys fall back", decoded?.barStats == [.cpu, .mem, .disk])
            check("missing icon line falls back", decoded?.iconLine1 == .value(.cpu))

            print("dock icon")
            let renderer = DockIconRenderer()
            let spec = IconSpec(line1: "27%", line2: "CPU")
            let image = renderer.image(for: spec)
            check("icon renders at 256pt", image.size == NSSize(width: 256, height: 256))
            check("icon has a PNG representation",
                  image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?
                      .representation(using: .png, properties: [:]) != nil)
            check("cache returns the same instance", renderer.image(for: spec) === image)

            let oneLine = renderer.image(for: IconSpec(line1: "42%"))
            check("single-line icon renders", oneLine.size.width == 256)
        }

        if let backup {
            defaults.set(backup, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }

        print(failures == 0 ? "self-test: PASS" : "self-test: \(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}

extension Probe {
    /// Timing breakdown of the per-tick work, to keep the polling budget honest.
    @MainActor
    static func bench() {
        func time(_ label: String, _ iterations: Int, _ body: () -> Void) {
            let start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<iterations { body() }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            let per = elapsed / Double(iterations) * 1000
            print("  \(label.padded(28)) \(String(format: "%8.3f", per)) ms/op  (\(iterations)x in \(String(format: "%.0f", elapsed * 1000)) ms)")
        }

        let sampler = StatsSampler()
        sampler.warmUp()
        time("StatsSampler.sample()", 200) { _ = sampler.sample() }

        let renderer = DockIconRenderer()
        var counter = 0
        time("DockIconRenderer.image()", 50) {
            counter += 1
            _ = renderer.image(for: IconSpec(line1: "\(counter % 100)%", line2: "CPU"))
        }

        time("IOPSGetProvidingPowerSourceType", 200) { _ = PollScheduler.isOnBattery() }
        time("ProcessInfo.isLowPowerModeEnabled", 200) { _ = ProcessInfo.processInfo.isLowPowerModeEnabled }

        _ = NSApplication.shared
        let image = renderer.image(for: IconSpec(line1: "42%", line2: "CPU"))
        time("NSApp.applicationIconImage = image", 50) { NSApp.applicationIconImage = image }
        time("NSApp.dockTile.display()", 50) { NSApp.dockTile.display() }
        for size in [512.0, 256.0, 128.0] {
            let img = renderer.image(for: IconSpec(line1: "42%", line2: "CPU", size: size))
            time("assign icon @\(Int(size))pt", 50) { NSApp.applicationIconImage = img }
        }
        let tileView = DockTileView()
        tileView.frame = NSRect(x: 0, y: 0, width: 128, height: 128)
        NSApp.dockTile.contentView = tileView
        var n = 0
        time("dockTile contentView update", 50) {
            n += 1
            tileView.spec = IconSpec(line1: "\(n % 100)%", line2: "CPU", size: 128)
            NSApp.dockTile.display()
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        var k = 0
        time("statusItem.title (plain)", 50) {
            k += 1
            item.button?.title = "\(k % 100)%  \(k % 100)%  \(k % 100)%"
        }
        time("statusItem.attributedTitle", 50) {
            k += 1
            let s = NSMutableAttributedString()
            for i in 0..<3 {
                if i > 0 { s.append(NSAttributedString(string: "  ", attributes: [.font: font, .foregroundColor: NSColor.labelColor])) }
                s.append(NSAttributedString(string: "\(k % 100)%", attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
            }
            item.button?.attributedTitle = s
        }
        NSStatusBar.system.removeStatusItem(item)

        time("both (as in updateDockIcon)", 50) {
            NSApp.applicationIconImage = image
            NSApp.dockTile.display()
        }
    }
}
