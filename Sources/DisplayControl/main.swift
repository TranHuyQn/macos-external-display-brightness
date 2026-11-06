import Foundation
import AppKit
import DisplayCore

let args = CommandLine.arguments

if args.contains("--ddc-read") {
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
    let tap = BrightnessKeyTap { direction in
        print("key: \(direction)")
        return false // let all keys through
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

    let osd = OSDPanel()
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
    print("DisplayControl version \(DisplayCorePlaceholder.version)")
}
