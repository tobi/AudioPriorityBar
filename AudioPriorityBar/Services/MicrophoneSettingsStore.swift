import Foundation

final class MicrophoneSettingsStore {
    private static let key = "microphoneAutomation.v1"
    private let defaults: UserDefaults
    private(set) var settings: MicrophoneSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(MicrophoneSettings.self, from: data) {
            settings = saved.normalized()
        } else {
            settings = MicrophoneSettings()
        }
    }

    func save(_ settings: MicrophoneSettings) {
        let normalized = settings.normalized()
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: Self.key)
        self.settings = normalized
    }
}
