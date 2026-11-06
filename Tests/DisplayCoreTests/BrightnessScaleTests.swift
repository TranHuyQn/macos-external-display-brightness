import Testing
@testable import DisplayCore

struct BrightnessScaleTests {
    @Test func scaleInitialization() {
        #expect(BrightnessScale(max: 0) == nil)
        #expect(BrightnessScale(max: -5) == nil)
        #expect(BrightnessScale(max: 100) != nil)
    }

    @Test func levelsAndValues() {
        guard let scale100 = BrightnessScale(max: 100) else {
            Issue.record("Failed to create scale with max 100")
            return
        }

        #expect(scale100.level(forValue: 50) == 8)
        #expect(scale100.value(forLevel: 9) == 56)

        guard let scale255 = BrightnessScale(max: 255) else {
            Issue.record("Failed to create scale with max 255")
            return
        }
        #expect(scale255.value(forLevel: 16) == 255)
    }

    @Test func stepping() {
        guard let scale = BrightnessScale(max: 100) else {
            Issue.record("Failed to create scale with max 100")
            return
        }

        #expect(scale.stepped(from: 100, direction: .up) == 100)
        #expect(scale.stepped(from: 0, direction: .down) == 0)
        #expect(scale.stepped(from: 50, direction: .up) == 56)
    }
}
