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

    private var writer: LatestWinsWriter<Int>!
    private(set) var activeDDC: DDCDevice?
    private(set) var currentScale: BrightnessScale?
    private(set) var currentBrightness: Int?
    private(set) var targetDisplayID: UInt32?

    private(set) var totalKeyEvents: Int = 0
    private(set) var totalActualWrites: Int = 0

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
            queue: DispatchQueue(label: "com.displaycontrol.ddc.writer"),
            minInterval: minInterval
        ) { [weak self] value in
            self?.performDDCWrite(value)
        }
    }

    func start() {
        refreshExternalDisplay()

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
            print("[AppController] Screen parameters changed, refreshing display...")
        }
        refreshExternalDisplay()
    }

    @objc private func systemDidWake() {
        if isVerbose {
            print("[AppController] System woke up, refreshing display...")
        }
        refreshExternalDisplay()
    }

    func refreshExternalDisplay() {
        let screens = screenProvider()
        guard let ext = screens.first(where: { !$0.isBuiltIn }) else {
            activeDDC = nil
            currentScale = nil
            targetDisplayID = nil
            if isVerbose {
                print("[AppController] No external display detected.")
            }
            return
        }

        targetDisplayID = ext.id
        guard let ddc = ddcLocator(ext.id) else {
            activeDDC = nil
            currentScale = nil
            if isVerbose {
                print("[AppController] Could not locate DDC for external display id \(ext.id).")
            }
            return
        }

        activeDDC = ddc
        do {
            let (current, max) = try ddc.readBrightness()
            currentScale = BrightnessScale(max: max)
            currentBrightness = current
            settings.lastValue = current
            if isVerbose {
                print("[AppController] External display detected: brightness=\(current), max=\(max)")
            }
        } catch {
            if let last = settings.lastValue {
                currentBrightness = last
                currentScale = BrightnessScale(max: 100)
            }
            if isVerbose {
                print("[AppController] Failed to read brightness via DDC: \(error)")
            }
        }
    }

    func setCustomDDC(_ ddc: DDCDevice, scale: BrightnessScale, initialBrightness: Int, displayID: UInt32) {
        self.activeDDC = ddc
        self.currentScale = scale
        self.currentBrightness = initialBrightness
        self.targetDisplayID = displayID
    }

    func handle(_ direction: Direction) -> Bool {
        totalKeyEvents += 1

        let mouse = mouseLocationProvider()
        let screens = screenProvider()
        let target = resolveTarget(mouse: mouse, screens: screens)

        switch target {
        case .builtIn, .none:
            return false

        case .external(let id):
            if activeDDC == nil || targetDisplayID != id {
                refreshExternalDisplay()
            }

            guard let scale = currentScale, activeDDC != nil else {
                return false
            }

            let startVal = currentBrightness ?? settings.lastValue ?? 50
            let newVal = scale.stepped(from: startVal, direction: direction)
            currentBrightness = newVal
            settings.lastValue = newVal

            // Show OSD immediately on matching NSScreen
            if let osd = osdPanel {
                let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
                if let scr = targetScreen {
                    let level = scale.level(forValue: newVal)
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
        totalActualWrites += 1
        if isVerbose {
            print("[DDC Writer] Writing value: \(value) (actual write #\(totalActualWrites) / key events: \(totalKeyEvents))")
        }
        do {
            try activeDDC?.writeBrightness(value)
        } catch {
            if isVerbose {
                fputs("[DDC Writer] Write failed: \(error)\n", stderr)
            }
        }
    }
}
