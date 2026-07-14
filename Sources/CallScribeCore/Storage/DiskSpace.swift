import Foundation

public enum DiskSpace {
    /// Recording is refused below this (a 90-min call is ~350 MB of WAV; 1 GB
    /// leaves comfortable headroom).
    public static let minimumBytesForRecording: Int64 = 1_000_000_000

    public static func availableBytes(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

// rebuild marker
