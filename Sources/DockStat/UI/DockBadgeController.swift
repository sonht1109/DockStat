import AppKit

/// System red badge bubble on the Dock tile. No notification permission needed.
@MainActor
final class DockBadgeController {
    private var current: String?

    func update(_ text: String?) {
        guard text != current else { return }
        current = text
        NSApp.dockTile.badgeLabel = text
        NSApp.dockTile.display()
    }
}
