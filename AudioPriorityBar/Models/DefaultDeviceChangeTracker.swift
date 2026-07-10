import CoreAudio

struct DefaultDeviceChangeTracker {
    private var preservedInputId: AudioObjectID?
    private var preservedOutputId: AudioObjectID?

    mutating func preserveManualSelection(_ deviceId: AudioObjectID, type: AudioDeviceType) {
        switch type {
        case .input:
            preservedInputId = deviceId
        case .output:
            preservedOutputId = deviceId
        }
    }

    mutating func shouldPreserveManualSelection(
        currentDeviceId: AudioObjectID?,
        type: AudioDeviceType
    ) -> Bool {
        let preserved: AudioObjectID?
        switch type {
        case .input:
            preserved = preservedInputId
        case .output:
            preserved = preservedOutputId
        }

        guard let preserved else { return false }
        guard preserved == currentDeviceId else {
            clearManualSelection(type: type)
            return false
        }
        return true
    }

    mutating func clearManualSelection(type: AudioDeviceType) {
        switch type {
        case .input:
            preservedInputId = nil
        case .output:
            preservedOutputId = nil
        }
    }

    mutating func clearAllManualSelections() {
        preservedInputId = nil
        preservedOutputId = nil
    }
}
