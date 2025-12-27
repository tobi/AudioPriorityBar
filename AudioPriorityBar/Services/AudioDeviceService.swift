import Foundation
import CoreAudio
import AudioToolbox

class AudioDeviceService {
    var onDevicesChanged: (() -> Void)?

    private var listenerBlock: AudioObjectPropertyListenerBlock?

    func getDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIds = [AudioObjectID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIds
        )

        guard status == noErr else { return [] }

        var devices: [AudioDevice] = []

        for deviceId in deviceIds {
            if let inputDevice = createDevice(id: deviceId, type: .input) {
                devices.append(inputDevice)
            }
            if let outputDevice = createDevice(id: deviceId, type: .output) {
                devices.append(outputDevice)
            }
        }

        return devices
    }

    func getCurrentDefaultDevice(type: AudioDeviceType) -> AudioObjectID? {
        let selector: AudioObjectPropertySelector = type == .input
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceId: AudioObjectID = 0
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceId
        )

        return status == noErr ? deviceId : nil
    }

    func setDefaultDevice(_ deviceId: AudioObjectID, type: AudioDeviceType) {
        let selector: AudioObjectPropertySelector = type == .input
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableDeviceId = deviceId
        let dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &mutableDeviceId
        )
    }

    func getOutputVolume() -> Float {
        guard let deviceId = getCurrentDefaultDevice(type: .output) else { return 0 }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var volume: Float32 = 0
        var dataSize = UInt32(MemoryLayout<Float32>.size)

        let status = AudioObjectGetPropertyData(
            deviceId,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &volume
        )

        return status == noErr ? volume : 0
    }

    func setOutputVolume(_ volume: Float) {
        guard let deviceId = getCurrentDefaultDevice(type: .output) else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableVolume = volume
        let dataSize = UInt32(MemoryLayout<Float32>.size)

        AudioObjectSetPropertyData(
            deviceId,
            &propertyAddress,
            0,
            nil,
            dataSize,
            &mutableVolume
        )
    }

    func startListening() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        listenerBlock = { [weak self] _, _ in
            self?.onDevicesChanged?()
        }

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            listenerBlock!
        )
    }

    func stopListening() {
        guard let block = listenerBlock else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )

        listenerBlock = nil
    }

    private func createDevice(id: AudioObjectID, type: AudioDeviceType) -> AudioDevice? {
        let scope: AudioObjectPropertyScope = type == .input
            ? kAudioDevicePropertyScopeInput
            : kAudioDevicePropertyScopeOutput

        guard hasStreams(deviceId: id, scope: scope) else { return nil }

        guard let name = getDeviceName(id: id) else { return nil }
        guard let uid = getDeviceUID(id: id) else { return nil }

        return AudioDevice(id: id, uid: uid, name: name, type: type)
    }

    private func hasStreams(deviceId: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceId,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        return status == noErr && dataSize > 0
    }

    private func getDeviceName(id: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(
            id,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        return status == noErr ? name as String? : nil
    }

    private func getDeviceUID(id: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(
            id,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &uid
        )

        return status == noErr ? uid as String? : nil
    }

    deinit {
        stopListening()
    }
}
