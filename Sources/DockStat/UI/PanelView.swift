import AppKit
import SwiftUI

/// The panel that drops out of the menu bar item: live values with a meter each,
/// the polling interval and the two actions. Colours mirror the menu bar, so a
/// warning reads the same in both places.
struct PanelView: View {
    let store: StatsStore
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    @Bindable private var settings: SettingsModel

    /// `false` draws a flat backing instead of the desktop blur: an offscreen
    /// preview (`--panel`) has nothing to blur.
    var vibrancy = true

    /// Fixed width, used to size the hosting window.
    static let width: CGFloat = 264
    private static let radius: CGFloat = 12

    init(
        store: StatsStore,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        vibrancy: Bool = true
    ) {
        self.store = store
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.vibrancy = vibrancy
        self._settings = Bindable(store.settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            metrics
            Divider()
            controls
            Divider()
            actions
        }
        .frame(width: Self.width)
        .background {
            if vibrancy {
                VisualEffectBackground()
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "speedometer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("DockStat")
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 8)
            Button {
                store.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(StatKind.allCases) { kind in
                metric(kind)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private func metric(_ kind: StatKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 13, alignment: .leading)
                Text(kind.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(store.displayText(for: kind))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(valueColor(for: kind))
            }
            Meter(fraction: fraction(for: kind), color: color(for: kind))
                .padding(.leading, 20)
        }
    }

    private var controls: some View {
        HStack(spacing: 7) {
            Image(systemName: "timer")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 13, alignment: .leading)
            Text("Update every")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Picker("", selection: $settings.interval) {
                ForEach([1.0, 2.0, 5.0, 10.0, 30.0, 60.0], id: \.self) { value in
                    Text(Formatters.seconds(value)).tag(value)
                }
                if ![1.0, 2.0, 5.0, 10.0, 30.0, 60.0].contains(settings.interval) {
                    Text(Formatters.seconds(settings.interval)).tag(settings.interval)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 86)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Settings…", action: onOpenSettings)
                .keyboardShortcut(",", modifiers: .command)
            Spacer(minLength: 8)
            Button("Quit", action: onQuit)
                .keyboardShortcut("q", modifiers: .command)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Values

    private func fraction(for kind: StatKind) -> Double {
        guard let value = store.metric(for: kind) else { return 0 }
        return (value / 100).clamped(to: 0...1)
    }

    private func color(for kind: StatKind) -> Color {
        switch store.severity(for: kind) {
        case .critical: .red
        case .warning: .orange
        case .normal: .green
        }
    }

    /// Only an escalated value is tinted; a healthy one stays plain text.
    private func valueColor(for kind: StatKind) -> Color {
        switch store.severity(for: kind) {
        case .critical: .red
        case .warning: .orange
        case .normal: .primary
        }
    }
}

/// Thin usage meter under a metric row.
private struct Meter: View {
    var fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// Blurs whatever is behind the panel. Cheaper and more predictable than a
/// SwiftUI material in a transparent borderless window.
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
