import AppKit

private struct GeometryField {
    let born: Double
    let center: CGPoint
    let radius: Double
    let seed: Int
    let style: FireworkStyle
}

/// Screen-sized, click-through, parametric geometric light compositions.
final class FireworksView: NSView {
    weak var model: AppModel?
    private var timer: Timer?
    private var fields: [GeometryField] = []
    private var nextLaunch = 0.0
    private var lastBeat = 0.0
    private var previousEnergy = 0.0
    private var serial = 0
    private var activeStyle: FireworkStyle?
    var frozenTime: Double?
    override var isOpaque: Bool { false }
    func start() {
        stop(); nextLaunch = ProcessInfo.processInfo.systemUptime
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 45, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func stop() { timer?.invalidate(); timer = nil; fields.removeAll(); needsDisplay = true }
    deinit { timer?.invalidate() }
    private func launch(_ now: Double) {
        serial += 1
        let seed = serial * 179
        fields.append(GeometryField(born: now,
                                    center: CGPoint(x: bounds.width * (0.1 + geometricNoise(seed) * 0.8), y: bounds.height * (0.15 + geometricNoise(seed + 1) * 0.7)),
                                    radius: min(bounds.width, bounds.height) * (0.23 + geometricNoise(seed + 2) * 0.20),
                                    seed: seed, style: model?.preferences.fireworkStyle ?? .mixed))
    }
    private func tick() {
        guard let model, model.session.phase == .resting, model.preferences.fireworks else { fields.removeAll(); needsDisplay = true; return }
        let now = ProcessInfo.processInfo.systemUptime
        if activeStyle != model.preferences.fireworkStyle {
            activeStyle = model.preferences.fireworkStyle; fields.removeAll(); nextLaunch = now
        }
        let energy = model.energy
        let beat = energy - previousEnergy > 0.08 && now - lastBeat > 0.27
        if now >= nextLaunch || beat {
            launch(now)
            if beat { lastBeat = now }
            nextLaunch = now + 0.95 - model.preferences.intensity * 0.38 - energy * 0.2
        }
        previousEnergy = energy
        fields.removeAll { now - $0.born > 3.4 }
        if fields.count > 8 { fields.removeFirst(fields.count - 8) }
        needsDisplay = true
    }
    func prepareSnapshot() {
        let now = ProcessInfo.processInfo.systemUptime
        frozenTime = now; fields.removeAll()
        for i in 0..<6 { launch(now - 0.3 - Double(i) * 0.34) }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let model, model.preferences.fireworks else { return }
        let now = frozenTime ?? ProcessInfo.processInfo.systemUptime
        let p = model.preferences, colors = model.colors
        let count = 36 + Int(p.particleDensity * 114)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        for field in fields {
            let age = now - field.born
            guard age >= 0 else { continue }
            let fade = min(1, age * 9) * pow(max(0, 1 - age / 3.4), 1.1)
            for colorIndex in 0..<3 {
                let color = colors[(colorIndex + field.seed) % 3]
                let strokes = CGMutablePath(), solids = CGMutablePath()
                for i in stride(from: colorIndex, to: count, by: 3) {
                    func position(_ t: Double) -> CGPoint {
                        let point = geometricParticle(style: field.style, index: i, count: count, seed: field.seed, age: t, spread: p.particleSpread, spin: p.particleSpin)
                        return CGPoint(x: field.center.x + point.x * field.radius, y: field.center.y + point.y * field.radius)
                    }
                    let point = position(age)
                    let kind = p.particleElement == .mixed ? [ParticleElement.dots, .strokes, .arcs, .shards][(i + field.seed) % 4] : p.particleElement
                    let size = 1.3 + geometricNoise(field.seed + i) * 3.1
                    let theta = Double(i) * 2.39996 + age * (p.particleSpin - 0.5) * 7
                    switch kind {
                    case .dots:
                        solids.addEllipse(in: CGRect(x: point.x - size, y: point.y - size, width: size * 2, height: size * 2))
                        if p.particleTrail > 0.25 { strokes.move(to: position(max(0, age - p.particleTrail * 0.12))); strokes.addLine(to: point) }
                    case .arcs:
                        let radius = 6 + size * 2 + p.particleSpread * 12
                        strokes.move(to: CGPoint(x: point.x + cos(theta) * radius, y: point.y + sin(theta) * radius))
                        strokes.addArc(center: point, radius: radius, startAngle: theta, endAngle: theta + 0.6 + p.particleTrail * 1.8, clockwise: false)
                    case .shards:
                        let length = 5 + size * 2
                        let dx = cos(theta), dy = sin(theta)
                        solids.move(to: CGPoint(x: point.x + dx * length, y: point.y + dy * length))
                        solids.addLine(to: CGPoint(x: point.x - dy * size, y: point.y + dx * size))
                        solids.addLine(to: CGPoint(x: point.x - dx * length, y: point.y - dy * length))
                        solids.addLine(to: CGPoint(x: point.x + dy * size, y: point.y - dx * size)); solids.closeSubpath()
                    default:
                        let length = 0.045 + p.particleTrail * 0.4
                        strokes.move(to: position(max(0, age - length)))
                        for step in 1...4 { strokes.addLine(to: position(max(0, age - length + length * Double(step) / 4))) }
                        // Retain visible geometry even at the tail of an expansion.
                        strokes.move(to: point); strokes.addLine(to: CGPoint(x: point.x + cos(theta) * (3 + size), y: point.y + sin(theta) * (3 + size)))
                    }
                }
                let alpha = fade * (0.2 + p.brightness * 0.8)
                ctx.setShadow(offset: .zero, blur: 8, color: color.withAlphaComponent(alpha * 0.8).cgColor)
                ctx.setStrokeColor(color.withAlphaComponent(alpha).cgColor); ctx.setLineWidth(1.4 + p.brightness)
                ctx.addPath(strokes); ctx.strokePath()
                ctx.setFillColor(color.withAlphaComponent(alpha).cgColor); ctx.addPath(solids); ctx.fillPath()
            }
        }
    }
}
