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
    private let inputPrioritiesConfiguredKey = "inputPrioritiesConfigured"
    private let outputPrioritiesConfiguredKey = "outputPrioritiesConfigured"
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
        initializePriorityConfigurationIfNeeded(type: .input)
        initializePriorityConfigurationIfNeeded(type: .output)
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
            removeRoleState(uid: uid, type: type)
        } else {
            known.removeAll { $0.uid == uid }
            removeRoleState(uid: uid, type: .input)
            removeRoleState(uid: uid, type: .output)
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
        let list = storedStringList(forKey: autoUseDisabledKey(for: device.type))
        return list.contains(device.uid)
    }

    func isEligibleForAutoUse(_ device: AudioDevice) -> Bool {
        device.isConnected && !isHidden(device) && !isAutoUseDisabled(device)
    }

    func setAutoUseDisabled(_ device: AudioDevice, disabled: Bool) {
        let key = autoUseDisabledKey(for: device.type)
        var list = storedStringList(forKey: key)
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

        let legacyList = storedStringList(forKey: legacyNeverUseKey)
        if !legacyList.isEmpty {
            appendUnique(legacyList, to: inputAutoUseDisabledKey)
            appendUnique(legacyList, to: outputAutoUseDisabledKey)
        }

        defaults.set(true, forKey: roleSpecificAutoUseMigrationKey)
    }

    private func appendUnique(_ uids: [String], to key: String) {
        var list = storedStringList(forKey: key)
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
        let hidden = storedStringList(forKey: key)
        return hidden.contains(device.uid)
    }

    func hideDevice(_ device: AudioDevice) {
        let key = hiddenKey(for: device)
        var hidden = storedStringList(forKey: key)
        if !hidden.contains(device.uid) {
            hidden.append(device.uid)
            defaults.set(hidden, forKey: key)
        }
    }

    func unhideDevice(_ device: AudioDevice) {
        let key = hiddenKey(for: device)
        var hidden = storedStringList(forKey: key)
        hidden.removeAll { $0 == device.uid }
        defaults.set(hidden, forKey: key)
    }

    private func hiddenKey(for device: AudioDevice) -> String {
        device.type == .input ? hiddenMicsKey : hiddenOutputsKey
    }

    // MARK: - Priority Management

    func sortByPriority(_ devices: [AudioDevice], type: AudioDeviceType) -> [AudioDevice] {
        sortDevices(devices, type: type)
    }

    func priorityUIDs(type: AudioDeviceType) -> [String] {
        storedStringList(forKey: priorityKey(for: type))
    }

    func isPriorityConfigured(type: AudioDeviceType) -> Bool {
        let key = priorityConfiguredKey(for: type)
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return !priorityUIDs(type: type).isEmpty
    }

    func registerDiscoveredUIDs(_ uids: [String], type: AudioDeviceType) {
        guard isPriorityConfigured(type: type) else { return }

        var canonical = priorityUIDs(type: type)
        let existing = Set(canonical)
        let newUIDs = unique(uids)
            .filter { !existing.contains($0) }
            .sorted()
        guard !newUIDs.isEmpty else { return }

        canonical.append(contentsOf: newUIDs)
        saveCanonical(canonical, type: type)
    }

    func mergeVisibleOrder(_ devices: [AudioDevice], type: AudioDeviceType) {
        let orderedVisible = deviceUIDs(devices, type: type)
        guard !orderedVisible.isEmpty else { return }

        var canonical = priorityUIDs(type: type)
        let known = knownUIDs(type: type)

        if !isPriorityConfigured(type: type) {
            saveCanonical(unique(orderedVisible + known), type: type)
            setPriorityConfigured(true, type: type)
            return
        }

        canonical = unique(canonical + known + orderedVisible)
        let visibleSet = Set(orderedVisible)
        var visibleIterator = orderedVisible.makeIterator()
        let merged = canonical.map { uid in
            guard visibleSet.contains(uid) else { return uid }
            return visibleIterator.next() ?? uid
        }

        saveCanonical(merged, type: type)
    }

    func promote(_ device: AudioDevice, visibleDevices: [AudioDevice]) {
        let type = device.type
        let visible = deviceUIDs(visibleDevices, type: type)
        var canonical = priorityUIDs(type: type)

        if !isPriorityConfigured(type: type) {
            canonical = unique(visible + knownUIDs(type: type))
        } else {
            canonical = unique(canonical + visible + knownUIDs(type: type))
        }

        canonical.removeAll { $0 == device.uid }
        canonical.insert(device.uid, at: 0)
        saveCanonical(canonical, type: type)
        setPriorityConfigured(true, type: type)
    }

    @discardableResult
    func reorderCanonical(_ devices: [AudioDevice], type: AudioDeviceType) -> Bool {
        let ordered = deviceUIDs(devices, type: type)
        let expectedUniverse = Set(unique(priorityUIDs(type: type) + knownUIDs(type: type)))
        guard ordered.count == expectedUniverse.count,
              Set(ordered) == expectedUniverse else {
            return false
        }

        saveCanonical(ordered, type: type)
        setPriorityConfigured(true, type: type)
        return true
    }

    func hasPriorities(type: AudioDeviceType) -> Bool {
        !priorityUIDs(type: type).isEmpty
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

    private func priorityConfiguredKey(for type: AudioDeviceType) -> String {
        switch type {
        case .input:
            return inputPrioritiesConfiguredKey
        case .output:
            return outputPrioritiesConfiguredKey
        }
    }

    private func migrateUnifiedOutputPrioritiesIfNeeded() {
        guard defaults.object(forKey: outputPrioritiesKey) == nil else { return }

        let headphonePriorities = storedStringList(forKey: headphonePrioritiesKey)
        let speakerPriorities = storedStringList(forKey: speakerPrioritiesKey)
        let legacyMode = defaults.string(forKey: currentModeKey)
        let mergedPriorities = legacyMode == "headphone"
            ? headphonePriorities + speakerPriorities
            : speakerPriorities + headphonePriorities
        defaults.set(unique(mergedPriorities), forKey: outputPrioritiesKey)
    }

    private func migrateUnifiedHiddenOutputsIfNeeded() {
        guard defaults.object(forKey: hiddenOutputsKey) == nil else { return }

        let hiddenHeadphones = storedStringList(forKey: hiddenHeadphonesKey)
        let hiddenSpeakers = storedStringList(forKey: hiddenSpeakersKey)
        defaults.set(unique(hiddenHeadphones + hiddenSpeakers), forKey: hiddenOutputsKey)
    }

    private func unique(_ uids: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for uid in uids where !uid.isEmpty && !seen.contains(uid) {
            seen.insert(uid)
            result.append(uid)
        }
        return result
    }

    private func sortDevices(_ devices: [AudioDevice], type: AudioDeviceType) -> [AudioDevice] {
        let priorities = priorityUIDs(type: type)
        let priorityIndexes = Dictionary(uniqueKeysWithValues: priorities.enumerated().map { ($1, $0) })
        let knownIndexes = Dictionary(uniqueKeysWithValues: knownUIDs(type: type).enumerated().map { ($1, $0) })

        return devices.sorted { a, b in
            let priorityA = priorityIndexes[a.uid] ?? Int.max
            let priorityB = priorityIndexes[b.uid] ?? Int.max
            if priorityA != priorityB {
                return priorityA < priorityB
            }

            let knownA = knownIndexes[a.uid] ?? Int.max
            let knownB = knownIndexes[b.uid] ?? Int.max
            if knownA != knownB {
                return knownA < knownB
            }

            if a.uid != b.uid {
                return a.uid < b.uid
            }
            return a.id < b.id
        }
    }

    private func initializePriorityConfigurationIfNeeded(type: AudioDeviceType) {
        let configuredKey = priorityConfiguredKey(for: type)
        if defaults.object(forKey: configuredKey) == nil {
            guard !priorityUIDs(type: type).isEmpty else { return }
            defaults.set(true, forKey: configuredKey)
        }

        guard defaults.bool(forKey: configuredKey) else { return }
        let priorities = priorityUIDs(type: type)
        let completeCanonical = unique(priorities + knownUIDs(type: type))
        if completeCanonical != priorities {
            saveCanonical(completeCanonical, type: type)
        }
    }

    private func setPriorityConfigured(_ configured: Bool, type: AudioDeviceType) {
        defaults.set(configured, forKey: priorityConfiguredKey(for: type))
    }

    private func saveCanonical(_ uids: [String], type: AudioDeviceType) {
        defaults.set(unique(uids), forKey: priorityKey(for: type))
    }

    private func knownUIDs(type: AudioDeviceType) -> [String] {
        let isInput = type == .input
        return unique(getKnownDevices().filter { $0.isInput == isInput }.map(\.uid))
    }

    private func deviceUIDs(_ devices: [AudioDevice], type: AudioDeviceType) -> [String] {
        unique(devices.filter { $0.type == type }.map(\.uid))
    }

    private func storedStringList(forKey key: String) -> [String] {
        let values = defaults.array(forKey: key) ?? []
        return unique(values.compactMap { $0 as? String })
    }

    private func removeRoleState(uid: String, type: AudioDeviceType) {
        remove(uid: uid, fromListForKey: priorityKey(for: type))
        remove(uid: uid, fromListForKey: autoUseDisabledKey(for: type))
        let hiddenKey = type == .input ? hiddenMicsKey : hiddenOutputsKey
        remove(uid: uid, fromListForKey: hiddenKey)
    }

    private func remove(uid: String, fromListForKey key: String) {
        var list = storedStringList(forKey: key)
        list.removeAll { $0 == uid }
        defaults.set(list, forKey: key)
    }
}
