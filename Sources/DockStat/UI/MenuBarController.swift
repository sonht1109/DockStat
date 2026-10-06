import AppKit
import SwiftUI

/// Owns the `NSStatusItem` and the panel below it.
///
/// The panel is a plain `NSPanel` that we place ourselves instead of an
/// `NSPopover`: only a window we position by hand is guaranteed to hang flush
/// off the bottom of the menu bar rather than float somewhere below it.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private weak var store: StatsStore?

    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    private var panel: StatsPanel?
    private var monitors: [Any] = []
    private var deactivationObserver: NSObjectProtocol?

    init(store: StatsStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .noImage
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }
    }

    func setTitle(_ title: NSAttributedString, accessibilityLabel: String) {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.imagePosition = .noImage
        button.attributedTitle = title
        button.setAccessibilityLabel(accessibilityLabel)
    }

    func setImage(_ image: NSImage?, accessibilityLabel: String) {
        guard let button = statusItem.button, let image else {
            setTitle(NSAttributedString(string: ""), accessibilityLabel: accessibilityLabel)
            return
        }
        button.attributedTitle = NSAttributedString(string: "")
        button.image = image
        // Never let AppKit rescale the drawing: the blocks are laid out to the point.
        button.imageScaling = .scaleNone
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(accessibilityLabel)
    }

    func setVisible(_ visible: Bool) {
        statusItem.isVisible = visible
        if !visible { hidePanel() }
    }

    // MARK: - Panel

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let store else { return }

        let panel: StatsPanel
        if let existing = self.panel {
            panel = existing
        } else {
            panel = makePanel(for: store)
            self.panel = panel
        }

        NSApp.activate(ignoringOtherApps: true)

        // Activating brings our own menu into the menu bar, which shifts the
        // status item sideways: let that settle before measuring where the panel
        // goes, so it lands centred on the item instead of on its old position.
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, self.panel === panel else { return }
            self.place(panel)
            panel.makeKeyAndOrderFront(nil)
            self.statusItem.button?.highlight(true)
            self.installMonitors()
        }
    }

    private func hidePanel() {
        removeMonitors()
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
    }

    private func makePanel(for store: StatsStore) -> StatsPanel {
        let root = PanelView(store: store, onOpenSettings: { [weak self] in
            self?.hidePanel()
            self?.onOpenSettings?()
        }, onQuit: { [weak self] in
            self?.onQuit?()
        })

        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]

        let panel = StatsPanel(contentViewController: hosting)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.setContentSize(NSSize(
            width: PanelView.width,
            height: max(hosting.view.fittingSize.height, 1)
        ))
        return panel
    }

    /// Hang the panel off the bottom edge of the menu bar, centred on the status
    /// item, kept inside the screen it belongs to.
    private func place(_ panel: StatsPanel) {
        guard let button = statusItem.button, let anchorWindow = button.window else { return }

        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        let visible = anchorWindow.screen?.visibleFrame ?? anchor.insetBy(dx: 8, dy: 8)

        let leftmost = visible.minX + 8
        let rightmost = Swift.max(leftmost, visible.maxX - size.width - 8)
        let x = (anchor.midX - size.width / 2).clamped(to: leftmost...rightmost)
        let y = anchorWindow.frame.minY - size.height

        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    // MARK: - Dismissal

    /// Esc closes the panel, a click outside our own windows closes it, a click
    /// in another app closes it. Deliberately not on key-window changes: the
    /// click that lands on the status item itself would close and reopen at once.
    private func installMonitors() {
        removeMonitors()

        let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard event.type == .keyDown else {
                let hit = event.window
                MainActor.assumeIsolated {
                    guard let self, self.isPanelVisible,
                          hit !== self.panel, hit !== self.statusItem.button?.window
                    else { return }
                    self.hidePanel()
                }
                return event
            }
            guard event.keyCode == 53 else { return event }
            let dismissed = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.isPanelVisible else { return false }
                self.hidePanel()
                return true
            }
            return dismissed ? nil : event
        }

        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hidePanel() }
        }

        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hidePanel() }
        }

        monitors = [local, global].compactMap { $0 }
    }

    private var isPanelVisible: Bool { panel?.isVisible == true }

    private func removeMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        if let deactivationObserver {
            NotificationCenter.default.removeObserver(deactivationObserver)
            self.deactivationObserver = nil
        }
    }

    // MARK: - Context menu

    private func showContextMenu() {
        hidePanel()
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DockStat", action: #selector(quit), keyEquivalent: "q").target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func quit() { onQuit?() }
}

/// Borderless panel that can take key focus (for Esc and the button shortcuts)
/// without pulling the whole app forward.
private final class StatsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
