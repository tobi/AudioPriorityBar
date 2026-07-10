import SwiftUI
import CoreAudio

@main
struct AudioPriorityBarApp: App {
    @StateObject private var audioManager = AudioManager()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(audioManager)
        } label: {
            Image(systemName: audioManager.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let volume: Float
    let isOutputMuted: Bool
    let isInputMuted: Bool
    let isAutomationPaused: Bool
    let micFlash: Bool

    var body: some View {
        HStack(spacing: 2) {
            if isInputMuted {
                Image(systemName: micFlash ? "mic.fill" : "mic.slash.fill")
            }
            if isAutomationPaused {
                Image(systemName: "pause.circle.fill")
            }
            if isOutputMuted {
                Image(systemName: "speaker.slash.fill")
            } else {
                Image(systemName: "speaker.wave.3.fill", variableValue: Double(volume))
            }
        }
    }
}

struct VolumeMeterView: View {
    let volume: Float
    let isMuted: Bool
    private let barCount = 4
    private let barSpacing: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let barWidth = (size.width - CGFloat(barCount - 1) * barSpacing) / CGFloat(barCount)
            let filledBars = isMuted ? 0 : Int(ceil(Double(volume) * Double(barCount)))
            for i in 0..<barCount {
                let x = CGFloat(i) * (barWidth + barSpacing)
                let barHeight = size.height * CGFloat(i + 1) / CGFloat(barCount)
                let y = size.height - barHeight
                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = Path(roundedRect: rect, cornerRadius: 1)
                if i < filledBars {
                    context.fill(path, with: .color(isMuted ? .red : .primary))
                } else {
                    context.fill(path, with: .color(.primary.opacity(0.25)))
                }
            }
        }
    }
}

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
        priorityManager.savePriorities(inputDevices, type: .input)
        if isInputAutomationActive {
            applyHighestPriorityInput()
        }
    }

    func moveOutputDevice(from source: IndexSet, to destination: Int) {
        outputDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(outputDevices, type: .output)
        if isOutputAutomationActive {
            applyHighestPriorityOutput()
        }
    }

    func setInputDevice(_ device: AudioDevice) {
        applyInputDevice(device)
    }

    func setOutputDevice(_ device: AudioDevice) {
        applyOutputDevice(device)
    }

    private func applyInputDevice(_ device: AudioDevice) {
        deviceService.setDefaultDevice(device.id, type: .input)
        currentInputId = device.id
    }

    private func applyOutputDevice(_ device: AudioDevice) {
        deviceService.setDefaultDevice(device.id, type: .output)
        currentOutputId = device.id
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
        deviceService.startListening()
    }

    private func handleDeviceChange() {
        refreshDevices()
        refreshMuteStatus()

        if isInputAutomationActive {
            applyHighestPriorityInput()
        }

        if isOutputAutomationActive {
            applyHighestPriorityOutput()
        }
    }
}
