import Testing
import Foundation
@testable import DisplayCore

struct LatestWinsWriterTests {
    @Test func noSubmitNoWrite() {
        let queue = DispatchQueue(label: "test.queue.idle")
        let recorder = TestRecorder<Int>()
        let writer = LatestWinsWriter<Int>(queue: queue, minInterval: 0.02) { val in
            recorder.record(val)
        }
        _ = writer

        usleep(30000)
        #expect(recorder.values.isEmpty)
    }

    @Test func latestWinsWhenBusy() {
        let queue = DispatchQueue(label: "test.queue.busy")
        let recorder = TestRecorder<Int>()
        let blockFirst = DispatchSemaphore(value: 0)
        let doneAll = DispatchSemaphore(value: 0)
        let firstFlag = TestFlag(true)

        let writer = LatestWinsWriter<Int>(queue: queue, minInterval: 0.01) { val in
            if firstFlag.testAndSetFalse() {
                blockFirst.wait()
            }
            recorder.record(val)
            if recorder.count == 2 {
                doneAll.signal()
            }
        }

        // Submit first value, which will block on blockFirst
        writer.submit(1)

        // Give queue time to start executing first write
        usleep(10000)

        // Submit 2...100 while first write is in progress
        for i in 2...100 {
            writer.submit(i)
        }

        // Unblock first write
        blockFirst.signal()

        // Wait for writer to process the latest pending value
        let res = doneAll.wait(timeout: .now() + 1.0)
        #expect(res == .success)
        #expect(recorder.values == [1, 100])
    }

    @Test func sequentialSubmitsWhenIdle() {
        let queue = DispatchQueue(label: "test.queue.seq")
        let recorder = TestRecorder<Int>()
        let writer = LatestWinsWriter<Int>(queue: queue, minInterval: 0.01) { val in
            recorder.record(val)
        }

        writer.submit(10)
        usleep(30000)
        writer.submit(20)
        usleep(30000)

        #expect(recorder.values == [10, 20])
    }

    @Test func minIntervalEnforcedBetweenWrites() {
        let queue = DispatchQueue(label: "test.queue.interval")
        let recorder = TestTimestampRecorder<Int>()
        let minInterval: TimeInterval = 0.05 // 50ms
        let done = DispatchSemaphore(value: 0)

        let writer = LatestWinsWriter<Int>(queue: queue, minInterval: minInterval) { val in
            recorder.record(val)
            if recorder.count == 2 {
                done.signal()
            }
        }

        // Submit 1, and immediately submit 2
        writer.submit(1)
        writer.submit(2)

        let res = done.wait(timeout: .now() + 1.0)
        #expect(res == .success)

        let timestamps = recorder.timestamps
        #expect(timestamps.count == 2)
        if timestamps.count == 2 {
            let diff = timestamps[1] - timestamps[0]
            #expect(diff >= minInterval - 0.005) // Allow tiny scheduling jitter
        }
    }
}

// Thread-safe helpers for testing
private final class TestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ initial: Bool) {
        self.value = initial
    }

    func testAndSetFalse() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value = false
        return old
    }
}

private final class TestRecorder<T: Sendable>: @unchecked Sendable {

    private let lock = NSLock()
    private var _values: [T] = []

    func record(_ val: T) {
        lock.lock()
        defer { lock.unlock() }
        _values.append(val)
    }

    var values: [T] {
        lock.lock()
        defer { lock.unlock() }
        return _values
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _values.count
    }
}

private final class TestTimestampRecorder<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _timestamps: [TimeInterval] = []

    func record(_ val: T) {
        lock.lock()
        defer { lock.unlock() }
        _timestamps.append(ProcessInfo.processInfo.systemUptime)
    }

    var timestamps: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return _timestamps
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _timestamps.count
    }
}
