import Foundation
import CoreAudio

enum MicrophoneRole: String, Codable, CaseIterable {
    case unknown, wired, bluetooth, builtIn, camera, continuity, external, virtual

    var label: String {
        switch self {
        case .unknown: return "Unclassified microphone"
        case .wired: return "Wired headset"
        case .bluetooth: return "Bluetooth microphone"
        case .builtIn: return "Mac microphone"
        case .camera: return "Camera microphone"
        case .continuity: return "iPhone Continuity"
        case .external: return "External microphone"
        case .virtual: return "Virtual or aggregate input"
        }
    }
}

enum LidState: String {
    case open, closed, unknown
}

enum MicrophoneCondition: String, Codable, CaseIterable {
    case always, lidOpen, lidClosed, never

    var label: String {
        switch self {
        case .always: return "Always"
        case .lidOpen: return "When lid is open"
        case .lidClosed: return "When lid is closed"
        case .never: return "Never"
        }
    }

    func allows(_ lid: LidState) -> Bool {
        switch self {
        case .always: return true
        case .lidOpen: return lid == .open
        case .lidClosed: return lid == .closed
        case .never: return false
        }
    }
}

struct MicrophoneRule: Codable, Equatable, Identifiable {
    var role: MicrophoneRole
    var condition: MicrophoneCondition
    var id: MicrophoneRole { role }

    static let defaults: [MicrophoneRule] = [
        .init(role: .wired, condition: .always),
        .init(role: .bluetooth, condition: .always),
        .init(role: .builtIn, condition: .always),
        .init(role: .external, condition: .always),
        .init(role: .camera, condition: .always),
        .init(role: .continuity, condition: .always),
        .init(role: .virtual, condition: .never),
        .init(role: .unknown, condition: .never)
    ]
}

struct MicrophoneMetadata: Equatable, Hashable {
    var transport: UInt32? = nil
    var inputTerminals: [UInt32] = []
}

struct MicrophoneClassification: Codable, Equatable {
    var role: MicrophoneRole
    var reason: String
}

enum MicrophoneClassifier {
    static func classify(name: String, metadata: MicrophoneMetadata) -> MicrophoneClassification {
        let transport = metadata.transport
        let headset = metadata.inputTerminals.contains(UInt32(kAudioStreamTerminalTypeHeadsetMicrophone))

        // Transport describes the actual endpoint. A name cannot override it.
        switch transport {
        case UInt32(kAudioDeviceTransportTypeVirtual),
             UInt32(kAudioDeviceTransportTypeAggregate),
             UInt32(kAudioDeviceTransportTypeAutoAggregate):
            return .init(role: .virtual, reason: "CoreAudio reports a virtual or aggregate device.")
        case UInt32(kAudioDeviceTransportTypeContinuityCaptureWired),
             UInt32(kAudioDeviceTransportTypeContinuityCaptureWireless),
             UInt32(kAudioDeviceTransportTypeContinuityCapture):
            return .init(role: .continuity, reason: "CoreAudio reports a Continuity Capture device.")
        case UInt32(kAudioDeviceTransportTypeBluetooth), UInt32(kAudioDeviceTransportTypeBluetoothLE):
            return .init(role: .bluetooth, reason: "CoreAudio reports a Bluetooth connection.")
        case UInt32(kAudioDeviceTransportTypeBuiltIn):
            return headset
                ? .init(role: .wired, reason: "CoreAudio reports a headset microphone on the built-in audio connection.")
                : .init(role: .builtIn, reason: "CoreAudio reports a built-in audio device.")
        default: break
        }

        if transport == UInt32(kAudioDeviceTransportTypeUSB), headset {
            return .init(role: .wired, reason: "CoreAudio reports a USB headset microphone terminal.")
        }

        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let headsetHints: Set<String> = ["headset", "headphones", "earbuds", "airpods"]
        let cameraHints: Set<String> = ["webcam", "camera", "streamcam"]
        if let hint = words.first(where: { headsetHints.contains($0) }) {
            // The name alone does not establish a wired connection.
            if transport == UInt32(kAudioDeviceTransportTypeUSB) {
                return .init(role: .wired, reason: "USB connection and the name contains ‘\(hint)’. Check this suggested role.")
            }
            return .init(role: .unknown, reason: "The name suggests a headset, but its connection type is not known. Choose a role.")
        }
        if let hint = words.first(where: { cameraHints.contains($0) }) {
            return .init(role: .camera, reason: "The name contains ‘\(hint)’. Check this suggested role.")
        }
        if metadata.inputTerminals.contains(UInt32(kAudioStreamTerminalTypeMicrophone)) {
            return .init(role: .external, reason: "CoreAudio reports a microphone terminal without a more specific device role.")
        }
        return .init(role: .unknown, reason: "CoreAudio metadata and the device name do not identify a microphone role. Choose a role.")
    }
}

struct MicrophoneSettings: Codable, Equatable {
    var enabled = false
    var rules: [MicrophoneRule] = MicrophoneRule.defaults
    // Persist by driver UID, not the transient numeric device ID. A changed UID is a new device.
    var overrides: [String: MicrophoneRole] = [:]

    func normalized() -> MicrophoneSettings {
        var result = self
        var seen = Set<MicrophoneRole>()
        result.rules = (rules + MicrophoneRule.defaults).filter { seen.insert($0.role).inserted }
        result.overrides = overrides.filter { !$0.key.isEmpty }
        return result
    }
}

extension MicrophoneSettings {
    private enum CodingKeys: String, CodingKey { case enabled, rules, overrides }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? false
        rules = []
        if var entries = try? container.nestedUnkeyedContainer(forKey: .rules) {
            while !entries.isAtEnd {
                // Read each element separately so an unknown future enum does not
                // discard unrelated user settings or stop decoder progress.
                let entry = try entries.superDecoder()
                if let rule = try? MicrophoneRule(from: entry) { rules.append(rule) }
            }
        }
        let storedOverrides = (try? container.decode([String: String].self, forKey: .overrides)) ?? [:]
        overrides = storedOverrides.compactMapValues(MicrophoneRole.init(rawValue:))
        self = normalized()
    }
}

enum MicrophoneSelection {
    static func choose(
        candidates: [AudioDevice],
        settings: MicrophoneSettings,
        classifications: [String: MicrophoneClassification],
        lid: LidState
    ) -> AudioDevice? {
        let connectedInputs = candidates.filter { $0.isConnected && $0.type == .input }
        guard settings.enabled else { return connectedInputs.first }
        for rule in settings.normalized().rules where rule.condition.allows(lid) {
            if let device = connectedInputs.first(where: {
                let role = settings.overrides[$0.uid] ?? classifications[$0.uid]?.role ?? .unknown
                return role == rule.role
            }) {
                return device
            }
        }
        return nil
    }
}
