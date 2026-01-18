import Foundation

/// Represents Mutagen sync status
enum MutagenSyncStatus: String, Equatable {
    case synced = "ok"
    case watching = "watching"
    case scanning = "scanning"
    case syncing = "syncing"
    case staging = "staging"
    case paused = "paused"
    case disconnected = "disconnected"
    case problems = "problems"
    case unknown = "unknown"
    
    /// Initialize from a status string
    init(fromString string: String) {
        let lowercased = string.lowercased()
        if lowercased.contains("scanning") || lowercased.contains("reconciling") {
            self = .scanning
        } else if lowercased.contains("syncing") || lowercased.contains("saving") || lowercased.contains("transitioning") {
            self = .syncing
        } else if lowercased.contains("staging") {
            self = .staging
        } else if lowercased.contains("watching") {
            self = .watching
        } else if lowercased.contains("ok") && lowercased.contains("watching") || lowercased.contains("healthy") {
            self = .synced
        } else if lowercased.contains("paused") {
            self = .paused
        } else if lowercased.contains("disconnected") || lowercased.contains("not running") {
            self = .disconnected
        } else if lowercased.contains("problems") {
            self = .problems
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
    
    /// Returns true if sync is complete and watching for changes
    var isSynced: Bool {
        switch self {
        case .synced, .watching:
            return true
        default:
            return false
        }
    }
    
    /// Returns a human-readable description
    var displayName: String {
        switch self {
        case .synced, .watching:
            return "Synced"
        case .scanning:
            return "Scanning..."
        case .syncing, .staging:
            return "Syncing..."
        case .paused:
            return "Paused"
        case .disconnected:
            return "Disconnected"
        case .problems:
            return "Problems"
        case .unknown:
            return "Unknown"
        }
    }
}
