import AppKit
import QuartzCore

final class OSDPanel {
    private let isVerbose: Bool
    private var window: NSPanel?
    private var progressLayer: CALayer?
    private var levelTextLayer: CATextLayer?
    private var hideWorkItem: DispatchWorkItem?

    private let panelSize = CGSize(width: 200, height: 200)

    init(isVerbose: Bool = false) {
        self.isVerbose = isVerbose
    }

    private func createPanelIfNeeded() -> NSPanel {
        if let existing = window {
            return existing
        }

        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false

        guard let contentView = panel.contentView else { return panel }
        contentView.wantsLayer = true
        guard let rootLayer = contentView.layer else { return panel }

        rootLayer.backgroundColor = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.85)
        rootLayer.cornerRadius = 20
        rootLayer.masksToBounds = true

        // Sun / Brightness Icon
        let iconLayer = CATextLayer()
        iconLayer.string = "☀️"
        iconLayer.fontSize = 48
        iconLayer.alignmentMode = .center
        iconLayer.frame = CGRect(x: 0, y: 105, width: panelSize.width, height: 60)
        iconLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        rootLayer.addSublayer(iconLayer)

        // Progress bar background track
        let trackLayer = CALayer()
        let trackWidth: CGFloat = 160
        let trackHeight: CGFloat = 10
        let trackX = (panelSize.width - trackWidth) / 2
        let trackY: CGFloat = 50
        trackLayer.frame = CGRect(x: trackX, y: trackY, width: trackWidth, height: trackHeight)
        trackLayer.backgroundColor = CGColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 0.8)
        trackLayer.cornerRadius = trackHeight / 2
        trackLayer.masksToBounds = true
        rootLayer.addSublayer(trackLayer)

        // Progress bar fill layer
        let fill = CALayer()
        fill.frame = CGRect(x: 0, y: 0, width: 0, height: trackHeight)
        fill.backgroundColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95)
        fill.cornerRadius = trackHeight / 2
        trackLayer.addSublayer(fill)
        self.progressLayer = fill

        // Level text indicator
        let textLayer = CATextLayer()
        textLayer.fontSize = 13
        textLayer.alignmentMode = .center
        textLayer.foregroundColor = CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
        textLayer.frame = CGRect(x: 0, y: 22, width: panelSize.width, height: 20)
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        rootLayer.addSublayer(textLayer)
        self.levelTextLayer = textLayer

        self.window = panel
        return panel
    }

    func show(level: Int, steps: Int = 16, on screen: NSScreen) {
        let startTime = CFAbsoluteTimeGetCurrent()
        hideWorkItem?.cancel()

        let panel = createPanelIfNeeded()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let clampedLevel = max(0, min(steps, level))
        let fraction = steps > 0 ? CGFloat(clampedLevel) / CGFloat(steps) : 0
        let trackWidth: CGFloat = 160
        progressLayer?.frame.size.width = trackWidth * fraction
        levelTextLayer?.string = "\(clampedLevel) / \(steps)"

        CATransaction.commit()

        let screenFrame = screen.frame
        let originX = screenFrame.midX - panelSize.width / 2
        let originY = screenFrame.midY - panelSize.height / 2
        panel.setFrameOrigin(CGPoint(x: originX, y: originY))

        panel.orderFrontRegardless()

        if isVerbose {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            print(String(format: "[OSD] show() latency: %.2f ms (level: %d/%d)", elapsedMs, clampedLevel, steps))
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.window?.orderOut(nil)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }
}
