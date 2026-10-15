// Draws the app icon: a git branch whose tip grows into a leaf.
// Usage: swift Scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = size / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)

    // Background tile, with the margin macOS icons keep around it.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 24
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(red: 0.12, green: 0.45, blue: 0.27, alpha: 1).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(
        starting: NSColor(red: 0.42, green: 0.80, blue: 0.50, alpha: 1),
        ending: NSColor(red: 0.10, green: 0.44, blue: 0.27, alpha: 1)
    )!.draw(in: tilePath, angle: -90)

    // The leaf makes the drawing wider on the right: shift it so it sits centered.
    NSGraphicsContext.current!.cgContext.translateBy(x: -55, y: 0)
    let white = NSColor.white
    let lineWidth: CGFloat = 54

    // Trunk.
    let trunk = NSBezierPath()
    trunk.move(to: NSPoint(x: 400, y: 250))
    trunk.line(to: NSPoint(x: 400, y: 740))
    trunk.lineWidth = lineWidth
    trunk.lineCapStyle = .round
    white.setStroke()
    trunk.stroke()

    // Branch leaving the trunk and curving up to the right.
    let branch = NSBezierPath()
    branch.move(to: NSPoint(x: 400, y: 380))
    branch.curve(to: NSPoint(x: 610, y: 560), controlPoint1: NSPoint(x: 400, y: 480), controlPoint2: NSPoint(x: 610, y: 450))
    branch.lineWidth = lineWidth
    branch.lineCapStyle = .round
    branch.stroke()

    // Commits on the trunk.
    for y in [250.0, 740.0] {
        let r: CGFloat = 58
        NSBezierPath(ovalIn: NSRect(x: 400 - r, y: y - r, width: 2 * r, height: 2 * r)).fill(with: white)
    }

    // Leaf at the branch tip, tilted up and to the right.
    let transform = NSAffineTransform()
    transform.translateX(by: 610, yBy: 560)
    transform.rotate(byDegrees: -40)
    let leaf = NSBezierPath()
    leaf.move(to: NSPoint(x: 0, y: 0))
    leaf.curve(to: NSPoint(x: 0, y: 290), controlPoint1: NSPoint(x: 150, y: 60), controlPoint2: NSPoint(x: 130, y: 230))
    leaf.curve(to: NSPoint(x: 0, y: 0), controlPoint1: NSPoint(x: -130, y: 230), controlPoint2: NSPoint(x: -150, y: 60))
    leaf.close()
    leaf.transform(using: transform as AffineTransform)
    NSColor(red: 0.85, green: 0.98, blue: 0.80, alpha: 1).setFill()
    leaf.fill()
    white.setStroke()
    leaf.lineWidth = 16
    leaf.stroke()

    let vein = NSBezierPath()
    vein.move(to: NSPoint(x: 0, y: 20))
    vein.curve(to: NSPoint(x: 0, y: 250), controlPoint1: NSPoint(x: 10, y: 100), controlPoint2: NSPoint(x: 10, y: 180))
    vein.transform(using: transform as AffineTransform)
    vein.lineWidth = 14
    vein.lineCapStyle = .round
    NSColor(red: 0.16, green: 0.55, blue: 0.32, alpha: 1).setStroke()
    vein.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

extension NSBezierPath {
    func fill(with color: NSColor) {
        color.setFill()
        fill()
    }
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = drawIcon(size: CGFloat(points * factor)).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
exit(iconutil.terminationStatus)
