import Darwin
import Foundation

/// Free / total bytes for a mounted volume via `statfs`.
final class DiskSampler: @unchecked Sendable {
    private var cachedPath: String?
    private var cachedFree: (free: UInt64, total: UInt64)?

    /// Returns `(free, total)` in bytes.
    func sample(path: String) -> (free: UInt64, total: UInt64)? {
        // statfs is a syscall; the volume's free space moves slowly, so the
        // cached value is reused between polls of the same path only when the
        // caller asks for it (see StatsSampler).
        _ = cachedPath

        var info = statfs()
        let ok = path.withCString { statfs($0, &info) == 0 }
        guard ok else { return nil }

        let blockSize = UInt64(info.f_bsize)
        cachedPath = path
        let values = (free: UInt64(info.f_bavail) &* blockSize,
                      total: UInt64(info.f_blocks) &* blockSize)
        cachedFree = values
        return values
    }

    /// Available local volumes, cheapest useful set for the settings picker.
    static func mountedVolumes() -> [(name: String, path: String)] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsBrowsableKey, .volumeIsLocalKey]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else { return [("/", "/")] }

        var seen = Set<String>()
        var result: [(name: String, path: String)] = []
        for url in urls {
            let path = url.path
            // Ignore synthetic APFS helper volumes under /System/Volumes.
            if path.hasPrefix("/System/Volumes") { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsLocal != false
            else { continue }
            guard seen.insert(path).inserted else { continue }
            result.append((values.volumeName ?? path, path))
        }
        result.sort { $0.path.count < $1.path.count }
        return result.isEmpty ? [("/", "/")] : result
    }
}
