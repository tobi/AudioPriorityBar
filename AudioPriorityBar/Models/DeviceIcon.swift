import Foundation
import CoreAudio

extension AudioDevice {
    /// SF Symbol describing the kind of hardware, similar to the macOS Sound menu.
    /// Name matches win over transport type, since e.g. a display or webcam usually connects over USB.
    func hardwareIcon(category: OutputCategory?) -> String {
        let nameLower = name.lowercased()

        if nameLower.contains("airpods max") { return "airpodsmax" }
        if nameLower.contains("airpods pro") { return "airpodspro" }
        if nameLower.contains("airpods") { return "airpods" }
        if nameLower.contains("beats") { return "beats.headphones" }
        if nameLower.contains("iphone") { return "iphone" }
        if nameLower.contains("ipad") { return "ipad" }
        if Self.cameraKeywords.contains(where: nameLower.contains) { return "web.camera" }
        if Self.displayKeywords.contains(where: nameLower.contains) { return "display" }

        switch transportType {
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "display"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless:
            return "iphone"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate:
            return "waveform"
        case kAudioDeviceTransportTypeBuiltIn:
            return type == .input ? "mic" : "speaker.wave.2"
        default:
            break
        }

        if type == .input {
            return "mic"
        }
        if category == .headphone || HeadphoneDetection.isHeadphone(deviceName: name) {
            return "headphones"
        }
        if transportType == kAudioDeviceTransportTypeBluetooth || transportType == kAudioDeviceTransportTypeBluetoothLE {
            return "hifispeaker"
        }
        return "speaker.wave.2"
    }

    private static let cameraKeywords = ["camera", "webcam", "brio", "c920", "c922", "kiyo", "facecam", "opal"]
    private static let displayKeywords = ["display", "monitor", "lg ultrafine", "tv"]
}
