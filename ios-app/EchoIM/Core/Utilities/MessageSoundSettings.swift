import Foundation

enum MessageSoundSettings {
    static let userDefaultsKey = "messageSoundEnabled"
    static let defaultIsEnabled = true

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: userDefaultsKey) != nil else {
            return defaultIsEnabled
        }
        return defaults.bool(forKey: userDefaultsKey)
    }

    static func setEnabled(_ isEnabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: userDefaultsKey)
    }
}
