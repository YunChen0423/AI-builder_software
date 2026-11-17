import Foundation

func geometricNoise(_ seed: Int) -> Double {
    let value = sin(Double(seed) * 127.1 + 311.7) * 43758.5453123
    return value - floor(value)
}

/// A continuous particle field, composed from radial expansion, angular flow,
/// layered waves and affine shear. No outlines of objects or literal motifs.
func geometricParticle(style: FireworkStyle, index: Int, count: Int, seed: Int,
                       age: Double, spread: Double, spin: Double) -> (x: Double, y: Double) {
    let t = max(0, age)
    let q = geometricNoise(seed + index * 17)
    let angle = Double(index) * 2.399963229728653 + Double(seed) * 0.031
    let reach = (1 - exp(-t * 2.1)) * (0.32 + q * 0.75) * (0.35 + spread * 0.95)
    let rotation = (spin - 0.5) * 7
    let resolved = style == .mixed ? [FireworkStyle.radial, .vortex, .wave, .scatter][abs(seed) % 4] : style
    var theta = angle, radius = reach, x = 0.0, y = 0.0
    switch resolved {
    case .vortex:
        theta += rotation * t + t * (0.7 + q * 1.4)
        radius *= 0.7 + 0.25 * sin(Double(index % 5) + t * 2)
        x = cos(theta) * radius; y = sin(theta) * radius
    case .wave:
        theta += rotation * t * 0.35
        let layer = Double(index % 4) / 4
        radius = reach * (0.35 + layer * 0.85) + sin(t * 3 - layer * 4) * 0.06
        x = cos(theta) * radius; y = sin(theta) * radius * (0.6 + 0.15 * sin(t))
        x += sin(y * 4 + t * 2) * 0.14 * min(1, t)
    case .scatter:
        let direction = (Double(index % 8) / 8) * .pi * 2 + rotation * t * 0.15
        x = cos(direction) * reach + (q - 0.5) * t * 0.18
        y = sin(direction) * reach * 0.7
        x += y * (0.3 + spin * 0.7); y -= t * t * 0.045
    default:
        theta += rotation * t * 0.3
        x = cos(theta) * radius; y = sin(theta) * radius - t * t * 0.025
    }
    return (x, y)
}
