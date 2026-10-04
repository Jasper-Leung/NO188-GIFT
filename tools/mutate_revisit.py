import subprocess, sys, os, io

GODOT = r"D:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe"
PROJ  = r"D:\code\20260926\no188"
LOG   = os.path.join(PROJ, "tools", "_mutate_revisit.log")


def run(script, quit_after=90000):
    p = subprocess.run([GODOT, "--headless", "--path", PROJ, "--script", "res://" + script,
                        "--quit-after", str(quit_after)],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    return (p.stdout or "") + (p.stderr or "")


def fails(txt):
    out = []
    for line in txt.split("\n"):
        if line.startswith("[FAIL] ") or line.startswith("  [FAIL] "):
            # "[FAIL] " 是 **7** 个字符。第一版写的是 [8:]，于是每一条断言的
            # 名字都被啃掉第一个字，驱动报 WRONG-RED——**量具自己歪一格的时候，
            # 被量的东西全错，而它报出来的样子和"判据写错了"一模一样**。
            out.append(line.strip()[7:])
    return out


def oks(txt):
    out = []
    for line in txt.split("\n"):
        if line.startswith("[OK] ") or line.startswith("  [OK] "):
            out.append(line.strip()[5:])
    return out


MG    = "tools/verify_mini_game.gd"
LATCH = "tools/verify_interact_latch.gd"

# (label, file, old, new, [(script, 断言片段, "red"|"green"), ...])
#
# `"green"` 是**正对照**：它必须**保持绿**。第一版把正对照也塞进同一张表、
# 用同一个 AND 去判，于是"突变咬住了、正对照如约没红"被报成 NOT-RED——
# **量具把"判据对了"读成"判据坏了"**，而这两种在报告里长得一模一样。
# 和 CLAUDE.md 里「绝对数与正对照成对写」「量具自己歪一格的时候，
# 被量的东西全错」是同一条：正对照不参与"有没有咬住"的判定，它只用来
# 确认这一次红得**只该红那一条**。
#
# 目标脚本只列**该由它**抓住的那些突变：verify_mini_game 量纯函数与接线，
# verify_interact_latch 量玩家真读到的那一块面板。分开列是刻意的——
# 哪条判据是"这条路的唯一守门人"只有这样才看得出来。
MUT = [
 ("回访四句塌成两句：圈数那一路整个删掉（又绕了一圈也读不出区别）",
  "scripts/RevisitNote.gd",
  "\tvar l: int = 1 if lap >= 1 else 0",
  "\tvar l: int = 0",
  [(MG, "第 2 次，绕没绕完一圈不是同一句", "red"),
   (MG, "第 3 次，绕没绕完一圈不是同一句", "red"),
   (MG, "四句两两不同", "red")]),

 ("回访四句塌成两句：第几次那一路整个删掉（第2次和第3次读起来一样）",
  "scripts/RevisitNote.gd",
  "\tvar v: int = 0 if visit <= 1 else 1",
  "\tvar v: int = 0",
  [(MG, "第 2 次和第 3 次不是同一句", "red"),
   (MG, "四句两两不同", "red")]),

 ("面板正文钉死成一句话（选句函数不再被调）",
  "scripts/World3D.gd",
  "\treturn Localization.t(RevisitNote.key(GameManager.get_station_count(idx), _lap_index()))",
  "\treturn Localization.t(\"revisit_2nd_here\")",
  [(MG, "面板正文真的调了 RevisitNote.key()", "red"),
   (LATCH, "回访面板写的是「第 2 次 + 已绕完一圈」那一句", "red")]),

 ("面板底行不再报这一趟的乐事（藏回原来那样）",
  "scripts/World3D.gd",
  "\tif _is_revisit(idx):\n\t\tif _last_joy_slot < 0:\n\t\t\treturn \"\"\n\t\treturn Localization.t(\"mg_played\") \\\n\t\t\t\t+ Localization.t(RevisitNote.joy_key(_last_joy_slot))",
  "\tif _is_revisit(idx):\n\t\treturn \"\"",
  [(MG, "面板底行真的调了 RevisitNote.joy_key()", "red"),
   (LATCH, "回访面板说出了这一趟轮到的乐事", "red")]),

 ("底行报的是「这座驿站自己的那件」而不是这一趟真玩的那件（轮换对玩家不可见）",
  "scripts/World3D.gd",
  "\t_last_joy_slot = MiniGamePicker.game_for(slot, GameManager.get_station_count(station_idx))",
  "\t_last_joy_slot = slot",
  [(LATCH, "回访面板说出了这一趟轮到的乐事", "red")]),

 ("回访判据退化成「到过几次」（13 座普通驿站第一次路过也被写成回访）",
  "scripts/World3D.gd",
  "\treturn _road_builder.get_road_data().station_has_fragment(idx) \\\n\t\t\tand GameManager.is_collected(idx)",
  "\treturn GameManager.get_station_count(idx) > 0",
  [(MG, "回访的判据是「有碎片且收过了」，不是「到过几次」", "red")]),

 ("圈数写死成 1（不再是里程）",
  "scripts/World3D.gd",
  "\tif _total_arclen <= 1.0:\n\t\treturn 0\n\treturn int(_odometer_units / _total_arclen)",
  "\treturn 1",
  [(MG, "_lap_index() 真的是从里程算的，不是写死的圈数", "red")]),

 ("里程那一路整个不接（永远按第一圈算）",
  "scripts/World3D.gd",
  "\treturn Localization.t(RevisitNote.key(GameManager.get_station_count(idx), _lap_index()))",
  "\treturn Localization.t(RevisitNote.key(GameManager.get_station_count(idx), 0))",
  [(LATCH, "里程推了一整圈，写出来的不再是「没绕圈」那一句", "red")]),

 ("切语言那条路不跟着换（回访途中切语言把刚写的那句话刷回自我介绍）",
  "scripts/World3D.gd",
  "\t\t\t_popup_text.text = _popup_body_text(idx)\n\t\t\tvar foot := _popup_foot_text(idx)",
  "\t\t\t_popup_text.text = _station_text(idx)\n\t\t\tvar foot := \"\"",
  [(MG, "切语言走的是同一个 _popup_body_text()", "red"),
   (MG, "切语言走的是同一个 _popup_foot_text()", "red")]),

 ("四句之一中英逐字相同（英文玩家切了语言等于没切）",
  "scripts/Localization.gd",
  "\"revisit_3rd_round\": \"又一整圈。到这里是最后一趟，慢慢来。\"",
  "\"revisit_3rd_round\": \"Another full loop. Last call here — take your time.\"",
  [(MG, "revisit_3rd_round 中英不逐字相同", "red"),
   (MG, "revisit_3rd_round 中文不是空串", "green")]),

 ("四句之一漏了英文（t() 查不到 key 时返回 key 自己，不报错）",
  "scripts/Localization.gd",
  "\t\t\"revisit_2nd_round\": \"A whole loop later, and the hills are the same ones.\",",
  "",
  [(MG, "英文表里有 revisit_2nd_round", "red"),
   (MG, "visit 超界落在第 3 次那一档", "green")]),
]


bad = 0
rep = []


def out(s):
    rep.append(s)


# 先跑一遍未突变的，把基线钉住。少了这一条，下面任何一次
# "0 条 FAIL" 都分不清是突变没咬住还是这一遍回归自己没跑起来。
base = {}
for s in (MG, LATCH):
    base[s] = fails(run(s))
    out("=== 基线（未突变）%s：FAIL %d 条 ===" % (s, len(base[s])))
    for f in base[s]:
        out("    %s" % f)
if any(base.values()):
    out("!! 基线就不干净，先修回归再谈突变")
    io.open(LOG, "w", encoding="utf-8", newline="").write("\n".join(rep))
    sys.exit(2)

for idx, (label, rel, old, new, expects) in enumerate(MUT, 1):
    p = os.path.join(PROJ, rel)
    src = io.open(p, encoding="utf-8").read()
    if old not in src:
        out("[%2d] ANCHOR-MISSING  %s" % (idx, label))
        print("[%2d] ANCHOR-MISSING" % idx)
        bad += 1
        continue
    io.open(p, "w", encoding="utf-8", newline="").write(src.replace(old, new, 1))
    results = {}
    try:
        for s, _, _ in expects:
            if s not in results:
                raw = run(s)
                results[s] = (fails(raw), oks(raw))
    finally:
        io.open(p, "w", encoding="utf-8", newline="").write(src)

    red_ok = True
    green_ok = True
    detail = []
    for s, expect, mode in expects:
        fs, oklines = results[s]
        if mode == "red":
            if [f for f in fs if expect in f]:
                detail.append("RED  %-22s %s" % (s.split("/")[-1], expect))
            else:
                red_ok = False
                detail.append("MISS %-22s %s（该红没红；这一遍 %d 条 FAIL）"
                              % (s.split("/")[-1], expect, len(fs)))
        else:
            # 正对照只能去 **[OK]** 那几行里找。第一版去 `[FAIL]` 里找，
            # 而一条**绿着的断言压根不往失败列表里写**——于是每一条正对照
            # 都被报成"跟着红了"，尽管这一遍只有该红的那一条红。
            # 这是本项目里第三次量具自己出错：读一份旧的绿日志、
            # `[8:]` 啃掉首字、这一条**都是在量具上**，而报告长得和判据有毛病一样。
            if [o for o in oklines if expect in o]:
                detail.append("ctrl %-22s %s 保持绿" % (s.split("/")[-1], expect))
            else:
                green_ok = False
                detail.append("CTRL-GONE %-22s %s（正对照没在 OK 列表里）"
                              % (s.split("/")[-1], expect))
    ok = red_ok and green_ok
    if not ok:
        bad += 1
    out("")
    out("[%2d] %-11s %s" % (idx, "RED" if ok else "NOT-RED", label))
    for d in detail:
        out("     %s" % d)
    for s, (fs, _) in results.items():
        for f in fs[:8]:
            out("     实报 %s | %s" % (s.split("/")[-1], f))
    print("[%2d] %-9s %s" % (idx, "RED" if ok else "NOT-RED", label))

out("")
out("=== 突变 %d 个 / 全部咬住 %d 个 ===" % (len(MUT), len(MUT) - bad))
print("=== %d mutants, %d bit ===" % (len(MUT), len(MUT) - bad))
io.open(LOG, "w", encoding="utf-8", newline="").write("\n".join(rep) + "\n")
sys.exit(1 if bad else 0)
