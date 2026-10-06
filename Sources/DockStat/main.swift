import AppKit

// `--probe` / `--render` run headless and exit before the app starts.
if Probe.run(arguments: CommandLine.arguments) {
    exit(0)
}

// DockStat keeps a normal Dock presence; the status item and the Dock icon are
// both driven by StatsStore.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
