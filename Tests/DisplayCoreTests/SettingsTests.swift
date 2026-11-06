import Testing
import Foundation
@testable import DisplayCore

struct SettingsTests {
    @Test func defaultSettings() {
        let suite = "SettingsTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("Failed to create UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = Settings(defaults: defaults)
        #expect(settings.showIcon == true)
        #expect(settings.lastValue == nil)
    }

    @Test func persistenceAcrossInstances() {
        let suite = "SettingsTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("Failed to create UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings1 = Settings(defaults: defaults)
        settings1.showIcon = false
        settings1.lastValue = 40

        let settings2 = Settings(defaults: defaults)
        #expect(settings2.showIcon == false)
        #expect(settings2.lastValue == 40)
    }
}
