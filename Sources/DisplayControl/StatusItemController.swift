import AppKit
import DisplayCore

final class StatusItemController: NSObject, NSMenuDelegate {
    private let settings: Settings
    private let appController: AppController
    private let onToggleIcon: (Bool) -> Void
    var onCheckPermission: (() -> Void)?

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    init(settings: Settings, appController: AppController, onToggleIcon: @escaping (Bool) -> Void, onCheckPermission: (() -> Void)? = nil) {
        self.settings = settings
        self.appController = appController
        self.onToggleIcon = onToggleIcon
        self.onCheckPermission = onCheckPermission
        super.init()
        self.menu.delegate = self
    }

    func setVisible(_ visible: Bool) {
        if visible && statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                if let img = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "DisplayControl") {
                    img.isTemplate = true
                    button.image = img
                } else {
                    button.title = "☼"
                }
            }
            item.menu = menu
            statusItem = item
            rebuildMenu()
        } else if !visible && statusItem != nil {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
            }
            statusItem = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        onCheckPermission?()
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        // 1. Display info & brightness level
        let brightnessText: String
        if let current = appController.currentBrightness {
            brightnessText = "Độ sáng màn rời: \(current)%"
        } else if let last = settings.lastValue {
            brightnessText = "Độ sáng màn rời: \(last)%"
        } else {
            brightnessText = "Độ sáng màn rời: --"
        }
        let infoItem = NSMenuItem(title: brightnessText, action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Accessibility permission warning if missing
        if !hasAccessibilityPermission(prompt: false) {
            let permItem = NSMenuItem(
                title: "⚠️ Quyền Accessibility…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            permItem.target = self
            menu.addItem(permItem)
            menu.addItem(NSMenuItem.separator())
        }

        // 3. Toggle "Hiện icon menu bar"
        let iconToggleItem = NSMenuItem(
            title: "Hiện icon trên Menu Bar",
            action: #selector(toggleIcon),
            keyEquivalent: ""
        )
        iconToggleItem.target = self
        iconToggleItem.state = settings.showIcon ? .on : .off
        menu.addItem(iconToggleItem)

        // 4. Toggle "Khởi động cùng máy"
        let loginToggleItem = NSMenuItem(
            title: "Khởi động cùng máy",
            action: #selector(toggleLogin),
            keyEquivalent: ""
        )
        loginToggleItem.target = self
        loginToggleItem.state = LoginItem.isEnabled() ? .on : .off
        menu.addItem(loginToggleItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Quit
        let quitItem = NSMenuItem(title: "Thoát", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func toggleIcon() {
        let newState = !settings.showIcon
        settings.showIcon = newState
        onToggleIcon(newState)
    }

    @objc private func toggleLogin() {
        let isCurrentlyEnabled = LoginItem.isEnabled()
        do {
            try LoginItem.setEnabled(!isCurrentlyEnabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Lỗi cài đặt khởi động"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
