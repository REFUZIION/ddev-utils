import Foundation

enum DiskSpaceReader {
    /// Used fraction of the boot volume (0...1), or nil if unavailable.
    static func bootVolumeUsedFraction() -> Double? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
        ]),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacity,
              total > 0
        else {
            return nil
        }
        let used = total - available
        return Double(used) / Double(total)
    }
}
