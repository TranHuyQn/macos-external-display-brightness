import Foundation
import CoreGraphics

public struct ScreenInfo: Sendable, Equatable {
    public let id: UInt32
    public let frame: CGRect
    public let isBuiltIn: Bool

    public init(id: UInt32, frame: CGRect, isBuiltIn: Bool) {
        self.id = id
        self.frame = frame
        self.isBuiltIn = isBuiltIn
    }
}

public enum DisplayTarget: Equatable, Sendable {
    case builtIn
    case external(UInt32)
    case none
}

public func resolveTarget(mouse: CGPoint, screens: [ScreenInfo]) -> DisplayTarget {
    for screen in screens {
        if screen.frame.contains(mouse) {
            return screen.isBuiltIn ? .builtIn : .external(screen.id)
        }
    }
    return .none
}
