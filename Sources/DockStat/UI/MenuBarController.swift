import AppKit
import SwiftUI

/// Owns the `NSStatusItem` and its popover.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private weak var store: StatsStore?

    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

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

        let root = PopoverView(store: store, onOpenSettings: { [weak self] in
            self?.closePopover()
            self?.onOpenSettings?()
        }, onQuit: { [weak self] in
            self?.onQuit?()
        })
        popover.contentViewController = NSHostingController(rootView: root)
        popover.contentSize = NSSize(width: 280, height: 250)
        popover.behavior = .transient
        popover.delegate = self
    }

    func setTitle(_ title: NSAttributedString) {
        statusItem.button?.attributedTitle = title
    }

    func setVisible(_ visible: Bool) {
        statusItem.isVisible = visible
        if !visible { closePopover() }
    }

    // MARK: - Popover

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    private func showContextMenu() {
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
