import AppKit
import DisplayCore

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: Settings
    private let onToggleIcon: (Bool) -> Void
    var onClose: (() -> Void)?

    private var iconCheckbox: NSButton!
    private var loginCheckbox: NSButton!

    init(settings: Settings, onToggleIcon: @escaping (Bool) -> Void) {
        self.settings = settings
        self.onToggleIcon = onToggleIcon

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cài đặt DisplayControl"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = self.window else { return }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 160))

        iconCheckbox = NSButton(checkboxWithTitle: "Hiện icon trên Menu Bar", target: self, action: #selector(iconToggled(_:)))
        iconCheckbox.frame = NSRect(x: 24, y: 105, width: 250, height: 24)
        iconCheckbox.state = settings.showIcon ? .on : .off
        container.addSubview(iconCheckbox)

        loginCheckbox = NSButton(checkboxWithTitle: "Khởi động cùng máy", target: self, action: #selector(loginToggled(_:)))
        loginCheckbox.frame = NSRect(x: 24, y: 70, width: 250, height: 24)
        loginCheckbox.state = LoginItem.isEnabled() ? .on : .off
        container.addSubview(loginCheckbox)

        let quitButton = NSButton(title: "Thoát ứng dụng", target: self, action: #selector(quitClicked(_:)))
        quitButton.frame = NSRect(x: 24, y: 20, width: 252, height: 32)
        quitButton.bezelStyle = .rounded
        container.addSubview(quitButton)

        window.contentView = container
    }

    @objc private func iconToggled(_ sender: NSButton) {
        let isChecked = (sender.state == .on)
        settings.showIcon = isChecked
        onToggleIcon(isChecked)
    }

    @objc private func loginToggled(_ sender: NSButton) {
        let isChecked = (sender.state == .on)
        do {
            try LoginItem.setEnabled(isChecked)
        } catch {
            sender.state = isChecked ? .off : .on
            let alert = NSAlert()
            alert.messageText = "Lỗi cài đặt khởi động"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func quitClicked(_ sender: Any) {
        NSApp.terminate(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
