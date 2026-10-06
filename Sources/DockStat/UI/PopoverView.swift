import SwiftUI

/// The minimal click-through panel under the menu bar item.
struct PopoverView: View {
    let store: StatsStore
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    @Bindable private var settings: SettingsModel

    init(store: StatsStore, onOpenSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.store = store
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self._settings = Bindable(store.settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(StatKind.allCases) { kind in
                    row(for: kind)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            Divider().padding(.vertical, 10)

            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)
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
                .frame(width: 90)

                Spacer()

                Button {
                    store.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
            }
            .padding(.horizontal, 14)

            Divider().padding(.vertical, 10)

            HStack {
                Button("Settings…", action: onOpenSettings)
                    .keyboardShortcut(",", modifiers: .command)
                Spacer()
                Button("Quit", action: onQuit)
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 280)
    }

    private func row(for kind: StatKind) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color(for: kind))
                .frame(width: 7, height: 7)
            Text(kind.title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(store.displayText(for: kind))
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
        }
    }

    private func color(for kind: StatKind) -> Color {
        switch store.severity(for: kind) {
        case .critical: .red
        case .warning: .orange
        case .normal: .green
        }
    }
}
