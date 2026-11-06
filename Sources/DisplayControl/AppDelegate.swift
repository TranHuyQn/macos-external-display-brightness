import AppKit
import DisplayCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings()
    var appController: AppController!
    var statusItemController: StatusItemController!
    var keyTap: BrightnessKeyTap!
    var settingsWindowController: SettingsWindowController?
    let isVerbose: Bool

    init(isVerbose: Bool = false) {
        self.isVerbose = isVerbose
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        appController = AppController(settings: settings, isVerbose: isVerbose)
        appController.start()

        keyTap = BrightnessKeyTap { [weak self] direction in
            return self?.appController.handle(direction) ?? false
        }
        keyTap.start(prompt: true)

        statusItemController = StatusItemController(
            settings: settings,
            appController: appController
        ) { [weak self] visible in
            self?.statusItemController.setVisible(visible)
        }
        statusItemController.setVisible(settings.showIcon)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    func showSettingsWindow() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController(settings: settings) { [weak self] visible in
                self?.statusItemController.setVisible(visible)
            }
            controller.onClose = { [weak self] in
                self?.settingsWindowController = nil
            }
            self.settingsWindowController = controller
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
