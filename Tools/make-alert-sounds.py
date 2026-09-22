#!/usr/bin/env python3
"""可重建的原创提示音：python3 Tools/make-alert-sounds.py（macOS afconvert）。"""
import math
from pathlib import Path
import struct
import subprocess
import tempfile
import wave

RATE = 44100
DEST = Path(__file__).resolve().parents[1] / "Kanpan/Kanpan/Resources"


def tone(samples, start, duration, frequency, gain, decay, partials):
    for i in range(round(duration * RATE)):
        t = i / RATE
        # 8ms attack / 60ms release eliminate edge clicks. Exponential decay softens the chime.
        env = min(1, t / .008) * min(1, (duration - t) / .060) * math.exp(-decay * t)
        value = sum(a * math.sin(2 * math.pi * frequency * ratio * t) for ratio, a in partials)
        samples[round(start * RATE) + i] += gain * env * value


def build(name, duration, notes):
    samples = [0.0] * round(duration * RATE)
    for note in notes:
        tone(samples, *note)
    rms = math.sqrt(sum(x*x for x in samples) / len(samples))
    gain = min(10 ** (-20 / 20) / rms, .75 / max(abs(x) for x in samples))
    pcm = b"".join(struct.pack("<h", round(x * gain * 32767)) for x in samples)
    with tempfile.TemporaryDirectory() as folder:
        wav = Path(folder) / "source.wav"
        with wave.open(str(wav), "wb") as out:
            out.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
            out.writeframes(pcm)
        dest = DEST / f"alert-{name}.caf"
        subprocess.run(["afconvert", "-f", "caff", "-d", "ima4", str(wav), str(dest)], check=True)
    print(f"{dest.name}: {duration:.2f}s, RMS {20*math.log10(rms*gain):.2f} dBFS, peak {max(abs(x) for x in samples)*gain:.3f}")


if __name__ == "__main__":
    DEST.mkdir(parents=True, exist_ok=True)
    # 清脆：两颗上行木质短音；电子：三颗低音正弦；玻璃：一颗渐衰非整数泛音钟。
    build("crisp", .85, [(0, .38, 880, 1, 9, [(1, 1), (2, .15)]),
                          (.22, .55, 1174.66, .85, 8, [(1, 1), (2, .12)])])
    build("electronic", 1.05, [(start, .24, freq, 1, 3, [(1, 1), (2, .18), (3, .06)])
                               for start, freq in [(0, 440), (.25, 554.37), (.50, 659.25)]])
    build("glass", 1.4, [(0, 1.35, 740, 1, 3.8, [(1, 1), (2.76, .23), (4.07, .07)])])
