#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""量草皮在屏上到底读成什么颜色——量的是**像素**，不是反照率。

CLAUDE.md 里记过两次教训：
  · 「反照率对比度不是渲出来的对比度」（中间隔着法线、太阳、AGX 与雾）
  · 「一个取样框里的均值会被框里别的东西拖走」（CLAUDE.md 里另有一处）
所以这里**不取均值**——先按色相把草从路面/天空/白边线里分出来，
再报草那一类的**分布**（p10/p50/p90），并把非草的像素单独报出来，
好知道这一框到底是"没取到草"还是"草真的是这个颜色"。

用法：python tools/probe_grass_hue.py <png> [x0 y0 x1 y1]
不带框就量整张图的下半部分。
"""
import sys
import colorsys
from PIL import Image


def luma(r, g, b):
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def is_grass(r, g, b):
    """草 = 有颜色的（sat ≥ 0.18）、且色相落在 45~160（黄绿到绿）。

    路面是低饱和的灰（sat 0.05 那一档）、白边线 sat 极低、天空落在 200+。
    这三条都不是"猜"，是把**已知**的三类排除掉，剩下那一片才拿来量。
    """
    mx, mn = max(r, g, b), min(r, g, b)
    if mx <= 1e-6:
        return False
    sat = (mx - mn) / mx
    if sat < 0.18:
        return False
    h, _, _ = colorsys.rgb_to_hsv(r, g, b)
    deg = h * 360.0
    return 45.0 <= deg <= 160.0


def pct(vals, p):
    if not vals:
        return 0.0
    v = sorted(vals)
    return v[min(len(v) - 1, int(len(v) * p))]


def main():
    path = sys.argv[1]
    im = Image.open(path).convert("RGB")
    W, H = im.size
    px = im.load()
    if len(sys.argv) >= 6:
        x0, y0, x1, y1 = (int(sys.argv[i]) for i in range(2, 6))
    else:
        x0, y0, x1, y1 = 0, H // 2, W, H
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(W, x1), min(H, y1)

    print("image %s  %dx%d   box %d,%d-%d,%d" % (path, W, H, x0, y0, x1, y1))

    grass = []
    other = 0
    total = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            p = px[x, y]
            r, g, b = p[0] / 255.0, p[1] / 255.0, p[2] / 255.0
            total += 1
            if is_grass(r, g, b):
                grass.append((r, g, b))
            else:
                other += 1

    print("  grass %d / %d  (%.1f%%)   non-grass %d"
          % (len(grass), total, 100.0 * len(grass) / max(1, total), other))
    if not grass:
        print("  !! 这一框里一��草像素都没有——量具的取样框落在别的东西上了")
        return

    for k, name in ((0, "r"), (1, "g"), (2, "b")):
        ch = [c[k] for c in grass]
        print("  %s  p10=%.3f p50=%.3f p90=%.3f" % (name, pct(ch, .1), pct(ch, .5), pct(ch, .9)))
    lm = [luma(*c) for c in grass]
    print("  lum p10=%.3f p50=%.3f p90=%.3f  spread=%.3f"
          % (pct(lm, .1), pct(lm, .5), pct(lm, .9), pct(lm, .9) - pct(lm, .1)))
    gr = [(c[1] - c[0]) for c in grass]
    print("  g-r   p10=%.3f p50=%.3f p90=%.3f   <-- 越小越像干草/麦子"
          % (pct(gr, .1), pct(gr, .5), pct(gr, .9)))
    sat = [0.0 if max(c) <= 0 else (max(c) - min(c)) / max(c) for c in grass]
    print("  sat   p10=%.3f p50=%.3f p90=%.3f" % (pct(sat, .1), pct(sat, .5), pct(sat, .9)))


if __name__ == "__main__":
    main()
