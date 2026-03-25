import Foundation
import CoreAudio
import AudioToolbox
import OSLog

class AudioDeviceService {
    var onDevicesChanged: ((_ isDeviceListChange: Bool) -> Void)?
    var onMuteOrVolumeChanged: (() -> Void)?

    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteVolumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var monitoredDeviceIds: Set<AudioObjectID> = []

    private let logger = Logger(subsystem: "com.audioprioritybar", category: "AudioDeviceService")
    private var deviceChangeCount = 0
    private var muteVolumeChangeCount = 0
    private var updateListenersCount = 0

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

    func setDefaultDevice(_ deviceId: AudioObjectID, type: AudioDeviceType, syncSystemOutput: Bool = true) {
        let selector: AudioObjectPropertySelector = type == .input
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice

        logger.debug("📍 setDefaultDevice called - type: \(type == .input ? "input" : "output"), deviceId: \(deviceId)")

        // Set the default device
        setAudioDevice(deviceId, selector: selector)

        // Sync system output if this is an output device and the preference is enabled
        if type == .output && syncSystemOutput {
            setAudioDevice(deviceId, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
            logger.debug("🔊 Synced system output to match default output")
        }

        logger.debug("✅ setDefaultDevice completed - type: \(type == .input ? "input" : "output"), deviceId: \(deviceId)")
    }
    
    private func setAudioDevice(_ deviceId: AudioObjectID, selector: AudioObjectPropertySelector) {
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

    func isDeviceMuted(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        let scope: AudioObjectPropertyScope = type == .input
            ? kAudioDevicePropertyScopeInput
            : kAudioDevicePropertyScopeOutput

        // Try kAudioDevicePropertyMute (per-channel, element 0 is master)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var muted: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        var status = AudioObjectGetPropertyData(
            deviceId,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &muted
        )

        if status == noErr && muted != 0 {
            return true
        }

        // Try element 1 (first channel) if master didn't work
        propertyAddress.mElement = 1
        status = AudioObjectGetPropertyData(
            deviceId,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &muted
        )

        if status == noErr && muted != 0 {
            return true
        }

        // Check if volume is essentially zero (some devices report this as muted)
        if type == .output {
            let volume = getDeviceVolume(deviceId)
            if volume < 0.01 {
                return true
            }
        }

        return false
    }

    func setDeviceMuted(_ deviceId: AudioObjectID, type: AudioDeviceType, muted: Bool) {
        let scope: AudioObjectPropertyScope = type == .input
            ? kAudioDevicePropertyScopeInput
            : kAudioDevicePropertyScopeOutput

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var muteValue: UInt32 = muted ? 1 : 0
        let dataSize = UInt32(MemoryLayout<UInt32>.size)

        var status = AudioObjectSetPropertyData(
            deviceId,
            &propertyAddress,
            0,
            nil,
            dataSize,
            &muteValue
        )

        // If master element didn't work, try element 1 (first channel)
        if status != noErr {
            propertyAddress.mElement = 1
            AudioObjectSetPropertyData(
                deviceId,
                &propertyAddress,
                0,
                nil,
                dataSize,
                &muteValue
            )
        }
    }

    func getDeviceVolume(_ deviceId: AudioObjectID) -> Float {
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

        return status == noErr ? volume : 1.0
    }

    func startListening() {
        logger.debug("🎧 startListening called")

        // Listener for device list changes (devices added/removed)
        var deviceListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        listenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            self.deviceChangeCount += 1
            self.logger.debug("🔔 Device LIST changed #\(self.deviceChangeCount) - devices added/removed")

            // Notify with isDeviceListChange = true
            self.onDevicesChanged?(true)

            // Re-register mute/volume listeners when devices are added/removed
            self.logger.debug("  → Updating mute/volume listeners")
            self.updateMuteVolumeListeners()
        }

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceListAddress,
            DispatchQueue.main,
            listenerBlock!
        )

        // Separate listener for default device changes (just switching devices)
        defaultDeviceListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            self.deviceChangeCount += 1
            self.logger.debug("🔔 Default device SWITCHED #\(self.deviceChangeCount) - user/system changed active device")

            // Notify with isDeviceListChange = false - DON'T reapply priorities
            self.onDevicesChanged?(false)
        }

        // Listen to default input device changes
        var inputDefaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &inputDefaultAddress,
            DispatchQueue.main,
            defaultDeviceListenerBlock!
        )

        // Listen to default output device changes
        var outputDefaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &outputDefaultAddress,
            DispatchQueue.main,
            defaultDeviceListenerBlock!
        )

        // Initial setup of mute/volume listeners
        logger.debug("🎧 Setting up initial mute/volume listeners")
        updateMuteVolumeListeners()
    }

    func updateMuteVolumeListeners() {
        updateListenersCount += 1
        logger.debug("🔄 updateMuteVolumeListeners called #\(self.updateListenersCount)")

        // Remove old listeners
        removeMuteVolumeListeners()

        // Create listener block
        muteVolumeListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            self.muteVolumeChangeCount += 1
            self.logger.trace("🔊 Mute/volume listener fired #\(self.muteVolumeChangeCount)")
            self.onMuteOrVolumeChanged?()
        }

        // Get all current device IDs
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

        guard status == noErr else { return }

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

        guard status == noErr else { return }

        // Register listeners for each device
        for deviceId in deviceIds {
            // Listen to mute on output scope
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(
                deviceId,
                &muteAddress,
                DispatchQueue.main,
                muteVolumeListenerBlock!
            )

            // Listen to mute on input scope
            muteAddress.mScope = kAudioDevicePropertyScopeInput
            AudioObjectAddPropertyListenerBlock(
                deviceId,
                &muteAddress,
                DispatchQueue.main,
                muteVolumeListenerBlock!
            )

            // Listen to volume changes
            var volumeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(
                deviceId,
                &volumeAddress,
                DispatchQueue.main,
                muteVolumeListenerBlock!
            )

            monitoredDeviceIds.insert(deviceId)
        }
    }

    private func removeMuteVolumeListeners() {
        guard let block = muteVolumeListenerBlock else { return }

        for deviceId in monitoredDeviceIds {
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceId, &muteAddress, DispatchQueue.main, block)

            muteAddress.mScope = kAudioDevicePropertyScopeInput
            AudioObjectRemovePropertyListenerBlock(deviceId, &muteAddress, DispatchQueue.main, block)

            var volumeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceId, &volumeAddress, DispatchQueue.main, block)
        }

        monitoredDeviceIds.removeAll()
        muteVolumeListenerBlock = nil
    }

    func stopListening() {
        // Remove mute/volume listeners first
        removeMuteVolumeListeners()

        // Remove device list listener
        if let block = listenerBlock {
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

        // Remove default device change listeners
        if let defaultBlock = defaultDeviceListenerBlock {
            var inputDefaultAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &inputDefaultAddress,
                DispatchQueue.main,
                defaultBlock
            )

            var outputDefaultAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &outputDefaultAddress,
                DispatchQueue.main,
                defaultBlock
            )
            defaultDeviceListenerBlock = nil
        }
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
