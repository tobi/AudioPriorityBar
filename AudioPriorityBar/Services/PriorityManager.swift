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
        return .speaker // Default to speaker
    }

    func setCategory(_ category: OutputCategory, for device: AudioDevice) {
        var categories = defaults.dictionary(forKey: deviceCategoriesKey) as? [String: String] ?? [:]
        categories[device.uid] = category.rawValue
        defaults.set(categories, forKey: deviceCategoriesKey)
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
