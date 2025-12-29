import Foundation

/// Represents a device that has been seen before and persisted for priority management
struct StoredDevice: Codable, Equatable {
    let uid: String
    let name: String
    let isInput: Bool
    var lastSeen: Date

    /// Human-readable relative time since device was last seen
    var lastSeenRelative: String {
        let interval = Date().timeIntervalSince(lastSeen)

        switch interval {
        case ..<60:
            return "now"
        case ..<3600:
            return "\(Int(interval / 60))m ago"
        case ..<86400:
            return "\(Int(interval / 3600))h ago"
        case ..<604800:
            return "\(Int(interval / 86400))d ago"
        case ..<2592000:
            return "\(Int(interval / 604800))w ago"
        default:
            return "\(Int(interval / 2592000))mo ago"
        }
    }
}
