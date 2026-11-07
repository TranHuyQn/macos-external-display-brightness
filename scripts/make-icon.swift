import Cocoa
import CoreGraphics
import Foundation

// MARK: - Icon Generator for DisplayControl

func createIcon(size: Int) -> CGImage {
    let s = Double(size)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        fatalError("Failed to create CGContext for size \(size)")
    }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Margin ~10% each side according to macOS icon guidelines
    let margin = s * 0.10
    let squircleSide = s - 2.0 * margin
    let squircleRect = CGRect(x: margin, y: margin, width: squircleSide, height: squircleSide)
    let cornerRadius = squircleSide * 0.224
    let squirclePath = CGPath(
        roundedRect: squircleRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )

    // Clip to macOS squircle shape
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // Background gradient: from #1B2740 (top) down to #0B1020 (bottom)
    // Rendered row-by-row to prevent noisy gradient dithering, keeping PNGs small and crisp
    let steps = Int(ceil(squircleSide))
    let yStart = squircleRect.minY
    for i in 0..<steps {
        let t = Double(i) / Double(max(1, steps - 1))
        let r = (1.0 - t) * (0x0B / 255.0) + t * (0x1B / 255.0)
        let g = (1.0 - t) * (0x10 / 255.0) + t * (0x27 / 255.0)
        let b = (1.0 - t) * (0x20 / 255.0) + t * (0x40 / 255.0)
        ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1.0))
        let rowRect = CGRect(x: squircleRect.minX, y: yStart + Double(i), width: squircleSide, height: 1.05)
        ctx.fill(rowRect)
    }

    let center = CGPoint(x: squircleRect.midX, y: squircleRect.midY)
    let sunR = squircleSide * 0.165
    let rayStart = squircleSide * 0.225
    let rayEnd = squircleSide * 0.315
    let rayWidth = max(1.0, squircleSide * 0.034)
    let sunColor = CGColor(srgbRed: 1.0, green: 200.0 / 255.0, blue: 61.0 / 255.0, alpha: 1.0) // #FFC83D

    // Gentle warm glow around sun
    ctx.saveGState()
    if size >= 32 {
        ctx.setShadow(
            offset: .zero,
            blur: squircleSide * 0.022,
            color: CGColor(srgbRed: 1.0, green: 200.0 / 255.0, blue: 61.0 / 255.0, alpha: 0.85)
        )
    }

    // Solid central sun disk
    ctx.setFillColor(sunColor)
    ctx.addArc(center: center, radius: sunR, startAngle: 0, endAngle: 2.0 * .pi, clockwise: false)
    ctx.fillPath()

    // 8 short rays with rounded ends
    ctx.setStrokeColor(sunColor)
    ctx.setLineWidth(rayWidth)
    ctx.setLineCap(.round)

    let innerR = rayStart + rayWidth * 0.5
    let outerR = rayEnd - rayWidth * 0.5

    for i in 0..<8 {
        let angle = Double(i) * (.pi / 4.0)
        let p1 = CGPoint(x: center.x + cos(angle) * innerR, y: center.y + sin(angle) * innerR)
        let p2 = CGPoint(x: center.x + cos(angle) * outerR, y: center.y + sin(angle) * outerR)
        ctx.beginPath()
        ctx.move(to: p1)
        ctx.addLine(to: p2)
        ctx.strokePath()
    }
    ctx.restoreGState()

    // Subtle edge highlight on squircle boundary
    let innerBorderColor = CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.06)
    ctx.setStrokeColor(innerBorderColor)
    ctx.setLineWidth(max(0.5, squircleSide * 0.002))
    ctx.addPath(squirclePath)
    ctx.strokePath()

    ctx.restoreGState()

    guard let image = ctx.makeImage() else {
        fatalError("Failed to make CGImage for size \(size)")
    }
    return image
}

func savePNG(image: CGImage, path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to convert image to PNG for path \(path)")
    }
    let url = URL(fileURLWithPath: path)
    try! data.write(to: url)
}

// MARK: - Main Execution

let fileManager = FileManager.default
let projectRoot = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let buildDir = projectRoot.appendingPathComponent("build")
let iconsetDir = buildDir.appendingPathComponent("AppIcon.iconset")
let resourcesDir = projectRoot.appendingPathComponent("Resources")
let icnsPath = resourcesDir.appendingPathComponent("AppIcon.icns")
let previewPath = buildDir.appendingPathComponent("icon-preview-512.png")

try? fileManager.createDirectory(at: buildDir, withIntermediateDirectories: true)
try? fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
try? fileManager.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

print("==> Generating AppIcon PNGs into \(iconsetDir.path)...")

let iconSpecs: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for spec in iconSpecs {
    let img = createIcon(size: spec.size)
    let filePath = iconsetDir.appendingPathComponent(spec.name).path
    savePNG(image: img, path: filePath)
    print("  Created \(spec.name) (\(spec.size)x\(spec.size))")
}

print("==> Exporting preview image to \(previewPath.path)...")
let previewImg = createIcon(size: 512)
savePNG(image: previewImg, path: previewPath.path)

print("==> Running iconutil to generate \(icnsPath.path)...")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsPath.path]

do {
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus == 0 {
        let attrs = try fileManager.attributesOfItem(atPath: icnsPath.path)
        let fileSize = (attrs[.size] as? Int64) ?? 0
        print("==> Successfully created \(icnsPath.path) (\(fileSize) bytes / \(fileSize / 1024) KB)")
    } else {
        fatalError("iconutil failed with code \(process.terminationStatus)")
    }
} catch {
    fatalError("Failed to run iconutil: \(error)")
}
