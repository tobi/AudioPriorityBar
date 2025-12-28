import Foundation
import AVFoundation

struct CameraDevice: Identifiable, Equatable, Hashable {
    let id: String  // AVCaptureDevice.uniqueID
    let uid: String // Same as id for cameras
    let name: String
    var isConnected: Bool = true

    var isValid: Bool {
        !id.isEmpty
    }

    // Create a disconnected placeholder from stored device
    static func disconnected(uid: String, name: String) -> CameraDevice {
        CameraDevice(id: uid, uid: uid, name: name, isConnected: false)
    }

    // Create from AVCaptureDevice
    static func from(_ device: AVCaptureDevice) -> CameraDevice {
        CameraDevice(
            id: device.uniqueID,
            uid: device.uniqueID,
            name: device.localizedName,
            isConnected: true
        )
    }
}
