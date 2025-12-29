import SwiftUI
import CoreAudio

@MainActor
class AudioManager: ObservableObject {
    // MARK: - Published State

    @Published var inputDevices: [AudioDevice] = []
    @Published var speakerDevices: [AudioDevice] = []
    @Published var headphoneDevices: [AudioDevice] = []
    @Published var hiddenInputDevices: [AudioDevice] = []
    @Published var hiddenSpeakerDevices: [AudioDevice] = []
    @Published var hiddenHeadphoneDevices: [AudioDevice] = []
    @Published var currentInputId: AudioObjectID?
    @Published var currentOutputId: AudioObjectID?
    @Published var currentMode: OutputCategory = .speaker
    @Published var volume: Float = 0
    @Published var isEditMode: Bool = false
    @Published var isCustomMode: Bool = false
    @Published var mutedDeviceIds: Set<AudioObjectID> = []
    @Published var micFlashState: Bool = false

    // MARK: - Dependencies

    private let deviceService = AudioDeviceService()
    let priorityManager = PriorityManager()

    // MARK: - Private State

    private var micFlashTimer: Timer?
    private var connectedDeviceUIDs: Set<String> = []

    // MARK: - Computed Properties

    var menuBarIcon: String {
        currentMode.icon
    }

    var activeOutputDevices: [AudioDevice] {
        switch currentMode {
        case .speaker: return speakerDevices
        case .headphone: return headphoneDevices
        }
    }

    var allHiddenDevices: [AudioDevice] {
        hiddenInputDevices + hiddenSpeakerDevices + hiddenHeadphoneDevices
    }

    /// Whether the currently active output device is muted (derived from mutedDeviceIds)
    var isActiveOutputMuted: Bool {
        guard let outputId = currentOutputId else { return false }
        return mutedDeviceIds.contains(outputId)
    }

    /// Whether the currently active input device is muted (derived from mutedDeviceIds)
    var isActiveInputMuted: Bool {
        guard let inputId = currentInputId else { return false }
        return mutedDeviceIds.contains(inputId)
    }

    // MARK: - Initialization

    init() {
        currentMode = priorityManager.currentMode
        isCustomMode = priorityManager.isCustomMode
        refreshDevices()
        refreshVolume()
        refreshMuteStatus()
        setupDeviceChangeListener()
        setupMuteVolumeListener()

        // Apply priority on startup (unless in custom mode)
        if !isCustomMode {
            applyHighestPriorityInput()
            applyHighestPriorityOutput()
        }
    }

    // MARK: - Volume Control

    func refreshVolume() {
        volume = deviceService.getOutputVolume()
    }

    func setVolume(_ newVolume: Float) {
        volume = newVolume
        deviceService.setOutputVolume(newVolume)
    }

    // MARK: - Mute Status

    func refreshMuteStatus() {
        var muted: Set<AudioObjectID> = []

        for device in inputDevices where device.isConnected {
            if deviceService.isDeviceMuted(device.id, type: .input) {
                muted.insert(device.id)
            }
        }

        for device in speakerDevices where device.isConnected {
            if deviceService.isDeviceMuted(device.id, type: .output) {
                muted.insert(device.id)
            }
        }

        for device in headphoneDevices where device.isConnected {
            if deviceService.isDeviceMuted(device.id, type: .output) {
                muted.insert(device.id)
            }
        }

        mutedDeviceIds = muted
        updateMicFlashTimer()
    }

    func isDeviceMuted(_ device: AudioDevice) -> Bool {
        mutedDeviceIds.contains(device.id)
    }

    private func updateMicFlashTimer() {
        // Start/stop mic flash timer based on mute state
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

    // MARK: - Device Refresh

    func refreshDevices() {
        let allConnectedDevices = deviceService.getDevices()

        // Remember all connected devices
        connectedDeviceUIDs = Set(allConnectedDevices.map { $0.uid })
        for device in allConnectedDevices {
            priorityManager.rememberDevice(device.uid, name: device.name, isInput: device.type == .input)
        }

        let connectedInputs = allConnectedDevices.filter { $0.type == .input }
        let connectedOutputs = allConnectedDevices.filter { $0.type == .output }

        if isEditMode {
            refreshDevicesForEditMode(connectedInputs: connectedInputs, connectedOutputs: connectedOutputs)
        } else {
            refreshDevicesForNormalMode(connectedInputs: connectedInputs, connectedOutputs: connectedOutputs)
        }

        currentInputId = deviceService.getCurrentDefaultDevice(type: .input)
        currentOutputId = deviceService.getCurrentDefaultDevice(type: .output)
    }

    private func refreshDevicesForEditMode(connectedInputs: [AudioDevice], connectedOutputs: [AudioDevice]) {
        let knownDevices = priorityManager.getKnownDevices()

        // Build full input list including disconnected
        var allInputs: [AudioDevice] = connectedInputs
        for stored in knownDevices where stored.isInput {
            if !connectedDeviceUIDs.contains(stored.uid) {
                allInputs.append(.disconnected(uid: stored.uid, name: stored.name, type: .input))
            }
        }

        // Build full output list including disconnected
        var allOutputs: [AudioDevice] = connectedOutputs
        for stored in knownDevices where !stored.isInput {
            if !connectedDeviceUIDs.contains(stored.uid) {
                allOutputs.append(.disconnected(uid: stored.uid, name: stored.name, type: .output))
            }
        }

        // In edit mode, show everything (including ignored) in main lists
        inputDevices = priorityManager.sortByPriority(allInputs, type: .input)
        hiddenInputDevices = []

        let speakers = allOutputs.filter { priorityManager.getCategory(for: $0) == .speaker }
        let headphones = allOutputs.filter { priorityManager.getCategory(for: $0) == .headphone }

        speakerDevices = priorityManager.sortByPriority(speakers, category: .speaker)
        headphoneDevices = priorityManager.sortByPriority(headphones, category: .headphone)
        hiddenSpeakerDevices = []
        hiddenHeadphoneDevices = []
    }

    private func refreshDevicesForNormalMode(connectedInputs: [AudioDevice], connectedOutputs: [AudioDevice]) {
        // Normal mode: only show connected, non-ignored devices
        let visibleInputs = connectedInputs.filter { !priorityManager.isHidden($0) }
        let hiddenInputs = connectedInputs.filter { priorityManager.isHidden($0) }

        inputDevices = priorityManager.sortByPriority(visibleInputs, type: .input)
        hiddenInputDevices = hiddenInputs

        let speakers = connectedOutputs.filter { priorityManager.getCategory(for: $0) == .speaker }
        let headphones = connectedOutputs.filter { priorityManager.getCategory(for: $0) == .headphone }

        // Use category-specific ignore checks
        let visibleSpeakers = speakers.filter { !priorityManager.isHidden($0, inCategory: .speaker) }
        let hiddenSpeakers = speakers.filter { priorityManager.isHidden($0, inCategory: .speaker) }
        let visibleHeadphones = headphones.filter { !priorityManager.isHidden($0, inCategory: .headphone) }
        let hiddenHeadphones = headphones.filter { priorityManager.isHidden($0, inCategory: .headphone) }

        speakerDevices = priorityManager.sortByPriority(visibleSpeakers, category: .speaker)
        headphoneDevices = priorityManager.sortByPriority(visibleHeadphones, category: .headphone)
        hiddenSpeakerDevices = hiddenSpeakers
        hiddenHeadphoneDevices = hiddenHeadphones
    }

    // MARK: - Edit Mode

    func toggleEditMode() {
        isEditMode.toggle()
        refreshDevices()
    }

    func isDeviceConnected(_ device: AudioDevice) -> Bool {
        connectedDeviceUIDs.contains(device.uid)
    }

    // MARK: - Mode Management

    func setMode(_ mode: OutputCategory) {
        currentMode = mode
        priorityManager.currentMode = mode
        if !isCustomMode {
            applyHighestPriorityOutput()
        }
    }

    func toggleMode() {
        let newMode: OutputCategory = currentMode == .speaker ? .headphone : .speaker
        setMode(newMode)
    }

    func setCustomMode(_ enabled: Bool) {
        isCustomMode = enabled
        priorityManager.isCustomMode = enabled
        if !enabled {
            // Exiting custom mode - apply highest priority
            applyHighestPriorityInput()
            applyHighestPriorityOutput()
        }
    }

    // MARK: - Device Category

    func setCategory(_ category: OutputCategory, for device: AudioDevice) {
        priorityManager.setCategory(category, for: device)
        refreshDevices()
        if !isCustomMode {
            applyHighestPriorityOutput()
        }
    }

    // MARK: - Hide/Unhide Devices

    func hideDevice(_ device: AudioDevice, category: OutputCategory? = nil) {
        if device.type == .input {
            priorityManager.hideDevice(device)
        } else if let cat = category {
            priorityManager.hideDevice(device, inCategory: cat)
        } else {
            priorityManager.hideDevice(device)
        }
        refreshDevices()
        if !isCustomMode {
            if device.type == .input {
                applyHighestPriorityInput()
            } else {
                applyHighestPriorityOutput()
            }
        }
    }

    func hideDeviceEntirely(_ device: AudioDevice) {
        priorityManager.hideDevice(device, inCategory: .speaker)
        priorityManager.hideDevice(device, inCategory: .headphone)
        refreshDevices()
        if !isCustomMode {
            applyHighestPriorityOutput()
        }
    }

    func unhideDevice(_ device: AudioDevice, category: OutputCategory? = nil) {
        if device.type == .input {
            priorityManager.unhideDevice(device)
        } else if let cat = category {
            priorityManager.unhideDevice(device, fromCategory: cat)
        } else {
            priorityManager.unhideDevice(device)
        }
        refreshDevices()
    }

    func isDeviceIgnored(_ device: AudioDevice, inCategory category: OutputCategory? = nil) -> Bool {
        if device.type == .input {
            return priorityManager.isHidden(device)
        } else if let cat = category {
            return priorityManager.isHidden(device, inCategory: cat)
        } else {
            return priorityManager.isHidden(device)
        }
    }

    // MARK: - Device Reordering

    func moveInputDevice(from source: IndexSet, to destination: Int) {
        inputDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(inputDevices, type: .input)
        if !isCustomMode {
            applyHighestPriorityInput()
        }
    }

    func moveSpeakerDevice(from source: IndexSet, to destination: Int) {
        speakerDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(speakerDevices, category: .speaker)
        if !isCustomMode && currentMode == .speaker {
            applyHighestPriorityOutput()
        }
    }

    func moveHeadphoneDevice(from source: IndexSet, to destination: Int) {
        headphoneDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(headphoneDevices, category: .headphone)
        if !isCustomMode && currentMode == .headphone {
            applyHighestPriorityOutput()
        }
    }

    // MARK: - Device Selection

    func setInputDevice(_ device: AudioDevice) {
        applyInputDevice(device)
    }

    func setOutputDevice(_ device: AudioDevice) {
        applyOutputDevice(device)
    }

    // MARK: - Private Helpers

    private func applyInputDevice(_ device: AudioDevice) {
        deviceService.setDefaultDevice(device.id, type: .input)
        currentInputId = device.id
    }

    private func applyOutputDevice(_ device: AudioDevice) {
        deviceService.setDefaultDevice(device.id, type: .output)
        currentOutputId = device.id
    }

    private func applyHighestPriorityInput() {
        if let first = inputDevices.first(where: { $0.isConnected }) {
            applyInputDevice(first)
        }
    }

    private func applyHighestPriorityOutput() {
        let devices = activeOutputDevices
        if let first = devices.first(where: { $0.isConnected }) {
            applyOutputDevice(first)
        }
        refreshMuteStatus()
    }

    // MARK: - Event Listeners

    private func setupDeviceChangeListener() {
        deviceService.onDevicesChanged = { [weak self] in
            Task { @MainActor in
                self?.handleDeviceChange()
            }
        }
        deviceService.startListening()
    }

    private func setupMuteVolumeListener() {
        deviceService.onMuteOrVolumeChanged = { [weak self] in
            Task { @MainActor in
                self?.handleMuteOrVolumeChange()
            }
        }
    }

    private func handleDeviceChange() {
        refreshDevices()
        refreshMuteStatus()
        if !isCustomMode {
            applyHighestPriorityInput()
            applyHighestPriorityOutput()
        }
    }

    private func handleMuteOrVolumeChange() {
        refreshMuteStatus()
        refreshVolume()
    }
}
