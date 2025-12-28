import Foundation
import AVFoundation

class CameraDeviceService {
    var onDevicesChanged: (() -> Void)?

    private var discoverySession: AVCaptureDevice.DiscoverySession?
    private var observers: [NSObjectProtocol] = []

    func getDevices() -> [CameraDevice] {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .externalUnknown
        ]

        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )

        return session.devices.map { CameraDevice.from($0) }
    }

    func getDefaultDevice() -> CameraDevice? {
        guard let device = AVCaptureDevice.default(for: .video) else {
            return nil
        }
        return CameraDevice.from(device)
    }

    func startListening() {
        // Listen for device connect/disconnect events
        let connectObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onDevicesChanged?()
        }
        observers.append(connectObserver)

        let disconnectObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onDevicesChanged?()
        }
        observers.append(disconnectObserver)
    }

    func stopListening() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    deinit {
        stopListening()
    }
}
