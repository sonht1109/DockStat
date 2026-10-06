import Foundation
import ServiceManagement

/// Launch at login: `SMAppService` first, LaunchAgent plist as fallback
/// (ad-hoc signed bundles do not always satisfy SMAppService).
enum LaunchAtLogin {
    static let label = "dev.sonht.dockstat"

    static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        if SMAppService.mainApp.status == .enabled { return true }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    /// - Returns: `nil` on success, otherwise a human-readable reason.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        if enabled {
            if SMAppService.mainApp.status == .enabled { return nil }
            // `register()` can succeed while leaving the service `notFound`
            // (app outside /Applications), so verify the resulting status.
            _ = try? SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .enabled { return nil }
            return writeAgent() ? nil : "could not register for launch at login"
        } else {
            try? SMAppService.mainApp.unregister()
            removeAgent()
            return nil
        }
    }

    private static func writeAgent() -> Bool {
        guard let executable = Bundle.main.executableURL?.path else { return false }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive"
        ]
        do {
            try FileManager.default.createDirectory(
                at: agentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: agentURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func removeAgent() {
        try? FileManager.default.removeItem(at: agentURL)
    }
}
