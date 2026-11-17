import Foundation

@main struct SessionTests {
    static func main() {
        var p = Preferences(); p.workMinutes = 1; p.restMinutes = 0.25
        var s = Session()
        for _ in 0..<59 { s.tick(delta: 1, computerIdle: 0, preferences: p) }
        assert(s.phase == .working && s.workElapsed == 59)
        s.tick(delta: 1, computerIdle: 0, preferences: p)
        assert(s.phase == .resting && s.restRemaining == 15)
        for _ in 0..<15 { s.tick(delta: 1, computerIdle: 0, preferences: p) }
        assert(s.phase == .working && s.completed == 1 && s.workElapsed == 0)
        s.tick(delta: 1, computerIdle: 80, preferences: p); assert(s.workElapsed == 0)
        s.tick(delta: 1, computerIdle: 0, preferences: p)
        s.tick(delta: 1, computerIdle: 301, preferences: p); assert(s.workElapsed == 0)
        s.tick(delta: 3600, computerIdle: 0, preferences: p); assert(s.workElapsed == 0)
        s.snooze()
        for _ in 0..<300 { s.tick(delta: 1, computerIdle: 0, preferences: p) }
        assert(s.workElapsed == 0 && s.phase == .resting)
        s.finish()
        s.togglePause(); s.tick(delta: 1, computerIdle: 0, preferences: p); assert(s.workElapsed == 0 && s.phase == .paused)
        s.togglePause(); p.contactMode = .sensor
        s.tick(delta: 1, computerIdle: 0, preferences: p); assert(s.workElapsed == 0)
        s.receiveContact(true); s.tick(delta: 1, computerIdle: 500, preferences: p); assert(s.workElapsed == 1)
        s.tick(delta: 1, computerIdle: 0, preferences: p)
        s.tick(delta: 1, computerIdle: 0, preferences: p)
        let stale = s.workElapsed
        s.tick(delta: 1, computerIdle: 0, preferences: p); assert(s.workElapsed == stale && !s.sensorConnected)
        s.receiveContact(false); s.tick(delta: 1, computerIdle: 0, preferences: p); assert(s.workElapsed == stale)
        p.workMinutes = .nan; p.intensity = 99; p.volume = -5; p.validate()
        assert(p.workMinutes == 45 && p.intensity == 1 && p.volume == 0)
        assert(airTargets(resting: false, energy: 1, time: 0, intensity: 1) == [1, 0.6, 1])
        for t in stride(from: 0.0, to: 100.0, by: 0.1) {
            let targets = airTargets(resting: true, energy: 1, time: t, intensity: 1)
            assert(targets.allSatisfy { (0...1).contains($0) }); assert(targets[1] >= 0.35)
            assert(targets[0] <= 0.96 && targets[2] <= 0.96)
        }
        let frames = stride(from: 0.0, to: 5.0, by: 0.02).map { airTargets(resting: true, energy: 1, time: $0, intensity: 1) }
        for chamber in 0..<3 {
            let values = frames.map { $0[chamber] }
            assert(values.max()! - values.min()! > 0.6)
        }
        // Existing users must keep their preferences when new appearance options are added.
        var saved = Preferences(); saved.workMinutes = 27; saved.palette = .lagoon
        var legacy = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
        legacy.removeValue(forKey: "fireworkStyle"); legacy.removeValue(forKey: "motionStyle")
        let restored = try! JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: legacy))
        assert(restored.workMinutes == 27 && restored.palette == .lagoon)
        assert(restored.fireworkStyle == .mixed && restored.motionStyle == .bounce)
        for style in MotionStyle.allCases {
            for t in stride(from: 0.0, to: 30, by: 0.05) {
                let point = motionPosition(style: style, time: t, intensity: 1)
                assert((0...1).contains(point.x) && (0...1).contains(point.y))
            }
        }
        for style in FireworkStyle.allCases {
            saved.fireworkStyle = style
            let roundTrip = try! JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(saved))
            assert(roundTrip.fireworkStyle == style)
        }
        for style in FireworkStyle.allCases {
            for element in ParticleElement.allCases {
                saved.fireworkStyle = style; saved.particleElement = element
                let decoded = try! JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(saved))
                assert(decoded.particleElement == element)
                for i in 0..<80 {
                    let point = geometricParticle(style: style, index: i, count: 80, seed: 19, age: Double(i) / 25, spread: 1, spin: 1)
                    assert(point.x.isFinite && point.y.isFinite && abs(point.x) < 5 && abs(point.y) < 5)
                }
            }
        }
        legacy["fireworkStyle"] = "heart"
        let migratedStyle = try! JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: legacy))
        assert(migratedStyle.fireworkStyle == .wave && migratedStyle.particleElement == .mixed)
        saved.particleSpread = .nan; saved.particleSpin = 8; saved.particleTrail = -1; saved.validate()
        assert(saved.particleSpread == 0.65 && saved.particleSpin == 1 && saved.particleTrail == 0)
        let radial = geometricParticle(style: .radial, index: 4, count: 80, seed: 1, age: 1, spread: 0.5, spin: 0.5)
        let vortex = geometricParticle(style: .vortex, index: 4, count: 80, seed: 1, age: 1, spread: 0.5, spin: 0.5)
        assert(abs(radial.x - vortex.x) + abs(radial.y - vortex.y) > 0.01)
        var region = RightClickRegion()
        region.track(CGRect(x: 500, y: 300, width: 520, height: 480), now: 0)
        assert(region.contains(CGPoint(x: 415, y: 550), now: 0.1))
        region.track(CGRect(x: 1000, y: 300, width: 520, height: 480), now: 0.5)
        assert(region.contains(CGPoint(x: 415, y: 550), now: 1.0))
        assert(!region.contains(CGPoint(x: 415, y: 550), now: 2.0))
        assert(!region.contains(CGPoint(x: 0, y: 0), now: 0.5))
        region.reset(); assert(!region.contains(CGPoint(x: 1000, y: 500), now: 0.6))
        // PCM features must distinguish bass from treble, and preserve amplitude changes.
        let sampleRate = 48000.0
        let bassSamples = (0..<4096).map { Float(sin(Double($0) * 2 * .pi * 70 / sampleRate) * 0.3) }
        let trebleSamples = (0..<4096).map { Float(sin(Double($0) * 2 * .pi * 7000 / sampleRate) * 0.3) }
        var lowAnalyzer = PCMFeatures(), highAnalyzer = PCMFeatures(), silentAnalyzer = PCMFeatures()
        let low = lowAnalyzer.analyze(bassSamples, sampleRate: sampleRate)
        let high = highAnalyzer.analyze(trebleSamples, sampleRate: sampleRate)
        assert(low.bass > high.bass && high.treble > low.treble)
        assert(silentAnalyzer.analyze([Float](repeating: 0, count: 2048), sampleRate: sampleRate).level == 0)
        var quietResponse = MusicResponse(), loudResponse = MusicResponse()
        for _ in 0..<30 {
            quietResponse.advance(AudioFeatures(), delta: 0.1)
            loudResponse.advance(high, delta: 0.1)
        }
        assert(loudResponse.phase > quietResponse.phase * 3 && loudResponse.hueTravel > 0.05)
        assert(quietResponse.hueTravel == 0)
        let priorHue = loudResponse.hueTravel
        loudResponse.advance(low, delta: 0.1)
        assert(loudResponse.hueTravel >= priorHue)
        print("PASS: threshold, rest completion, idle, sleep gap, snooze, pause, sensor freshness, preferences migration, air targets, motion styles, fireworks persistence, geometric fields, parameter validation, legacy style migration, large right-click region and recent positions, bass/treble features, music-driven motion/color")
    }
}
