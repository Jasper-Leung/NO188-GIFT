import subprocess, sys, os, io

GODOT = r"D:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe"
PROJ  = r"D:\code\20260926\no188"
LOG   = os.path.join(PROJ, "tools", "_mutate.log")

# 原来这里读的是 tools/_run.log —— 那是上一次 `check_all` / `_run.ps1` 跑完
# 留下的**绿**日志，而本函数自己 `capture_output=True` 把真正的输出丢掉了。
# 于是 12 个突变每一个都报「没红」，而真相是回归根本没被读。
# 教训和 CLAUDE.md 里那条同族：**驱动读的那份数据必须是这一遍产出的那一份**，
# 否则整轮结果是上一次运行的残留，而"全绿"是最危险的读数。
def run(script="tools/verify_settings.gd", quit_after=60000):
    p = subprocess.run([GODOT, "--headless", "--path", PROJ, "--script", "res://" + script,
                        "--quit-after", str(quit_after)],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    return (p.stdout or "") + (p.stderr or "")

def fails(txt):
    out = []
    for line in txt.split("\n"):
        if line.startswith("[FAIL] ") or line.startswith("  [FAIL] "):
            # "[FAIL] " 是 **7** 个字符（[ F A I L ] 空格）。第一版写的是
            # [8:]，于是每一条断言的名字都被啃掉第一个字——"按「?」之后…" 变成
            # "「?」之后…"，而驱动报的是 WRONG-RED。**量具自己歪一格的时候，
            # 被量的东西全错**，而它报出来的样子和"判据写错了"一模一样。
            out.append(line.strip()[7:])
    return out

# (label, file, old, new, expect_in_fail_output)
MUT = [
 ("HUD「?」按钮断线（这一族要修的那个原 bug）",
  "scripts/HUD3D.gd",
  "\t_help_btn.pressed.connect(_on_help_btn_pressed)\n",
  "\t#_help_btn.pressed.connect(_on_help_btn_pressed)\n",
  "按「?」之后设置面板真的开了"),

 ("暂停压低退回写死的绝对值 -18dB（20% 音量时暂停反而变吵）",
  "scripts/AudioManager.gd",
  "\treturn db - PAUSE_DUCK_DB if _ducked else db",
  "\treturn -18.0 if _ducked else db",
  "暂停压低的量是相对的 PAUSE_DUCK_DB"),

 ("取消静音退回 100%（不是玩家自己那一档）",
  "scripts/AudioManager.gd",
  "\t\tset_bgm_volume(_bgm_last_nonzero)",
  "\t\tset_bgm_volume(1.0)",
  "取消静音回到玩家自己那一档"),

 ("音量落盘退回覆盖写（抹掉画质那一档）",
  "scripts/AudioManager.gd",
  "\tvar cfg := ConfigFile.new()\n\tcfg.load(SAVE_PATH_CFG)\n\tcfg.set_value(\"audio\", which, value)",
  "\tvar cfg := ConfigFile.new()\n\tcfg.set_value(\"audio\", which, value)",
  "写音量之后画质档位还在"),

 ("分辨率排在窗口模式之前（FULLSCREEN 会抹掉刚设的尺寸）",
  "scripts/QualitySettings.gd",
  "\tmatch window_mode:",
  "\tif resolution_allowed(resolution_idx):\n\t\tDisplayServer.window_set_size(resolution_size(resolution_idx))\n\tmatch window_mode:",
  "分辨率排在窗口模式之后"),

 ("给 set_resolution 的 persist 加默认值",
  "scripts/QualitySettings.gd",
  "func set_resolution(idx: int, persist: bool) -> void:",
  "func set_resolution(idx: int, persist: bool = true) -> void:",
  "set_resolution 的参数表里一个默认值都没有"),

 ("冷启动引导退回自己手抄一份键位表",
  "scripts/OnboardingGuide.gd",
  "\t_add_control_rows(vbox, GameManager.player_control_rows())",
  "\t_add_control_rows(vbox, [[\"W\", \"前\"], [\"S\", \"后\"]])",
  "冷启动操作说明走的是 GameManager.player_control_rows()"),

 ("设置面板退回自己手抄一份键位表",
  "scripts/SettingsPanel.gd",
  "\tvar rows: Array = GameManager.touch_control_rows() \\\n\t\t\tif DisplayServer.is_touchscreen_available() else GameManager.player_control_rows()",
  "\tvar rows: Array = [[\"W\", \"前\"], [\"S\", \"后\"]]",
  "操作说明走的是 GameManager.player_control_rows()"),

 ("注册退回逐行手抄（PLAYER_ACTIONS 那个循环删掉）",
  "scripts/GameManager.gd",
  "\tfor entry in PLAYER_ACTIONS:\n\t\t_add_action(str(entry[\"action\"]), entry[\"keys\"])",
  "\t_add_action(\"move_up\", [KEY_W, KEY_UP])\n\t_add_action(\"move_down\", [KEY_S, KEY_DOWN])\n\t_add_action(\"move_left\", [KEY_A, KEY_LEFT])\n\t_add_action(\"move_right\", [KEY_D, KEY_RIGHT])\n\t_add_action(\"interact\", [KEY_SPACE, KEY_ENTER])\n\t_add_action(\"pause\", [KEY_ESCAPE])\n\t_add_action(\"mute\", [KEY_M])",
  "注册走的是 PLAYER_ACTIONS 那个循环"),

 ("滑杆不再对齐真状态（建面板那一刻的值钉死）",
  "scripts/SettingsPanel.gd",
  "\t\t_bgm_slider.set_value_no_signal(AudioManager.bgm_volume())",
  "\t\t_bgm_slider.set_value_no_signal(0.8)",
  "打开面板时滑杆对齐的是当前真音量"),

 ("Web/移动端不再排除（window_set_size 在那里静默无效）",
  "scripts/QualitySettings.gd",
  "\tif OS.has_feature(\"web\") or OS.has_feature(\"mobile\"):\n\t\treturn false\n\treturn true",
  "\treturn true",
  "video_available() 里排除了 web/mobile"),

 ("屏幕放不下也照样设窗口（玩家拿到比屏幕还大的窗口）",
  "scripts/QualitySettings.gd",
  "\treturn want.x <= _usable_size().x and want.y <= _usable_size().y",
  "\treturn true",
  "在可用区"),
]

bad = 0
rep = []
def out(s):
    rep.append(s)

# 先跑一遍未突变的，把基线钉住。少了这一条，下面 12 条里任何一次
# "0 条 FAIL" 都分不清是突变没咬住还是这一遍回归自己没跑起来。
base = fails(run())
out("=== 基线（未突变）：FAIL %d 条 ===" % len(base))
for f in base:
    out("    %s" % f)
if base:
    out("!! 基线就不干净，先修回归再谈突变")
    io.open(LOG, "w", encoding="utf-8", newline="").write("\n".join(rep))
    sys.exit(2)

for idx, (label, rel, old, new, expect) in enumerate(MUT, 1):
    p = os.path.join(PROJ, rel)
    src = io.open(p, encoding="utf-8").read()
    if old not in src:
        out("[%2d] ANCHOR-MISSING  %s" % (idx, label))
        print("[%2d] ANCHOR-MISSING" % idx)
        bad += 1
        continue
    io.open(p, "w", encoding="utf-8", newline="").write(src.replace(old, new, 1))
    try:
        raw = run()
        fs = fails(raw)
    finally:
        io.open(p, "w", encoding="utf-8", newline="").write(src)
    hit = [f for f in fs if expect in f]
    if hit:
        status = "RED"
    elif not fs:
        status = "NO-RUN"      # 回归一都没打：多半是突变把脚本编译搞挂了
    else:
        status = "WRONG-RED"
    if status != "RED":
        bad += 1
    out("")
    out("[%2d] %-11s %s" % (idx, status, label))
    out("     预期红：%s" % expect)
    for f in fs[:8]:
        out("     实报：%s" % f)
    if not fs:
        # 一条 FAIL 都没有 = 回归根本没跑起来（编译挂了 / autoload 拿不到）。
        # 把输出末尾抄进报告，否则"没红"和"没跑"这两种完全不同的病
        # 在这里长得一模一样——第一版 12 条全是"没红"，真相是读了一份旧的绿日志。
        tail = [l for l in raw.replace("\r", "").split("\n") if l.strip()][-14:]
        out("     —— 回归没跑，输出末尾：")
        for l in tail:
            out("     | %s" % l)
    print("[%2d] %-13s %s" % (idx, status, "fails=%d" % len(fs)))

out("")
out("=== 突变 %d 个 / 全部咬住 %d 个 ===" % (len(MUT), len(MUT) - bad))
print("=== %d mutants, %d bit ===" % (len(MUT), len(MUT) - bad))
io.open(LOG, "w", encoding="utf-8", newline="").write("\n".join(rep) + "\n")
sys.exit(1 if bad else 0)
