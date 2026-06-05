import Foundation
import CoreAudio

enum AudioDeviceType: String, Codable {
    case input
    case output
}

enum OutputCategory: String, Codable, CaseIterable {
    case speaker
    case headphone
    /// Display-only "mode" that shows all outputs in one combined priority list.
    /// Never used as a device category — devices are always categorized as
    /// .speaker or .headphone for the per-category lists.
    case combined

    /// The valid categories a device can be assigned to.
    static var deviceCategories: [OutputCategory] { [.speaker, .headphone] }

    /// The selectable display modes shown in the mode toggle bar.
    static var displayModes: [OutputCategory] { [.speaker, .headphone, .combined] }

    var icon: String {
        switch self {
        case .speaker: return "speaker.wave.2.fill"
        case .headphone: return "headphones"
        case .combined: return "rectangle.stack.fill"
        }
    }

    var label: String {
        switch self {
        case .speaker: return "Speakers"
        case .headphone: return "Headphones"
        case .combined: return "Auto"
        }
    }
}

struct AudioDevice: Identifiable, Equatable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let type: AudioDeviceType
    var isConnected: Bool = true

    var isValid: Bool {
        id != kAudioObjectUnknown
    }

    // Create a disconnected placeholder from stored device
    static func disconnected(uid: String, name: String, type: AudioDeviceType) -> AudioDevice {
        AudioDevice(id: 0, uid: uid, name: name, type: type, isConnected: false)
    }
}
