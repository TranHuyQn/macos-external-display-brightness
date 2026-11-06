import Foundation

public final class Settings: @unchecked Sendable {
    private let defaults: UserDefaults
    private let showIconKey = "showIcon"
    private let lastValueKey = "lastValue"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var showIcon: Bool {
        get {
            if defaults.object(forKey: showIconKey) == nil {
                return true
            }
            return defaults.bool(forKey: showIconKey)
        }
        set {
            defaults.set(newValue, forKey: showIconKey)
        }
    }

    public var lastValue: Int? {
        get {
            if defaults.object(forKey: lastValueKey) == nil {
                return nil
            }
            return defaults.integer(forKey: lastValueKey)
        }
        set {
            if let val = newValue {
                defaults.set(val, forKey: lastValueKey)
            } else {
                defaults.removeObject(forKey: lastValueKey)
            }
        }
    }
}
