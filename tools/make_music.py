"""Deterministic original 100 BPM loop; standard library only, no downloaded recordings."""
from array import array
from pathlib import Path
import math
import random
import wave

path = Path(__file__).resolve().parents[1] / "Resources" / "LittleIntermission.wav"
if path.exists():
    raise SystemExit(0)
rate, beat, bars = 22050, 0.6, 8
length = int(rate * beat * 4 * bars)
mix = array("f", [0]) * length
rng = random.Random(42)

def tone(start, seconds, hz, gain, kind="bell"):
    offset = int(start * rate)
    for i in range(min(int(seconds * rate), length - offset)):
        t = i / rate
        if kind == "kick":
            value = math.sin(2 * math.pi * (48 * t + 5 * (1 - math.exp(-30 * t)))) * math.exp(-18 * t)
        elif kind == "hat":
            value = rng.uniform(-1, 1) * math.exp(-65 * t)
        else:
            envelope = min(1, t / 0.012) * math.exp(-t * (3.2 if kind == "bell" else 2.2))
            value = (math.sin(2 * math.pi * hz * t) + 0.22 * math.sin(4 * math.pi * hz * t)) * envelope
        mix[offset + i] += value * gain

def frequency(midi):
    return 440 * 2 ** ((midi - 69) / 12)

chords = [(57, 60, 64, 71), (53, 57, 60, 67), (60, 64, 67, 74), (55, 59, 62, 69)]
for bar in range(bars):
    chord = chords[bar % len(chords)]
    base = bar * 4 * beat
    for tick in range(8):
        tone(base + tick * beat / 2, 1.4, frequency(chord[tick % 4] + 12), 0.13)
        tone(base + tick * beat / 2, 0.10, 0, 0.035 if tick % 2 else 0.022, "hat")
    for tick in range(4):
        tone(base + tick * beat, 0.4, 0, 0.19, "kick")
        if tick % 2 == 0:
            tone(base + tick * beat, 0.9, frequency(chord[0] - 12), 0.16, "bass")
peak = max(abs(v) for v in mix) or 1
pcm = array("h", (int(max(-1, min(1, value / peak * 0.76)) * 32767) for value in mix))
# Avoid a click at the loop boundary.
for i in range(220):
    pcm[i] = int(pcm[i] * i / 220)
    pcm[-i - 1] = int(pcm[-i - 1] * i / 220)
with wave.open(str(path), "wb") as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(rate)
    output.writeframes(pcm.tobytes())
print(f"原创循环已生成：{path.name} / {length / rate:.1f}s")
