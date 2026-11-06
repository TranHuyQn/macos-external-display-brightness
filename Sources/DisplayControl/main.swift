import Foundation
import AppKit
import DisplayCore

final class MockDDCDevice: DDCDevice, @unchecked Sendable {
    private let lock = NSLock()
    var writeCount: Int = 0
    var writtenValues: [Int] = []
    var readThreads: [Bool] = [] // Records Thread.isMainThread for each read
    var shouldFailReadCount: Int = 0
    let delayMicros: UInt32

    init(delayMicros: UInt32 = 4000, shouldFailReadCount: Int = 0) {
        self.delayMicros = delayMicros
        self.shouldFailReadCount = shouldFailReadCount
    }

    func readBrightness() throws -> (current: Int, max: Int) {
        usleep(delayMicros)
        lock.lock()
        defer { lock.unlock() }
        readThreads.append(Thread.isMainThread)

        if shouldFailReadCount > 0 {
            shouldFailReadCount -= 1
            throw DDCError.readFailed
        }
        return (current: 0, max: 100)
    }

    func writeBrightness(_ value: Int) throws {
        usleep(delayMicros)
        lock.lock()
        writeCount += 1
        writtenValues.append(value)
        lock.unlock()
    }
}

func runSelfTest() -> Int32 {
    print("==> Running AppController --self-test...")
    let suiteName = "SelfTestSuite-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fputs("ERROR: Failed to create test UserDefaults\n", stderr)
        return 1
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = Settings(defaults: defaults)
    let mockDDC = MockDDCDevice()
    let mockExternalScreen = ScreenInfo(
        id: 2,
        frame: CGRect(x: 1512, y: 0, width: 1920, height: 1200),
        isBuiltIn: false
    )
    let mockBuiltInScreen = ScreenInfo(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        isBuiltIn: true
    )

    // -------------------------------------------------------------
    // Test 1: handle() when cache is empty returns false immediately
    // and triggers background refresh WITHOUT blocking main thread
    // -------------------------------------------------------------
    print("[Self-Test 1] Testing uninitialized cache behavior on main thread...")
    var currentMouse = CGPoint(x: 2000, y: 500)
    let freshController = AppController(
        settings: settings,
        isVerbose: false,
        minInterval: 0.04,
        ddcLocator: { _ in mockDDC },
        screenProvider: { [mockBuiltInScreen, mockExternalScreen] },
        mouseLocationProvider: { currentMouse },
        osdPanel: nil
    )

    let t0 = CFAbsoluteTimeGetCurrent()
    let initialConsumed = freshController.handle(.up)
    let handleElapsedMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0

    guard !initialConsumed else {
        fputs("FAIL: handle() must return false when cache is not yet ready\n", stderr)
        return 1
    }
    guard handleElapsedMs < 20.0 else {
        fputs("FAIL: handle() took \(handleElapsedMs) ms, which blocked main thread!\n", stderr)
        return 1
    }
    print(String(format: "    handle() returned false immediately in %.2f ms", handleElapsedMs))

    // Wait for background refresh on ddcQueue to finish
    usleep(80_000)

    guard !mockDDC.readThreads.isEmpty else {
        fputs("FAIL: Background refresh did not trigger readBrightness()\n", stderr)
        return 1
    }
    guard !mockDDC.readThreads.contains(true) else {
        fputs("FAIL: readBrightness() was executed on MAIN thread!\n", stderr)
        return 1
    }
    print("    Verified: readBrightness() was executed on background queue (never main thread)")

    // -------------------------------------------------------------
    // Test 2: 100 rapid key events on external screen with valid cache
    // -------------------------------------------------------------
    print("[Self-Test 2] Testing rapid 100 key presses with LatestWinsWriter...")
    let controller = AppController(
        settings: settings,
        isVerbose: false,
        minInterval: 0.04,
        ddcLocator: { _ in mockDDC },
        screenProvider: { [mockBuiltInScreen, mockExternalScreen] },
        mouseLocationProvider: { currentMouse },
        osdPanel: nil
    )
    controller.setCustomDDC(mockDDC, scale: BrightnessScale(max: 100)!, initialBrightness: 0, displayID: 2)

    // Test mouse on built-in screen
    currentMouse = CGPoint(x: 100, y: 100)
    guard !controller.handle(.up) else {
        fputs("FAIL: Mouse on built-in screen must return false\n", stderr)
        return 1
    }

    // 100 rapid events on external screen
    currentMouse = CGPoint(x: 2000, y: 500)
    for i in 1...100 {
        let consumed = controller.handle(.up)
        if !consumed {
            fputs("FAIL: Event #\(i) on external screen was not consumed\n", stderr)
            return 1
        }
    }

    // Allow background writer to drain
    usleep(250_000)

    let actualWrites = mockDDC.writeCount
    let lastValue = mockDDC.writtenValues.last ?? -1
    print("    Key events: 100 -> Actual DDC writes: \(actualWrites), Final value: \(lastValue)")

    guard actualWrites < 10 else {
        fputs("FAIL: Expected actual writes < 10, got \(actualWrites)\n", stderr)
        return 1
    }
    guard lastValue == 100 else {
        fputs("FAIL: Expected final value 100, got \(lastValue)\n", stderr)
        return 1
    }

    // -------------------------------------------------------------
    // Test 3: Flaky read on first attempt, then retry succeeds
    // -------------------------------------------------------------
    print("[Self-Test 3] Testing retry after failed initial read...")
    let flakyDDC = MockDDCDevice(delayMicros: 2000, shouldFailReadCount: 1)
    let retryController = AppController(
        settings: settings,
        isVerbose: false,
        minInterval: 0.04,
        ddcLocator: { _ in flakyDDC },
        screenProvider: { [mockBuiltInScreen, mockExternalScreen] },
        mouseLocationProvider: { CGPoint(x: 2000, y: 500) },
        osdPanel: nil
    )

    // First attempt triggers background refresh that fails
    _ = retryController.handle(.up)
    usleep(50_000)

    // Scale must still be nil because read failed
    guard retryController.currentScale == nil else {
        fputs("FAIL: currentScale should be nil after failed read\n", stderr)
        return 1
    }

    // Next handle immediately should still return false without waiting
    guard !retryController.handle(.up) else {
        fputs("FAIL: handle() should return false when scale is nil\n", stderr)
        return 1
    }

    // Advance past the 1.0s throttle window to allow retry
    sleep(2)

    // Calling handle now triggers async retry
    _ = retryController.handle(.up)
    usleep(80_000)

    // Retry succeeded on background thread!
    guard retryController.currentScale != nil else {
        fputs("FAIL: retryController should have acquired valid scale after retry\n", stderr)
        return 1
    }
    guard !flakyDDC.readThreads.contains(true) else {
        fputs("FAIL: Retry read was executed on main thread!\n", stderr)
        return 1
    }

    // Subsequent handle should now succeed
    guard retryController.handle(.up) else {
        fputs("FAIL: handle() should now consume event after successful retry\n", stderr)
        return 1
    }
    print("    Verified: Initial read failure was retried asynchronously and recovered successfully")

    print("✔ All self-test scenarios passed successfully!")
    return 0
}

let args = CommandLine.arguments
let isVerbose = args.contains("--verbose")

if args.contains("--self-test") {
    let code = runSelfTest()
    exit(code)
} else if args.contains("--ddc-read") {
    guard let external = currentScreens().first(where: { !$0.isBuiltIn }) else {
        fputs("notFound\n", stderr)
        exit(1)
    }
    guard let ddc = locateExternalDDC(for: external.id) else {
        fputs("notFound\n", stderr)
        exit(1)
    }
    do {
        let (current, max) = try ddc.readBrightness()
        print("current=\(current) max=\(max)")
        exit(0)
    } catch {
        fputs("Error reading DDC brightness: \(error)\n", stderr)
        exit(1)
    }
} else if let writeIndex = args.firstIndex(of: "--ddc-write"), writeIndex + 1 < args.count {
    guard let value = Int(args[writeIndex + 1]) else {
        fputs("Usage: DisplayControl --ddc-write <0-100>\n", stderr)
        exit(1)
    }
    guard let external = currentScreens().first(where: { !$0.isBuiltIn }) else {
        fputs("notFound\n", stderr)
        exit(1)
    }
    guard let ddc = locateExternalDDC(for: external.id) else {
        fputs("notFound\n", stderr)
        exit(1)
    }
    do {
        try ddc.writeBrightness(value)
        print("Wrote brightness: \(value)")
        exit(0)
    } catch {
        fputs("Error writing DDC brightness: \(error)\n", stderr)
        exit(1)
    }
} else if args.contains("--check-permission") {
    let trusted = hasAccessibilityPermission(prompt: false)
    print("Accessibility permission: \(trusted)")
    exit(0)
} else if args.contains("--log-keys") {
    let trusted = hasAccessibilityPermission(prompt: false)
    print("Accessibility permission: \(trusted)")
    let tap = BrightnessKeyTap(isVerbose: isVerbose) { direction in
        print("key: \(direction)")
        return false
    }
    if args.contains("--simulate-disable") {
        tap.simulateDisable()
        exit(0)
    }
    guard tap.start(prompt: true) else {
        print("Accessibility permission not granted. Cannot start event tap.")
        exit(1)
    }
    print("Listening for brightness keys (F1/F2)... Press Ctrl+C to stop.")
    CFRunLoopRun()
} else if args.contains("--osd-demo") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let mouseLoc = NSEvent.mouseLocation
    let targetScreen: NSScreen
    if let found = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) {
        targetScreen = found
    } else if let main = NSScreen.main {
        targetScreen = main
    } else if !NSScreen.screens.isEmpty {
        targetScreen = NSScreen.screens[0]
    } else {
        fputs("No screens available for OSD demo\n", stderr)
        exit(1)
    }

    let osd = OSDPanel(isVerbose: true)
    DispatchQueue.main.async {
        osd.show(level: 8, steps: 16, on: targetScreen)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            osd.show(level: 12, steps: 16, on: targetScreen)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                exit(0)
            }
        }
    }
    app.run()
} else {
    // Normal launch: run NSApplication with AppDelegate
    let app = NSApplication.shared
    let delegate = AppDelegate(isVerbose: isVerbose)
    app.delegate = delegate
    app.run()
}
