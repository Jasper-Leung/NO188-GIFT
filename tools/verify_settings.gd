extends SceneTree
## 设置面板回归 —— 音量 / 画面 / 操作说明三样真的接到了玩家碰到的东西上。
##
## 这一族补的是评审列的三条空缺：音频只有开关（`set_bgm_volume_db()` 早就在
## `AudioManager` 里，**零调用者**）、没有分辨率/全屏/VSync、`OnboardingGuide`
## 手抄一份键位表且**中途没法重开**（HUD 上那个「?」按钮压根没接线）。
##
## 守七件事：
##   1. **静音与音量是同一个状态**：滑杆 0 就是静音。留一个独立布尔的话
##      "静音开着而滑杆显示 80%"是允许出现的，而 HUD 上那个「♪ 开」读的就是
##      那个布尔 —— 玩家看着两样互相拆台。取消静音要回到**他自己那一档**。
##   2. **音量真的落到播放器上**（写进字段 ≠ 读进世界），且**暂停压低是相对量**。
##      这条守的是一个已经修过的真 bug：原来 `set_paused_bgm()` 写死 -18 dB
##      （绝对值），玩家把 BGM 拉到 20%（约 -20 dB）时暂停反而**变吵**。
##   3. **落盘 + 读-改-写**：`AudioManager` 与 `QualitySettings` 现在共用
##      `user://settings.cfg`，而任何一方用 `ConfigFile.save()` 覆盖都会把另一方
##      挑的设置抹回默认值。配一条正对照。
##   4. 画面三项的**纯函数**：档位表、`resolution_allowed()`（屏幕比目标还小就不许
##      设 —— 否则玩家拿到一个比屏幕还大的窗口，而按钮上写着 1920×1080）。
##   5. 画面三项的**落盘闸**与**推真窗口的顺序**：`persist` 没有默认值；
##      分辨率必须排在窗口模式**之后**（反过来写的话 FULLSCREEN 会把刚设的尺寸抹掉，
##      而顺序反了这个 bug 两侧各自都绿：按钮上的字变了、窗口尺寸没变）。
##   6. **键位表只有一个出处**，而且那一行字承诺的键**真的注册进 InputMap**。
##      后者是"声明了却从没被读过"那一族：屏上写着「M」而 M 没绑，游戏照绿。
##   7. 面板**真能开**：两个入口进的是**同一个实例**，ESC 收得掉，
##      关闭按钮不许被顶出屏（内容装在 ScrollContainer 里，量的是它而不是整列）。
##
## 用法： godot --headless --path . --script tools/verify_settings.gd --quit-after 60000

var _fails: Array = []
var _oks := 0
var _gm: Node = null
var _loc: Node = null
var _qs: Node = null
var _am: Node = null


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_oks += 1
		print("[OK]   ", label)
	else:
		var msg := label + ("（" + detail + "）" if detail != "" else "")
		_fails.append(msg)
		print("[FAIL] ", msg)


func _eq(label: String, got: Variant, want: Variant) -> void:
	_ck(label, got == want, "got=%s want=%s" % [str(got), str(want)])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== 设置面板回归 ===")

	_gm = root.get_node_or_null("GameManager")
	_loc = root.get_node_or_null("Localization")
	_qs = root.get_node_or_null("QualitySettings")
	_am = root.get_node_or_null("AudioManager")
	if _gm == null or _loc == null or _qs == null or _am == null:
		print("[ABORT] 拿不到 autoload（注册进 project.godot 了没？）")
		quit(1)
		return

	_section_mute_is_volume()
	_section_reaches_players()
	await _section_persist_and_coexist()
	_section_video_pure()
	_section_video_gates()
	_section_key_table()
	await _section_panel()
	await _section_fits()

	print("\n=== 结果：OK %d / FAIL %d ===" % [_oks, _fails.size()])
	for f in _fails:
		print("  [FAIL] ", f)
	quit(0 if _fails.is_empty() else 1)


## ---- 1. 静音与音量是同一个状态 ----
func _section_mute_is_volume() -> void:
	print("\n-- 1. 静音 = 音量 0 --")
	_am.set_bgm_volume(0.5, false)
	_am.set_sfx_volume(0.5, false)
	_am.set_muted(false)

	_eq("BGM 音量真的写进去了", float(_am.bgm_volume()), 0.5)
	_ck("BGM 没静音", not bool(_am.is_bgm_muted()))

	_am.call("set_bgm_muted", true)
	_eq("静音就是音量 0", float(_am.bgm_volume()), 0.0)
	_eq("静音时 is_bgm_muted() 为真", bool(_am.is_bgm_muted()), true)

	# **不能退回 100%**：玩家在骑行途中按 HUD 上那个「♪」是最常按的一个键，
	# 取消静音之后突然满音量是耳朵惩罚。回到他自己刚才那一档。
	_am.call("set_bgm_muted", false)
	_eq("取消静音回到玩家自己那一档（不是 100%）", float(_am.bgm_volume()), 0.5)

	# 按钮那一侧：HUD 读的是同一个状态。两边各说各话就是这一族要防的事。
	_am.call("toggle_bgm_mute")
	_eq("按一下顶栏 BGM 按钮之后状态确实翻了", bool(_am.is_bgm_muted()), true)
	_eq("按一下之后滑杆读数也是 0（不是另存一个布尔）", float(_am.bgm_volume()), 0.0)
	_am.call("toggle_bgm_mute")
	_ck("再按一下恢复", not bool(_am.is_bgm_muted()) and absf(float(_am.bgm_volume()) - 0.5) < 0.001,
			"volume=%.3f" % float(_am.bgm_volume()))

	# 音效那一路同形（两条独立状态，坏一条不会带坏另一条）。
	_am.call("toggle_sfx_mute")
	_eq("音效静音独立于 BGM", bool(_am.is_bgm_muted()), false)
	_eq("音效确实静音了", bool(_am.is_sfx_muted()), true)
	_am.call("toggle_sfx_mute")


## ---- 2. 音量真的落到播放器上 ----
func _section_reaches_players() -> void:
	print("\n-- 2. 音量真的落到播放器 --")
	# 判据量的是 **AudioStreamPlayer.volume_db**（玩家真的听得见的那个），
	# 不是 `_bgm_volume` 那个字段 —— 字段写了而 `_apply_volumes()` 没调，
	# 两侧各自都绿（"写进字段 ≠ 读进世界"）。
	var bgm_player: Node = _am.get("_bgm_player")
	_ck("BGM 播放器建出来了", bgm_player != null)
	if bgm_player == null:
		return
	var sfx_players: Array = _am.get("_sfx_players")
	_ck("音效池建出来了", sfx_players.size() > 0, "size=%d" % sfx_players.size())
	if sfx_players.is_empty():
		return

	_am.set_bgm_volume(0.5, false)
	_am.set_sfx_volume(0.5, false)
	var want_bgm: float = float(_am.BGM_BASE_DB) + linear_to_db(0.5)
	var want_sfx: float = float(_am.SFX_BASE_DB) + linear_to_db(0.5)
	_ck("BGM 音量真的推到播放器上", absf(float(bgm_player.volume_db) - want_bgm) < 0.01,
			"got=%.3f want=%.3f" % [float(bgm_player.volume_db), want_bgm])
	var sp0: Node = sfx_players[0]
	_ck("音效音量真的推到播放器上", absf(float(sp0.volume_db) - want_sfx) < 0.01,
			"got=%.3f want=%.3f" % [float(sp0.volume_db), want_sfx])

	# **暂停压低必须是相对量**。绝对值那一版：玩家把 BGM 拉到 20%
	# （约 -20 dB），暂停时写回 -18 就比他还响一档 —— 暂停反而变吵。
	_am.set_bgm_volume(0.2, false)
	var quiet := float(bgm_player.volume_db)
	_am.set_paused_bgm(true)
	var ducked := float(bgm_player.volume_db)
	_ck("暂停时 BGM 真的压低了", ducked < quiet,
			"%.2f -> %.2f" % [quiet, ducked])
	_ck("暂停压低的量是相对的 PAUSE_DUCK_DB（不是写死的绝对值）",
			absf((quiet - ducked) - float(_am.PAUSE_DUCK_DB)) < 0.01,
			"压低了 %.2f，PAUSE_DUCK_DB=%.2f" % [quiet - ducked, float(_am.PAUSE_DUCK_DB)])
	_ck("低音量下暂停不会变吵（20%% 那一档）", ducked < quiet,
			"20%% 音量时 %.2f -> %.2f" % [quiet, ducked])
	_am.set_paused_bgm(false)
	_ck("收掉暂停之后音量回到原样", absf(float(bgm_player.volume_db) - quiet) < 0.01,
			"%.2f" % float(bgm_player.volume_db))

	# 音量 0 不许落成负无穷：负无穷的 volume_db 在混音里会算出 NaN。
	_am.set_bgm_volume(0.0, false)
	_ck("音量 0 落成有限的 SILENT_DB（不是 -inf）",
			is_finite(float(bgm_player.volume_db)) and float(bgm_player.volume_db) <= -60.0,
			"volume_db=%.1f" % float(bgm_player.volume_db))

	_am.set_bgm_volume(0.8, false)
	_am.set_sfx_volume(0.8, false)


## ---- 3. 落盘 + 两个主人不互相抹掉 ----
func _section_persist_and_coexist() -> void:
	print("\n-- 3. 落盘与共用存档 --")
	var path := str(_am.SAVE_PATH_CFG)
	var backup: Variant = _read_or_null(path)

	_am.set_bgm_volume(0.35, false)
	_am.set_bgm_volume(0.35, true)
	_eq("音量真的落盘了", _saved_audio(path, "bgm"), 0.35)

	# **两个主人共用一份 settings.cfg**：AudioManager 写 "audio" 节，
	# QualitySettings 写 "video" 节。任何一方用 `ConfigFile.save()` 覆盖，
	# 都会把另一方玩家挑的设置抹回默认值（而两边各自都绿）。
	_qs.set_resolution(1, true)
	_am.set_sfx_volume(0.45, true)
	var cfg := ConfigFile.new()
	var ok := cfg.load(path) == OK
	_ck("存档读得回来", ok, path)
	_eq("写音量之后画质档位还在（读-改-写，不是覆盖）",
			int(cfg.get_value("video", "resolution", -1)), 1)
	_eq("写画质之后音量还在（同一件事的另一头）",
			float(cfg.get_value("audio", "sfx", -1.0)), 0.45)

	# **正对照**：只断"没被抹掉"的话，一个从不写盘的东西也能让上面全绿。
	_qs.set_resolution(2, true)
	_eq("画质那一项自己也真的落盘了", _saved_video(path, "resolution"), 2)

	if backup != null:
		var wf := FileAccess.open(path, FileAccess.WRITE)
		if wf != null:
			wf.store_string(backup)
			wf.close()
	else:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_qs.set_resolution(_qs.RESOLUTION_AUTO, false)


func _read_or_null(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var rf := FileAccess.open(path, FileAccess.READ)
	if rf == null:
		return null
	var t := rf.get_as_text()
	rf.close()
	return t


func _saved_audio(path: String, key: String) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return -1.0
	return float(cfg.get_value("audio", key, -1.0))


func _saved_video(path: String, key: String) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return -1
	return int(cfg.get_value("video", key, -1))


## ---- 4. 画面三项的纯函数 ----
func _section_video_pure() -> void:
	print("\n-- 4. 画面档位（纯函数）--")
	var res: Array = _qs.RESOLUTIONS
	_ck("分辨率档位表不是空的", res.size() > 1, "size=%d" % res.size())
	# 纯函数：headless 下 DisplayServer 是空驱动，那里量不到任何东西，
	# 而"选 1920×1080 是不是真的落成 1920×1080"是这一族唯一能量到的判据。
	_eq("自动档返回零向量（意思是这一路压根不调 window_set_size）",
			_qs.resolution_size(_qs.RESOLUTION_AUTO), Vector2i.ZERO)
	for i in range(1, res.size()):
		var v: Vector2i = _qs.resolution_size(i)
		_eq("第 %d 档解析成 %s" % [i, str(v)], v, res[i])
		_ck("第 %d 档是个真的分辨率（不是零向量）" % i, v.x > 0 and v.y > 0, str(v))
	_eq("越界下标落回零向量（不崩也不返回垃圾）",
			_qs.resolution_size(res.size() + 5), Vector2i.ZERO)

	# 屏幕比目标还小的时候**不许**去设那个尺寸：玩家拿到一个比屏幕还大的窗口，
	# 四条黑边外加一个够不着的标题栏，而按钮上明明白白写着「1920×1080」。
	var usable: Vector2i = _qs._usable_size()
	_ck("自动档一律不许设窗口", not bool(_qs.resolution_allowed(_qs.RESOLUTION_AUTO)))
	for i in range(1, res.size()):
		var want: Vector2i = res[i]
		var expect: bool = want.x <= usable.x and want.y <= usable.y
		_eq("第 %d 档在可用区 %s 之内 = %s" % [i, str(usable), str(expect)],
				bool(_qs.resolution_allowed(i)), expect)
	# 上面那几条在"可用区比全表都大"的机器上会**全部为真**，于是这一族
	# 恒绿。本脚本是无头专用的（`--headless` 下 `_usable_size()` 返回固定的
	# 保守值 1152×648），所以这里能确定"至少有一档被拒"真的发生过。
	_ck("至少有一档因为屏幕放不下而被拒（无头下可用区固定 1152×648，这条不是恒真）",
			res.size() - 1 > _allowed_count(usable),
			"通过的 %d / 共 %d，可用区 %s" % [_allowed_count(usable), res.size() - 1, str(usable)])

	_eq("窗口模式档数与名字表一致", _qs.WINDOW_MODE_NAMES.size(), 3)
	_eq("VSync 档数与名字表一致", _qs.VSYNC_NAMES.size(), 3)
	_eq("默认开着 VSync（全部定妆照量的都是那一档）", int(_qs.vsync_mode), int(_qs.DEFAULT_VSYNC))

	# Web / 移动端推不了真窗口：`window_set_size()` 在那里调下去不报错、
	# 也什么都不发生 —— 和「Web 上引擎静默从 Forward+ 掉到 Compatibility」
	# 是同一族的"没有警告的静默"，所以按平台排除，而不是调完发现没反应再回头查。
	# 本机跑回归是桌面，所以这里量的是它**真的**推得动。
	if DisplayServer.get_name() == "headless":
		_ck("无头下 video_available() 为假（不推真窗口）", not bool(_qs.video_available()))
	elif OS.has_feature("web") or OS.has_feature("mobile"):
		_ck("Web/移动端 video_available() 为假", not bool(_qs.video_available()))
	else:
		_ck("桌面 video_available() 为真", bool(_qs.video_available()))

	# 每个名字 key 中英都得在 —— 查不到时 `t()` 返回 key 自己，
	# 屏上会出现一串英文下划线而没有任何回归变红。
	var name_keys: Array = []
	for i in range(_qs.WINDOW_MODE_NAMES.size()):
		name_keys.append(_qs.WINDOW_MODE_NAMES[i])
	for i in range(_qs.VSYNC_NAMES.size()):
		name_keys.append(_qs.VSYNC_NAMES[i])
	for k in name_keys:
		var key := str(k)
		var zh: String = str(_loc.STRINGS["zh"].get(key, ""))
		var en: String = str(_loc.STRINGS["en"].get(key, ""))
		_ck("档位名 %s 中英都在且不是空串" % key, zh != "" and en != "", "zh=%s en=%s" % [zh, en])


func _allowed_count(usable: Vector2i) -> int:
	var n := 0
	var res: Array = _qs.RESOLUTIONS
	for i in range(1, res.size()):
		var v: Vector2i = res[i]
		if v.x <= usable.x and v.y <= usable.y:
			n += 1
	return n


## ---- 5. 落盘闸 + 推真窗口的顺序 ----
func _section_video_gates() -> void:
	print("\n-- 5. 画面设置的闸与顺序 --")
	var src := FileAccess.get_file_as_string("res://scripts/QualitySettings.gd")

	# `persist` 有没有默认值靠反射量不到。判据是"参数表里一个 `=` 都没有"，
	# **不是 `params.contains("persist =")`** —— 带类型的默认值长成
	# `persist: bool = true`，中间隔着 `: bool `，那个子串压根不存在，
	# 于是把默认值写回去这条照样绿（第一版就是这么写的）。
	for fn in ["set_resolution", "set_window_mode", "set_vsync"]:
		var params := _param_list(src, fn)
		_ck("%s 的参数表里一个默认值都没有" % fn,
				params != "" and not params.contains("="), "参数表=%s" % params)

	# 分辨率必须排在窗口模式**之后**：反过来写的话 `WINDOW_MODE_FULLSCREEN`
	# 会把刚设的尺寸抹掉。而顺序反了这个 bug 两侧各自都绿 —— 按钮上的字变了、
	# 窗口尺寸没变，没有任何断言量的是真窗口。
	var i_mode := src.find("DisplayServer.window_set_mode")
	var i_size := src.find("DisplayServer.window_set_size")
	_ck("apply_video() 里两处都找得到", i_mode > 0 and i_size > 0,
			"mode=%d size=%d" % [i_mode, i_size])
	_ck("分辨率排在窗口模式之后（反过来的话 FULLSCREEN 会抹掉刚设的尺寸）",
			i_size > i_mode, "mode=%d size=%d" % [i_mode, i_size])
	# 屏幕放不下时那一行必须被 `resolution_allowed()` 挡着
	_ck("设尺寸那一行前面有 resolution_allowed 闸",
			src.find("if resolution_allowed(") < i_size and src.find("if resolution_allowed(") > 0,
			"闸在 %d，目标 %d" % [src.find("if resolution_allowed("), i_size])

	# Web 排除是靠 `video_available()` 里的两个 `has_feature`，不是靠别的。
	#
	# **两处都得做**，缺一条它照样绿：
	# ① 剔注释——`QualitySettings.gd` 里有一段注释写着"Web / 移动端上
	#    `window_set_size` 是静默无效的"，不剔的话把 `video_available()`
	#    整个改成 `return true` 它量到的是那段说明；
	# ② 限死在**这个函数的函数体里**——文件里另有一处一模一样的
	#    `has_feature("web")`（默认画质档那档），扫整个文件的话
	#    改成 `return true` 之后它匹配到的是**那一处**。
	# 这正是 `edge_line_color` 那一族：断言匹配到了文档/别处而不是行为，
	# 而两侧各自都绿。
	var va := _func_body(_strip_comments(src), "video_available")
	_ck("video_available() 里排除了 web/mobile",
			va.contains("has_feature(\"web\")") and va.contains("has_feature(\"mobile\")"),
			"函数体=%s" % va.substr(0, 120))


func _param_list(src: String, fn: String) -> String:
	for line in src.split("\n"):
		if line.begins_with("func %s(" % fn):
			var sig := line.strip_edges()
			return sig.substr(sig.find("(") + 1, sig.rfind(")") - sig.find("(") - 1)
	return ""


## 剔掉行注释（GDScript 只有 `#` 行注释），保留字符串字面量里的 `#`。
## 文本判据读源码之前必须先过这一道：**注释里写着的那句话和代码真的那么干，
## 是本工程栽过两次的同一个坑**（`edge_line_color` 声明了从没被读、
## HUD3D 那块死掉的帮助面板）。
func _strip_comments(src: String) -> String:
	var out: Array = []
	for line in src.split("\n"):
		var res := ""
		var quote := ""
		for i in line.length():
			var ch := line[i]
			if quote != "":
				res += ch
				if ch == quote:
					quote = ""
			elif ch == "\"" or ch == "'":
				quote = ch
				res += ch
			elif ch == "#":
				break
			else:
				res += ch
		out.append(res)
	return "\n".join(out)


## ---- 6. 键位表只有一个出处 ----
func _section_key_table() -> void:
	print("\n-- 6. 键位表 --")
	var acts: Array = _gm.PLAYER_ACTIONS
	_ck("键位表不是空的", acts.size() >= 5, "size=%d" % acts.size())

	for entry in acts:
		var action := str(entry["action"])
		var keys: Array = entry["keys"]
		var label := str(entry["keys_label"])
		var desc_key := str(entry["desc_key"])

		_ck("InputMap 里注册了 %s" % action, InputMap.has_action(action))
		_ck("%s 的每一行都有键面写法（屏上不能是空的）" % action, label != "", "keys_label=%s" % label)
		_ck("%s 至少绑了一个键" % action, keys.size() > 0, "keys=%s" % str(keys))

		var zh: String = str(_loc.STRINGS["zh"].get(desc_key, ""))
		var en: String = str(_loc.STRINGS["en"].get(desc_key, ""))
		_ck("%s 的说明 %s 中英都在" % [action, desc_key], zh != "" and en != "", "zh=%s en=%s" % [zh, en])

	# **注册走的就是这张表**（钉住"注册处与屏上那份不是两份独立的手抄"）。
	# 这是读源码文本的判据：`_setup_input_map()` 的函数体里那个 `for … PLAYER_ACTIONS`
	# 循环必须在，而且循环之外不许再有拿字面量键列表的 `_add_action(` 调用
	# —— 把循环改回逐行手抄的话，下面两条一起红。
	#
	# 第一版这一节写的是"表里每个键都注册进 InputMap 了"。**那条恒绿**：
	# 注册恰恰是从这张表生成的，拿表去对表必然一致。它量的是"我抄得对吗"，
	# 而产品上的风险是"有人又添了第二份出处"。一条恒绿的断言比没有还坏——
	# 它让人以为这一族有人守着。
	var gm_src := _strip_comments(FileAccess.get_file_as_string("res://scripts/GameManager.gd"))
	var body := _func_body(gm_src, "_setup_input_map")
	var i_loop := body.find("for entry in PLAYER_ACTIONS")
	_ck("注册走的是 PLAYER_ACTIONS 那个循环，不是逐行手抄", i_loop >= 0,
			"_setup_input_map() 里找不到那个循环")
	_ck("循环里调的是 _add_action(entry[\"action\"], entry[\"keys\"])",
			body.contains("_add_action(str(entry[\"action\"]), entry[\"keys\"])"))
	# 循环之外那些 `_add_action` 带的是**编辑模式动作**（`editor_*`），
	# 它们本来就不在玩家要记的那张表里，不算第二份出处。要钉的是
	# "玩家那几个动作名又被人拿字面量键列表注册了一遍"。
	var tail := body.substr(i_loop) if i_loop >= 0 else ""
	var after_loop := tail.substr(tail.find("\n"))
	var re_added: Array = []
	for line in after_loop.split("\n"):
		var s := line.strip_edges()
		if not s.begins_with("_add_action("):
			continue
		for entry in acts:
			if s.contains("\"%s\"" % str(entry["action"])):
				re_added.append(str(entry["action"]))
	_ck("循环之外没有第二份玩家键位的手抄（editor_* 那些不算）",
			re_added.is_empty(), "又逐行注册了 %s" % str(re_added))

	# **冷启动引导那份不许是第二份手抄**：它原来就是一份独立的结构化 Label。
	#
	# 同样**必须先剔注释**。这两个文件里各有一行注释写着
	# "所以它们调 `GameManager.player_control_rows()` 这一个出处"——
	# 把真正的调用换成手抄数组之后，`contains()` 仍然为真，
	# 因为它量到了那句说明。突变验证就是这么发现的（12 条里这两条一条没红）。
	var ob_src := _strip_comments(FileAccess.get_file_as_string("res://scripts/OnboardingGuide.gd"))
	_ck("冷启动操作说明走的是 GameManager.player_control_rows()",
			ob_src.contains("GameManager.player_control_rows()"))
	_ck("触屏那三行也走同一个出处",
			ob_src.contains("GameManager.touch_control_rows()"))

	# 屏上那份表的行数必须等于这张表 —— 冷启动引导与设置面板读的是同一个出处，
	# 所以这里量的是"两者行数相同且逐行相同"，量的是**产品后果**而不是
	# "它们调的是同一个函数"（那等于拿自己测自己）。
	var want: Array = _gm.player_control_rows()
	_ck("player_control_rows() 每一行都有键和说明",
			want.size() == acts.size() and all_rows_filled(want),
			"rows=%d acts=%d" % [want.size(), acts.size()])
	for i in range(mini(want.size(), acts.size())):
		_eq("第 %d 行的键与表一致" % i, str(want[i][0]), str(acts[i]["keys_label"]))

	var touch: Array = _gm.touch_control_rows()
	_ck("触屏键位表三行都有内容", touch.size() == 3 and all_rows_filled(touch))


## 取一个函数从 `func xxx` 到下一个顶格 `func` 之间的正文。
func _func_body(src: String, fn: String) -> String:
	var start := src.find("func %s(" % fn)
	if start < 0:
		return ""
	# 下一个函数的行首。**要认 `static func`**：只找 `"\nfunc "` 的话，
	# 一个 static 函数后面若跟的是另一个 static 函数，正文会一路取到文件末尾，
	# 于是"这个函数里有 X"实际上量的是"这个文件里有 X"。
	var lines := src.substr(start).split("\n")
	var body: Array = []
	for i in lines.size():
		if i > 0:
			var t := lines[i].strip_edges()
			if t.begins_with("func ") or t.begins_with("static func "):
				break
		body.append(lines[i])
	return "\n".join(body)


func all_rows_filled(rows: Array) -> bool:
	for r in rows:
		if str(r[0]) == "" or str(r[1]) == "":
			return false
	return true


## ---- 7. 面板真能开 ----
func _section_panel() -> void:
	print("\n-- 7. 设置面板 --")
	_gm.reset()
	_gm.onboarding_shown = true
	_gm.prologue_done = true
	_gm.headless_mode = true

	var world: Node = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(world)
	await create_timer(3.0).timeout

	var panel: Control = world.get_node_or_null("SettingsPanel")
	_ck("场景里有设置面板", panel != null)
	if panel == null:
		world.queue_free()
		return
	_ck("面板开场是不可见的", not panel.visible)

	# **两个入口必须进同一个实例**。两块面板各写一份的话键位表立刻又多一份
	# —— 而它已经有四次前科。
	var hud: Node = world.get_node_or_null("HUD3D")
	var pause: Node = world.get_node_or_null("PausePanel")
	_ck("HUD3D 与 PausePanel 都在", hud != null and pause != null)

	var help_btn: Button = null
	if hud != null:
		help_btn = hud.get_node_or_null("TopRightHBox/HelpBtn")
		_ck("顶栏右上角那个「?」按钮在", help_btn != null)
		_ck("「?」按钮键盘可达", help_btn != null and help_btn.focus_mode != Control.FOCUS_NONE,
				"focus_mode=%d" % (help_btn.focus_mode if help_btn != null else -1))

	if help_btn != null:
		# 这个按钮原来压根没接线（`show_help()` 零调用者，
		# 场景文件里也没有 [connection] 段）—— 按钮**存在**不等于**接上了**。
		help_btn.emit_signal("pressed")
		await process_frame
		_ck("按「?」之后设置面板真的开了", panel.visible)
		var close_btn: Button = panel.get_node_or_null("Panel/VBox/CloseBtn")
		_ck("面板上有关闭按钮", close_btn != null)
		if close_btn != null:
			# 只断 `focus_mode`：headless 的 dummy display server **不做真焦点路由**
			# （CLAUDE.md 陷阱清单里「headless 测不出小游戏的按键」是同一条），
			# 所以"焦点真的落在它身上"只有带窗口的 `verify_panel_keyboard.gd` 量得到，
			# 在这里量只会得到一个与被测性质无关的假红。
			_ck("关闭按钮键盘可达（focus_mode 不是 NONE）",
					close_btn.focus_mode != Control.FOCUS_NONE, "focus_mode=%d" % close_btn.focus_mode)
			close_btn.emit_signal("pressed")
			await process_frame
			_ck("按关闭按钮之后面板收了", not panel.visible)

	# 暂停菜单那一行走的是同一个实例
	if pause != null:
		var settings_btn: Button = pause.get_node_or_null("Overlay/Panel/VBox/HelpBtn")
		_ck("暂停菜单里有那一行「设置」", settings_btn != null)
		if settings_btn != null:
			pause.visible = true
			settings_btn.emit_signal("pressed")
			await process_frame
			_ck("从暂停菜单进去开的是同一块面板", panel.visible)
			_ck("暂停菜单那行显示的是「设置」而不是「操作说明」",
					settings_btn.text != "" and not settings_btn.text.contains("操作说明"),
					"text=%s" % settings_btn.text)
			panel.call("close")
			pause.visible = false
			await process_frame

	# 三档静音按钮已经不在暂停菜单里了（它们是音量滑杆拉到 0 这一个状态）
	var vbox: Node = pause.get_node_or_null("Overlay/Panel/VBox") if pause != null else null
	if vbox != null:
		for gone in ["MuteBtn", "BgmBtn", "SfxBtn"]:
			_ck("暂停菜单里不再有 %s（音量滑杆取代了它）" % gone,
					vbox.get_node_or_null(gone) == null)

	# 面板里的三段：音量 / 画面 / 操作说明
	var body: Node = panel.get_node_or_null("Panel/VBox/Scroll/Body")
	_ck("面板内容装在 ScrollContainer 里（内容比容器高是它本来的活）", body != null)
	if body != null:
		# 滑杆在**自己那一行 HBox 里面**（`_add_slider` 建的行叫 `BgmSliderRow`，
		# 滑杆是它的子节点）——第一版按 `Body/BgmSlider` 找，量的是一个不存在
		# 的路径，报出来的是"尺子取错格子"而不是产品坏了。
		for row_name in ["BgmSliderRow", "SfxSliderRow"]:
			var row: Node = body.get_node_or_null(row_name)
			_ck("面板里有 %s 那一行" % row_name, row != null)
			if row != null:
				# 行名带 `Row` 后缀，滑杆自己没有（`_add_slider` 的两处 `name`）。
				var sl: HSlider = row.get_node_or_null(row_name.trim_suffix("Row"))
				_ck("%s 那一行里真的有滑杆（不是只建了个空行）" % row_name, sl != null)
		for b in ["ResolutionBtn", "WindowBtn", "VsyncBtn"]:
			_ck("面板里有画面按钮 %s" % b, body.get_node_or_null(b) != null)
		# 滑杆读数必须等于**真状态**，不是建面板那一刻的值
		var bgm_slider: HSlider = body.get_node_or_null("BgmSliderRow/BgmSlider")
		_am.set_bgm_volume(0.7, false)
		panel.call("open")
		await process_frame
		if bgm_slider != null:
			_ck("打开面板时滑杆对齐的是当前真音量（不是建面板那一刻的值）",
					absf(bgm_slider.value - float(_am.bgm_volume())) < 0.01,
					"slider=%.2f 真值=%.2f" % [bgm_slider.value, float(_am.bgm_volume())])
		# 拖滑杆要真的推音量
		if bgm_slider != null:
			bgm_slider.value = 0.25
			bgm_slider.emit_signal("value_changed", 0.25)
			await process_frame
			_ck("拖滑杆真的改了音量（接线不是断的）",
					absf(float(_am.bgm_volume()) - 0.25) < 0.01,
					"真值=%.2f" % float(_am.bgm_volume()))

		# **读源码文本**：几何/控件断言量得到"控件在不在"，量不到
		# "画笔/构造有没有真的调它"。控件的行文出处必须真的是
		# `player_control_rows()` —— 否则这就是第五份手抄。
		#
		# 剔注释：`SettingsPanel.gd` 第 169 行那句注释里就写着
		# "键位表**不是**这里抄的：`GameManager.player_control_rows()` 是冷启动的"，
		# 不剔的话把真正的调用换成手抄数组这条照样绿（突变验证发现的）。
		var src := _strip_comments(FileAccess.get_file_as_string("res://scripts/SettingsPanel.gd"))
		_ck("操作说明走的是 GameManager.player_control_rows()（不是第五份手抄）",
				src.contains("GameManager.player_control_rows()"))

	world.queue_free()
	await process_frame


## ---- 8. 关闭按钮不许被顶出屏 ----
func _section_fits() -> void:
	print("\n-- 8. 面板装得下 --")
	_gm.reset()
	_gm.onboarding_shown = true
	_gm.headless_mode = true
	var world: Node = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(world)
	await create_timer(3.0).timeout

	var panel: Control = world.get_node_or_null("SettingsPanel")
	if panel == null:
		world.queue_free()
		return
	panel.call("open")
	await process_frame

	var close_btn: Control = panel.get_node_or_null("Panel/VBox/CloseBtn")
	_ck("关闭按钮存在", close_btn != null)
	if close_btn != null:
		var vp: Vector2 = Vector2(panel.get_viewport().get_visible_rect().size)
		var r: Rect2 = close_btn.get_global_rect()
		_ck("关闭按钮整个在屏内（不许被内容顶出下沿）",
				r.position.y >= 0.0 and r.end.y <= vp.y + 0.5
					and r.position.x >= 0.0 and r.end.x <= vp.x + 0.5,
				"视口=%s 按钮=%s" % [str(vp), str(r)])

	# 英文才是卡边的那一份：每行的字更长、行数更多。
	# `Localization.language_changed` 会自动把面板重刷一遍（`SettingsPanel._ready()`
	# 里连着的），所以这里只要等两帧让容器重新排版。
	_loc.set_language("en")
	await process_frame
	await process_frame
	if close_btn != null:
		var r2: Rect2 = close_btn.get_global_rect()
		var vp2: Vector2 = Vector2(panel.get_viewport().get_visible_rect().size)
		_ck("英文下关闭按钮也还在屏内",
				r2.position.y >= 0.0 and r2.end.y <= vp2.y + 0.5,
				"视口=%s 按钮=%s" % [str(vp2), str(r2)])
	_loc.set_language("zh")

	world.queue_free()
	await process_frame
