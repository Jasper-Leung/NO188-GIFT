#!/usr/bin/env python3
"""逐个撤掉本轮（#20）新加的判据，证明每一条都会红。

沿用 tools/mutate_settings.py 的读法，但那条自己踩过一个坑：
驱动读的是上一次跑剩下的绿日志，于是十二条突变全部报"没红"——
**量具的输入不是这一遍的输出时，整轮结论都是上一轮的**。
所以这里每次都真的起一个 Godot 进程，并且只读它这次的 stdout。
"""
import io
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT = r"D:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe"


# 每条回归各自需要的额外参数。**不给的话脚本抛异常就永远走不到 quit()**，
# 进程会挂到超时——而"挂住"在驱动眼里和"红"不是一回事（见 CLAUDE.md
# 「抛异常的回归退出码是 0」那条的加强版：这次连退出码都没有）。
EXTRA_ARGS = {
    "verify_minimap.gd": ["--quit-after", "30000"],
    "verify_mood_mask.gd": ["--quit-after", "30000"],
}


def run(script):
    p = subprocess.run(
        [GODOT, "--headless", "--path", str(ROOT), "--script", f"tools/{script}"]
        + EXTRA_ARGS.get(script, []),
        capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=600,
    )
    return p.stdout + p.stderr


def fails(out):
    return [l for l in out.splitlines() if "[FAIL]" in l]


MUTATIONS = [
    # (说明, 文件, 原文, 改后, 跑哪条回归, 期望红的条数下限)
    ("README 出图套数退回 8（仓库里是 11）", "README.md",
     "**11 套出图**", "**8 套出图**", "verify_story.gd", 1),
    ("README.en 出图套数退回 8", "README.en.md",
     "11 screenshot", "8 screenshot", "verify_story.gd", 1),
    ("README 探针条数退回 2（仓库里是 4）", "README.md",
     "4 条探针", "2 条探针", "verify_story.gd", 2),
    ("check_all.ps1 的 NEEDS_WINDOW 少写一条", "tools/check_all.ps1",
     "$NEEDS_WINDOW = @('verify_bamboo_done', 'verify_bamboo_world', 'verify_camera_bike',",
     "$NEEDS_WINDOW = @('verify_bamboo_done', 'verify_bamboo_world',",
     "verify_story.gd", 1),
    ("GameManager.gd 预算注释的「全清」写成 800", "scripts/GameManager.gd",
     "全清 799 旅币", "全清 800 旅币", "verify_economy.gd", 1),
    ("GameManager.gd 预算注释的「缺口」写成 210", "scripts/GameManager.gd",
     "缺口 211", "缺口 210", "verify_economy.gd", 1),
    ("shop_data.gd 预算注释的「合理全购」写成 1020", "scripts/shop_data.gd",
     "合理全购 1010 旅币", "合理全购 1020 旅币", "verify_economy.gd", 1),
    ("shop_data.gd 把「全清」那个锚点整个删掉", "scripts/shop_data.gd",
     "理想全清总收入 799 旅币；", "理想总收入 799 旅币；", "verify_economy.gd", 2),
    # ---- 完满明示那一族（暂停面板上那一行）----
    ("PausePanel 根本不建那一行（收工决定时看不见还差几次）", "scripts/PausePanel.gd",
     "\t_tier_label = _make_tier_label()", "\t_tier_label = null", "verify_minimap.gd", 3),
    ("visits_to_full() 恒返回 0（那行字永远说「已完满」）", "scripts/PostcardVariant.gd",
     "\t\tleft += maxi(0, int(GameManager.MAX_VISITS_PER_STATION) - GameManager.get_station_count(st_idx))",
     "\t\tleft += 0", "verify_postcard_ending.gd", 3),
    ("档名表少一档（面板会报「第 5 档 / 共 4 档」）", "scripts/PostcardVariant.gd",
     '\t"tier_4",  # 4 完满\n]', '\t]', "verify_postcard_ending.gd", 3),
    ("中英档名填成同一个词（英文界面里这一行分不出档）", "scripts/Localization.gd",
     '"tier_1": "Explorer"', '"tier_1": "Master"', "verify_postcard_ending.gd", 1),
]


def main():
    # 基线：先跑一遍未突变的，基线不干净下面每一条都分不清"没咬住"和"没跑"
    for script in sorted({m[4] for m in MUTATIONS}):
        base = fails(run(script))
        if base:
            print(f"基线不干净：{script} 已经有 {len(base)} 条 FAIL")
            for l in base:
                print("   ", l)
            return 1
    print("基线干净。\n")

    bad = 0
    for desc, rel, old, new, script, want in MUTATIONS:
        path = ROOT / rel
        src = io.open(path, encoding="utf-8").read()
        if src.count(old) < 1:
            print(f"[ANCHOR-MISSING] {desc} —— {rel} 里找不到 {old!r}")
            bad += 1
            continue
        io.open(path, "w", encoding="utf-8").write(src.replace(old, new, 1))
        try:
            got = fails(run(script))
        finally:
            io.open(path, "w", encoding="utf-8").write(src)
        if len(got) >= want:
            print(f"[OK]      {desc} → 红 {len(got)} 条")
        else:
            print(f"[NO-RED]  {desc} → 只红 {len(got)} 条（要 ≥{want}）")
            bad += 1
    print(f"\n{len(MUTATIONS) - bad}/{len(MUTATIONS)} 个突变咬住了")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
