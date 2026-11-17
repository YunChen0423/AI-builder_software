import AppKit
import SwiftUI

final class SculptureView: NSView {
    weak var model: AppModel?
    var preview = false
    var forcedTime: Double?
    var contextAction: ((NSEvent) -> Void)?
    var doubleClick: (() -> Void)?
    var dragEnded: (() -> Void)?
    private var animation: Timer?
    private(set) var interactionPaused = false
    private var pauseClock = 0.0
    private var clockOffset = 0.0
    private var pausedResponse: MusicResponse?
    private var paintedPaths: [CGPath] = []
    private var hotPath: CGPath?
    private(set) var lastPaintBounds = CGRect.zero
    override var isOpaque: Bool { false }
    private var currentClock: Double { model?.response.phase ?? 0 }
    func resetAnimation() {
        interactionPaused = false; pausedResponse = nil; clockOffset = 0; pauseClock = currentClock
    }
    func setInteractionPaused(_ paused: Bool) {
        guard paused != interactionPaused else { return }
        if paused { pauseClock = currentClock; pausedResponse = model?.response }
        else { clockOffset += currentClock - pauseClock; pausedResponse = nil }
        interactionPaused = paused; needsDisplay = true
    }
    func containsScreenPoint(_ point: CGPoint, hotZone: Bool) -> Bool {
        guard let window else { return false }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        if hotZone { return hotPath?.contains(local) ?? false }
        return paintedPaths.contains { $0.contains(local) }
    }
    var interactionCenterOnScreen: CGPoint? {
        guard let window, let hotPath else { return nil }
        let point = CGPoint(x: hotPath.boundingBox.midX, y: hotPath.boundingBox.midY)
        return window.convertPoint(toScreen: convert(point, to: nil))
    }
    override func viewDidMoveToWindow() {
        animation?.invalidate(); animation = nil
        if window != nil {
            animation = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.needsDisplay = true }
            RunLoop.main.add(animation!, forMode: .common)
        }
    }
    deinit { animation?.invalidate() }
    override func rightMouseDown(with event: NSEvent) { contextAction?(event) }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { doubleClick?(); return }
        guard !preview else { return }
        window?.performDrag(with: event); dragEnded?()
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let p = model?.preferences ?? Preferences()
        let resting = model?.session.phase == .resting
        let response = pausedResponse ?? model?.response ?? MusicResponse()
        let t = forcedTime ?? (response.phase - clockOffset)
        let energy = response.energy
        let drive = min(1, energy * (0.6 + p.intensity * 0.8))
        let tempo = p.motionStyle == .float ? 0.45 : (p.motionStyle == .zigzag ? 1.35 : 1.0)
        let targets = airTargets(resting: resting, energy: energy, time: t * tempo, intensity: p.intensity)
        let colors = model?.colors ?? paletteColors(p.palette)
        let dance = resting ? 0.06 + drive * (0.4 + p.intensity) : 0.03
        var hop = sin(t) * 2.0, sway = 0.0, tilt = 0.0
        if resting {
            switch p.motionStyle {
            case .bounce, .inPlace:
                hop = abs(sin(t * 5)) * 30 * dance + response.beat * 22
                sway = sin(t * 4) * 16 * dance; tilt = sin(t * 4.1) * 0.23 * dance
            case .orbit:
                hop = 16 + sin(t * 3.5) * 16 * dance + response.beat * 12
                sway = cos(t * 3.5) * 24 * dance; tilt = sin(t * 3.5) * 0.34 * dance
            case .zigzag:
                hop = abs(sin(t * 6)) * 19 * dance + response.beat * 16
                sway = sin(t * 9) * 24 * dance; tilt = sin(t * 6) * 0.22 * dance
            case .float:
                hop = 12 + sin(t * 1.5) * 10 * dance + response.beat * 6
                sway = sin(t * 1.2) * 13 * dance; tilt = sin(t * 1.2) * 0.10 * dance
            }
        }
        let pump = pow(max(0, sin(t * 5.2 * tempo)), 2)
        let scaleX = 1 + (resting ? drive * (0.15 - pump * 0.22) : 0)
        let scaleY = 1 + (resting ? drive * (pump * 0.22 - 0.06) + response.beat * 0.07 : 0)
        var global = CGAffineTransform(translationX: sway, y: hop).rotated(by: tilt).scaledBy(x: scaleX, y: scaleY)
        var chambers: [(CGPath, Int)] = []
        for side in [-1.0, 1.0] {
            let index = side < 0 ? 0 : 2, fullness = targets[index]
            let width = 100 + fullness * 16, height = 52 + sqrt(fullness) * 62
            let pillow = softPanel(width: width, height: height)
            let flutter = sin(t * 2.8 + side * 0.7) * drive * 0.07
            var placement = CGAffineTransform(translationX: side * 58, y: 28 + fullness * 22)
                .rotated(by: -side * (0.22 + (1 - fullness) * 0.15) + flutter)
            let placed = pillow.copy(using: &placement)!
            chambers.append((placed.copy(using: &global)!, index))
        }
        let centerWidth = 108 + targets[1] * 8, centerHeight = 58 + sqrt(targets[1]) * 56
        let middle = softPanel(width: centerWidth, height: centerHeight)
        var centerPlacement = CGAffineTransform(translationX: 0, y: -24 + response.beat * 3)
            .rotated(by: sin(t * 2.1) * drive * 0.035)
        let centerPath = middle.copy(using: &centerPlacement)!
        chambers.append((centerPath.copy(using: &global)!, 1))
        let rawBounds = chambers.reduce(CGRect.null) { $0.union($1.0.boundingBoxOfPath) }
        // Fit the entire transformed silhouette, then reserve room for the largest LED glow.
        let margin = 64.0
        let fit = min(0.98, min((bounds.width - margin * 2) / rawBounds.width, (bounds.height - margin * 2) / rawBounds.height))
        var layout = CGAffineTransform(a: fit, b: 0, c: 0, d: fit, tx: bounds.midX, ty: bounds.height * 0.40)
        let located = rawBounds.applying(layout)
        layout.tx += max(margin - located.minX, min(0, bounds.width - margin - located.maxX))
        layout.ty += max(margin - located.minY, min(0, bounds.height - margin - located.maxY))
        paintedPaths = chambers.map { $0.0.copy(using: &layout)! }
        lastPaintBounds = paintedPaths.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
        let core = CGPath(ellipseIn: CGRect(x: -42, y: -42, width: 84, height: 50), transform: nil)
        hotPath = core.copy(using: &global)?.copy(using: &layout)
        var webPlacement = global.concatenating(layout)
        if let web = CGPath(roundedRect: CGRect(x: -68, y: -18, width: 136, height: 52), cornerWidth: 24, cornerHeight: 24, transform: nil).copy(using: &webPlacement) {
            ctx.addPath(web); ctx.setFillColor(NSColor.white.withAlphaComponent(0.65).cgColor); ctx.fillPath()
        }
        for (index, chamber) in chambers.enumerated() {
            pouch(paintedPaths[index], color: colors[chamber.1], context: ctx,
                  light: resting ? min(1, p.brightness * 1.5 * (0.5 + energy * 0.4 + response.beat * 0.2)) : (p.quietLight ? 0.04 : 0))
        }
    }
    /// A soft superellipse with continuous, bowed sides, rather than a box or capsule.
    private func softPanel(width: Double, height: Double) -> CGPath {
        let count = 32, exponent = 2.0 / 2.65
        let points = (0..<count).map { index -> CGPoint in
            let angle = Double(index) * .pi * 2 / Double(count)
            let x = cos(angle), y = sin(angle)
            return CGPoint(x: (x < 0 ? -1 : 1) * pow(abs(x), exponent) * width / 2,
                           y: (y < 0 ? -1 : 1) * pow(abs(y), exponent) * height / 2)
        }
        let path = CGMutablePath(); path.move(to: points[0])
        for i in 0..<count {
            let p0 = points[(i + count - 1) % count], p1 = points[i]
            let p2 = points[(i + 1) % count], p3 = points[(i + 2) % count]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.closeSubpath(); return path
    }
    private func pouch(_ path: CGPath, color: NSColor, context ctx: CGContext, light: Double) {
        let box = path.boundingBox
        ctx.saveGState()
        // Short, restrained rim glow; the light should feel inside the PVC.
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 7 + light * 5, color: color.withAlphaComponent(light * 0.25).cgColor)
        ctx.addPath(path); ctx.setFillColor(NSColor.white.withAlphaComponent(0.95).cgColor); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        let film = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor.white.cgColor, NSColor(hex: 0xEAF1F6).withAlphaComponent(0.96).cgColor, NSColor(hex: 0xCBD7E1).withAlphaComponent(0.93).cgColor] as CFArray, locations: [0, 0.52, 1])!
        ctx.drawLinearGradient(film, start: CGPoint(x: box.minX, y: box.maxY), end: CGPoint(x: box.maxX, y: box.minY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        let led = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color.withAlphaComponent(light * 0.95).cgColor, color.withAlphaComponent(light * 0.82).cgColor, color.withAlphaComponent(light * 0.08).cgColor] as CFArray, locations: [0, 0.43, 1])!
        let source = CGPoint(x: box.midX, y: box.minY + box.height * 0.25)
        ctx.drawRadialGradient(led, startCenter: source, startRadius: 0, endCenter: source, endRadius: max(box.width, box.height) * 0.8, options: [.drawsAfterEndLocation])
        // Broad soft highlight gives the panel volume without a hard glossy stripe.
        let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor.white.withAlphaComponent(0.52).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        let highlight = CGPoint(x: box.minX + box.width * 0.32, y: box.minY + box.height * 0.79)
        ctx.drawRadialGradient(sheen, startCenter: highlight, startRadius: 0, endCenter: highlight, endRadius: box.width * 0.6, options: [])
        for i in 0..<150 {
            let x = box.minX + geometricNoise(i * 3 + 11) * box.width, y = box.minY + geometricNoise(i * 3 + 12) * box.height
            let size = 0.35 + geometricNoise(i * 3 + 13) * 0.5
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.07).cgColor)
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
        }
        ctx.addPath(path); ctx.setLineWidth(5); ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.3).cgColor); ctx.strokePath()
        ctx.restoreGState()
        ctx.addPath(path); ctx.setLineWidth(0.85); ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.82).cgColor); ctx.strokePath()
    }

}

struct SculpturePreview: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeNSView(context: Context) -> SculptureView { let view = SculptureView(); view.model = model; view.preview = true; return view }
    func updateNSView(_ nsView: SculptureView, context: Context) { nsView.needsDisplay = true }
}
