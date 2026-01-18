import AppKit

enum StatusIcon {
    case initializing
    case idle
    case synced
    case syncing
    case scanning
    case error
    
    var symbolName: String {
        switch self {
        case .initializing:
            return "arrow.triangle.2.circlepath"
        case .idle:
            return "d.circle.fill"
        case .synced:
            return "checkmark.circle.fill"
        case .syncing, .scanning:
            return "arrow.triangle.2.circlepath"
        case .error:
            return "exclamationmark.circle.fill"
        }
    }
    
    var tintColor: NSColor {
        switch self {
        case .initializing:
            return .systemBlue
        case .idle:
            return .secondaryLabelColor
        case .synced:
            return .systemGreen
        case .syncing, .scanning:
            return .systemOrange
        case .error:
            return .systemRed
        }
    }
    
    var statusText: String {
        switch self {
        case .initializing:
            return "Initializing..."
        case .idle:
            return "Idle"
        case .synced:
            return "Synced"
        case .syncing:
            return "Syncing"
        case .scanning:
            return "Scanning"
        case .error:
            return "Error"
        }
    }
}
