import Foundation
import CoreGraphics
import ApplicationServices
import AppKit
import DisplayCore

func hasAccessibilityPermission(prompt: Bool = false) -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

final class BrightnessKeyTap {
    private let shouldConsume: (Direction) -> Bool
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isConsumingCurrentPress = false

    init(shouldConsume: @escaping (Direction) -> Bool) {
        self.shouldConsume = shouldConsume
    }

    deinit {
        stop()
    }

    @discardableResult
    func start(prompt: Bool = true) -> Bool {
        guard hasAccessibilityPermission(prompt: prompt) else {
            return false
        }

        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        let observer = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                let tap = Unmanaged<BrightnessKeyTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) else {
            return false
        }

        self.machPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let port = machPort {
            CGEvent.tapEnable(tap: port, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                runLoopSource = nil
            }
            machPort = nil
        }
    }

    func handleEvent(proxy: CGEventTapProxy?, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = machPort {
                CGEvent.tapEnable(tap: port, enable: true)
                print("tap re-enabled")
            }
            return Unmanaged.passRetained(event)
        }

        guard type.rawValue == 14 else {
            return Unmanaged.passRetained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passRetained(event)
        }

        let data1 = nsEvent.data1
        let keyCode = (data1 >> 16) & 0xFFFF
        let keyFlags = (data1 >> 8) & 0xFF
        let isKeyDown = (keyFlags == 0xA)
        let isKeyUp = (keyFlags == 0xB)

        // 2 = Brightness Up, 3 = Brightness Down
        guard keyCode == 2 || keyCode == 3 else {
            return Unmanaged.passRetained(event)
        }

        let direction: Direction = (keyCode == 2) ? .up : .down

        if isKeyDown {
            let consume = shouldConsume(direction)
            isConsumingCurrentPress = consume
            if consume {
                return nil
            }
        } else if isKeyUp {
            if isConsumingCurrentPress {
                isConsumingCurrentPress = false
                return nil
            }
        }

        return Unmanaged.passRetained(event)
    }

    func simulateDisable() {
        if let dummyEvent = CGEvent(source: nil) {
            _ = handleEvent(proxy: nil, type: .tapDisabledByTimeout, event: dummyEvent)
        }
    }
}
