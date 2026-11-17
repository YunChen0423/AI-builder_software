import AppKit
import SwiftUI

final class AppModel: ObservableObject {
    @Published var preferences: Preferences {
        didSet {
            var checked = preferences; checked.validate()
            if checked != preferences { preferences = checked; return }
            if persistPreferences, let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: "preferences.v1") }
            music.setVolume(preferences.volume)
        }
    }
    @Published var session = Session()
    @Published var energy = 0.0
    @Published var response = MusicResponse()
    @Published var geometryExpanded = false
    @Published var audioMessage = "内置原创节奏 · 无需音乐账户"
    @Published var bridgeMessage = "硬件模拟 · 尚未连接三气囊控制器"
    let music = MusicController()
    let bridge = HardwareBridge()
    var onPhase: ((SessionPhase) -> Void)?
    private var persistPreferences = true
    private var timer: Timer?
    private var previousTime = ProcessInfo.processInfo.systemUptime
    private var sequence: UInt64 = 0
    private var lastPhase: SessionPhase = .working
    private var sleeping = false
    var air: [Double] { airTargets(resting: session.phase == .resting, energy: energy, time: response.phase, intensity: preferences.intensity) }
    var colors: [NSColor] { musicPalette(preferences.palette, response: response) }
    var status: String {
        switch session.phase {
        case .resting: return "现在，把时间还给自己"
        case .paused: return "提醒已暂停"
        case .working:
            if session.snoozeRemaining > 0 { return "稍后再来 · 还剩 \(clock(session.snoozeRemaining))" }
            if preferences.contactMode == .sensor && !session.sensorConnected { return "等待腕托接触信号"
            }
            return "安静承托，专注此刻"
        }
    }
    var progress: Double { min(1, session.workElapsed / (preferences.workMinutes * 60)) }
    init(testing: Bool = false) {
        persistPreferences = !testing
        var p = Preferences()
        if !testing, let data = UserDefaults.standard.data(forKey: "preferences.v1"), let saved = try? JSONDecoder().decode(Preferences.self, from: data) { p = saved }
        p.validate(); preferences = p
        music.system.onError = { [weak self] text in self?.music.message = text; self?.audioMessage = text }
        bridge.onContact = { [weak self] pressed in self?.session.receiveContact(pressed) }
        bridge.onDisconnect = { [weak self] in self?.session.sensorAge = .infinity; self?.session.hasContact = false }
        bridge.onStatus = { [weak self] text in self?.bridgeMessage = text }
        if !testing {
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer!, forMode: .common)
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        }
    }
    @objc private func willSleep() { sleeping = true; finish(); session.sensorAge = .infinity }
    @objc private func didWake() { sleeping = false; previousTime = ProcessInfo.processInfo.systemUptime; session.finish(); synchronize() }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = now - previousTime; previousTime = now
        guard !sleeping else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        session.tick(delta: delta, computerIdle: idle, preferences: preferences)
        synchronize()
        let features = session.phase == .resting ? music.features() : AudioFeatures()
        response.advance(features, delta: delta)
        energy = response.energy
        audioMessage = music.message
        sequence &+= 1
        let lit = session.phase == .resting ? preferences.brightness * (0.2 + 0.8 * energy) : (preferences.quietLight ? 0.035 : 0)
        let colors = (0..<3).map { index -> [Int] in
            let c = self.colors[index].usingColorSpace(.deviceRGB)!
            return [Int(c.redComponent * 255 * lit), Int(c.greenComponent * 255 * lit), Int(c.blueComponent * 255 * lit)]
        }
        bridge.send(AirFrame(sequence: sequence, mode: session.phase.rawValue, air: air, rgb: colors, contact: session.sensorConnected ? session.hasContact : nil))
    }
    private func synchronize() {
        guard session.phase != lastPhase else { return }
        lastPhase = session.phase
        if session.phase == .resting { response = MusicResponse(); music.play(preferences) }
        else { music.stop(); energy = 0; response = MusicResponse() }
        onPhase?(session.phase)
    }
    func startRest() { session.startRest(seconds: preferences.restMinutes * 60); synchronize() }
    func finish() { session.finish(); synchronize() }
    func snooze() { session.snooze(); synchronize() }
    func pause() { session.togglePause(); synchronize() }
    func replay() { if session.phase == .resting { music.play(preferences); audioMessage = music.message } }
    func chooseMusic() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preferences.localPath = url.path; preferences.source = .local; replay()
    }
    func toggleBridge() {
        if bridge.enabled { bridge.stop(); bridgeMessage = "本机接口已关闭 · 硬件模拟" }
        else { bridge.start() }
        objectWillChange.send()
    }
    func shutdown() { timer?.invalidate(); music.stop(); bridge.stop() }
}

func clock(_ seconds: Double) -> String {
    let value = max(0, Int(ceil(seconds)))
    return String(format: "%02d:%02d", value / 60, value % 60)
}
func paletteColors(_ palette: Palette) -> [NSColor] {
    switch palette {
    case .iris: return [NSColor(hex: 0x5747FF), NSColor(hex: 0xFF30B8), NSColor(hex: 0x00D9FF)]
    case .sunrise: return [NSColor(hex: 0xFF3D00), NSColor(hex: 0xFF1268), NSColor(hex: 0xFFB800)]
    case .lagoon: return [NSColor(hex: 0x00E29A), NSColor(hex: 0x009BFF), NSColor(hex: 0xB8FF00)]
    case .pearl: return [NSColor(hex: 0xFF2B54), NSColor(hex: 0x38FF6E), NSColor(hex: 0x268BFF)]
    }
}
extension NSColor {
    convenience init(hex: UInt32) { self.init(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1) }
}

func musicPalette(_ palette: Palette, response: MusicResponse) -> [NSColor] {
    paletteColors(palette).enumerated().map { index, base in
        var hue: CGFloat = 0, saturation: CGFloat = 0, value: CGFloat = 0, alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &value, alpha: &alpha)
        let travel = response.hueTravel * 0.65
        let shift = travel + response.treble * 0.04 * sin(Double(index) * 2.1 + response.phase)
        let nextHue = (Double(hue) + shift).truncatingRemainder(dividingBy: 1)
        return NSColor(calibratedHue: nextHue < 0 ? nextHue + 1 : nextHue, saturation: max(0.8, saturation), brightness: 1, alpha: 1)
    }
}
