"""Generate ambient WAV assets for No.218 gift game.

Usage:
    python tools/gen_ambient_audio.py

Outputs to assets/audio/ambient/:
    wind.wav    — 15s mountain wind (Brownian noise + low-frequency amplitude LFO)
    birds.wav   — 8s bird chirps (random short sine chirps on quiet bed)
    water.wav   — 10s water trickle (bandpass white noise + slow LFO)
    song.wav    — 20s Hakka pentatonic melody (two phrases, C-D-E-G-A)

Only uses Python stdlib (math / random / struct / wave / os).
"""

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)),
                       "assets", "audio", "ambient")


def clamp_amp(samples, max_amp):
    m = max(abs(s) for s in samples) or 1.0
    k = max_amp / m
    return [s * k for s in samples]


def save_wav(path, samples):
    samples = clamp_amp(samples, 0.95)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(b"".join(struct.pack("<h",
                       max(-32767, min(32767, int(s * 32767)))) for s in samples))


def gen_wind(seconds=15.0):
    n = int(SAMPLE_RATE * seconds)
    out = [0.0] * n
    low = 0.0
    for i in range(n):
        t = i / SAMPLE_RATE
        low += (random.random() * 2 - 1) * 0.03
        low *= 0.998
        mod = 0.55 + 0.45 * math.sin(2 * math.pi * 0.08 * t) \
                     + 0.25 * math.sin(2 * math.pi * 0.17 * t + 0.7)
        out[i] = low * mod
    return out


def gen_water(seconds=10.0):
    n = int(SAMPLE_RATE * seconds)
    out = [0.0] * n
    lp = 0.0
    for i in range(n):
        white = random.random() * 2 - 1
        lp += (white - lp) * 0.2
        t = i / SAMPLE_RATE
        mod = 0.5 + 0.4 * math.sin(2 * math.pi * 0.4 * t) \
                       + 0.2 * math.sin(2 * math.pi * 0.6 * t + 1.3)
        out[i] = lp * mod * 1.2
    return out


def add_chirp(samples, center_i, freq, dur=0.12, amp=0.35, chirp=800.0):
    n_c = int(SAMPLE_RATE * dur)
    for i in range(n_c):
        idx = center_i + i
        if 0 <= idx < len(samples):
            t = i / n_c
            freq_t = freq + chirp * t
            env = min(1.0, t * 8) * math.exp(-3.0 * t)
            samples[idx] += amp * env * math.sin(2 * math.pi * freq_t * i / SAMPLE_RATE)


def gen_birds(seconds=8.0):
    n = int(SAMPLE_RATE * seconds)
    out = [0.0] * n
    for i in range(n):
        t = i / SAMPLE_RATE
        out[i] = 0.015 * math.sin(2 * math.pi * 0.5 * t) \
                  + 0.01 * (random.random() * 2 - 1)
    for _ in range(random.randint(20, 35)):
        start = random.randint(0, max(1, n - int(SAMPLE_RATE * 0.3)))
        dur = random.uniform(0.05, 0.2)
        freq = random.uniform(900.0, 2600.0)
        amp = random.uniform(0.25, 0.45)
        chirp = random.uniform(-600.0, 1400.0)
        add_chirp(out, start, freq, dur, amp, chirp)
    return out


def _note(f, beat, amp=0.22, harm=(1.0, 0.25, 0.1, 0.05)):
    n = int(SAMPLE_RATE * beat)
    out = [0.0] * n
    for i in range(n):
        t = i / SAMPLE_RATE
        env = min(1.0, t * 6) * math.exp(-1.8 * t)
        s = 0.0
        for k, a in enumerate(harm, 1):
            s += a * math.sin(2 * math.pi * f * k * t)
        out[i] += amp * env * s
    return out


def gen_song(total_seconds=20.0):
    beat = 2.0
    C4, D4, E4, G4, A4 = 261.63, 293.66, 329.63, 392.0, 440.0
    G3, C3 = 196.0, 130.81
    phrases = [
        [(C4, 1), (E4, 1), (G4, 1), (A4, 1)],
        [(G4, 1), (E4, 1), (D4, 1), (C4, 2)],
    ]
    chords = [
        [C4, E4, G4],
        [D4, G4, A4],
        [C4, E4, G4],
        [E4, G4, C4],
    ]
    n_total = int(SAMPLE_RATE * total_seconds)
    out = [0.0] * n_total
    for pi, phrase in enumerate(phrases):
        for ci, (f, b) in enumerate(phrase):
            pos = int((pi * 4 * beat + ci * beat) * SAMPLE_RATE)
            nn = _note(f, b, 0.22)
            for i in range(min(len(nn), n_total - pos)):
                out[pos + i] += nn[i]
            hc = chords[ci % len(chords)]
            for hf in hc:
                cn = _note(hf, b, 0.05)
                for i in range(min(len(cn), n_total - pos)):
                    out[pos + i] += cn[i]
            bn = _note(hc[0] / 2.0, b, 0.1, harm=(1.0, 0.3, 0.1))
            for i in range(min(len(bn), n_total - pos)):
                out[pos + i] += bn[i]
    return out


def main():
    random.seed(218)
    os.makedirs(OUT_DIR, exist_ok=True)
    save_wav(os.path.join(OUT_DIR, "wind.wav"), gen_wind(15.0))
    save_wav(os.path.join(OUT_DIR, "birds.wav"), gen_birds(8.0))
    save_wav(os.path.join(OUT_DIR, "water.wav"), gen_water(10.0))
    save_wav(os.path.join(OUT_DIR, "song.wav"), gen_song(20.0))
    for name in ("wind", "birds", "water", "song"):
        p = os.path.join(OUT_DIR, name + ".wav")
        size = os.path.getsize(p) / 1024.0
        print(f"  {name}.wav  {size:.1f} KB")


if __name__ == "__main__":
    print("Generating ambient audio to", OUT_DIR)
    main()
