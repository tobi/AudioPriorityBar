import Combine
import Foundation
import CoreAudio

@MainActor
class AudioManager: ObservableObject {
    @Published var inputDevices: [AudioDevice] = []
    @Published var outputDevices: [AudioDevice] = []
    @Published var currentInputId: AudioObjectID?
    @Published var currentOutputId: AudioObjectID?
    @Published var volume: Float = 0
    @Published var isEditMode: Bool = false
    @Published var isOutputAutoSwitchEnabled: Bool = true
    @Published var isInputAutoSwitchEnabled: Bool = true
    @Published var isAutomationPaused: Bool = false
    @Published var mutedDeviceIds: Set<AudioObjectID> = []
    @Published var isActiveOutputMuted: Bool = false
    @Published var isActiveInputMuted: Bool = false
    @Published var micFlashState: Bool = false

    private let deviceService = AudioDeviceService()
    private var micFlashTimer: Timer?
    let priorityManager = PriorityManager()
    private var connectedDeviceRoleIdentifiers: Set<String> = []
    private var connectedInputDevices: [AudioDevice] = []
    private var connectedOutputDevices: [AudioDevice] = []
    private var defaultDeviceChangeTracker = DefaultDeviceChangeTracker()

    var menuBarIcon: String {
        isAutomationPaused ? "pause.circle.fill" : "speaker.wave.2.fill"
    }

    var isOutputAutomationActive: Bool {
        isOutputAutoSwitchEnabled && !isAutomationPaused
    }

    var isInputAutomationActive: Bool {
        isInputAutoSwitchEnabled && !isAutomationPaused
    }

    func isAutomationActive(for type: AudioDeviceType) -> Bool {
        switch type {
        case .input:
            return isInputAutomationActive
        case .output:
            return isOutputAutomationActive
        }
    }

    func refreshVolume() {
        volume = deviceService.getOutputVolume()
    }

    func refreshMuteStatus() {
        var muted: Set<AudioObjectID> = []
        for device in connectedInputDevices {
            if deviceService.isDeviceMuted(device.id, type: .input) {
                muted.insert(device.id)
            }
        }
        for device in connectedOutputDevices {
            if deviceService.isDeviceMuted(device.id, type: .output) {
                muted.insert(device.id)
            }
        }
        mutedDeviceIds = muted
        if let outputId = currentOutputId {
            isActiveOutputMuted = muted.contains(outputId)
        } else {
            isActiveOutputMuted = false
        }
        if let inputId = currentInputId {
            isActiveInputMuted = muted.contains(inputId)
        } else {
            isActiveInputMuted = false
        }
        if isActiveInputMuted && micFlashTimer == nil {
            micFlashTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.micFlashState.toggle()
                }
            }
        } else if !isActiveInputMuted && micFlashTimer != nil {
            micFlashTimer?.invalidate()
            micFlashTimer = nil
            micFlashState = false
        }
    }

    func isDeviceMuted(_ device: AudioDevice) -> Bool {
        mutedDeviceIds.contains(device.id)
    }

    func setVolume(_ newVolume: Float) {
        volume = newVolume
        deviceService.setOutputVolume(newVolume)
    }

    init() {
        isOutputAutoSwitchEnabled = priorityManager.isOutputAutoSwitchEnabled
        isInputAutoSwitchEnabled = priorityManager.isInputAutoSwitchEnabled
        isAutomationPaused = priorityManager.isGlobalAutoSwitchPaused
        refreshDevices()
        refreshVolume()
        refreshMuteStatus()
        setupDeviceChangeListener()
        setupMuteVolumeListener()
        if isInputAutomationActive {
            applyHighestPriorityInput()
        }
        if isOutputAutomationActive {
            applyHighestPriorityOutput()
        }
    }

    private func setupMuteVolumeListener() {
        deviceService.onMuteOrVolumeChanged = { [weak self] in
            Task { @MainActor in
                self?.handleMuteOrVolumeChange()
            }
        }
    }

    private func handleMuteOrVolumeChange() {
        refreshMuteStatus()
        refreshVolume()
    }

    func refreshDevices() {
        let allConnectedDevices = deviceService.getDevices()
        connectedDeviceRoleIdentifiers = Set(allConnectedDevices.map { $0.roleIdentifier })
        for device in allConnectedDevices {
            priorityManager.rememberDevice(device.uid, name: device.name, isInput: device.type == .input)
        }
        let connectedInputs = allConnectedDevices.filter { $0.type == .input }
        let connectedOutputs = allConnectedDevices.filter { $0.type == .output }
        connectedInputDevices = connectedInputs
        connectedOutputDevices = connectedOutputs
        priorityManager.registerDiscoveredUIDs(connectedInputs.map(\.uid), type: .input)
        priorityManager.registerDiscoveredUIDs(connectedOutputs.map(\.uid), type: .output)

        if isEditMode {
            let knownDevices = priorityManager.getKnownDevices()
            var allInputs: [AudioDevice] = connectedInputs
            for stored in knownDevices where stored.isInput {
                let roleIdentifier = "\(AudioDeviceType.input.rawValue):\(stored.uid)"
                if !connectedDeviceRoleIdentifiers.contains(roleIdentifier) {
                    allInputs.append(.disconnected(uid: stored.uid, name: stored.name, type: .input))
                }
            }
            var allOutputs: [AudioDevice] = connectedOutputs
            for stored in knownDevices where !stored.isInput {
                let roleIdentifier = "\(AudioDeviceType.output.rawValue):\(stored.uid)"
                if !connectedDeviceRoleIdentifiers.contains(roleIdentifier) {
                    allOutputs.append(.disconnected(uid: stored.uid, name: stored.name, type: .output))
                }
            }
            appendCanonicalPlaceholders(to: &allInputs, type: .input)
            appendCanonicalPlaceholders(to: &allOutputs, type: .output)
            inputDevices = priorityManager.sortByPriority(allInputs, type: .input)
            outputDevices = priorityManager.sortByPriority(allOutputs, type: .output)
        } else {
            // Auto-use eligibility is separate from visibility; only ignored devices are hidden here.
            let visibleInputs = connectedInputs.filter { !priorityManager.isHidden($0) }
            inputDevices = priorityManager.sortByPriority(visibleInputs, type: .input)

            let visibleOutputs = connectedOutputs.filter { !priorityManager.isHidden($0) }
            outputDevices = priorityManager.sortByPriority(visibleOutputs, type: .output)
        }
        currentInputId = deviceService.getCurrentDefaultDevice(type: .input)
        currentOutputId = deviceService.getCurrentDefaultDevice(type: .output)
    }

    func toggleEditMode() {
        isEditMode.toggle()
        refreshDevices()
    }

    func isDeviceConnected(_ device: AudioDevice) -> Bool {
        connectedDeviceRoleIdentifiers.contains(device.roleIdentifier)
    }

    func setOutputAutoSwitchEnabled(_ enabled: Bool) {
        isOutputAutoSwitchEnabled = enabled
        priorityManager.isOutputAutoSwitchEnabled = enabled
        if isOutputAutomationActive {
            applyHighestPriorityOutput()
        }
    }

    func setInputAutoSwitchEnabled(_ enabled: Bool) {
        isInputAutoSwitchEnabled = enabled
        priorityManager.isInputAutoSwitchEnabled = enabled
        if isInputAutomationActive {
            applyHighestPriorityInput()
        }
    }

    func setAutomationPaused(_ paused: Bool) {
        isAutomationPaused = paused
        priorityManager.isGlobalAutoSwitchPaused = paused

        guard !paused else { return }
        if isOutputAutoSwitchEnabled {
            applyHighestPriorityOutput()
        }
        if isInputAutoSwitchEnabled {
            applyHighestPriorityInput()
        }
    }

    func hideDevice(_ device: AudioDevice) {
        priorityManager.hideDevice(device)
        refreshDevices()
        if device.type == .input, isInputAutomationActive {
            applyHighestPriorityInput()
        } else if device.type == .output, isOutputAutomationActive {
            applyHighestPriorityOutput()
        }
    }

    func unhideDevice(_ device: AudioDevice) {
        priorityManager.unhideDevice(device)
        refreshDevices()
        if device.type == .input, isInputAutomationActive {
            applyHighestPriorityInput()
        } else if device.type == .output, isOutputAutomationActive {
            applyHighestPriorityOutput()
        }
    }

    func isDeviceIgnored(_ device: AudioDevice) -> Bool {
        priorityManager.isHidden(device)
    }

    func isAutoUseDisabled(_ device: AudioDevice) -> Bool {
        priorityManager.isAutoUseDisabled(device)
    }

    func setAutoUseDisabled(_ device: AudioDevice, disabled: Bool) {
        priorityManager.setAutoUseDisabled(device, disabled: disabled)
        refreshDevices()
        if !device.isConnected {
            return
        }
        if device.type == .input, isInputAutomationActive {
            applyHighestPriorityInput()
        } else if device.type == .output, isOutputAutomationActive {
            applyHighestPriorityOutput()
        }
    }

    func moveInputDevice(from source: IndexSet, to destination: Int) {
        inputDevices.move(fromOffsets: source, toOffset: destination)
        if isEditMode {
            guard priorityManager.reorderCanonical(inputDevices, type: .input) else {
                refreshDevices()
                return
            }
        } else {
            priorityManager.mergeVisibleOrder(inputDevices, type: .input)
        }
        if isInputAutomationActive {
            applyHighestPriorityInput()
        }
    }

    func moveOutputDevice(from source: IndexSet, to destination: Int) {
        outputDevices.move(fromOffsets: source, toOffset: destination)
        if isEditMode {
            guard priorityManager.reorderCanonical(outputDevices, type: .output) else {
                refreshDevices()
                return
            }
        } else {
            priorityManager.mergeVisibleOrder(outputDevices, type: .output)
        }
        if isOutputAutomationActive {
            applyHighestPriorityOutput()
        }
    }

    func promoteInputDevice(_ device: AudioDevice) {
        priorityManager.promote(device, visibleDevices: inputDevices)
        refreshDevices()
        applyInputDevice(
            device,
            preserveManualSelection: !priorityManager.isEligibleForAutoUse(device)
        )
    }

    func promoteOutputDevice(_ device: AudioDevice) {
        priorityManager.promote(device, visibleDevices: outputDevices)
        refreshDevices()
        applyOutputDevice(
            device,
            preserveManualSelection: !priorityManager.isEligibleForAutoUse(device)
        )
    }

    func forgetDevice(_ device: AudioDevice) {
        priorityManager.forgetDevice(device.uid, type: device.type)
        refreshDevices()
        if device.type == .input, isInputAutomationActive {
            applyHighestPriorityInput()
        } else if device.type == .output, isOutputAutomationActive {
            applyHighestPriorityOutput()
        }
    }

    func setInputDevice(_ device: AudioDevice) {
        applyInputDevice(device)
    }

    func setOutputDevice(_ device: AudioDevice) {
        applyOutputDevice(device)
    }

    private func applyInputDevice(
        _ device: AudioDevice,
        preserveManualSelection: Bool = false
    ) {
        guard device.isConnected else {
            defaultDeviceChangeTracker.clearManualSelection(type: .input)
            return
        }
        if preserveManualSelection {
            defaultDeviceChangeTracker.preserveManualSelection(device.id, type: .input)
        } else {
            defaultDeviceChangeTracker.clearManualSelection(type: .input)
        }
        guard currentInputId != device.id else { return }
        if deviceService.setDefaultDevice(device.id, type: .input) {
            currentInputId = device.id
        } else {
            defaultDeviceChangeTracker.clearManualSelection(type: .input)
            currentInputId = deviceService.getCurrentDefaultDevice(type: .input)
        }
    }

    private func applyOutputDevice(
        _ device: AudioDevice,
        preserveManualSelection: Bool = false
    ) {
        guard device.isConnected else {
            defaultDeviceChangeTracker.clearManualSelection(type: .output)
            return
        }
        if preserveManualSelection {
            defaultDeviceChangeTracker.preserveManualSelection(device.id, type: .output)
        } else {
            defaultDeviceChangeTracker.clearManualSelection(type: .output)
        }
        guard currentOutputId != device.id else { return }
        if deviceService.setDefaultDevice(device.id, type: .output) {
            currentOutputId = device.id
        } else {
            defaultDeviceChangeTracker.clearManualSelection(type: .output)
            currentOutputId = deviceService.getCurrentDefaultDevice(type: .output)
        }
    }

    private func applyHighestPriorityInput() {
        guard isInputAutomationActive,
              priorityManager.hasPriorities(type: .input) else { return }

        let sortedConnectedInputs = priorityManager.sortByPriority(connectedInputDevices, type: .input)
        if let first = sortedConnectedInputs.first(where: priorityManager.isEligibleForAutoUse) {
            applyInputDevice(first)
        }
    }

    private func applyHighestPriorityOutput() {
        guard isOutputAutomationActive,
              priorityManager.hasPriorities(type: .output) else { return }

        let sortedConnectedOutputs = priorityManager.sortByPriority(connectedOutputDevices, type: .output)
        if let first = sortedConnectedOutputs.first(where: priorityManager.isEligibleForAutoUse) {
            applyOutputDevice(first)
        }
        refreshMuteStatus()
    }

    private func setupDeviceChangeListener() {
        deviceService.onDevicesChanged = { [weak self] in
            Task { @MainActor in
                self?.handleDeviceChange()
            }
        }
        deviceService.onDefaultDeviceChanged = { [weak self] type in
            Task { @MainActor in
                self?.handleDefaultDeviceChange(type: type)
            }
        }
        deviceService.startListening()
    }

    private func handleDefaultDeviceChange(type: AudioDeviceType) {
        let currentDeviceId = deviceService.getCurrentDefaultDevice(type: type)
        let preservesManualSelection = defaultDeviceChangeTracker.shouldPreserveManualSelection(
            currentDeviceId: currentDeviceId,
            type: type
        )

        switch type {
        case .input:
            currentInputId = currentDeviceId
        case .output:
            currentOutputId = currentDeviceId
            refreshVolume()
        }
        refreshMuteStatus()

        guard !preservesManualSelection else { return }
        if type == .input, isInputAutomationActive {
            applyHighestPriorityInput()
        } else if type == .output, isOutputAutomationActive {
            applyHighestPriorityOutput()
        }
    }

    private func handleDeviceChange() {
        defaultDeviceChangeTracker.clearAllManualSelections()
        refreshDevices()
        refreshMuteStatus()

        if isInputAutomationActive {
            applyHighestPriorityInput()
        }

        if isOutputAutomationActive {
            applyHighestPriorityOutput()
        }
    }

    private func appendCanonicalPlaceholders(
        to devices: inout [AudioDevice],
        type: AudioDeviceType
    ) {
        var existingUIDs = Set(devices.map(\.uid))
        for uid in priorityManager.priorityUIDs(type: type) where !existingUIDs.contains(uid) {
            let suffix = uid.count > 8 ? String(uid.suffix(8)) : uid
            devices.append(
                .disconnected(
                    uid: uid,
                    name: "Unknown Device (\(suffix))",
                    type: type
                )
            )
            existingUIDs.insert(uid)
        }
    }
}
