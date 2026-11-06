import AppKit
import DisplayCore

func currentScreens() -> [ScreenInfo] {
    return NSScreen.screens.compactMap { screen in
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = screenNumber.uint32Value
        let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
        return ScreenInfo(id: displayID, frame: screen.frame, isBuiltIn: isBuiltIn)
    }
}
