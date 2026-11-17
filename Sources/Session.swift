import Foundation

enum SessionPhase: String, Codable { case working, resting, paused }
enum ContactMode: String, Codable, CaseIterable { case computer, sensor }
enum MusicSource: String, Codable, CaseIterable { case builtIn, local, appleMusic, netease, spotify }
enum Palette: String, Codable, CaseIterable { case iris, sunrise, lagoon, pearl }

enum FireworkStyle: String, Codable, CaseIterable {
    // Retain persisted raw values from v0.3, while replacing the literal shapes entirely.
    case mixed, radial = "circle", vortex = "flower", wave = "heart", scatter = "willow"
    var title: String {
        switch self { case .mixed: return "随机组合"; case .radial: return "径向脉冲"; case .vortex: return "旋涡流场"; case .wave: return "波纹叠层"; case .scatter: return "几何散射" }
    }
}
enum ParticleElement: String, Codable, CaseIterable {
    case mixed, dots, strokes, arcs, shards
    var title: String {
        switch self { case .mixed: return "混合几何"; case .dots: return "光点"; case .strokes: return "线段"; case .arcs: return "圆弧"; case .shards: return "棱片" }
    }
}
enum MotionStyle: String, Codable, CaseIterable {
    case bounce, orbit, zigzag, float, inPlace
    var title: String {
        switch self { case .bounce: return "蹦蹦跳跳"; case .orbit: return "绕圈飞舞"; case .zigzag: return "左右冲刺"; case .float: return "轻盈漂浮"; case .inPlace: return "原地起舞" }
    }
}

struct Preferences: Codable, Equatable {
    var workMinutes = 45.0
    var restMinutes = 3.0
    var intensity = 0.8
    var brightness = 0.55
    var volume = 0.35
    var palette: Palette = .iris
    var source: MusicSource = .builtIn
    var localPath = ""
    var playlist = ""
    var contactMode: ContactMode = .computer
    var fireworkStyle: FireworkStyle = .mixed
    var motionStyle: MotionStyle = .bounce
    var particleElement: ParticleElement = .mixed
    var particleSpread = 0.65
    var particleSpin = 0.55
    var particleDensity = 0.55
    var particleTrail = 0.5
    var fireworks = true
    var roaming = true
    var quietLight = false
    var autoReminder = true

    init() {}
    enum CodingKeys: String, CodingKey { case workMinutes, restMinutes, intensity, brightness, volume, palette, source, localPath, playlist, contactMode, fireworks, roaming, quietLight, autoReminder, fireworkStyle, motionStyle, particleElement, particleSpread, particleSpin, particleDensity, particleTrail }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workMinutes = try c.decodeIfPresent(Double.self, forKey: .workMinutes) ?? workMinutes
        restMinutes = try c.decodeIfPresent(Double.self, forKey: .restMinutes) ?? restMinutes
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? intensity
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? brightness
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? volume
        palette = try c.decodeIfPresent(Palette.self, forKey: .palette) ?? palette
        source = try c.decodeIfPresent(MusicSource.self, forKey: .source) ?? source
        localPath = try c.decodeIfPresent(String.self, forKey: .localPath) ?? localPath
        playlist = try c.decodeIfPresent(String.self, forKey: .playlist) ?? playlist
        contactMode = try c.decodeIfPresent(ContactMode.self, forKey: .contactMode) ?? contactMode
        fireworks = try c.decodeIfPresent(Bool.self, forKey: .fireworks) ?? fireworks
        roaming = try c.decodeIfPresent(Bool.self, forKey: .roaming) ?? roaming
        quietLight = try c.decodeIfPresent(Bool.self, forKey: .quietLight) ?? quietLight
        autoReminder = try c.decodeIfPresent(Bool.self, forKey: .autoReminder) ?? autoReminder
        fireworkStyle = try c.decodeIfPresent(FireworkStyle.self, forKey: .fireworkStyle) ?? fireworkStyle
        motionStyle = try c.decodeIfPresent(MotionStyle.self, forKey: .motionStyle) ?? motionStyle
        particleElement = try c.decodeIfPresent(ParticleElement.self, forKey: .particleElement) ?? particleElement
        particleSpread = try c.decodeIfPresent(Double.self, forKey: .particleSpread) ?? particleSpread
        particleSpin = try c.decodeIfPresent(Double.self, forKey: .particleSpin) ?? particleSpin
        particleDensity = try c.decodeIfPresent(Double.self, forKey: .particleDensity) ?? particleDensity
        particleTrail = try c.decodeIfPresent(Double.self, forKey: .particleTrail) ?? particleTrail
        validate()
    }

    mutating func validate() {
        workMinutes = workMinutes.isFinite ? min(120, max(1, workMinutes)) : 45
        restMinutes = restMinutes.isFinite ? min(15, max(0.25, restMinutes)) : 3
        intensity = intensity.isFinite ? min(1, max(0, intensity)) : 0.45
        brightness = brightness.isFinite ? min(1, max(0, brightness)) : 0.55
        particleSpread = particleSpread.isFinite ? min(1, max(0, particleSpread)) : 0.65
        particleSpin = particleSpin.isFinite ? min(1, max(0, particleSpin)) : 0.55
        particleDensity = particleDensity.isFinite ? min(1, max(0, particleDensity)) : 0.55
        particleTrail = particleTrail.isFinite ? min(1, max(0, particleTrail)) : 0.5
        volume = volume.isFinite ? min(1, max(0, volume)) : 0.35
    }
}

/// Pure state machine. All elapsed time is monotonic and excludes sleep / long scheduler gaps.
struct Session {
    var phase: SessionPhase = .working
    var workElapsed = 0.0
    var restRemaining = 0.0
    var completed = 0
    var snoozeRemaining = 0.0
    var hasContact = false
    var sensorAge = Double.infinity
    var sensorAwayElapsed = 0.0
    var sensorConnected: Bool { sensorAge < 3 }

    mutating func tick(delta: Double, computerIdle: Double, preferences p: Preferences) {
        guard delta > 0, delta < 3 else { return }
        sensorAge += delta
        switch phase {
        case .paused: return
        case .resting:
            restRemaining = max(0, restRemaining - delta)
            if restRemaining == 0 { completed += 1; finish() }
        case .working:
            if computerIdle >= 300 && p.contactMode == .computer {
                workElapsed = 0; snoozeRemaining = 0
            }
            let active = p.contactMode == .sensor ? (sensorConnected && hasContact) : computerIdle < 60
            if p.contactMode == .sensor {
                sensorAwayElapsed = active ? 0 : sensorAwayElapsed + delta
                if sensorAwayElapsed >= 300 { workElapsed = 0; snoozeRemaining = 0 }
            }
            guard active, p.autoReminder else { return }
            if snoozeRemaining > 0 {
                snoozeRemaining = max(0, snoozeRemaining - delta)
                if snoozeRemaining == 0 { startRest(seconds: p.restMinutes * 60) }
                return
            }
            workElapsed += delta
            if workElapsed >= p.workMinutes * 60 { startRest(seconds: p.restMinutes * 60) }
        }
    }
    mutating func receiveContact(_ value: Bool) { hasContact = value; sensorAge = 0 }
    mutating func startRest(seconds: Double) { phase = .resting; restRemaining = seconds; snoozeRemaining = 0 }
    mutating func finish() { phase = .working; workElapsed = 0; restRemaining = 0; snoozeRemaining = 0 }
    mutating func snooze() { finish(); snoozeRemaining = 300 }
    mutating func togglePause() { phase = phase == .paused ? .working : .paused; restRemaining = 0 }
}

struct AirFrame: Codable {
    var type = "target"
    var version = 1
    var sequence: UInt64
    var mode: String
    /// Normalized design targets, never measured pressure or valve timings.
    var air: [Double]
    var rgb: [[Int]]
    var ttl_ms = 750
    var simulated = true
    var contact: Bool? = nil
}

func airTargets(resting: Bool, energy: Double, time: Double, intensity: Double) -> [Double] {
    guard resting else { return [1, 0.6, 1] } // left, center, right
    let e = min(1, max(0, energy) * (0.55 + intensity * 0.75))
    // These are visual / simulated targets. Real pneumatic rate limits belong in the adapter.
    let left = pow(max(0, sin(time * 6.0)), 1.5)
    let right = pow(max(0, sin(time * 6.0 + .pi)), 1.5)
    return [0.04 + e * 0.92 * left,
            1 - e * 0.64 * (0.5 + 0.5 * cos(time * 6.4)),
            0.04 + e * 0.92 * right]
}

/// Normalized trajectory, independent of screen geometry and pause state.
func motionPosition(style: MotionStyle, time: Double, intensity: Double) -> (x: Double, y: Double) {
    let t = max(0, time) * (0.32 + intensity * 0.66)
    switch style {
    case .bounce: return (0.5 + 0.48 * sin(t), 0.12 + 0.76 * abs(sin(t * 0.79)))
    case .orbit: return (0.5 + 0.43 * sin(t), 0.5 - 0.40 * cos(t))
    case .zigzag: return (0.5 + 0.47 * (2 / .pi) * asin(sin(t * 1.8)), 0.38 + 0.32 * sin(t * 0.91))
    case .float: return (0.5 + 0.38 * sin(t * 0.43), 0.4 + 0.23 * sin(t * 0.59))
    case .inPlace: return (0.5, 0.12)
    }
}
