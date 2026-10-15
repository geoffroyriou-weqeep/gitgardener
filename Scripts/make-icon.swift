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
    NSColor(red: 0.30, green: 0.50, blue: 0.20, alpha: 1).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(
        starting: NSColor(red: 0.62, green: 0.80, blue: 0.38, alpha: 1),
        ending: NSColor(red: 0.30, green: 0.52, blue: 0.22, alpha: 1)
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
    // Dashed: this is the part being cut.
    branch.lineWidth = lineWidth
    branch.lineCapStyle = .round
    branch.setLineDash([1, 68], count: 2, phase: 0)
    branch.stroke()

    // Commits on the trunk.
    for y in [250.0, 740.0] {
        let r: CGFloat = 58
        NSBezierPath(ovalIn: NSRect(x: 400 - r, y: y - r, width: 2 * r, height: 2 * r)).fill(with: white)
    }

    // Leaf at the branch tip: two tones split by a curved midrib.
    let transform = NSAffineTransform()
    transform.translateX(by: 600, yBy: 548)
    transform.rotate(byDegrees: -38)
    func place(_ path: NSBezierPath) -> NSBezierPath {
        path.transform(using: transform as AffineTransform)
        return path
    }
    let tip = NSPoint(x: 0, y: 330)
    func half(right: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: .zero)
        if right {
            path.curve(to: tip, controlPoint1: NSPoint(x: 190, y: 30), controlPoint2: NSPoint(x: 150, y: 260))
            path.curve(to: .zero, controlPoint1: NSPoint(x: -8, y: 215), controlPoint2: NSPoint(x: 18, y: 100))
        } else {
            path.curve(to: tip, controlPoint1: NSPoint(x: -150, y: 40), controlPoint2: NSPoint(x: -130, y: 250))
            path.curve(to: .zero, controlPoint1: NSPoint(x: -8, y: 215), controlPoint2: NSPoint(x: 18, y: 100))
        }
        path.close()
        return path
    }
    NSColor(red: 0.96, green: 1.0, blue: 0.80, alpha: 1).setFill()
    place(half(right: true)).fill()
    NSColor(red: 0.80, green: 0.93, blue: 0.58, alpha: 1).setFill()
    place(half(right: false)).fill()

    let midrib = NSBezierPath()
    midrib.move(to: NSPoint(x: 0, y: -20))
    midrib.curve(to: NSPoint(x: 0, y: 300), controlPoint1: NSPoint(x: 18, y: 100), controlPoint2: NSPoint(x: -8, y: 215))
    midrib.lineWidth = 15
    midrib.lineCapStyle = .round
    NSColor(red: 0.30, green: 0.52, blue: 0.20, alpha: 1).setStroke()
    place(midrib).stroke()

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
