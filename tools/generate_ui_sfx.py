from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = PROJECT_ROOT / "assets" / "audio" / "sfx"
SR = 48_000
SEED = 218


def smoothstep(edge0, edge1, x):
    span = edge1 - edge0
    s = np.clip((x - edge0) / span, 0.0, 1.0)
    return s * s * (3.0 - 2.0 * s)


def filter_band(x, low_hz=None, high_hz=None, order=5):
    nyquist = SR / 2.0
    if low_hz is not None and high_hz is not None:
        sos = butter(order, [low_hz / nyquist, high_hz / nyquist], btype="bandpass", output="sos")
    elif low_hz is not None:
        sos = butter(order, low_hz / nyquist, btype="lowpass", output="sos")
    else:
        sos = butter(order, high_hz / nyquist, btype="highpass", output="sos")
    return sosfilt(sos, x)


def delay(x, delay_seconds):
    n = int(round(delay_seconds * SR))
    if n <= 0:
        return x.copy()
    y = np.zeros_like(x)
    y[n:] = x[:-n]
    return y


def stereo(left, right=None, gain=0.95, delay_seconds=0.002):
    if right is None:
        right = delay(left, delay_seconds) * gain
    return np.column_stack((left, right))


def fade_edges(x, attack=0.002, release=0.025):
    attack_samples = max(1, int(round(attack * SR)))
    release_samples = max(1, int(round(release * SR)))
    x = x.copy()
    if x.ndim == 1:
        x[:attack_samples] *= smoothstep(0.0, attack_samples - 1.0, np.arange(attack_samples))
        x[-release_samples:] *= smoothstep(release_samples - 1.0, 0.0, np.arange(release_samples))
    else:
        x[:attack_samples] *= smoothstep(0.0, attack_samples - 1.0, np.arange(attack_samples)).reshape(-1, 1)
        x[-release_samples:] *= smoothstep(release_samples - 1.0, 0.0, np.arange(release_samples)).reshape(-1, 1)
    return x


def normalize_peak(x, target=0.92):
    peak = np.max(np.abs(x))
    if peak > 1e-8:
        x = x / peak * target
    return np.clip(x, -1.0, 1.0)


def impulse_train(length, starts, amps, widths):
    out = np.zeros(length, dtype=np.float64)
    for start, amp, width in zip(starts, amps, widths):
        dt = np.arange(length) / SR - start
        out += amp * np.exp(-(dt / width) ** 2 * 2.0)
    return out


def paper_ribbon():
    rng = np.random.default_rng(SEED)
    n = int(round(0.58 * SR))
    t = np.arange(n) / SR

    tear_noise = rng.normal(size=n)
    tear_env = smoothstep(0.0, 0.003, t) * smoothstep(0.175, 0.015, t)
    tear = 0.62 * filter_band(tear_noise, 1800.0, 5600.0)
    tear += 0.38 * filter_band(tear_noise, high_hz=4500.0)
    tear *= tear_env

    crackles = impulse_train(
        n,
        [0.012, 0.035, 0.057, 0.079, 0.101, 0.122, 0.138, 0.153],
        [0.13, 0.09, 0.12, 0.06, 0.10, 0.05, 0.08, 0.035],
        [0.0024, 0.0018, 0.0028, 0.0015, 0.0022, 0.0013, 0.0019, 0.0012],
    )
    tear += crackles

    ribbon_t = t - 0.19
    ribbon_env = smoothstep(0.0, 0.08, ribbon_t) * smoothstep(0.205, 0.07, ribbon_t)
    ribbon_noise = rng.normal(size=n)
    ribbon = filter_band(ribbon_noise, 1000.0, 3400.0)
    ribbon += 0.35 * filter_band(ribbon_noise, 2600.0, 6200.0)
    ribbon *= ribbon_env * 0.36

    paper = normalize_peak(fade_edges(tear + ribbon, 0.001, 0.03))
    return stereo(paper, paper, 0.92, 0.0018)


def bell(freq, start, gain, duration, seed, decay_scale=1.0):
    rng = np.random.default_rng(seed)
    t = np.arange(int(round(duration * SR))) / SR
    left = np.zeros_like(t)
    right = np.zeros_like(t)
    partials = [
        (1.0, 0.40, 7.5),
        (2.003, 0.22, 11.0),
        (2.74, 0.16, 13.0),
        (4.16, 0.10, 17.0),
        (5.40, 0.065, 22.0),
        (8.40, 0.030, 30.0),
    ]

    for ratio, partial_gain, decay in partials:
        frequency = freq * ratio * rng.uniform(0.9991, 1.0009)
        phase_left = rng.uniform(0.0, 2.0 * np.pi)
        phase_right = phase_left + rng.uniform(-0.24, 0.24)
        dt = np.clip(t - start, 0.0, None)
        envelope = smoothstep(0.0, 0.0012, dt) * np.exp(-dt * decay * decay_scale)
        left += np.sin(2.0 * np.pi * frequency * dt + phase_left) * envelope * partial_gain
        right += np.sin(2.0 * np.pi * frequency * dt + phase_right) * envelope * partial_gain

    return (left * gain, right * gain)


def sparkle(start, gain=0.055, duration=0.055):
    rng = np.random.default_rng(271)
    n = int(round(duration * SR))
    noise = filter_band(rng.normal(size=n), 7500.0, 16_000.0)
    envelope = smoothstep(0.0, 0.001, np.arange(n) / SR) * np.exp(-np.arange(n) / SR * 42.0)
    return stereo(noise * envelope * gain, delay(noise * envelope * gain, 0.0013) * 0.88)


def ding_dong():
    duration = 0.88
    samples = int(round(duration * SR))
    left = np.zeros(samples)
    right = np.zeros(samples)

    for freq, start, gain, seed in [(1318.51, 0.008, 0.62, 31), (1760.0, 0.176, 0.52, 33)]:
        bell_out = bell(freq, start, gain, duration, seed)
        left += bell_out[0]
        right += bell_out[1]
        sparkle_out = sparkle(start, 0.045, 0.055)
        sparkle_samples = sparkle_out.shape[0]
        left[:sparkle_samples] += sparkle_out[:sparkle_samples, 0]
        right[:sparkle_samples] += sparkle_out[:sparkle_samples, 1]

    return normalize_peak(fade_edges(stereo(left, right, 0.98, 0.000), 0.001, 0.03))


def magical_glow():
    rng = np.random.default_rng(SEED + 41)
    duration = 1.52
    n = int(round(duration * SR))
    t = np.arange(n) / SR

    shimmer_noise = filter_band(rng.normal(size=n), 7000.0, 14_000.0)
    shimmer_env = smoothstep(0.0, 0.48, t) * smoothstep(duration, 0.86, t)
    shimmer_env *= 0.82 + 0.18 * np.sin(2.0 * np.pi * 3.7 * t)
    shimmer = 0.075 * shimmer_noise * shimmer_env

    frequencies = [523.25, 659.25, 783.99, 987.77, 1174.66]
    amplitudes = [0.44, 0.30, 0.25, 0.22, 0.17]
    chord_env = smoothstep(0.36, 0.95, t) * smoothstep(duration, 1.32, t)
    vibrato = np.sin(2.0 * np.pi * 4.7 * t)
    left = shimmer.copy()
    right = shimmer.copy()

    for frequency, amplitude in zip(frequencies, amplitudes):
        phase_left = rng.uniform(0.0, 2.0 * np.pi)
        phase_right = phase_left + rng.uniform(-0.20, 0.20)
        wave_left = np.sin(2.0 * np.pi * frequency * t + phase_left + 0.007 * vibrato)
        wave_left += 0.17 * np.sin(4.0 * np.pi * frequency * t + phase_left + 0.011 * vibrato)
        wave_left += 0.055 * np.sin(6.0 * np.pi * frequency * t + phase_left)
        wave_right = np.sin(2.0 * np.pi * frequency * t + phase_right + 0.008 * vibrato)
        wave_right += 0.17 * np.sin(4.0 * np.pi * frequency * t + phase_right + 0.010 * vibrato)
        wave_right += 0.055 * np.sin(6.0 * np.pi * frequency * t + phase_right)
        left += wave_left * amplitude * chord_env
        right += wave_right * amplitude * chord_env

    return normalize_peak(fade_edges(np.column_stack((left, right)), 0.008, 0.05))


def camera_confirm():
    rng = np.random.default_rng(SEED + 73)
    duration = 0.62
    n = int(round(duration * SR))
    t = np.arange(n) / SR
    noise = rng.normal(size=n)

    click_a = impulse_train(n, [0.018], [0.42], [0.0020])
    click_b = impulse_train(n, [0.092], [0.25], [0.0016])
    body = filter_band((click_a + click_b) * noise, 1200.0, 8500.0)
    body += 0.25 * filter_band((click_a + click_b) * noise, high_hz=5500.0)
    body += 0.06 * np.sin(2.0 * np.pi * 340.0 * np.clip(t - 0.018, 0.0, None)) * np.exp(-np.clip(t - 0.018, 0.0, None) * 92.0)

    ding_left, ding_right = bell(1567.98, 0.252, 0.40, duration, 47, decay_scale=1.8)
    left = body + ding_left
    right = body + ding_right
    return normalize_peak(fade_edges(stereo(left, right, 0.97, 0.001), 0.001, 0.025))


SOUNDS = [
    ("sfx_ribbon_unwrap", paper_ribbon),
    ("sfx_ding_dong", ding_dong),
    ("sfx_magical_glow", magical_glow),
    ("sfx_camera_confirm", camera_confirm),
]


def write_pair(name, audio):
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    wav_path = OUTPUT_DIR / f"{name}.wav"
    ogg_path = OUTPUT_DIR / f"{name}.ogg"
    sf.write(wav_path, audio.astype(np.float32), SR, format="WAV", subtype="PCM_24")
    sf.write(ogg_path, audio.astype(np.float32), SR, format="OGG", subtype="VORBIS")
    return wav_path, ogg_path


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, factory in SOUNDS:
        audio = factory()
        wav_path, ogg_path = write_pair(name, audio)
        print(f"{name}: {len(audio) / SR:.3f}s -> {wav_path.relative_to(PROJECT_ROOT)} / {ogg_path.relative_to(PROJECT_ROOT)}")


if __name__ == "__main__":
    main()
