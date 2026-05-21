import Foundation
import Testing
@testable import EchoIM

@Suite("Message sound settings")
struct MessageSoundSettingsTests {
    @Test
    func defaultsToEnabledWhenUnset() {
        let defaultsName = "MessageSoundSettingsTests.defaults"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        #expect(MessageSoundSettings.isEnabled(defaults: defaults))
    }

    @Test
    func storesDisabledPreference() {
        let defaultsName = "MessageSoundSettingsTests.disabled"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        MessageSoundSettings.setEnabled(false, defaults: defaults)

        #expect(!MessageSoundSettings.isEnabled(defaults: defaults))
    }
}
