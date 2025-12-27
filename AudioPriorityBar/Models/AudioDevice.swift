import Foundation
import CoreAudio

enum AudioDeviceType: String, Codable {
    case input
    case output
}

enum OutputCategory: String, Codable, CaseIterable {
    case speaker
    case headphone

    var icon: String {
        switch self {
        case .speaker: return "speaker.wave.2.fill"
        case .headphone: return "headphones"
        }
    }

    var label: String {
        switch self {
        case .speaker: return "Speakers"
        case .headphone: return "Headphones"
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
