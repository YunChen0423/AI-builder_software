import Foundation
import CoreGraphics

/// A large right-click region follows the artwork, leaving a short trail so there is no chasing.
/// This only decides whether to show our menu; it never intercepts normal left clicks.
struct RightClickRegion {
    private var history: [(time: Double, rect: CGRect)] = []
    mutating func track(_ frame: CGRect, now: Double) {
        history.removeAll { now - $0.time > 1.8 }
        if let last = history.last, now - last.time < 0.1 { return }
        history.append((now, frame.insetBy(dx: -110, dy: -95)))
    }
    func contains(_ point: CGPoint, now: Double) -> Bool {
        history.contains { now - $0.time <= 1.8 && $0.rect.contains(point) }
    }
    mutating func reset() { history.removeAll() }
}
