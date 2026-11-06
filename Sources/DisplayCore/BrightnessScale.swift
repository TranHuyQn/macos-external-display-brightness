import Foundation

public enum Direction: Sendable, Equatable {
    case up
    case down
}

public struct BrightnessScale: Sendable {
    public static let steps = 16
    public let max: Int

    public init?(max: Int) {
        guard max > 0 else { return nil }
        self.max = max
    }

    /// Returns the step level (0...16) for a given raw brightness value.
    public func level(forValue value: Int) -> Int {
        let clamped = Swift.max(0, Swift.min(max, value))
        let fraction = Double(clamped) / Double(max)
        let lvl = Int((fraction * Double(Self.steps)).rounded())
        return Swift.max(0, Swift.min(Self.steps, lvl))
    }

    /// Returns the raw brightness value (0...max) for a given step level (0...16).
    public func value(forLevel level: Int) -> Int {
        let clampedLevel = Swift.max(0, Swift.min(Self.steps, level))
        let fraction = Double(clampedLevel) / Double(Self.steps)
        let val = Int((fraction * Double(max)).rounded())
        return Swift.max(0, Swift.min(max, val))
    }

    /// Steps up or down by 1 level from the current value, clamped to 0...max.
    public func stepped(from value: Int, direction: Direction) -> Int {
        let currentLvl = level(forValue: value)
        let targetLvl: Int
        switch direction {
        case .up:
            if self.value(forLevel: currentLvl) > value {
                targetLvl = currentLvl
            } else {
                targetLvl = currentLvl + 1
            }
        case .down:
            if self.value(forLevel: currentLvl) < value {
                targetLvl = currentLvl
            } else {
                targetLvl = currentLvl - 1
            }
        }
        return self.value(forLevel: targetLvl)
    }
}
