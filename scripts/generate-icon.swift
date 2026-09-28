import AppKit

// Run `swift scripts/generate-icon.swift` from the project root, then ./build.sh.
// Render the 1024px master without external artwork tools; build.sh derives the icon sizes.
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current!.imageInterpolation = .high

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}
func fill(_ path: NSBezierPath, _ hex: UInt32) {
    color(hex).setFill()
    path.fill()
}
func gradient(_ path: NSBezierPath, _ top: UInt32, _ bottom: UInt32) {
    NSGradient(starting: color(bottom), ending: color(top))!.draw(in: path, angle: 90)
}
func shadow(_ blur: CGFloat, _ y: CGFloat, _ alpha: CGFloat, draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(alpha)
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: y)
    s.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

let tile = rounded(64, 64, 896, 896, 202)
shadow(18, -9, 0.3) { fill(tile, 0x152C43) }
gradient(tile, 0x264860, 0x0B192B)
color(0x426078).withAlphaComponent(0.65).setStroke()
tile.lineWidth = 3
tile.stroke()

// A machined drive body gives the destructive utility a stable, recognizable silhouette.
let drive = rounded(246, 203, 532, 626, 66)
shadow(28, -20, 0.45) { fill(drive, 0xB3C3CE) }
gradient(drive, 0xF4F8FA, 0x91A6B5)
let face = rounded(266, 244, 492, 561, 49)
gradient(face, 0xDDE7ED, 0xB8C9D4)
color(0xFFFFFF).withAlphaComponent(0.8).setStroke()
face.lineWidth = 3
face.stroke()
fill(rounded(308, 225, 293, 9, 4.5), 0x5C7283)
fill(rounded(673, 224, 35, 11, 5.5), 0x62E3CC)
for x: CGFloat in [296, 728] {
    for y: CGFloat in [282, 769] {
        fill(NSBezierPath(ovalIn: NSRect(x: x - 9, y: y - 9, width: 18, height: 18)), 0x8196A6)
        let slot = NSBezierPath()
        slot.move(to: NSPoint(x: x - 4, y: y))
        slot.line(to: NSPoint(x: x + 4, y: y))
        color(0xDDE7ED).setStroke()
        slot.lineWidth = 2
        slot.stroke()
    }
}

let shield = NSBezierPath()
shield.move(to: NSPoint(x: 512, y: 726))
shield.curve(to: NSPoint(x: 681, y: 660), controlPoint1: NSPoint(x: 560, y: 696), controlPoint2: NSPoint(x: 615, y: 671))
shield.line(to: NSPoint(x: 672, y: 553))
shield.curve(to: NSPoint(x: 512, y: 363), controlPoint1: NSPoint(x: 665, y: 461), controlPoint2: NSPoint(x: 600, y: 400))
shield.curve(to: NSPoint(x: 352, y: 553), controlPoint1: NSPoint(x: 424, y: 400), controlPoint2: NSPoint(x: 359, y: 461))
shield.line(to: NSPoint(x: 343, y: 660))
shield.curve(to: NSPoint(x: 512, y: 726), controlPoint1: NSPoint(x: 409, y: 671), controlPoint2: NSPoint(x: 464, y: 696))
shield.close()
shadow(12, -8, 0.24) { fill(shield, 0x126E7A) }
gradient(shield, 0x39C5C0, 0x096272)
color(0xA2F1E2).withAlphaComponent(0.8).setStroke()
shield.lineWidth = 5
shield.stroke()

// A single eraser crosses the shield; no tiny text or security guarantees in the artwork.
NSGraphicsContext.saveGraphicsState()
let transform = AffineTransform(translationByX: 587, byY: 361)
(transform as NSAffineTransform).concat()
let rotation = NSAffineTransform()
rotation.rotate(byDegrees: 36)
rotation.concat()
let eraser = rounded(-147, -60, 294, 120, 24)
shadow(14, -9, 0.32) { fill(eraser, 0xF6C2B5) }
gradient(eraser, 0xFFE1D4, 0xE89486)
NSGraphicsContext.saveGraphicsState()
eraser.addClip()
gradient(rounded(18, -60, 129, 120, 0), 0xEFF3F4, 0xB4C6D1)
fill(rounded(14, -60, 6, 120, 0), 0x8FABB7)
NSGraphicsContext.restoreGraphicsState()
color(0xFFFFFF).withAlphaComponent(0.6).setStroke()
eraser.lineWidth = 3
eraser.stroke()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()

let destination = URL(fileURLWithPath: "Resources/AppIcon.png")
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
print("Generated \(destination.path)")
