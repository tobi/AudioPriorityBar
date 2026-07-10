import Foundation
import CoreAudio

enum AudioDeviceType: String, Codable {
    case input
    case output
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

    var roleIdentifier: String {
        "\(type.rawValue):\(uid)"
    }

    // Create a disconnected placeholder from stored device
    static func disconnected(uid: String, name: String, type: AudioDeviceType) -> AudioDevice {
        AudioDevice(id: 0, uid: uid, name: name, type: type, isConnected: false)
    }
}
