import Foundation

struct StoredDevice: Codable, Equatable {
    let uid: String
    let name: String
    let isInput: Bool
    var lastSeen: Date

    var lastSeenRelative: String {
        let now = Date()
        let interval = now.timeIntervalSince(lastSeen)

        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else if interval < 2592000 {
            let weeks = Int(interval / 604800)
            return "\(weeks)w ago"
        } else {
            let months = Int(interval / 2592000)
            return "\(months)mo ago"
        }
    }
}

class PriorityManager {
    private let defaults: UserDefaults

    private let inputPrioritiesKey = "inputPriorities"
    private let outputPrioritiesKey = "outputPriorities"
    private let speakerPrioritiesKey = "speakerPriorities"
    private let headphonePrioritiesKey = "headphonePriorities"
    private let currentModeKey = "currentMode"
    private let customModeKey = "customMode"
    private let outputAutoSwitchEnabledKey = "outputAutoSwitchEnabled"
    private let inputAutoSwitchEnabledKey = "inputAutoSwitchEnabled"
    private let globalAutoSwitchPausedKey = "globalAutoSwitchPaused"
    private let automationSettingsMigrationKey = "automationSettingsMigration_v1"
    private let knownDevicesKey = "knownDevices"
    private let legacyNeverUseKey = "neverUseDevices"
    private let inputAutoUseDisabledKey = "inputAutoUseDisabledDevices"
    private let outputAutoUseDisabledKey = "outputAutoUseDisabledDevices"
    private let roleSpecificAutoUseMigrationKey = "roleSpecificAutoUseMigration_v1"
    private let hiddenOutputsKey = "hiddenOutputs"
    private let hiddenMicsKey = "hiddenMics"
    private let hiddenSpeakersKey = "hiddenSpeakers"
    private let hiddenHeadphonesKey = "hiddenHeadphones"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let hadUnifiedOutputPriorities = defaults.object(forKey: outputPrioritiesKey) != nil

        migrateLegacyNeverUseDevicesIfNeeded()
        migrateAutomationSettingsIfNeeded(hadUnifiedOutputPriorities: hadUnifiedOutputPriorities)
        migrateUnifiedOutputPrioritiesIfNeeded()
        migrateUnifiedHiddenOutputsIfNeeded()
    }

    // MARK: - Known Devices (Persistent Memory)

    func getKnownDevices() -> [StoredDevice] {
        guard let data = defaults.data(forKey: knownDevicesKey),
              let devices = try? JSONDecoder().decode([StoredDevice].self, from: data) else {
            return []
        }
        return devices
    }

    func rememberDevice(_ uid: String, name: String, isInput: Bool) {
        var known = getKnownDevices()
        let now = Date()
        if let index = known.firstIndex(where: { $0.uid == uid && $0.isInput == isInput }) {
            // Update name and lastSeen
            known[index] = StoredDevice(uid: uid, name: name, isInput: isInput, lastSeen: now)
        } else {
            known.append(StoredDevice(uid: uid, name: name, isInput: isInput, lastSeen: now))
        }
        saveKnownDevices(known)
    }

    func getStoredDevice(for device: AudioDevice) -> StoredDevice? {
        let isInput = device.type == .input
        return getKnownDevices().first { $0.uid == device.uid && $0.isInput == isInput }
    }

    func forgetDevice(_ uid: String, type: AudioDeviceType? = nil) {
        var known = getKnownDevices()
        if let type {
            let isInput = type == .input
            known.removeAll { $0.uid == uid && $0.isInput == isInput }
        } else {
            known.removeAll { $0.uid == uid }
        }
        saveKnownDevices(known)
    }

    private func saveKnownDevices(_ devices: [StoredDevice]) {
        if let data = try? JSONEncoder().encode(devices) {
            defaults.set(data, forKey: knownDevicesKey)
        }
    }

    // MARK: - Automation Settings

    var isOutputAutoSwitchEnabled: Bool {
        get { storedBool(forKey: outputAutoSwitchEnabledKey, defaultValue: true) }
        set { defaults.set(newValue, forKey: outputAutoSwitchEnabledKey) }
    }

    var isInputAutoSwitchEnabled: Bool {
        get { storedBool(forKey: inputAutoSwitchEnabledKey, defaultValue: true) }
        set { defaults.set(newValue, forKey: inputAutoSwitchEnabledKey) }
    }

    var isGlobalAutoSwitchPaused: Bool {
        get { storedBool(forKey: globalAutoSwitchPausedKey, defaultValue: false) }
        set { defaults.set(newValue, forKey: globalAutoSwitchPausedKey) }
    }

    // MARK: - Auto-Use Eligibility

    func isAutoUseDisabled(_ device: AudioDevice) -> Bool {
        let list = defaults.array(forKey: autoUseDisabledKey(for: device.type)) as? [String] ?? []
        return list.contains(device.uid)
    }

    func isEligibleForAutoUse(_ device: AudioDevice) -> Bool {
        device.isConnected && !isHidden(device) && !isAutoUseDisabled(device)
    }

    func setAutoUseDisabled(_ device: AudioDevice, disabled: Bool) {
        let key = autoUseDisabledKey(for: device.type)
        var list = defaults.array(forKey: key) as? [String] ?? []
        if disabled {
            if !list.contains(device.uid) {
                list.append(device.uid)
            }
        } else {
            list.removeAll { $0 == device.uid }
        }
        defaults.set(list, forKey: key)
    }

    private func autoUseDisabledKey(for type: AudioDeviceType) -> String {
        switch type {
        case .input:
            return inputAutoUseDisabledKey
        case .output:
            return outputAutoUseDisabledKey
        }
    }

    private func migrateLegacyNeverUseDevicesIfNeeded() {
        guard !defaults.bool(forKey: roleSpecificAutoUseMigrationKey) else { return }

        let legacyList = defaults.array(forKey: legacyNeverUseKey) as? [String] ?? []
        if !legacyList.isEmpty {
            appendUnique(legacyList, to: inputAutoUseDisabledKey)
            appendUnique(legacyList, to: outputAutoUseDisabledKey)
        }

        defaults.set(true, forKey: roleSpecificAutoUseMigrationKey)
    }

    private func appendUnique(_ uids: [String], to key: String) {
        var list = defaults.array(forKey: key) as? [String] ?? []
        for uid in uids where !list.contains(uid) {
            list.append(uid)
        }
        defaults.set(list, forKey: key)
    }

    private func migrateAutomationSettingsIfNeeded(hadUnifiedOutputPriorities: Bool) {
        guard !defaults.bool(forKey: automationSettingsMigrationKey) else { return }

        var outputAutoSwitchEnabled = true
        let inputAutoSwitchEnabled = true
        var globalAutoSwitchPaused = false

        if defaults.bool(forKey: customModeKey) {
            if hadUnifiedOutputPriorities {
                // The local unified-output build used Custom Mode as an Output-only override.
                outputAutoSwitchEnabled = false
            } else {
                // Upstream used Custom Mode to pause both roles.
                globalAutoSwitchPaused = true
            }
        }

        setBoolIfMissing(outputAutoSwitchEnabled, forKey: outputAutoSwitchEnabledKey)
        setBoolIfMissing(inputAutoSwitchEnabled, forKey: inputAutoSwitchEnabledKey)
        setBoolIfMissing(globalAutoSwitchPaused, forKey: globalAutoSwitchPausedKey)
        defaults.set(true, forKey: automationSettingsMigrationKey)
    }

    private func storedBool(forKey key: String, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private func setBoolIfMissing(_ value: Bool, forKey key: String) {
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(value, forKey: key)
    }

    // MARK: - Hidden Devices (per role)

    func isHidden(_ device: AudioDevice) -> Bool {
        let key = hiddenKey(for: device)
        let hidden = defaults.array(forKey: key) as? [String] ?? []
        return hidden.contains(device.uid)
    }

    func hideDevice(_ device: AudioDevice) {
        let key = hiddenKey(for: device)
        var hidden = defaults.array(forKey: key) as? [String] ?? []
        if !hidden.contains(device.uid) {
            hidden.append(device.uid)
            defaults.set(hidden, forKey: key)
        }
    }

    func unhideDevice(_ device: AudioDevice) {
        let key = hiddenKey(for: device)
        var hidden = defaults.array(forKey: key) as? [String] ?? []
        hidden.removeAll { $0 == device.uid }
        defaults.set(hidden, forKey: key)
    }

    private func hiddenKey(for device: AudioDevice) -> String {
        device.type == .input ? hiddenMicsKey : hiddenOutputsKey
    }

    // MARK: - Priority Management

    func sortByPriority(_ devices: [AudioDevice], type: AudioDeviceType) -> [AudioDevice] {
        let key = priorityKey(for: type)
        return sortDevices(devices, usingKey: key)
    }

    func savePriorities(_ devices: [AudioDevice], type: AudioDeviceType) {
        let key = priorityKey(for: type)
        savePriorities(devices, key: key)
    }

    func hasPriorities(type: AudioDeviceType) -> Bool {
        let key = priorityKey(for: type)
        return !(defaults.array(forKey: key) as? [String] ?? []).isEmpty
    }

    // MARK: - Private Helpers

    private func priorityKey(for type: AudioDeviceType) -> String {
        switch type {
        case .input:
            return inputPrioritiesKey
        case .output:
            return outputPrioritiesKey
        }
    }

    private func migrateUnifiedOutputPrioritiesIfNeeded() {
        guard defaults.object(forKey: outputPrioritiesKey) == nil else { return }

        let headphonePriorities = defaults.array(forKey: headphonePrioritiesKey) as? [String] ?? []
        let speakerPriorities = defaults.array(forKey: speakerPrioritiesKey) as? [String] ?? []
        let legacyMode = defaults.string(forKey: currentModeKey)
        let mergedPriorities = legacyMode == "headphone"
            ? headphonePriorities + speakerPriorities
            : speakerPriorities + headphonePriorities
        defaults.set(unique(mergedPriorities), forKey: outputPrioritiesKey)
    }

    private func migrateUnifiedHiddenOutputsIfNeeded() {
        guard defaults.object(forKey: hiddenOutputsKey) == nil else { return }

        let hiddenHeadphones = defaults.array(forKey: hiddenHeadphonesKey) as? [String] ?? []
        let hiddenSpeakers = defaults.array(forKey: hiddenSpeakersKey) as? [String] ?? []
        defaults.set(unique(hiddenHeadphones + hiddenSpeakers), forKey: hiddenOutputsKey)
    }

    private func unique(_ uids: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for uid in uids where !seen.contains(uid) {
            seen.insert(uid)
            result.append(uid)
        }
        return result
    }

    private func sortDevices(_ devices: [AudioDevice], usingKey key: String) -> [AudioDevice] {
        let priorities = defaults.array(forKey: key) as? [String] ?? []

        return devices.sorted { a, b in
            let indexA = priorities.firstIndex(of: a.uid) ?? Int.max
            let indexB = priorities.firstIndex(of: b.uid) ?? Int.max
            return indexA < indexB
        }
    }

    private func savePriorities(_ devices: [AudioDevice], key: String) {
        let uids = devices.map { $0.uid }
        defaults.set(uids, forKey: key)
    }
}
