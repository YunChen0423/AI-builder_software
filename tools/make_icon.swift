import AppKit

let destination = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 215, yRadius: 215)
NSGradient(starting: NSColor(srgbRed: 0.97, green: 0.98, blue: 1.0, alpha: 1), ending: NSColor(srgbRed: 0.86, green: 0.93, blue: 1.0, alpha: 1))!.draw(in: background, angle: -40)
func fill(_ path: NSBezierPath, _ color: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = color.withAlphaComponent(0.4); shadow.shadowBlurRadius = 35; shadow.shadowOffset = NSSize(width: 0, height: -10); shadow.set()
    NSGradient(starting: .white, ending: color)!.draw(in: path, angle: -70)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.75).setStroke(); path.lineWidth = 4; path.stroke()
}
for right in [false, true] {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: right ? 665 : 359, yBy: 595)
    transform.rotate(byDegrees: right ? -17 : 17); transform.concat()
    let pouch = NSBezierPath(roundedRect: NSRect(x: -145, y: -143, width: 290, height: 286), xRadius: 96, yRadius: 96)
    fill(pouch, right ? NSColor(srgbRed: 0, green: 0.85, blue: 1, alpha: 1) : NSColor(srgbRed: 0.26, green: 0.19, blue: 1, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()
}
let middle = NSBezierPath(roundedRect: NSRect(x: 362, y: 285, width: 300, height: 286), xRadius: 98, yRadius: 98)
fill(middle, NSColor(srgbRed: 1, green: 0.06, blue: 0.64, alpha: 1))
image.unlockFocus()
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for retina in [false, true] {
        let pixels = size * (retina ? 2 : 1)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(retina ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination).appendingPathComponent(name))
    }
}
