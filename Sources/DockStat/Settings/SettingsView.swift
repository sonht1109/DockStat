import SwiftUI

/// Preferences window.
struct SettingsView: View {
    @Bindable var settings: SettingsModel
    private let volumes = DiskSampler.mountedVolumes()

    var body: some View {
        Form {
            menuBarSection
            pollingSection
            iconSection
            badgeSection
            diskSection
            thresholdsSection
            generalSection
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 660)
    }

    // MARK: - Menu bar

    private var menuBarSection: some View {
        Section("Menu bar") {
            Toggle("Show menu bar item", isOn: $settings.showMenuBarIcon)

            ForEach(StatKind.allCases) { kind in
                HStack(spacing: 12) {
                    Toggle(kind.title, isOn: shownBinding(kind))
                    Spacer()
                    Text(orderLabel(kind))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .frame(width: 24, alignment: .trailing)
                    Button { settings.move(kind, by: -1) } label: { Image(systemName: "arrow.up") }
                        .buttonStyle(.borderless)
                        .disabled(!canMove(kind, by: -1))
                    Button { settings.move(kind, by: 1) } label: { Image(systemName: "arrow.down") }
                        .buttonStyle(.borderless)
                        .disabled(!canMove(kind, by: 1))
                }
            }

            Picker("Style", selection: $settings.barStyle) {
                ForEach(BarStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }

            LabeledContent("Separator") {
                TextField("", text: $settings.barSeparator)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            Toggle("Custom colours", isOn: $settings.useCustomColors)
            if settings.useCustomColors {
                colorRow("CPU", $settings.cpuColor)
                colorRow("Memory", $settings.memColor)
                colorRow("Disk", $settings.diskColor)
            }
        }
    }

    // MARK: - Polling

    private var pollingSection: some View {
        Section("Polling") {
            Picker("Interval", selection: $settings.interval) {
                ForEach([1.0, 2.0, 5.0, 10.0, 30.0, 60.0], id: \.self) { value in
                    Text(Formatters.seconds(value)).tag(value)
                }
                if ![1.0, 2.0, 5.0, 10.0, 30.0, 60.0].contains(settings.interval) {
                    Text(Formatters.seconds(settings.interval)).tag(settings.interval)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("Custom interval") {
                Stepper(value: $settings.interval, in: 0.5...600, step: 0.5) {
                    Text(Formatters.seconds(settings.interval))
                        .monospacedDigit()
                        .frame(width: 60, alignment: .leading)
                }
            }

            Toggle("Stretch interval on battery / Low Power Mode", isOn: $settings.adaptivePolling)
            if settings.adaptivePolling {
                LabeledContent("Multiplier") {
                    Stepper(value: $settings.adaptiveMultiplier, in: 1...10, step: 0.5) {
                        Text("×\(settings.adaptiveMultiplier, specifier: "%.1f")")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .leading)
                    }
                }
            }

            Toggle("Pause while the display is asleep", isOn: $settings.pauseOnDisplaySleep)
        }
    }

    // MARK: - Dock icon

    private var iconSection: some View {
        Section("Dock icon") {
            Toggle("Custom Dock icon", isOn: $settings.dockIconEnabled)
            Toggle("Classic icon image renderer", isOn: Binding(
                get: { !settings.useDockTileView },
                set: { settings.useDockTileView = !$0 }
            ))
            .help("Off (default): draw into the Dock tile view — cheaper and repaints reliably. On: assign NSApp.applicationIconImage.")

            Picker("Top line", selection: $settings.iconLine1) {
                ForEach(IconLine.all, id: \.self) { line in
                    Text(line.title).tag(line)
                }
            }
            Picker("Bottom line", selection: $settings.iconLine2) {
                ForEach(IconLine.all, id: \.self) { line in
                    Text(line.title).tag(line)
                }
            }

            colorRow("Background", $settings.iconBackground)
            colorRow("Border", $settings.iconBorder)
            colorRow("Text", $settings.iconText)

            LabeledContent("Border width") {
                HStack {
                    Slider(value: $settings.iconBorderWidth, in: 0...0.08)
                        .frame(width: 160)
                    Text("\(settings.iconBorderWidth * 100, specifier: "%.1f")%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Badge

    private var badgeSection: some View {
        Section("Dock badge") {
            Toggle("Show badge", isOn: $settings.badgeEnabled)
            Picker("Metric", selection: $settings.badgeStat) {
                ForEach(StatKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .disabled(!settings.badgeEnabled)
        }
    }

    // MARK: - Disk

    private var diskSection: some View {
        Section("Disk") {
            Picker("Volume", selection: $settings.volumePath) {
                ForEach(volumes, id: \.path) { volume in
                    Text("\(volume.name) — \(volume.path)").tag(volume.path)
                }
                if !volumes.contains(where: { $0.path == settings.volumePath }) {
                    Text(settings.volumePath).tag(settings.volumePath)
                }
            }
            Toggle("Show free space instead of used %", isOn: $settings.diskShowFree)
        }
    }

    // MARK: - Thresholds

    private var thresholdsSection: some View {
        Section("Thresholds") {
            ForEach(StatKind.allCases) { kind in
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.caption).foregroundStyle(.secondary)
                    thresholdRow("Warn", value: warnBinding(kind))
                    thresholdRow("Critical", value: critBinding(kind))
                }
            }
            LabeledContent("Hysteresis") {
                HStack {
                    Slider(value: $settings.thresholds.hysteresis, in: 0...20)
                        .frame(width: 160)
                    Text("\(settings.thresholds.hysteresis, specifier: "%.0f") pp")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
            Text("Disk thresholds apply to used space.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func thresholdRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).frame(width: 56, alignment: .leading)
            Slider(value: value, in: 0...100)
            Text("\(value.wrappedValue, specifier: "%.0f")%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section("General") {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
            Toggle("Bounce Dock icon on warning", isOn: $settings.bounceOnCritical)

            HStack {
                Spacer()
                Button("Reset to defaults") { settings.resetToDefaults() }
            }
        }
    }

    // MARK: - Helpers

    private func shownBinding(_ kind: StatKind) -> Binding<Bool> {
        Binding(
            get: { settings.isShown(kind) },
            set: { settings.toggle(kind, shown: $0) }
        )
    }

    private func orderLabel(_ kind: StatKind) -> String {
        guard let index = settings.barStats.firstIndex(of: kind) else { return "—" }
        return "#\(index + 1)"
    }

    private func canMove(_ kind: StatKind, by offset: Int) -> Bool {
        guard let index = settings.barStats.firstIndex(of: kind) else { return false }
        return settings.barStats.indices.contains(index + offset)
    }

    private func warnBinding(_ kind: StatKind) -> Binding<Double> {
        Binding(
            get: { settings.thresholds.warn(kind) },
            set: { settings.thresholds.setWarn(kind, min($0, settings.thresholds.crit(kind))) }
        )
    }

    private func critBinding(_ kind: StatKind) -> Binding<Double> {
        Binding(
            get: { settings.thresholds.crit(kind) },
            set: { settings.thresholds.setCrit(kind, max($0, settings.thresholds.warn(kind))) }
        )
    }

    private func colorRow(_ title: String, _ color: Binding<RGBAColor>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                ColorPicker("", selection: colorBinding(color), supportsOpacity: true)
                    .labelsHidden()
                HexField(color: color)
            }
        }
    }

    private func colorBinding(_ binding: Binding<RGBAColor>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: binding.wrappedValue.nsColor) },
            set: { binding.wrappedValue = RGBAColor(NSColor($0)) }
        )
    }
}

/// Hex entry with a local draft so partial input is not clobbered.
private struct HexField: View {
    @Binding var color: RGBAColor
    @State private var draft: String = ""

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.roundedBorder)
            .font(.system(.caption, design: .monospaced))
            .frame(width: 84)
            .onAppear { draft = color.hex }
            .onChange(of: color) { _, newValue in
                if draft.uppercased() != newValue.hex { draft = newValue.hex }
            }
            .onSubmit(commit)
            .onDisappear(perform: commit)
    }

    private func commit() {
        if let parsed = RGBAColor(hex: draft) {
            color = parsed
        }
        draft = color.hex
    }
}
