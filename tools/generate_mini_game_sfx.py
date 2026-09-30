"""五个碎片的「那件事本身」的发声。

`generate_ui_sfx.py` 出的四个音都是界面反馈（撕纸、叮咚、闪光、快门），而
云/茶/琴/竹/禽 恰好是东坡那五件「乐事」本身——琴音林不出一声琴音，茶烟小筑
没有倒水声。这一组补的就是这五个。

音色都按场景来，不按素材库来：琴是丝弦拨奏（Karplus-Strong，竹节式衰减），
茶是带气泡的水流，竹是空腔炸裂，禽是短促的音节滑音，云是软毛笔擦纸。
"""

from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = PROJECT_ROOT / "assets" / "audio" / "sfx"
SR = 48_000
SEED = 913


def smoothstep(edge0, edge1, x):
    span = edge1 - edge0
    s = np.clip((x - edge0) / span, 0.0, 1.0)
    return s * s * (3.0 - 2.0 * s)


def filter_band(x, low_hz=None, high_hz=None, order=4):
    nyq = SR / 2.0
    if low_hz is not None and high_hz is not None:
        sos = butter(order, [low_hz / nyq, high_hz / nyq], btype="bandpass", output="sos")
    elif low_hz is not None:
        sos = butter(order, low_hz / nyq, btype="lowpass", output="sos")
    else:
        sos = butter(order, high_hz / nyq, btype="highpass", output="sos")
    return sosfilt(sos, x)


def fade_edges(x, attack=0.003, release=0.05):
    a = max(1, int(round(attack * SR)))
    r = max(1, int(round(release * SR)))
    x = x.copy()
    ramp_in = smoothstep(0.0, a - 1.0, np.arange(a))
    ramp_out = smoothstep(r - 1.0, 0.0, np.arange(r))
    if x.ndim == 1:
        x[:a] *= ramp_in
        x[-r:] *= ramp_out
    else:
        x[:a] *= ramp_in.reshape(-1, 1)
        x[-r:] *= ramp_out.reshape(-1, 1)
    return x


def normalize_peak(x, target=0.9):
    peak = np.max(np.abs(x))
    if peak > 1e-8:
        x = x / peak * target
    return np.clip(x, -1.0, 1.0)


def stereo(mono, width=0.0009, gain=0.95):
    n = int(round(width * SR))
    right = np.concatenate((np.zeros(n), mono[:-n])) * gain
    return np.column_stack((mono, right))


def zither_note(freq, seed, duration=1.5):
    """丝弦拨奏：泛音列 1/n^1.5，高次泛音衰减更快，拨弦点靠琴码留一道陷波。

    不用 Karplus-Strong 延迟线：它的梳状响应让各泛音的回路增益几乎一样高
    （一赫兹一下的衰减量在 330Hz 上区分不出 1/2 次泛音），谱峰会随机落到
    泛音上，实测四个音里有一个跑到了 2 次泛音。基音最强才是"是弦不是锯齿"的关键。
    """
    rng = np.random.default_rng(seed)
    n = int(round(duration * SR))
    t = np.arange(n) / SR
    out = np.zeros(n)

    # 拨弦点在弦长的 0.13 处（靠近琴码）→ 第 8 次泛音被压掉，是丝弦的招牌
    pluck_pos = 0.13
    detune = rng.uniform(-0.0016, 0.0016)   # 两根弦的失谐，慢拍频
    for k in range(1, 13):
        fk = freq * k
        if fk > SR * 0.45:
            break
        amp = (1.0 / k ** 1.5) * abs(np.sin(np.pi * k * pluck_pos))
        if amp < 1e-3:
            continue
        decay = 2.1 * (1.0 + 0.42 * (k - 1))
        env = smoothstep(0.0, 0.0012, t) * np.exp(-t * decay)
        out += np.sin(2.0 * np.pi * fk * (1.0 + detune) * t + rng.uniform(0, 2 * np.pi)) * env * amp
        out += np.sin(2.0 * np.pi * fk * (1.0 - detune) * t + rng.uniform(0, 2 * np.pi)) * env * amp * 0.85

    body = filter_band(out, 150.0, 6000.0)
    # 指甲擦弦的那一下
    finger = filter_band(rng.normal(size=n), 2200.0, 9000.0)
    finger *= np.exp(-t * 90.0) * 0.14
    return normalize_peak(fade_edges(body + finger, 0.0012, 0.10), 0.82)


def tea_pour():
    rng = np.random.default_rng(SEED + 11)
    duration = 1.9
    n = int(round(duration * SR))
    t = np.arange(n) / SR

    # 主体：宽带噪声做水柱，中间随时间上下飘
    noise = rng.normal(size=n)
    flow_env = smoothstep(0.0, 0.22, t) * smoothstep(duration, duration - 0.55, t)
    flow_env *= 0.72 + 0.28 * np.sin(2.0 * np.pi * 5.3 * t + 0.7)
    body = filter_band(noise, 700.0, 5200.0) * flow_env * 0.55
    body += 0.45 * filter_band(noise, 180.0, 1100.0) * flow_env * 0.4

    # 落进杯底的鼓泡：随机密度的短促谐振，越往后越稀
    rng2 = np.random.default_rng(SEED + 12)
    bubbles = np.zeros(n)
    pos = int(0.30 * SR)
    while pos < n - 400:
        gap = int(rng2.uniform(0.012, 0.055) * SR)
        f = rng2.uniform(420.0, 1500.0)
        d = int(0.018 * SR)
        seg = np.arange(d) / SR
        env = np.exp(-seg * 210.0)
        bubbles[pos:pos + d] += np.sin(2.0 * np.pi * f * seg) * env * rng2.uniform(0.10, 0.26)
        pos += gap
    body += bubbles

    return normalize_peak(fade_edges(stereo(body, 0.0016, 0.9), 0.02, 0.30))


def bamboo_cut():
    rng = np.random.default_rng(SEED + 21)
    duration = 0.78
    n = int(round(duration * SR))
    t = np.arange(n) / SR

    # 竹子断是"啪"的一下：起始瞬态宽频，之后是被拉直的纤维共振
    transient = rng.normal(size=n)
    crack = filter_band(transient, 900.0, 12000.0)
    crack *= np.exp(-t * 95.0) * 0.75
    crack += filter_band(transient, 250.0, 1800.0) * np.exp(-t * 30.0) * 0.30

    # 空腔：两个失谐的筒模，左右各一个（真竹筒本来就有点椭圆）
    body = np.zeros(n)
    for mode_hz, decay, gain in [(196.0, 13.0, 1.0), (247.5, 17.0, 0.62), (389.0, 24.0, 0.34)]:
        body += np.sin(2.0 * np.pi * mode_hz * t) * np.exp(-t * decay) * gain
    # 落地的一下闷响
    thud = np.sin(2.0 * np.pi * 92.0 * np.clip(t - 0.17, 0.0, None))
    thud *= np.exp(-np.clip(t - 0.17, 0.0, None) * 26.0) * 0.42

    out = crack + body * 0.26 + thud
    return normalize_peak(fade_edges(stereo(out, 0.0011, 0.86), 0.0008, 0.14), 0.9)


def bird_call():
    rng = np.random.default_rng(SEED + 31)
    duration = 1.35
    n = int(round(duration * SR))
    t = np.arange(n) / SR
    out = np.zeros(n)

    # 三个音节：一声长的上滑 + 两声短的颤音，这是最常见的"能叫的鸟"句式
    syllables = [
        (0.02, 0.30, 2350.0, 3450.0, 0.55, 16.0),
        (0.44, 0.13, 3100.0, 2750.0, 0.40, 42.0),
        (0.66, 0.11, 2950.0, 3300.0, 0.34, 46.0),
    ]
    for start, dur, f0, f1, gain, vib in syllables:
        d = int(round(dur * SR))
        seg = np.arange(d) / SR
        # 频率在音节内线性滑动
        freq = f0 + (f1 - f0) * (seg / max(dur, 1e-6))
        phase = 2.0 * np.pi * np.cumsum(freq) / SR
        # 叠一点颤音，鸟声才有"活"的质感
        tone = np.sin(phase) + 0.30 * np.sin(2.0 * phase + 0.9) + 0.12 * np.sin(3.0 * phase)
        tone *= np.sin(2.0 * np.pi * vib * seg) * 0.5 + 0.5
        env = smoothstep(0.0, dur * 0.16, seg) * smoothstep(dur, dur * 0.45, seg)
        # 嘶声边：鸟的声门不是纯正弦
        breath = filter_band(rng.normal(size=d), 3200.0, 11000.0) * 0.10
        begin = int(round(start * SR))
        out[begin:begin + d] += (tone + breath) * env * gain

    out = filter_band(out, 1500.0, 13000.0)
    return normalize_peak(fade_edges(stereo(out, 0.0022, 0.82), 0.004, 0.10), 0.68)


def cloud_brush():
    rng = np.random.default_rng(SEED + 41)
    duration = 0.62
    n = int(round(duration * SR))
    t = np.arange(n) / SR

    # 软毫擦纸：几乎没有音高，全靠摩擦的颗粒感
    grain = filter_band(rng.normal(size=n), 1400.0, 7500.0)
    body = filter_band(rng.normal(size=n), 380.0, 2200.0)
    env = smoothstep(0.0, 0.09, t) * smoothstep(duration, duration * 0.35, t)
    # 走笔快慢不匀：让响度自己起伏，否则听起来像一块恒定的噪声
    env *= 0.62 + 0.38 * np.sin(2.0 * np.pi * 4.6 * t + 0.4)
    out = (grain * 0.62 + body * 0.38) * env * 0.7
    # 收笔的一点顿
    out += filter_band(rng.normal(size=n), 2200.0, 9000.0) * np.exp(-t * 55.0) * 0.14
    return normalize_peak(fade_edges(stereo(out, 0.0013, 0.9), 0.012, 0.13), 0.5)


# 琴音林的四个键，音高走 D 调五声音阶（宫商角徵羽），和"东坡"这个调子不打架
ZITHER_PENTATONIC = [293.66, 329.63, 392.00, 440.00]


SOUNDS = [
    ("zither_1", lambda: zither_note(ZITHER_PENTATONIC[0], SEED + 1)),
    ("zither_2", lambda: zither_note(ZITHER_PENTATONIC[1], SEED + 2)),
    ("zither_3", lambda: zither_note(ZITHER_PENTATONIC[2], SEED + 3)),
    ("zither_4", lambda: zither_note(ZITHER_PENTATONIC[3], SEED + 4)),
    ("tea_pour", tea_pour),
    ("bamboo_cut", bamboo_cut),
    ("bird_call", bird_call),
    ("cloud_brush", cloud_brush),
]


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, factory in SOUNDS:
        audio = factory()
        sf.write(OUTPUT_DIR / f"{name}.ogg", audio.astype(np.float32), SR, format="OGG", subtype="VORBIS")
        print(f"{name}: {len(audio) / SR:.3f}s")


if __name__ == "__main__":
    main()
