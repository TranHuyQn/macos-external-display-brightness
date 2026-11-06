import Foundation

public final class LatestWinsWriter<T: Sendable>: @unchecked Sendable {
    private let queue: DispatchQueue
    private let minInterval: TimeInterval
    private let writeAction: @Sendable (T) -> Void

    private let lock = NSLock()
    private var isWriting: Bool = false
    private var isScheduled: Bool = false
    private var pendingValue: T? = nil
    private var lastWriteTime: TimeInterval = 0

    public init(queue: DispatchQueue, minInterval: TimeInterval, write: @escaping @Sendable (T) -> Void) {
        self.queue = queue
        self.minInterval = minInterval
        self.writeAction = write
    }

    /// Submits a new value. If a write is in progress or minInterval has not elapsed,
    /// this replaces any pending value and schedules a one-shot execution.
    public func submit(_ value: T) {
        lock.lock()
        pendingValue = value
        scheduleNextIfNeededLocked()
        lock.unlock()
    }

    private func scheduleNextIfNeededLocked() {
        // If a write is currently executing or a next write is already scheduled,
        // the pending value will be picked up automatically.
        guard !isWriting && !isScheduled else { return }
        guard pendingValue != nil else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastWriteTime

        if elapsed >= minInterval {
            // Can execute immediately
            let valueToWrite = pendingValue!
            pendingValue = nil
            isWriting = true
            lastWriteTime = now

            queue.async { [weak self] in
                self?.performWrite(valueToWrite)
            }
        } else {
            // Must wait remaining time before writing
            let delay = minInterval - elapsed
            isScheduled = true

            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.handleScheduled()
            }
        }
    }

    private func performWrite(_ value: T) {
        writeAction(value)

        lock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        lastWriteTime = now
        isWriting = false

        if pendingValue != nil {
            // A new value arrived during write execution.
            // Schedule it after minInterval.
            isScheduled = true
            queue.asyncAfter(deadline: .now() + minInterval) { [weak self] in
                self?.handleScheduled()
            }
        }
        lock.unlock()
    }

    private func handleScheduled() {
        lock.lock()
        isScheduled = false
        guard let valueToWrite = pendingValue else {
            lock.unlock()
            return
        }

        pendingValue = nil
        isWriting = true
        lastWriteTime = ProcessInfo.processInfo.systemUptime
        lock.unlock()

        performWrite(valueToWrite)
    }
}
