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
            MenuBarLabel()
                .environmentObject(audioManager)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var audioManager: AudioManager

    var volumeLevel: Int {
        if audioManager.volume <= 0 { return 0 }
        else if audioManager.volume < 0.33 { return 1 }
        else if audioManager.volume < 0.66 { return 2 }
        else { return 3 }
    }

    var iconName: String {
        if audioManager.isCustomMode {
            return "hand.raised.fill"
        } else if audioManager.currentMode == .headphone {
            return "headphones"
        } else {
            switch volumeLevel {
            case 0: return "speaker.fill"
            case 1: return "speaker.wave.1.fill"
            case 2: return "speaker.wave.2.fill"
            default: return "speaker.wave.3.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
            Text("\(Int(audioManager.volume * 100))")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }
}

@MainActor
class AudioManager: ObservableObject {
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
    @Published var isCustomMode: Bool = false  // Disables auto-switching

    private let deviceService = AudioDeviceService()
    let priorityManager = PriorityManager()
    private var connectedDeviceUIDs: Set<String> = []

    var menuBarIcon: String {
        currentMode.icon
    }

    func refreshVolume() {
        volume = deviceService.getOutputVolume()
    }

    func setVolume(_ newVolume: Float) {
        volume = newVolume
        deviceService.setOutputVolume(newVolume)
    }

    var activeOutputDevices: [AudioDevice] {
        switch currentMode {
        case .speaker: return speakerDevices
        case .headphone: return headphoneDevices
        }
    }

    init() {
        currentMode = priorityManager.currentMode
        isCustomMode = priorityManager.isCustomMode
        refreshDevices()
        refreshVolume()
        setupDeviceChangeListener()
        // Apply priority on startup (unless in custom mode)
        if !isCustomMode {
            applyHighestPriorityInput()
            applyHighestPriorityOutput()
        }
    }

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
            // In edit mode: show all known devices, mark disconnected ones
            let knownDevices = priorityManager.getKnownDevices()

            // Build full input list
            var allInputs: [AudioDevice] = connectedInputs
            for stored in knownDevices where stored.isInput {
                if !connectedDeviceUIDs.contains(stored.uid) {
                    allInputs.append(.disconnected(uid: stored.uid, name: stored.name, type: .input))
                }
            }

            // Build full output list
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
        } else {
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

        currentInputId = deviceService.getCurrentDefaultDevice(type: .input)
        currentOutputId = deviceService.getCurrentDefaultDevice(type: .output)
    }

    func toggleEditMode() {
        isEditMode.toggle()
        refreshDevices()
    }

    func isDeviceConnected(_ device: AudioDevice) -> Bool {
        connectedDeviceUIDs.contains(device.uid)
    }

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

    func setCategory(_ category: OutputCategory, for device: AudioDevice) {
        priorityManager.setCategory(category, for: device)
        refreshDevices()
        if !isCustomMode {
            applyHighestPriorityOutput()
        }
    }

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

    func setInputDevice(_ device: AudioDevice) {
        if isCustomMode {
            // Custom mode: just select the device directly
            applyInputDevice(device)
        } else {
            // Normal mode: move device to top of priority list
            moveDeviceToTop(device, in: &inputDevices)
            priorityManager.savePriorities(inputDevices, type: .input)
            applyHighestPriorityInput()
        }
    }

    func setOutputDevice(_ device: AudioDevice) {
        if isCustomMode {
            // Custom mode: just select the device directly
            applyOutputDevice(device)
        } else {
            // Normal mode: move device to top of priority list for current category
            let category = priorityManager.getCategory(for: device)
            if category == .speaker {
                moveDeviceToTop(device, in: &speakerDevices)
                priorityManager.savePriorities(speakerDevices, category: .speaker)
            } else {
                moveDeviceToTop(device, in: &headphoneDevices)
                priorityManager.savePriorities(headphoneDevices, category: .headphone)
            }
            applyHighestPriorityOutput()
        }
    }

    private func applyInputDevice(_ device: AudioDevice) {
        deviceService.setDefaultDevice(device.id, type: .input)
        currentInputId = device.id
    }

    private func applyOutputDevice(_ device: AudioDevice) {
        deviceService.setDefaultDevice(device.id, type: .output)
        currentOutputId = device.id
    }

    private func moveDeviceToTop(_ device: AudioDevice, in devices: inout [AudioDevice]) {
        if let index = devices.firstIndex(where: { $0.uid == device.uid }) {
            let removed = devices.remove(at: index)
            devices.insert(removed, at: 0)
        }
    }

    private func applyHighestPriorityInput() {
        if let highest = inputDevices.first {
            applyInputDevice(highest)
        }
    }

    private func applyHighestPriorityOutput() {
        let devices = activeOutputDevices
        if let highest = devices.first {
            applyOutputDevice(highest)
        }
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
        if !isCustomMode {
            applyHighestPriorityInput()
            applyHighestPriorityOutput()
        }
    }
}
