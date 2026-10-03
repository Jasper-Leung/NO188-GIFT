extends SceneTree
## 画质档位回归 —— 低/中/高三档真的接到了世界、存档、按钮和键盘上。
##
## 这一族从 NO188-GIFT-REF 那条线搬过来。原作本项目**没有**：本作零贴图、满屏草皮
## 和行道树，而草皮最贵（一格 ring 0 约 10ms，见 `GrassScatter` 的建格预算）——
## "这台机器铺 200m 铺不动"只有跑过一次才知道，而顶栏、按钮、驿站全都不给玩家
## 任何办法降档。
##
## 这条回归守六件事：
##   1. 三档的代价必须**单调**：低档比高档更省，否则"低"只是个名字。
##   2. 桌面默认 high —— 全部回归量的都是那一档，低档等于让三十多条回归在不知情
##      的情况下量一个缩水的世界。
##   3. 档位要真的落到世界上：太阳 `shadow_enabled`、草皮/行道树的加载半径。
##      **半径这条必须量"setup() 之后 `_radius` 变成了多少"**，不是量
##      `radius_override` 那个字段被写了——字段写了而 setup() 没读它，
##      或者写了但被 `target_radius()` 盖回去，都属于"接线断了而两边各自都绿"。
##   4. 中途切档只有阴影当场生效，植被半径要下一趟 —— 所以面板上那行提示必须存在。
##      玩家看不到这半句就会以为按钮坏了。
##   5. **落盘闸**：`set_tier(t, persist)` 的 `persist` 没有默认值，任何只想改内存的
##      调用都必须自己说清。低档会关阴影、砍植被半径，于是"回归顺手把玩家存档改成
##      低档"会让后面一串回归量的是一个和平时不同的世界——从 CLAUDE.md 的原型注释
##      里抄来的教训（那边为此连撞了 6/6 次间歇性段错误，现场完全看不出是存档的锅）。
##   6. 面板在 720p / 1280 高下都装得下，且画质按钮键盘可达（`focus_mode` + 真的
##      在按钮排里）。
##
## 用法： godot --headless --path . --script tools/verify_quality_settings.gd --quit-after 40000
## 注意 --quit-after 单位是帧不是秒（本机 280+FPS，给小了会把脚本掐在场景加载处）。

var _fails: Array = []
var _oks := 0
var _gm: Node = null
var _loc: Node = null
var _qs: Node = null
var _world: Node = null


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
	print("=== 画质档位回归 ===")

	_gm = root.get_node_or_null("GameManager")
	_loc = root.get_node_or_null("Localization")
	_qs = root.get_node_or_null("QualitySettings")
	if _gm == null or _loc == null or _qs == null:
		print("[ABORT] 拿不到 autoload（QualitySettings 没注册进 project.godot？）")
		quit(1)
		return

	_section_params()
	_section_defaults_and_loc()
	_section_persist_gate()
	await _section_real_world()
	await _section_panel()

	print("\n=== 结果：OK %d / FAIL %d ===" % [_oks, _fails.size()])
	for f in _fails:
		print("  [FAIL] ", f)
	quit(0 if _fails.is_empty() else 1)


## ---- 1. 三档的代价必须单调 ----
func _section_params() -> void:
	print("\n-- 1. 三档参数 --")
	var P: Array = _qs.PARAMS
	_eq("三档齐了", P.size(), 3)
	_eq("档位数常量与参数表一致", _qs.TIER_COUNT, P.size())

	var lo: Dictionary = P[_qs.QUALITY_LOW]
	var me: Dictionary = P[_qs.QUALITY_MEDIUM]
	var hi: Dictionary = P[_qs.QUALITY_HIGH]

	# 阴影：低档是这台机器上最干净的一刀（影子要整场景重画深度图）。
	_eq("低档关太阳阴影", bool(lo["shadows"]), false)
	_eq("中档开阴影", bool(me["shadows"]), true)
	_eq("高档开阴影", bool(hi["shadows"]), true)

	# 植被半径：必须逐档收得更紧，否则"低"只是名字。
	#
	# **高档那一格要化成"生效值"再比**：表里写的是 -1（不动，沿用平台默认），
	# 拿 -1 直接比的话 lo < me < hi 恒不成立——而那不是产品坏了，是这一格
	# 故意不落数字。所以用 `target_radius()`（static、不碰 autoload，运行时
	# load 避开 `--script` 模式那个编译期拉依赖的坑）把高档解析成玩家真拿到
	# 的那个数，比的才是"三档谁更贵"。
	var gs: Script = load("res://scripts/GrassScatter.gd")
	var ts: Script = load("res://scripts/TreeScatter.gd")
	var lo_g := float(lo["grass_radius"])
	var me_g := float(me["grass_radius"])
	var hi_g := float(hi["grass_radius"])
	var hi_g_eff: float = gs.target_radius()
	_ck("草皮半径逐档收得更紧（低 < 中 < 高）",
			lo_g < me_g and me_g < hi_g_eff,
			"%.0f / %.0f / %.0f（高档写的是 %.0f）" % [lo_g, me_g, hi_g_eff, hi_g])
	var lo_t := float(lo["tree_radius"])
	var me_t := float(me["tree_radius"])
	var hi_t := float(hi["tree_radius"])
	var hi_t_eff: float = ts.target_radius()
	_ck("行道树半径逐档收得更紧（低 < 中 < 高）",
			lo_t < me_t and me_t < hi_t_eff,
			"%.0f / %.0f / %.0f（高档写的是 %.0f）" % [lo_t, me_t, hi_t_eff, hi_t])
	# 高档是 -1 = "不动，沿用平台默认"。这里要钉的是**那层意思**：
	# 改成一个具体的数不会让上面两条变红（还是比得过 110/90），可它会让
	# "桌面 200m"这个所有回归都在量的世界悄悄换成另一个半径。
	_ck("高档不写死草皮半径（沿用 target_radius()，全部回归量的就是那一档）",
			hi_g < 0.0, "grass_radius=%f" % hi_g)
	_ck("高档不写死行道树半径（同上）", hi_t < 0.0, "tree_radius=%f" % hi_t)
	# 顺带钉住"沿用平台默认"这件事真的是沿用桌面那档：这一趟跑的机器没有
	# web/mobile feature，所以 target_radius() 就该是 World3D.tscn 那一组数。
	_eq("草皮高档的生效值就是 target_radius()（本机 200m）", hi_g_eff, 200.0)
	_eq("行道树高档的生效值就是 target_radius()（本机 150m）", hi_t_eff, 150.0)

	# 三档都**不动** 3D 渲染分辨率 —— 实测 Compatibility 下 scaling_3d_scale
	# 反而更慢（多一条全屏 blit 通道）。所以判据是"表里根本没有这一项"。
	var has_scale := false
	for key in lo.keys():
		if String(key).contains("scale"):
			has_scale = true
	_ck("三档都不动 3D 渲染分辨率（实测降分辨率反而更慢）", not has_scale,
			"low 的键：%s" % str(lo.keys()))


## ---- 2. 默认档 + 文案 ----
func _section_defaults_and_loc() -> void:
	print("\n-- 2. 默认档与文案 --")
	# 桌面默认 high。本机跑回归时 OS.has_feature("web"/"mobile") 都是假，
	# 所以这一条量到的就是桌面那一档——也正是全部回归量的那一档。
	_eq("桌面默认高档（全部回归量的就是这一档）", int(_qs.tier), int(_qs.QUALITY_HIGH))

	for i in range(3):
		var k: String = str(_qs.TIER_NAME_KEYS[i])
		var zh: String = str(_loc.STRINGS["zh"].get(k, ""))
		var en: String = str(_loc.STRINGS["en"].get(k, ""))
		_ck("档位名 %s 中英都在且不是空串" % k, zh != "" and en != "", "zh=%s en=%s" % [zh, en])
		_ck("档位名 %s 中英不是同一句" % k, zh != en)
	var hint_zh := str(_loc.STRINGS["zh"].get("quality_hint", ""))
	_ck("面板提示中英都在", hint_zh != ""
			and str(_loc.STRINGS["en"].get("quality_hint", "")) != "")
	# 提示必须说清"植被范围下一趟才生效"这件事：切档之后只有阴影当场变，
	# 玩家看不到这半句就会以为按钮坏了。
	_ck("提示说清了植被范围要重新进这一趟才生效",
			hint_zh.contains("下一趟") or hint_zh.contains("生效"),
			"zh=%s" % hint_zh)


## ---- 3. 落盘闸 ----
func _section_persist_gate() -> void:
	print("\n-- 3. 落盘闸 --")
	# 存档先备份。这条测试**不许**把开发机画质改成低档。
	var path := str(_qs.SAVE_PATH_CFG)
	var backup: Variant = _read_or_null(path)

	# 判据是"存档一个字节都没动"，而不是"存档里存着 high"——后者在这台机器上
	# 根本没成立过：`_load_tier()` 只**读**不写，玩家没挑过档位时那个文件压根不存在。
	# 按不存在的文件写断言，测出来的红是"前提错了"而不是"闸坏了"。
	_qs.persist_enabled = false
	_qs.set_tier(_qs.QUALITY_LOW, true)
	_eq("内存里的档位真的翻了", int(_qs.tier), 0)
	var after: Variant = _read_or_null(path)
	_ck("persist_enabled=false 时存档一个字节都没动",
			after == backup,
			"跑之前存在=%s，跑之后存在=%s" % [backup != null, after != null])

	# **必须有这个正对照**：只测"闸没开"的话，一个从来就不落盘的 `set_tier`
	# 也能让上面那条绿一辈子。闸开着的时候要真的写到。
	_qs.persist_enabled = true
	_qs.set_tier(_qs.QUALITY_HIGH, true)
	_eq("persist_enabled=true 时确实落盘了（否则上面那条恒真）", _saved_tier(path), 2)

	# 读源码文本：`persist` 有没有默认值，靠反射量不到，而"曾经写成 persist := true"
	# 正是原型那边栽的地方（任何只想改内存的调用都会顺手改掉玩家存档）。
	#
	# **判据是"参数表里一个 `=` 都没有"，不是 `sig.contains("persist =")`**：
	# 第一版找的就是那个子串，而带类型的默认值长成 `persist: bool = true`——
	# 中间隔着 `: bool `，那个子串压根不存在，于是把默认值写回去这条**照样绿**。
	# 一条恒绿的断言比没有还坏：它让人以为这一族有人守着。
	var src := FileAccess.get_file_as_string("res://scripts/QualitySettings.gd")
	var sig := ""
	for line in src.split("\n"):
		if line.begins_with("func set_tier("):
			sig = line.strip_edges()
			break
	var params := ""
	if sig != "":
		params = sig.substr(sig.find("(") + 1, sig.rfind(")") - sig.find("(") - 1)
	_ck("set_tier 的参数表里一个默认值都没有（每个调用点都得自己说清要不要落盘）",
			sig != "" and not params.contains("="), "参数表=%s" % params)

	if backup != null:
		var wf := FileAccess.open(path, FileAccess.WRITE)
		if wf != null:
			wf.store_string(backup)
			wf.close()
	else:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## 存档整份文本；文件不存在时返回 null（而不是空串——"空文件"和"没这个文件"
## 在这里要分得清：前者是玩家挑过档位又清空，后者是压根没碰过画质设置）。
func _read_or_null(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var rf := FileAccess.open(path, FileAccess.READ)
	if rf == null:
		return null
	var t := rf.get_as_text()
	rf.close()
	return t


func _saved_tier(path: String) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return -1
	return int(cfg.get_value("video", _qs.SAVE_KEY, -1))


## ---- 4. 真的落到世界上 ----
func _section_real_world() -> void:
	print("\n-- 4. 档位真的落到世界上 --")
	_gm.reset()
	_gm.onboarding_shown = true
	_gm.prologue_done = true
	_gm.headless_mode = true

	# 先切到低档再起世界：World3D._ready() 在两个散落体 setup **之前**调
	# apply_to_world()，所以半径得在那之前就摆好。这一档也让建池便宜一半。
	_qs.set_tier(_qs.QUALITY_LOW, false)

	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	await create_timer(3.0).timeout

	var sun: DirectionalLight3D = _world.get_node_or_null("DirectionalLight3D")
	_ck("场景里有太阳", sun != null)
	if sun != null:
		_eq("低档：太阳阴影确实关了（World3D 起来之后读的档）", sun.shadow_enabled, false)

	# **这条是这一族的核心**：量 setup() 之后的 `_radius`，不是量
	# `radius_override` 那个字段被写了。字段写了而 setup() 没读它、或者写了
	# 又被 `target_radius()` 盖回去，都属于"接线断了而两边各自都绿"。
	var grass: Node = _world.get_node_or_null("GrassScatter")
	var tree: Node = _world.get_node_or_null("TreeScatter")
	_ck("场景里有草皮与行道树", grass != null and tree != null)
	if grass == null or tree == null:
		return
	var g_rad: float = float(grass.get("_radius"))
	var t_rad: float = float(tree.get("_radius"))
	_ck("草皮加载半径跟着档位走（不是 target_radius 的 200m）",
			absf(g_rad - 70.0) < 0.5, "%.1fm" % g_rad)
	_ck("行道树加载半径跟着档位走（不是 target_radius 的 150m）",
			absf(t_rad - 70.0) < 0.5, "%.1fm" % t_rad)
	# 淡出带不能比加载半径还远，否则整圈草都淡成 0——半径一改它必须跟着收。
	#
	# 这里量的是**材质上那个 `fade_end` 参数**，不是某个字段：淡出带压根没有成员
	# 变量，`apply_ground_fade()` 每次现算再 `set_shader_parameter()` 写进去，而
	# `World3D._stream_focus_pos()` 每帧又用 `set_fade_for_camera()` 按相机高度
	# 把它外扩——所以这里先显式调一次地面那版（玩家正常骑行的相机离地 1.6m，
	# 走的正是这一条），紧接着读回来。
	var mat: ShaderMaterial = grass.call("grass_material")
	grass.call("apply_ground_fade")
	var fade_end: float = float(mat.get_shader_parameter("fade_end"))
	_ck("草皮淡出带跟着半径收（没有落在加载半径之外，否则整圈草淡成 0）",
			fade_end > 0.0 and fade_end <= g_rad + 0.5,
			"fade_end=%.1f radius=%.1f" % [fade_end, g_rad])
	# 反过来也要钉住"它真的跟着半径走"：低档 70m 时淡出带必须明显短于桌面档的
	# 200m，否则半径收紧了而淡出带还留在 200——那时 70m 那一圈全部落在
	# fade_start 之前，看着就是"低档的草一丛都不长"。
	_ck("低档的淡出带明显短于桌面档那一组（不是忘了跟着半径收）",
			fade_end < 100.0, "fade_end=%.1f（桌面档是 200）" % fade_end)

	# 中途切档：阴影当场生效，植被半径只写回 override 供下一趟。
	_qs.set_tier(_qs.QUALITY_HIGH, false)
	_qs.apply_to_world(_world)
	_eq("中途切到高档：阴影当场打开", sun.shadow_enabled, true)
	_ck("中途切到高档：半径 override 让位回平台默认（不是粘在低档那个数上）",
			absf(float(grass.get("radius_override"))) < 0.001,
			"radius_override=%f" % float(grass.get("radius_override")))
	_eq("行道树的 override 也让位回平台默认",
			absf(float(tree.get("radius_override"))) < 0.001, true)
	_ck("中途切档不重建草皮（_radius 仍是这一趟建好的那个）",
			absf(float(grass.get("_radius")) - g_rad) < 0.5,
			"%.1f" % float(grass.get("_radius")))

	_world.queue_free()
	await process_frame
	_qs.set_tier(_qs.QUALITY_HIGH, false)


## ---- 5. 面板装得下 + 键盘可达 ----
func _section_panel() -> void:
	print("\n-- 5. 暂停面板 --")
	_gm.reset()
	_gm.onboarding_shown = true
	_gm.headless_mode = true
	var world: Node = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(world)
	await create_timer(3.0).timeout

	var panel: Node = world.get_node_or_null("PausePanel")
	_ck("场景里有暂停面板", panel != null)
	if panel == null:
		world.queue_free()
		return
	var vbox: Node = panel.get_node_or_null("Overlay/Panel/VBox")
	var btn: Button = panel.get_node_or_null("Overlay/Panel/VBox/QualityBtn")
	var hint: Label = panel.get_node_or_null("Overlay/Panel/VBox/QualityHintLabel")
	_ck("面板里有画质按钮与提示行", btn != null and hint != null)

	if btn != null:
		_ck("画质按钮键盘可达（focus_mode 不是 NONE）",
				btn.focus_mode != Control.FOCUS_NONE, "focus_mode=%d" % btn.focus_mode)
		# 切档之后按钮文字必须跟着换（玩家靠它确认自己挑的是哪一档）
		var before: String = btn.text
		btn.emit_signal("pressed")
		var after: String = btn.text
		_ck("按一下画质按钮之后档位真的翻了",
				before != after, "%s -> %s" % [before, after])
		# 复原，免得后面的断言量在低档上
		btn.emit_signal("pressed")
		btn.emit_signal("pressed")

	# 面板那一列现在有九个控件。按 CLAUDE.md 那条"按窗口高度的百分比取的尺寸在别的
	# 分辨率上必然越界"的同族教训，这里量的是**面板自己的内容区**装不装得下，
	# 而 VBox 的最小高度会随内容长高 —— 装不下时它不会报错，只会把最下面那两行
	# （正好是新增的画质按钮和提示）顶出面板下沿。
	if vbox != null and btn != null:
		await _content_fits(panel, vbox, btn, 1280, 720)
		await _content_fits(panel, vbox, btn, 1280, 1080)
		# **英文那一句才是卡边的那一份**：提示行 33 个中文字占 396px，一行就放得下；
		# 英文 108 个字符约 650px，同样的框宽下要折成两行——只量中文的话
		# 面板在英文界面下溢出，而中文那一份量着宽裕得很。
		_loc.set_language("en")
		panel.call("_apply_language")
		await process_frame
		await _content_fits(panel, vbox, btn, 1280, 720, "EN")
		await _content_fits(panel, vbox, btn, 1280, 1080, "EN")
		_loc.set_language("zh")
		panel.call("_apply_language")

	world.queue_free()
	await process_frame


## 面板内容区装不装得下那一列。用真实控件的最小高度，不许拿"它们互不叠"充数。
func _content_fits(panel: Node, vbox: Node, btn: Button, vw: int, vh: int, tag: String = "") -> void:
	# **必须真的把窗口改成那一档**。之前两行都量的是同一个 rect（headless 下
	# 视口是固定的 project.godot 窗口大小），于是"720p 和 1080p 都装得下"
	# 实际上只量了一次——而按窗口高度的百分比取的尺寸恰恰是那种换一台
	# 机器就失效的东西（见 CLAUDE.md 陷阱清单里"百分比尺寸在别的分辨率上
	# 必然越界"那一条）。改完要等一帧，容器才按新尺寸重排。
	root.size = Vector2i(vw, vh)
	await process_frame
	await process_frame
	var panel_rect: Rect2 = (panel.get_node("Overlay/Panel") as Control).get_global_rect()
	var need: float = vbox.get_combined_minimum_size().y
	var avail: float = panel_rect.size.y - 40.0     # .tscn 里 VBox 上下各留 20
	var at := "%dx%d%s" % [vw, vh, (" " + tag) if tag != "" else ""]
	_ck("暂停面板那一列在 %s 下装得下（最下面两行不许被顶出去）" % at,
			need <= avail, "需要 %.0fpx，可用 %.0fpx" % [need, avail])
	var btn_bottom: float = btn.get_global_rect().end.y
	_ck("画质按钮在 %s 下没有掉出面板下沿" % at,
			btn_bottom <= panel_rect.end.y + 0.5,
			"按钮下沿 %.0f，面板下沿 %.0f" % [btn_bottom, panel_rect.end.y])
