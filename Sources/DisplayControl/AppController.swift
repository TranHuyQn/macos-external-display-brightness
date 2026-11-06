import Foundation
import AppKit
import DisplayCore

final class AppController {
    let settings: Settings
    private let isVerbose: Bool
    private let minInterval: TimeInterval
    private let ddcLocator: (UInt32) -> DDCDevice?
    private let screenProvider: () -> [ScreenInfo]
    private let mouseLocationProvider: () -> CGPoint
    private let osdPanel: OSDPanel?

    private let ddcQueue = DispatchQueue(label: "com.displaycontrol.ddc.serial", qos: .userInitiated)
    private var writer: LatestWinsWriter<Int>!

    private struct CachedState {
        var ddc: DDCDevice?
        var scale: BrightnessScale?
        var brightness: Int?
        var displayID: UInt32?
    }

    private let lock = NSLock()
    private var state = CachedState()
    private var isRefreshing = false
    private var lastRefreshAttemptTime: TimeInterval = 0

    private(set) var totalKeyEvents: Int = 0
    private(set) var totalActualWrites: Int = 0

    var currentBrightness: Int? {
        lock.lock()
        defer { lock.unlock() }
        return state.brightness
    }

    var currentScale: BrightnessScale? {
        lock.lock()
        defer { lock.unlock() }
        return state.scale
    }

    var activeDDC: DDCDevice? {
        lock.lock()
        defer { lock.unlock() }
        return state.ddc
    }

    var targetDisplayID: UInt32? {
        lock.lock()
        defer { lock.unlock() }
        return state.displayID
    }

    init(
        settings: Settings,
        isVerbose: Bool = false,
        minInterval: TimeInterval = 0.04,
        ddcLocator: @escaping (UInt32) -> DDCDevice? = { locateExternalDDC(for: $0) },
        screenProvider: @escaping () -> [ScreenInfo] = { currentScreens() },
        mouseLocationProvider: @escaping () -> CGPoint = { NSEvent.mouseLocation },
        osdPanel: OSDPanel? = OSDPanel()
    ) {
        self.settings = settings
        self.isVerbose = isVerbose
        self.minInterval = minInterval
        self.ddcLocator = ddcLocator
        self.screenProvider = screenProvider
        self.mouseLocationProvider = mouseLocationProvider
        self.osdPanel = osdPanel

        self.writer = LatestWinsWriter<Int>(
            queue: self.ddcQueue,
            minInterval: minInterval
        ) { [weak self] value in
            self?.performDDCWrite(value)
        }
    }

    func start() {
        triggerAsyncRefreshIfNeeded(force: true)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged() {
        if isVerbose {
            print("[AppController] Screen parameters changed, queuing async refresh...")
        }
        triggerAsyncRefreshIfNeeded(force: true)
    }

    @objc private func systemDidWake() {
        if isVerbose {
            print("[AppController] System woke up, queuing async refresh...")
        }
        triggerAsyncRefreshIfNeeded(force: true)
    }

    func triggerAsyncRefreshIfNeeded(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        if isRefreshing {
            lock.unlock()
            return
        }
        if !force && (now - lastRefreshAttemptTime < 1.0) {
            lock.unlock()
            return
        }
        lastRefreshAttemptTime = now
        isRefreshing = true
        lock.unlock()

        ddcQueue.async { [weak self] in
            self?.performBackgroundRefresh()
        }
    }

    private func performBackgroundRefresh() {
        let screens = screenProvider()
        guard let ext = screens.first(where: { !$0.isBuiltIn }) else {
            lock.lock()
            state = CachedState()
            isRefreshing = false
            lock.unlock()
            if isVerbose {
                print("[AppController] No external display detected.")
            }
            return
        }

        lock.lock()
        let existingDDC = (state.displayID == ext.id) ? state.ddc : nil
        lock.unlock()

        let ddc = existingDDC ?? ddcLocator(ext.id)
        guard let validDDC = ddc else {
            lock.lock()
            state.ddc = nil
            state.scale = nil
            state.displayID = nil
            isRefreshing = false
            lock.unlock()
            if isVerbose {
                print("[AppController] Could not locate DDC for external display id \(ext.id).")
            }
            return
        }

        do {
            let (current, max) = try validDDC.readBrightness()
            guard let scale = BrightnessScale(max: max) else {
                throw DDCError.invalidRange
            }
            lock.lock()
            state.ddc = validDDC
            state.scale = scale
            state.brightness = current
            state.displayID = ext.id
            isRefreshing = false
            lock.unlock()

            settings.lastValue = current
            if isVerbose {
                print("[AppController] External display detected & read: id=\(ext.id), brightness=\(current), max=\(max)")
            }
        } catch {
            lock.lock()
            state.ddc = validDDC
            state.scale = nil // Will trigger retry on subsequent key attempt
            state.displayID = ext.id
            isRefreshing = false
            lock.unlock()

            if isVerbose {
                print("[AppController] Failed to read brightness via DDC: \(error)")
            }
        }
    }

    func setCustomDDC(_ ddc: DDCDevice, scale: BrightnessScale?, initialBrightness: Int?, displayID: UInt32) {
        lock.lock()
        state.ddc = ddc
        state.scale = scale
        state.brightness = initialBrightness
        state.displayID = displayID
        lock.unlock()
    }

    func handle(_ direction: Direction) -> Bool {
        lock.lock()
        totalKeyEvents += 1
        lock.unlock()

        let mouse = mouseLocationProvider()
        let screens = screenProvider()
        let target = resolveTarget(mouse: mouse, screens: screens)

        switch target {
        case .builtIn, .none:
            return false

        case .external(let id):
            lock.lock()
            let ddc = state.ddc
            let scale = state.scale
            let currentVal = state.brightness ?? settings.lastValue
            let cachedID = state.displayID
            lock.unlock()

            // If not initialized or display changed or scale missing, trigger async refresh and do not swallow
            guard let validScale = scale, let _ = ddc, cachedID == id else {
                triggerAsyncRefreshIfNeeded()
                return false
            }

            let startVal = currentVal ?? 50
            let newVal = validScale.stepped(from: startVal, direction: direction)

            lock.lock()
            state.brightness = newVal
            lock.unlock()

            settings.lastValue = newVal

            // Show OSD immediately on matching NSScreen on main thread
            if let osd = osdPanel {
                let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
                if let scr = targetScreen {
                    let level = validScale.level(forValue: newVal)
                    osd.show(level: level, steps: BrightnessScale.steps, on: scr)
                }
            }

            if isVerbose {
                print("[AppController] Key \(direction): \(startVal) -> \(newVal) (event #\(totalKeyEvents))")
            }

            writer.submit(newVal)
            return true
        }
    }

    private func performDDCWrite(_ value: Int) {
        lock.lock()
        totalActualWrites += 1
        let ddc = state.ddc
        let writesCount = totalActualWrites
        let eventsCount = totalKeyEvents
        lock.unlock()

        if isVerbose {
            print("[DDC Writer] Writing value: \(value) (actual write #\(writesCount) / key events: \(eventsCount))")
        }
        do {
            try ddc?.writeBrightness(value)
        } catch {
            if isVerbose {
                fputs("[DDC Writer] Write failed: \(error)\n", stderr)
            }
        }
    }
}
