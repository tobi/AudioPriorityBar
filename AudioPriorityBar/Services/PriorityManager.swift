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
    private let defaults = UserDefaults.standard

    private let inputPrioritiesKey = "inputPriorities"
    private let speakerPrioritiesKey = "speakerPriorities"
    private let headphonePrioritiesKey = "headphonePriorities"
    private let deviceCategoriesKey = "deviceCategories"
    private let currentModeKey = "currentMode"
    private let customModeKey = "customMode"
    private let hiddenDevicesKey = "hiddenDevices"
    private let knownDevicesKey = "knownDevices"

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
        if let index = known.firstIndex(where: { $0.uid == uid }) {
            // Update name and lastSeen
            known[index] = StoredDevice(uid: uid, name: name, isInput: isInput, lastSeen: now)
        } else {
            known.append(StoredDevice(uid: uid, name: name, isInput: isInput, lastSeen: now))
        }
        saveKnownDevices(known)
    }

    func getStoredDevice(uid: String) -> StoredDevice? {
        getKnownDevices().first { $0.uid == uid }
    }

    func forgetDevice(_ uid: String) {
        var known = getKnownDevices()
        known.removeAll { $0.uid == uid }
        saveKnownDevices(known)
    }

    private func saveKnownDevices(_ devices: [StoredDevice]) {
        if let data = try? JSONEncoder().encode(devices) {
            defaults.set(data, forKey: knownDevicesKey)
        }
    }

    // MARK: - UID Migration
    //
    // Some devices (notably display speakers like the Apple Studio Display,
    // whose audio UID embeds the DisplayPort/USB connection path) come back
    // with a DIFFERENT UID after being unplugged or moved to another port.
    // All settings are keyed by UID, so without migration the device loses
    // its priority slot, category, and hidden/never-use flags on every replug.
    // When a "new" UID appears whose name matches a known device that is NOT
    // currently connected, transfer all settings from the old UID to the new.

    /// Migrates stored settings if `device` looks like a known device that came back with a new UID.
    func migrateDeviceUIDIfNeeded(for device: AudioDevice, connectedUIDs: Set<String>) {
        // Already known under this UID -> nothing to do
        guard getStoredDevice(uid: device.uid) == nil else { return }
        // Find a known device with the same name that is not currently connected
        guard let old = getKnownDevices().first(where: {
            $0.name == device.name && $0.uid != device.uid && !connectedUIDs.contains($0.uid)
        }) else { return }
        migrateUID(from: old.uid, to: device.uid)
    }

    private func migrateUID(from oldUID: String, to newUID: String) {
        // Priority lists
        for key in [inputPrioritiesKey, speakerPrioritiesKey, headphonePrioritiesKey] {
            if var list = defaults.array(forKey: key) as? [String], let idx = list.firstIndex(of: oldUID) {
                list[idx] = newUID
                defaults.set(list, forKey: key)
            }
        }
        // Category mapping
        if var categories = defaults.dictionary(forKey: deviceCategoriesKey) as? [String: String],
           let category = categories.removeValue(forKey: oldUID) {
            categories[newUID] = category
            defaults.set(categories, forKey: deviceCategoriesKey)
        }
        // Hidden / never-use flags
        for key in [neverUseKey, hiddenMicsKey, hiddenSpeakersKey, hiddenHeadphonesKey] {
            if var list = defaults.array(forKey: key) as? [String], let idx = list.firstIndex(of: oldUID) {
                list[idx] = newUID
                defaults.set(list, forKey: key)
            }
        }
        // Known devices: drop the stale entry (rememberDevice will add the new one)
        var known = getKnownDevices()
        known.removeAll { $0.uid == oldUID }
        saveKnownDevices(known)
    }

    // MARK: - Mode Management

    var currentMode: OutputCategory {
        get {
            guard let raw = defaults.string(forKey: currentModeKey),
                  let mode = OutputCategory(rawValue: raw) else {
                return .speaker
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: currentModeKey)
        }
    }

    var isCustomMode: Bool {
        get { defaults.bool(forKey: customModeKey) }
        set { defaults.set(newValue, forKey: customModeKey) }
    }

    // MARK: - Device Categories

    func getCategory(for device: AudioDevice) -> OutputCategory {
        let categories = defaults.dictionary(forKey: deviceCategoriesKey) as? [String: String] ?? [:]
        if let raw = categories[device.uid], let category = OutputCategory(rawValue: raw) {
            return category
        }
        // Default headphone-like devices to headphone category
        if HeadphoneDetection.isHeadphone(deviceName: device.name) {
            return .headphone
        }
        return .speaker
    }

    func setCategory(_ category: OutputCategory, for device: AudioDevice) {
        var categories = defaults.dictionary(forKey: deviceCategoriesKey) as? [String: String] ?? [:]
        categories[device.uid] = category.rawValue
        defaults.set(categories, forKey: deviceCategoriesKey)
    }

    // MARK: - Never Use Devices (never auto-selected)

    private let neverUseKey = "neverUseDevices"

    func isNeverUse(_ device: AudioDevice) -> Bool {
        let list = defaults.array(forKey: neverUseKey) as? [String] ?? []
        return list.contains(device.uid)
    }

    func setNeverUse(_ device: AudioDevice, neverUse: Bool) {
        var list = defaults.array(forKey: neverUseKey) as? [String] ?? []
        if neverUse {
            if !list.contains(device.uid) {
                list.append(device.uid)
            }
        } else {
            list.removeAll { $0 == device.uid }
        }
        defaults.set(list, forKey: neverUseKey)
    }

    // MARK: - Hidden Devices (per category)

    private let hiddenMicsKey = "hiddenMics"
    private let hiddenSpeakersKey = "hiddenSpeakers"
    private let hiddenHeadphonesKey = "hiddenHeadphones"

    func isHidden(_ device: AudioDevice) -> Bool {
        let key = hiddenKey(for: device)
        let hidden = defaults.array(forKey: key) as? [String] ?? []
        return hidden.contains(device.uid)
    }

    func isHidden(_ device: AudioDevice, inCategory category: OutputCategory) -> Bool {
        let key = category == .speaker ? hiddenSpeakersKey : hiddenHeadphonesKey
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

    func hideDevice(_ device: AudioDevice, inCategory category: OutputCategory) {
        let key = category == .speaker ? hiddenSpeakersKey : hiddenHeadphonesKey
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

    func unhideDevice(_ device: AudioDevice, fromCategory category: OutputCategory) {
        let key = category == .speaker ? hiddenSpeakersKey : hiddenHeadphonesKey
        var hidden = defaults.array(forKey: key) as? [String] ?? []
        hidden.removeAll { $0 == device.uid }
        defaults.set(hidden, forKey: key)
    }

    private func hiddenKey(for device: AudioDevice) -> String {
        if device.type == .input {
            return hiddenMicsKey
        } else {
            let category = getCategory(for: device)
            return category == .speaker ? hiddenSpeakersKey : hiddenHeadphonesKey
        }
    }

    // MARK: - Priority Management

    func sortByPriority(_ devices: [AudioDevice], type: AudioDeviceType) -> [AudioDevice] {
        let key = priorityKey(for: type, category: nil)
        return sortDevices(devices, usingKey: key)
    }

    func sortByPriority(_ devices: [AudioDevice], category: OutputCategory) -> [AudioDevice] {
        let key = priorityKey(for: .output, category: category)
        return sortDevices(devices, usingKey: key)
    }

    func savePriorities(_ devices: [AudioDevice], type: AudioDeviceType) {
        let key = priorityKey(for: type, category: nil)
        savePriorities(devices, key: key)
    }

    func savePriorities(_ devices: [AudioDevice], category: OutputCategory) {
        let key = priorityKey(for: .output, category: category)
        savePriorities(devices, key: key)
    }

    // MARK: - Private Helpers

    private func priorityKey(for type: AudioDeviceType, category: OutputCategory?) -> String {
        switch type {
        case .input:
            return inputPrioritiesKey
        case .output:
            switch category {
            case .speaker, .none:
                return speakerPrioritiesKey
            case .headphone:
                return headphonePrioritiesKey
            }
        }
    }

    private func sortDevices(_ devices: [AudioDevice], usingKey key: String) -> [AudioDevice] {
        let priorities = defaults.array(forKey: key) as? [String] ?? []

        // Fallback: map device NAME -> priority index via known devices, so a
        // device that reappeared with a new UID (e.g. Studio Display speakers
        // after a replug) still lands in its old slot even before migration.
        var nameIndex: [String: Int] = [:]
        let known = getKnownDevices()
        for (idx, uid) in priorities.enumerated() {
            if let stored = known.first(where: { $0.uid == uid }), nameIndex[stored.name] == nil {
                nameIndex[stored.name] = idx
            }
        }

        func priorityIndex(_ device: AudioDevice) -> Int {
            if let i = priorities.firstIndex(of: device.uid) { return i }
            if let i = nameIndex[device.name] { return i }
            return Int.max
        }

        // Stable sort: Swift's sorted(by:) is not guaranteed stable, so ties
        // (devices not in the priority list) would otherwise shuffle randomly.
        return devices.enumerated()
            .sorted { a, b in
                let ia = priorityIndex(a.element)
                let ib = priorityIndex(b.element)
                if ia != ib { return ia < ib }
                return a.offset < b.offset
            }
            .map { $0.element }
    }

    private func savePriorities(_ devices: [AudioDevice], key: String) {
        let newOrder = devices.map { $0.uid }
        let stored = defaults.array(forKey: key) as? [String] ?? []

        // Merge instead of overwrite: devices not currently visible (e.g. an
        // unplugged Studio Display) keep their slot in the stored list instead
        // of being wiped every time the user reorders the visible devices.
        let newSet = Set(newOrder)
        var remaining = newOrder[...]
        var merged: [String] = []
        for uid in stored {
            if newSet.contains(uid) {
                if let next = remaining.first {
                    merged.append(next)
                    remaining = remaining.dropFirst()
                }
            } else {
                merged.append(uid)
            }
        }
        merged.append(contentsOf: remaining)

        // De-dupe, preserving first occurrence
        var seen = Set<String>()
        merged = merged.filter { seen.insert($0).inserted }

        defaults.set(merged, forKey: key)
    }
}
