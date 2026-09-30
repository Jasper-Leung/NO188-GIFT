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
## 0.52 的雾 —— 玩家在最需要看清路去找剩下几块碎片的时候看得最差。MOOD_MASK_MAX
## 仍然是叙事档的天花板，只是不该在骑行时长期占着它。
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

	# 遮罩必须在所有 HUD 子节点之下：TopBar / TopRightHBox / HelpOverlay 都在它后面。
	# 走 get_children() 数序号，不用 get_index()：untyped 持有者上它会解析成错误重载。
	var order: Array = []
	for c in _hud.get_children():
		order.append(str(c.name))
	var mask_pos := int(order.find("MoodMask"))
	var top_pos := int(order.find("TopBar"))
	var help_pos := int(order.find("HelpOverlay"))
	_eq("遮罩是第一个子节点 (index 0)", mask_pos, 0)
	_ck("TopBar 压在遮罩上面", top_pos > mask_pos, "top=%d mask=%d" % [top_pos, mask_pos])
	_ck("HelpOverlay 压在遮罩上面", help_pos > mask_pos, "help=%d mask=%d" % [help_pos, mask_pos])

	# ---- 2. 顶部经济栏标签 ----
	_ck("旅币标签已创建", _hud._lvbi_label != null)
	_ck("心神标签已创建", _hud._mood_label != null)
	# 场景里自带 StationLabel / ProgressLabel，运行时再加旅币 / 心神 / 下一处，共 5 个。
	var box = _hud.get_node("TopBar/HBox")
	_eq("TopBar 里有 5 个标签", int(box.get_child_count()), 5)
	_ck("旅币标签挂在 TopBar", box.is_ancestor_of(_hud._lvbi_label))
	_ck("心神标签挂在 TopBar", box.is_ancestor_of(_hud._mood_label))
	await process_frame
	_eq("旅币标签文字对得上", _hud._lvbi_label.text, _loc.t("lvbi_label", [int(_gm.lvbi)]))
	_eq("心神标签文字对得上", _hud._mood_label.text, _loc.t("mood_label", [int(_gm.mood)]))

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
	_eq("心神 2 时标签跟着变", _hud._mood_label.text, _loc.t("mood_label", [2]))

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

	# toast 挂的是 HUD3D、不是 TopBar/HBox，HBox 的子节点数不该因此变化
	var hbox = _hud.get_node("TopBar/HBox")
	_eq("入账后 TopBar 仍是 5 个标签", int(hbox.get_child_count()), 5)
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

	_finish(backup)


func _finish(backup: String) -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	if backup != "":
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
