import Foundation

/// Represents Mutagen sync status
enum MutagenSyncStatus: String, Equatable {
    case synced = "ok"
    case scanning = "scanning"
    case syncing = "syncing"
    case staging = "staging"
    case paused = "paused"
    case disconnected = "disconnected"
    case problems = "problems"
    case disabled = "disabled"
    case unknown = "unknown"

    /// Initialize from a status string. Bad states are checked first: output can say
    /// "problems" and "Watching for changes" at the same time.
    init(fromString string: String) {
        let lowercased = string.lowercased()
        if lowercased.contains("not enabled") {
            self = .disabled
        } else if lowercased.contains("problems") {
            self = .problems
        } else if lowercased.contains("paused") {
            self = .paused
        } else if lowercased.contains("disconnected") || lowercased.contains("not running") {
            self = .disconnected
        } else if lowercased.contains("scanning") || lowercased.contains("reconciling") {
            self = .scanning
        } else if lowercased.contains("syncing") || lowercased.contains("saving") || lowercased.contains("transitioning") {
            self = .syncing
        } else if lowercased.contains("staging") {
            self = .staging
        } else if lowercased.contains("watching") || lowercased.contains("healthy") {
            self = .synced
        } else {
            self = .unknown
        }
    }

    /// Returns true if files are actively being synced
    var isSyncing: Bool {
        switch self {
        case .syncing, .staging, .scanning:
            return true
        default:
            return false
        }
    }
}
