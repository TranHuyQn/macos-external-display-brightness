import Foundation

public enum DDCError: Error, Equatable, Sendable {
    case notFound
    case readFailed
    case writeFailed
    case invalidRange
}

public protocol DDCDevice: Sendable {
    func readBrightness() throws -> (current: Int, max: Int)
    func writeBrightness(_ value: Int) throws
}
