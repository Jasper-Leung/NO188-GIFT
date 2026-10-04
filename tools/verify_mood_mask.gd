extends SceneTree
## 心神遮罩 + 顶部经济栏回归 —— 用真实 World3D 场景验证「心神 → 遮罩」的接线。
##
## 只测接线，不重算数值：期望值一律取 GameManager.get_mood_mask_alpha() 自己给的结果，
## 数学口径由 verify_economy.gd 第 7 节负责。
##
## 覆盖：
##   1. 遮罩存在、全屏、mouse_filter = IGNORE，且位于 HUD3D 子节点 index 0（最底层）
##   2. TopBar 多出旅币 / 心神两个标签，文字跟 GameManager 同步
##   3. 骑行档（未脉冲）透明度收敛到 GameManager 目标 × MOOD_REST_SCALE
##   4. 心神 5→1 时遮罩单调变浓，**且骑行档永远低于可读上限**
##   5. 遮罩只随心神走：买灯笼 / 香囊不会把遮罩淡回去
##   6. 可见系数真的传到草皮（shader fade_*）与行道树（visibility_range_end），
##      驻留半径不动
##   7. 入账时浮出一条「+N 旅币」toast，且顶栏**不重排**（余额/心神/下一处都不许位移）
##   8. 叙事脉冲：亮起对白时冲上叙事档、收掉后退回骑行档
##
## 第 4 条的"可读上限"是这个文件存在的主要理由。改之前遮罩是常驻的：心神初始 4、
## 每收一块碎片 −1，于是从第 3 块碎片起（5 块里最长的一半流程）屏幕永久挂着
## 一层雾 —— 玩家在最需要看清路去找剩下几块碎片的时候看得最差。MOOD_MASK_MAX
## 仍然是叙事档的天花板，只是不该在骑行时长期占着它。
## 天花板本身也从 0.52 降到 0.34：收满五块碎片正好把心神打到 1，而 1 就是
## 那一档，于是**集齐二选一那面面板**——全场信息量最大的那一刻——是最暗的。
## 降它的前提是心神有一条上行口（`restore_mood()` + 茶铺的清心茶），
## 否则玩家只剩一条单向的下水道。
##
## 用法： godot --headless --path . --script tools/verify_mood_mask.gd --quit-after 30000
## 注意 --quit-after 单位是帧不是秒（本机 280+FPS，90 帧只有 0.3 秒，
## 会把脚本掐死在场景加载处，只剩一串 warning 看着像通过）。

var _fails: Array = []
var _oks := 0
var _gm: Node = null
var _loc: Node = null
var _world: Node = null
var _hud = null


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


func _approx(label: String, got: float, want: float, eps: float = 0.005) -> void:
	_ck(label, absf(got - want) <= eps, "got=%.4f want=%.4f" % [got, want])


func _mask_alpha() -> float:
	return float(_hud._mood_mask.modulate.a)


## 骑行档的目标值：叙事档乘 MOOD_REST_SCALE。
func _rest_target() -> float:
	return float(_gm.get_mood_mask_alpha()) * float(_hud.MOOD_REST_SCALE)


## 叙事档的目标值。
func _narr_target() -> float:
	return float(_gm.get_mood_mask_alpha())


## 等到遮罩收敛到 want。按差值收敛而不是按时间睡：headless 下帧率不可预测
## （可能远超 60FPS，delta 极小），写死秒数容易两头不靠。
func _settle_to(want: float, cap_msec: int = 4000) -> void:
	var t0 := Time.get_ticks_msec()
	while absf(_mask_alpha() - want) > 0.002:
		if Time.get_ticks_msec() - t0 > cap_msec:
			break
		await process_frame


## 等到遮罩落回骑行档。
func _settle(cap_msec: int = 4000) -> void:
	await _settle_to(_rest_target(), cap_msec)


## 脉冲标志每个物理帧都被 World3D 重写，所以这一段必须按物理帧等。
func _settle_pulse(want: float, cap_msec: int = 4000) -> void:
	var t0 := Time.get_ticks_msec()
	while absf(_mask_alpha() - want) > 0.002:
		if Time.get_ticks_msec() - t0 > cap_msec:
			break
		await physics_frame


## 等到两套流式都把 GameManager 给的可见系数吃进去。系数是 World3D 在
## _physics_process 里每帧推的，所以要等一个物理帧；按值收敛同样比按时间睡稳。
func _settle_factor(cap_msec: int = 4000) -> void:
	var want := float(_gm.get_visibility_factor())
	var t0 := Time.get_ticks_msec()
	while absf(float(_world._grass_scatter.visibility_factor()) - want) > 0.0005 \
			or absf(float(_world._tree_scatter.visibility_factor()) - want) > 0.0005:
		if Time.get_ticks_msec() - t0 > cap_msec:
			break
		await physics_frame


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== 心神遮罩 + 经济栏回归 ===")

	_gm = root.get_node_or_null("GameManager")
	# 不能直接写 Localization.t(...)：--script 模式下 analyzer 解析不到 autoload
	# 全局名，直接 Identifier not found 编译失败。一律走 root.get_node()。
	_loc = root.get_node_or_null("Localization")
	if _gm == null or _loc == null:
		print("[ABORT] 拿不到 autoload")
		quit(1)
		return

	# 存档备份：脚本会 reset() 和写档，跑完还原
	var backup := ""
	if FileAccess.file_exists(str(_gm.SAVE_PATH)):
		var rf = FileAccess.open(str(_gm.SAVE_PATH), FileAccess.READ)
		if rf != null:
			backup = rf.get_as_text()
			rf.close()

	_gm.reset()
	_gm.onboarding_shown = true
	_gm.headless_mode = true

	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	await create_timer(2.5).timeout
	_world._onboarding.visible = false

	_hud = _world.get_node("HUD3D")

	# ---- 1. 遮罩存在性与层级 ----
	_ck("HUD3D 里挂上了遮罩", _hud._mood_mask != null)
	if _hud._mood_mask == null:
		_finish(backup)
		return
	var mask: TextureRect = _hud._mood_mask
	_ck("遮罩是 TextureRect", mask is TextureRect)
	_ck("遮罩纹理非空", mask.texture != null)
	_eq("遮罩纹理边长 128", int(mask.texture.get_size().x), 128)
	_eq("遮罩不拦输入 (MOUSE_FILTER_IGNORE)", int(mask.mouse_filter), 2)
	_ck("遮罩锚点铺满", absf(mask.anchor_right - 1.0) < 0.001 and absf(mask.anchor_bottom - 1.0) < 0.001)

	# 遮罩必须在所有 HUD 子节点之下：TopBar / TopRightHBox 都在它后面。
	# 走 get_children() 数序号，不用 get_index()：untyped 持有者上它会解析成错误重载。
	#
	# 原来这一节量的是 `HelpOverlay`（那块帮助面板），而它已经删掉了 ——
	# `find()` 在找不到时返回 -1，`help_pos > mask_pos` 就**恒假**，
	# 于是这条断言会一直红，而它红的原因跟被测的性质无关。
	# 换成 `TopRightHBox`：那才是玩家真的隔着遮罩在按的东西
	# （「?」那一下现在进设置面板，见 `HUD3D._settings_panel()`）。
	var order: Array = []
	for c in _hud.get_children():
		order.append(str(c.name))
	var mask_pos := int(order.find("MoodMask"))
	var top_pos := int(order.find("TopBar"))
	var btn_pos := int(order.find("TopRightHBox"))
	_eq("遮罩是第一个子节点 (index 0)", mask_pos, 0)
	_ck("TopBar 压在遮罩上面", top_pos > mask_pos, "top=%d mask=%d" % [top_pos, mask_pos])
	_ck("按钮排压在遮罩上面", btn_pos > mask_pos, "btn=%d mask=%d" % [btn_pos, mask_pos])

	# ---- 2. 顶部经济栏标签 ----
	_ck("旅币标签已创建", _hud._lvbi_label != null)
	_ck("心神标签已创建", _hud._mood_label != null)
	# 场景里自带 StationLabel / ProgressLabel，运行时再加旅币 / 心神 / 下一处，
	# 共 5 个**标签**；心神和「下一处」之间还有一个撑开的弹簧（见第 10 节），
	# 所以子节点是 6 个、标签是 5 个 —— 这里守的是标签，别把弹簧算成标签。
	var box = _hud.get_node("TopBar/HBox")
	var topbar_labels := 0
	for ch in box.get_children():
		if ch is Label:
			topbar_labels += 1
	_eq("TopBar 里有 5 个标签", topbar_labels, 5)
	_ck("旅币标签挂在 TopBar", box.is_ancestor_of(_hud._lvbi_label))
	_ck("心神标签挂在 TopBar", box.is_ancestor_of(_hud._mood_label))
	await process_frame
	_eq("旅币标签文字对得上", _hud._lvbi_label.text, _loc.t("lvbi_label", [int(_gm.lvbi)]))
	_eq("心神标签文字对得上", _hud._mood_label.text, _loc.t("mood_label", [int(_gm.mood), int(_gm.MOOD_CEIL)]))

	# 上面那条是拿标签去比**同一个 key 渲染出来的句子**，它证明"接线通了"，
	# 不证明"玩家看得见上限"——key 里的 %d 掉了几个它照样全绿。补一条量成品：
	# 顶栏上必须真的看得见 "/上限"，否则玩家永远不知道自己掉到了 1/5 还是 3/5。
	_ck("顶栏上看得见心神的分母",
		str(_hud._mood_label.text).contains("/%d" % int(_gm.MOOD_CEIL)),
		"got=%s want 含有 /%d" % [_hud._mood_label.text, int(_gm.MOOD_CEIL)])

	# ---- 2b. 三个音频开关在顶栏上必须彼此可分 ----
	# BGM 和音效原来共用一个字形「♪」和同一句话「♪ 开」，两个按钮长得一模一样，
	# 旁边还杵着一个同样显眼的全静音 🔊。玩家点第一个不知道静音的是音乐。
	# 判据不是"文案不一样"——那本来就不一样，是"**首字符**不一样"，
	# 因为顶栏上真正被一眼扫到的只有那个字形。
	await _audit_audio_buttons()

	# ---- 3. 骑行档收敛到目标值 × MOOD_REST_SCALE ----
	await _settle()
	_approx("遮罩收敛到骑行档", _mask_alpha(), _rest_target())
	_ck("骑行档比叙事档淡", _mask_alpha() < _narr_target() or _narr_target() <= 0.005,
			"rest=%f narr=%f" % [_mask_alpha(), _narr_target()])

	# ---- 4. 心神 5→1 单调变浓，骑行档永远低于可读上限 ----
	var alphas: Array = []
	for m in [5, 4, 3, 2, 1]:
		_gm.mood = m
		await _settle()
		_approx("心神 %d 遮罩 = 骑行档目标值" % m, _mask_alpha(), _rest_target())
		alphas.append(_mask_alpha())

	for i in range(1, alphas.size()):
		_ck("心神 %d → %d 变浓" % [5 - i + 1, 5 - i], alphas[i] > alphas[i - 1],
			"%f !> %f" % [alphas[i], alphas[i - 1]])
	_ck("心神 5 遮罩全清", alphas[0] <= 0.005, "got=%f" % alphas[0])
	# 可读上限：最差时（心神 1）骑行档的雾也必须看得清路。这是这个文件的主要断言。
	_ck("心神 1 骑行档仍可读（<0.20）", alphas[4] < 0.20, "got=%f" % alphas[4])
	_ck("遮罩永远不盖满", alphas[4] <= float(_gm.MOOD_MASK_MAX) + 0.001,
			"got=%f max=%f" % [alphas[4], float(_gm.MOOD_MASK_MAX)])

	# ---- 5. 遮罩只随心神：买了灯笼 / 香囊也不淡 ----
	# 灯笼 / 香囊走的是 get_visibility_factor()（看得见的半径），不是遮罩——
	# 买灯是把「看得见的范围」撑回来，不是把雾买散。遮罩这一路只有心神进得来。
	_gm.inv = {}
	_gm.mood = int(_gm.MOOD_FLOOR)
	await _settle()
	var base := _mask_alpha()
	_gm.inv["lamp"] = 1
	await _settle()
	var with_lamp := _mask_alpha()
	_gm.inv["lamp"] = 2
	_gm.inv["sachet"] = 1
	await _settle()
	var with_all := _mask_alpha()

	_eq("买一盏灯笼遮罩不变", with_lamp, base)
	_eq("买满灯笼+香囊遮罩仍不变", with_all, base)
	_approx("遮罩收敛到骑行档", with_all, _rest_target())

	# ---- 6. 系数真的传到草皮与行道树 ----
	# 只收「看得见的半径」：草是 shader 的两个 uniform，树是 visibility_range_end。
	# 驻留半径（_radius）不动，所以这两项只该随系数缩。
	_ck("草皮节点在场", _world._grass_scatter != null)
	_ck("行道树节点在场", _world._tree_scatter != null)
	if _world._grass_scatter != null and _world._tree_scatter != null:
		var grass = _world._grass_scatter
		var trees = _world._tree_scatter
		_gm.inv = {}
		_gm.mood = int(_gm.MOOD_CEIL)
		await _settle_factor()
		var gr0 := float(grass.grass_material().get_shader_parameter("fade_end"))
		var tr0 := float(trees.range_end())
		_approx("系数传到草皮", float(grass.visibility_factor()), 1.0)
		_approx("系数传到行道树", float(trees.visibility_factor()), 1.0)

		_gm.mood = int(_gm.MOOD_FLOOR)
		await _settle_factor()
		var f1 := float(_gm.get_visibility_factor())
		_approx("心神 1 系数 0.65", f1, 0.65)
		_approx("草皮 fade_end 随系数收缩",
				float(grass.grass_material().get_shader_parameter("fade_end")),
				float(grass.radius()) * f1)
		_approx("草皮淡出起点也收缩",
				float(grass.grass_material().get_shader_parameter("fade_start")),
				minf(float(grass.RING_DIST[grass.RING_COUNT - 2]), float(grass.radius()) * f1 * 0.65))
		# 树的 range_end 里还有 BUILD_LEAD / 相机补偿两项，这里不比绝对值、
		# 比**差量**：系数从 1.0 掉到 f1，可见边界应该正好缩 radius × (1-f1)。
		_approx("行道树可见边界缩了 radius×(1-f)",
				float(tr0 - trees.range_end()), float(trees.radius()) * (1.0 - f1))
		_ck("草皮驻留半径没被动", float(grass.radius()) > 0.0, "r=%f" % float(grass.radius()))

		# 买了两件灯笼：方案 §7.1 的算例 0.65 × 1.50 = 0.975
		_gm.inv["lamp"] = 2
		await _settle_factor()
		var f2 := float(_gm.get_visibility_factor())
		_approx("两件灯笼后系数 0.975", f2, 0.975)
		_approx("草皮跟着撑回来",
				float(grass.grass_material().get_shader_parameter("fade_end")),
				float(grass.radius()) * f2)
		_approx("行道树跟着撑回来", float(trees.range_end() - float(tr0)),
				float(trees.radius()) * (f2 - 1.0))

	# ---- 7. 标签同步 + 入账闪光 ----
	_gm.inv = {}
	_gm.mood = 4
	_gm.lvbi = 0
	await process_frame
	_eq("余额为 0 时标签是 0", _hud._lvbi_label.text, _loc.t("lvbi_label", [0]))
	_gm.lvbi = 123
	await process_frame
	_eq("余额 123 时标签跟着变", _hud._lvbi_label.text, _loc.t("lvbi_label", [123]))
	_gm.mood = 2
	await process_frame
	_eq("心神 2 时标签跟着变", _hud._mood_label.text, _loc.t("mood_label", [2, int(_gm.MOOD_CEIL)]))

	# 余额标签的位置在入账前后必须一模一样：入账提示走独立 toast，不许顶栏重排。
	# 记录位置前先让一帧走完——HBox 的排布是 _process 写完 text 之后才生效的。
	await process_frame
	var lvbi_x_before: float = _hud._lvbi_label.get_global_rect().position.x
	var mood_x_before: float = _hud._mood_label.get_global_rect().position.x
	var next_x_before: float = _hud._next_label.get_global_rect().position.x

	_gm.earn(20, "test_flash")
	_ck("入账 toast 已创建", _hud._lvbi_toast != null)
	await process_frame
	if _hud._lvbi_toast != null:
		_eq("入账后 toast 显示「+20 旅币」", _hud._lvbi_toast.text,
				_loc.t("collecting_lvbi", [20]))
		_ck("入账后 toast 亮起", _hud._lvbi_toast.modulate.a > 0.5,
				"a=%f" % _hud._lvbi_toast.modulate.a)
	_eq("余额标签只显示余额", _hud._lvbi_label.text, _loc.t("lvbi_label", [143]))
	_approx("余额标签位置不动", _hud._lvbi_label.get_global_rect().position.x,
			lvbi_x_before, 0.5)
	_approx("心神标签没被挤走", _hud._mood_label.get_global_rect().position.x,
			mood_x_before, 0.5)
	_approx("「下一处」没被挤走", _hud._next_label.get_global_rect().position.x,
			next_x_before, 0.5)

	# toast 挂的是 HUD3D、不是 TopBar/HBox，HBox 的子节点数不该因此变化。
	# 数目是 6 而不是 5：心神和「下一处」之间还有一个撑开的弹簧（见第 10 节），
	# 而这里要守的是"入账没有往 HBox 里添东西"，所以按**标签**数断，
	# 不按子节点数——弹簧不是标签，把它算进去这条断言将来就只记得住 6。
	var hbox = _hud.get_node("TopBar/HBox")
	var hbox_labels := 0
	for ch in hbox.get_children():
		if ch is Label:
			hbox_labels += 1
	_eq("入账后 TopBar 仍是 5 个标签", hbox_labels, 5)
	_ck("toast 不在 TopBar 里", not hbox.is_ancestor_of(_hud._lvbi_toast))

	_gm.lvbi = 0
	_gm.mood = int(_gm.MOOD_INITIAL)

	# ---- 8. 叙事脉冲：亮起对白冲上叙事档、收掉后退回骑行档 ----
	# 驱动权不在测试手里：World3D 每个物理帧都按两个弹窗的真实可见性重写
	# set_mood_pulse。所以这里必须去点弹窗，直接调 set_mood_pulse 会被下一帧覆盖回去
	# ——那样测的是"我调了但没人理"，不是游戏真正的行为。
	# 叙事档也必须真的够浓，否则整个改动就只是把雾调淡了、什么叙事效果都没有。
	_gm.mood = int(_gm.MOOD_FLOOR)
	await _settle()
	_world._dialogue_popup.visible = true
	await _settle_pulse(_narr_target())
	_approx("对白亮起时冲上叙事档", _mask_alpha(), _narr_target())
	_approx("叙事档 = MOOD_MASK_MAX", _mask_alpha(), float(_gm.MOOD_MASK_MAX))
	_ck("叙事档比骑行档浓", _mask_alpha() > _rest_target() + 0.1,
			"pulse=%f rest=%f" % [_mask_alpha(), _rest_target()])

	_world._dialogue_popup.visible = false
	await _settle()
	_approx("对白收掉后退回骑行档", _mask_alpha(), _rest_target())
	_ck("退回后仍然可读", _mask_alpha() < 0.20, "got=%f" % _mask_alpha())

	# ---- 9. 顶栏衬底在最坏背景下仍然撑得住字 ----
	await _audit_scrim_contrast()

	# ---- 10. 顶栏排版：容器不许溢出，右端不许剩一条死区 ----
	await _audit_topbar_layout()

	_finish(backup)


## 顶栏这一栏**排出来是什么样**，而不是算出来对比度够不够（第 9 节管那个）。
##
## `TopBar/HBox` 在 .tscn 里写死 `offset_right = 480`，而它五个标签的最小宽度
## 加起来约 663px——**195px 是溢出出去的**，容器自己的 rect 一直是个谎。
## HBoxContainer 默认不裁剪，于是溢出既不报错也没有任何回归能量得到，
## 露出来的后果是：顶栏右端约 345px 的空档读成一条什么都没有的黑带
## （衬底一直铺到 1280），而"下一处"那一行恰好是空的时候空档整整翻倍
## ——评审第一轮记下来的就是那个约 600px 的死区。
##
## 三条判据各钉一个量：
## ①**没有溢出**——每个子节点的右沿都在容器右沿之内（容器的 rect 得说实话）；
## ②**没有死区**——"下一处"的右沿离按钮排左沿只剩设计好的那一道缝；
## ③**弹簧真的在吸**——把"下一处"塞成一条长得多的字，旅币和心神一个像素都不许动，
##    而"下一处"自己的右沿也不许动（它钉在弹簧右端 = 容器右沿）。
##    这一条正是 CLAUDE.md 里"顶栏 HBox 里任何一个 Label 改字都会把整排标签横向推走"
##    那条陷阱的正面：站名有长有短，"还差 N 次"的中英宽度差一大截，
##    变化必须由弹簧一个人吃掉。
func _audit_topbar_layout() -> void:
	var hud: Node = _world._hud3d
	var hbox: Control = hud.get_node("TopBar/HBox")
	var right_row: Control = hud.get_node("TopRightHBox")
	await process_frame
	await process_frame

	# ① 容器不许溢出。留 0.5px 是因为 Label 的最小宽度是浮点，取整误差有零点几。
	var worst_over := 0.0
	var worst_who := ""
	var box_r: float = hbox.get_global_rect().end.x
	for ch in hbox.get_children():
		if ch is Control and (ch as Control).visible:
			var over: float = (ch as Control).get_global_rect().end.x - box_r
			if over > worst_over:
				worst_over = over
				worst_who = str(ch.name)
	_ck("TopBar/HBox 不许溢出自己的右沿（容器 rect 得说实话）", worst_over <= 0.5,
			"最宽的是 %s，超出 %.1fpx，容器右沿 %.1f" % [worst_who, worst_over, box_r])

	# 容器得真的伸到按钮排左边，否则"没有死区"是拿两条不重叠的东西比出来的 0
	var gap_declared: float = right_row.get_global_rect().position.x - box_r
	_ck("TopBar/HBox 一直伸到按钮排左边",
			absf(gap_declared - float(_hud.TOP_RIGHT_GAP)) <= 0.5,
			"容器右沿 %.1f，按钮排左沿 %.1f，差 %.1f（应为 %.1f）"
			% [box_r, right_row.get_global_rect().position.x, gap_declared,
			float(_hud.TOP_RIGHT_GAP)])

	# ② 导航那一行离按钮排只剩设计好的那道缝 —— 这就是"死区"的量
	var nav_r: float = _hud._next_label.get_global_rect().end.x
	var dead_px: float = right_row.get_global_rect().position.x - nav_r
	_ck("「下一处」和按钮排之间没有死区", dead_px <= float(_hud.TOP_RIGHT_GAP) + 8.0,
			"空档 %.1fpx" % dead_px)

	# ③ 弹簧吸长度变化。三样都不许动：旅币、心神、以及"下一处"自己的右沿。
	var lvbi_x: float = _hud._lvbi_label.get_global_rect().position.x
	var mood_x: float = _hud._mood_label.get_global_rect().position.x
	var nav_right_before: float = nav_r
	var saved: String = str(_hud._next_label.text)
	_hud._next_label.text = "下一处 · 云影台的望江亭在东岸第三级石阶尽头那一边 · 1234m"
	await process_frame
	await process_frame
	_approx("顶栏文字变长时旅币标签不动", _hud._lvbi_label.get_global_rect().position.x,
			lvbi_x, 0.5)
	_approx("顶栏文字变长时心神标签不动", _hud._mood_label.get_global_rect().position.x,
			mood_x, 0.5)
	_approx("顶栏文字变长时「下一处」右沿不动（它钉在容器右沿）",
			_hud._next_label.get_global_rect().end.x, nav_right_before, 0.5)
	_hud._next_label.text = saved
	await process_frame


## 顶栏那行字在**最坏背景**上还读不读得出来。
##
## 量的是衬底自己，不量截图：`_make_scrim_image()` 是一张 1×N 的渐变图，
## 把它逐行按 alpha 合成到声明的最坏背景上、再按 WCAG 算对比度，全程纯算术。
## 之所以能量，是因为整条链上唯一会变的是这两个数（`SCRIM_TOP_ALPHA` /
## `SCRIM_SOLID_FRAC`）和背景色，而它们都不依赖渲染器——`lookdev_journey`
## 的 04/13 两屏才是"看起来对不对"，这一节是"算出来对不对"。
##
## 最坏背景取**正午那档天的地平线霾**，不是黄昏的地，也不是天顶：顶栏那几秒
## 抬头对的就是天，而那一档的霾 ≈ sRGB(198,210,237)、相对亮度 0.642，**比顶栏
## 那行金字本身（≈(245,200,126)，0.621）还亮**。所以调暗衬底色没有出路
## （衬底本来就接近黑），能救的只有 alpha，而 alpha 有个下限。
## （天顶那一档现在比字还暗——见 `_audit_scrim_contrast()` 里那段注释，
## 那是 sRGB→线性修好之后的结果，这里的数是**故意留的余量**，不许往下调。）
##
## 文字所在的那几行不是手写的：直接从真实 Label 的 `get_global_rect()` 换算成
## 渐变图上的 t 值。手写「字落在 y 14~32」的话，哪天字体改了、字号改了、
## TopBar 的内边距改了，这条回归还在验一条已经不存在的位置。
func _audit_scrim_contrast() -> void:
	var hud: Node = _world._hud3d
	var img: Image = hud._make_scrim_image()
	var n := img.get_height()
	_ck("衬底渐变图存在且是竖条", img.get_width() == 1 and n > 1,
			"%dx%d" % [img.get_width(), n])

	# 字色读真实的 Label，不抄一份常量表（抄的那份迟早跟 _make_hud_label 漂）
	var fg: Color = hud._lvbi_label.get_theme_color("font_color")
	# sRGB 口径：_make_hud_label() 填的就是 ThemeDB 里的 sRGB 值
	var fg_lin: Array = [_srgb_to_lin(fg.r), _srgb_to_lin(fg.g), _srgb_to_lin(fg.b)]

	# 最坏背景：正午那档天的**地平线霾**，sRGB(198,210,237)。
	#
	# 这个数原来标着"12b_day_正午.png 实测的天"，而它**现在不再是天顶那一片了**：
	# `DayCycle` 改成把天空色按 sRGB→线性换算之后再交给 `ProceduralSkyMaterial`
	# 之后，正午的天从一整片 sRGB(198,210,237) 变成上深下浅的一层——天顶那几行
	# 衬底底下那一行渲出来是 sRGB(81,104,205)、相对亮度 0.16，**比顶栏那行金字
	# （0.621）暗四倍**。
	# 所以这里保留霾那一档，理由是它本来就是**故意留的余量**，不是"当前最亮的那片"：
	# 相机俯仰不是恒定的（`_villain_camera_cue()` 会重新 look_at 一次），地平线
	# 有可能升进衬底覆盖的那一带；而余量的代价只是天被多压暗一点，不更难读。
	# 反过来说——**这个数不许往下调**：`SCRIM_TOP_ALPHA` 已经是 0.90，
	# 而它当初取 0.90 的唯一理由就是这一条（alpha ≥ 0.855 才够 4.5:1）。
	# "实测值变好看了"从来不是把下限放低的理由。
	# `lookdev_journey.gd` 在那两条天带断言旁边钉了"衬底底下那一带真的比它暗"，
	# 所以天色再变一次的话，这一节不会悄悄地变成一个够不着的数。
	var bg := Color(198.0 / 255.0, 210.0 / 255.0, 237.0 / 255.0)
	var bg_lin: Array = [_srgb_to_lin(bg.r), _srgb_to_lin(bg.g), _srgb_to_lin(bg.b)]
	_ck("最坏背景（正午那档天的地平线霾）本身比字还亮——这才是那条硬约束的由来",
			_lum(bg_lin) > _lum(fg_lin),
			"bg=%.3f fg=%.3f（衬底底下那一带实测 0.16，由 lookdev_journey 钉着）"
			% [_lum(bg_lin), _lum(fg_lin)])

	# 文字带：从真实 Label 的 rect 换算成渐变图上的行号区间。
	# 换算基准是 TopScrim **自己**的 rect 而不是 viewport 顶边——衬底挂在
	# HUD3D 下、偏移和锚点都可能变，写死 y=0 的话一次布局调整就让这条回归
	# 去验一条不存在的位置，而它照样是绿的。
	var scrim: Control = hud.get_node("TopScrim")
	var srect: Rect2 = scrim.get_global_rect()
	var rect: Rect2 = hud._lvbi_label.get_global_rect()
	var t0 := (rect.position.y - srect.position.y) / srect.size.y
	var t1 := (rect.end.y - srect.position.y) / srect.size.y
	var y0 := int(floor(t0 * float(n - 1)))
	var y1 := int(ceil(t1 * float(n - 1)))
	_ck("文字带落在衬底图范围内", y0 >= 0 and y1 < n,
			"rect=%s scrim=%s t=%.2f~%.2f → 行 %d~%d / 0~%d"
			% [str(rect), str(srect), t0, t1, y0, y1, n - 1])

	# 逐行合成 + WCAG，取文字带里最差的那一行
	var worst := 99.0
	var worst_y := -1
	for y in range(y0, y1 + 1):
		var c := img.get_pixel(0, y)
		var a := c.a
		var comp := [
			a * _srgb_to_lin(c.r) + (1.0 - a) * bg_lin[0],
			a * _srgb_to_lin(c.g) + (1.0 - a) * bg_lin[1],
			a * _srgb_to_lin(c.b) + (1.0 - a) * bg_lin[2],
		]
		var r := _contrast(comp, fg_lin)
		if r < worst:
			worst = r
			worst_y = y
	_ck("文字带每一行都过 4.5:1（AA 正文线）", worst >= 4.5,
			"最差 %.2f:1 落在第 %d 行（t=%.2f，alpha=%.2f）" % [
				worst, worst_y, float(worst_y) / float(n - 1),
				img.get_pixel(0, maxi(worst_y, 0)).a])

	# 实底段必须真的盖住整条文字带。纯渐变（没有平台）的话，
	# 文字带中段只剩 0.16~0.31 的 alpha，挡不住任何东西——而单看总对比度
	# 也许还能蒙混过关，所以这一条单独钉住平台本身。
	_ck("文字带完全落在实底段里（t ≤ SCRIM_SOLID_FRAC=%.2f）" % float(hud.SCRIM_SOLID_FRAC),
			t1 <= float(hud.SCRIM_SOLID_FRAC) + 0.001,
			"文字带到 t=%.2f" % t1)
	var plateau := true
	# 容差是 8bit 的量化误差（1/255 = 0.0039，取 0.006 留半档余量），
	# 不是"差不多就行"：旧版纯渐变在文字带里只有 0.16~0.31，离 0.90 差得远，
	# 真要写 0.001 也拦不住它，只是会把 0.90 自己判红而已。
	for y in range(y0, y1 + 1):
		if absf(img.get_pixel(0, y).a - float(hud.SCRIM_TOP_ALPHA)) > 0.006:
			plateau = false
	_ck("文字带里每一行的 alpha 都等于 SCRIM_TOP_ALPHA（确实有实底段，不是纯渐变）",
			plateau, "SCRIM_TOP_ALPHA=%.2f，实测带内 %.4f~%.4f" % [
				float(hud.SCRIM_TOP_ALPHA),
				img.get_pixel(0, y0).a, img.get_pixel(0, y1).a])

	# 衬底不许糊满一整块屏幕：淡出段必须真的淡到接近 0，
	# 否则下半个视野全是它，看山看草都像隔了一层。
	_ck("衬底最后一行淡到 0.05 以下（没糊成整块面板）",
			img.get_pixel(0, n - 1).a < 0.05,
			"末行 alpha=%.3f" % img.get_pixel(0, n - 1).a)


## WCAG 相对亮度。传入的是**线性**分量（Godot 的 Color 存的是 sRGB，
## 直接喂进去算出来的比值是错的）。
func _srgb_to_lin(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


func _lum(lin: Array) -> float:
	return 0.2126 * float(lin[0]) + 0.7152 * float(lin[1]) + 0.0722 * float(lin[2])


## WCAG 对比度：大的除以小的再各加 0.05。
##
## 「谁除以谁」必须取max/min，不能假定合成后一定比字暗——第一版就写死了
## `(合成+0.05)/(字+0.05)`，而合成是暗的、字是亮的，于是每个比值都小于 1，
## 最差那一行报出 0.18:1，看着像灾难，其实是**方向反了**，真值是 1/0.18 = 5.6:1。
## 归一化对称的量才会出现这种"红得没有道理"，所以它自己抓得住——
## 但前提是判据写的是「≥ 4.5」这种单边的线，而不是「比某个值小」。
func _contrast(a: Array, b: Array) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	var hi := maxf(la, lb)
	var lo := minf(la, lb)
	return (hi + 0.05) / (lo + 0.05)


## 三个音频开关在顶栏上必须彼此可分。
##
## 判据只看每行**第一个字形**（顶栏上被一眼扫到的就是它），不看整句：整句本来
## 就不同（"♫ 开" vs "♪ 开"），可两个按钮在全都显示"开"时是逐字相同的，
## 只比整句会在全开这一档放行。两种静音态都走一遍。
func _audit_audio_buttons() -> void:
	var hud = _world._hud3d
	# --script 模式下 autoload 在编译期解析不到，只能运行时按名字取
	var am: Node = root.get_node("AudioManager")
	# 回到三档全开，这是两个按钮最像彼此的一档
	am.set_muted(false)
	am.set_bgm_muted(false)
	am.set_sfx_muted(false)
	hud._update_buttons()
	var heads := {
		"全静音": hud._mute_btn.text.substr(0, 1),
		"BGM": hud._bgm_btn.text.substr(0, 1),
		"音效": hud._sfx_btn.text.substr(0, 1),
	}
	var uniq := {}
	for k in heads:
		uniq[heads[k]] = true
	_ck("三个音频开关的字形互不相同（全开档）", uniq.size() == 3,
			"实际：%s" % str(heads))
	# 上头那条比的是**字符串**，而这一条比的是"玩家分不分得出来"。
	# 原来 BGM / 音效用的是 ♫ / ♪：两个码位在字体里真的画得不一样
	# （`Font.has_char` 都报 true，单独放大渲染也看得见那根横杠），
	# 于是一条字符串判据全绿——而顶栏 18px 上那根横杠是亚像素的，
	# 两个按钮读起来就是同一个东西。区别只在符号的一根细笔画上 = 没有区别。
	# 所以要求区分用的那个字符是**字**（CJK / 拉丁字母），不是符号。
	for k in ["BGM", "音效"]:
		var c: int = heads[k].unicode_at(0)
		var is_word: bool = (c >= 0x4E00 and c <= 0x9FFF) 				or (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A)
		_ck("%s 那颗用字区分，不靠符号的一根笔画" % k, is_word,
				"首字符 U+%04X「%s」" % [c, heads[k]])
	_ck("BGM 与音效的 tooltip 也各说各的",
			hud._bgm_btn.tooltip_text != hud._sfx_btn.tooltip_text,
			"两者都是：%s" % hud._bgm_btn.tooltip_text)
	_eq("BGM tooltip 就是那条文案", hud._bgm_btn.tooltip_text, _loc.t("bgm_mute"))
	_eq("音效 tooltip 就是那条文案", hud._sfx_btn.tooltip_text, _loc.t("sfx_mute"))

	# 关掉 BGM 之后，两个按钮的**字形**仍然要不同 —— 少一个「♫ 写成 ♪」的
	# 笔误的话，玩家会以为点错了按钮
	am.set_bgm_muted(true)
	hud._update_buttons()
	_ck("静音 BGM 之后两个按钮仍可分",
			hud._bgm_btn.text.substr(0, 1) != hud._sfx_btn.text.substr(0, 1),
			"bgm=%s sfx=%s" % [hud._bgm_btn.text, hud._sfx_btn.text])
	_ck("静音 BGM 之后 BGM 那颗显示「关」",
			hud._bgm_btn.text.contains(_loc.t("off")), hud._bgm_btn.text)
	am.set_muted(false)
	am.set_bgm_muted(false)
	am.set_sfx_muted(false)
	hud._update_buttons()


func _finish(backup: String) -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	if backup != "":
		# 三份一起收：存档改成原子写之后，跑一遍会多出 .bak / .tmp，只写回正本会把它们留在盘上
		_gm._clear_save()
		var wf = FileAccess.open(str(_gm.SAVE_PATH), FileAccess.WRITE)
		if wf != null:
			wf.store_string(backup)
			wf.close()
	else:
		_gm._clear_save()

	print("\n=== 结果：OK %d / FAIL %d ===" % [_oks, _fails.size()])
	for f in _fails:
		print("  [FAIL] ", f)
	quit(0 if _fails.is_empty() else 1)
