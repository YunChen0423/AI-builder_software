import Foundation

struct AudioFeatures {
    var level = 0.0
    var bass = 0.0
    var treble = 0.0
}

/// Constant-memory PCM analysis; filters and amplitude compression preserve musical dynamics.
struct PCMFeatures {
    private var low = 0.0
    private var mid = 0.0
    mutating func analyze(_ samples: [Float], sampleRate: Double) -> AudioFeatures {
        guard !samples.isEmpty, sampleRate > 0 else { return AudioFeatures() }
        let a = 1 - exp(-2 * .pi * 180 / sampleRate)
        let b = 1 - exp(-2 * .pi * 2400 / sampleRate)
        var sum = 0.0, bassSum = 0.0, trebleSum = 0.0
        for sample in samples {
            let x = Double(sample)
            low += a * (x - low); mid += b * (x - mid)
            sum += x * x; bassSum += low * low; trebleSum += (x - mid) * (x - mid)
        }
        let n = Double(samples.count), rms = sqrt(sum / n)
        guard rms > 0.0001 else { return AudioFeatures() }
        return AudioFeatures(level: min(1, sqrt(rms) * 1.35),
                             bass: min(1, sqrt(sqrt(bassSum / n)) * 1.35),
                             treble: min(1, sqrt(trebleSum / max(sum, 0.000001))))
    }
}

struct MusicResponse {
    var energy = 0.0
    var bass = 0.0
    var treble = 0.0
    var beat = 0.0
    var phase = 0.0
    var hueTravel = 0.0
    private var previousLevel = 0.0
    mutating func advance(_ input: AudioFeatures, delta: Double) {
        let dt = max(0, min(0.2, delta))
        let onset = max(0, input.level - previousLevel - 0.025)
        previousLevel = input.level
        let follow = 1 - exp(-dt * (input.level > energy ? 14 : 5))
        energy += (input.level - energy) * follow
        bass += (input.bass - bass) * (1 - exp(-dt * 9))
        treble += (input.treble - treble) * (1 - exp(-dt * 7))
        beat = min(1, beat * exp(-dt * 7) + onset * 2.8)
        phase += dt * (0.12 + energy * 2.3 + bass * 0.65) + onset * 0.12
        if energy > 0.025 {
            hueTravel += dt * energy * (0.045 + treble * 0.15) + onset * 0.07
        }
    }
}
