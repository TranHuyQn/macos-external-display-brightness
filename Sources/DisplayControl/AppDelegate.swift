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

        appController = AppController(
            settings: settings,
            isVerbose: isVerbose,
            osdPanel: OSDPanel(isVerbose: isVerbose)
        )
        appController.start()

        keyTap = BrightnessKeyTap(isVerbose: isVerbose) { [weak self] direction in
            return self?.appController.handle(direction) ?? false
        }
        keyTap.start(prompt: true)

        statusItemController = StatusItemController(
            settings: settings,
            appController: appController,
            onToggleIcon: { [weak self] visible in
                self?.statusItemController.setVisible(visible)
            },
            onCheckPermission: { [weak self] in
                guard let self = self, !self.keyTap.isStarted, hasAccessibilityPermission(prompt: false) else { return }
                self.keyTap.start(prompt: false)
            }
        )
        statusItemController.setVisible(settings.showIcon)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !keyTap.isStarted && hasAccessibilityPermission(prompt: false) {
            keyTap.start(prompt: false)
        }
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
