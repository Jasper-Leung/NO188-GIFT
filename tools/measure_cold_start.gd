extends SceneTree
## measure_cold_start.gd — 冷启动逐段墙钟：按「开启旅程」到第一次拿到操纵权
##
## 为什么单独写一个，而不用 play_newcomer.gd 那一段：那边把 GiftBox
## `queue_free()` 掉、自己 `instantiate()` 出 World3D，等于**把标题页那 3.15 秒
## 的过场动画整段绕过去了**——而那 3.15 秒全部花在"玩家已经按下按钮、却还
## 动不了"的窗口里。所以它量出来的冷启动天然偏小，优化时也量不到真正该砍的那段。
##
## 这里走**玩家真实按的那条路**：StartBtn → `_on_start_pressed()` →
## `change_scene_to_packed` → World3D → 操作说明 → 序章对白 → 拿到操纵权。
##
## 计时一律用 `Time.get_ticks_msec()`。`t += 0.016` 那种写法在真实帧率不等于
## 60 时是假的（本机带窗口能跑 280+ FPS，会**低报**耗时）。
##
## 两种节奏都量，因为它们量的是两件事：
##   连打（0.3s 一次）——机器强加给玩家的等待，也就是本脚本要压的那部分
##   人读（1.4s 一次）——读完一句再按，是真人节奏，用来定位"内容本身有多长"
##
## **不能加 --headless**：按钮的焦点路由和 DialoguePopup 收按键都要真显示服务器。
##
## 用法： godot --path . --script tools/measure_cold_start.gd

const SAVE_DIR := "user://measure_cold_start"
const SHOT := Vector2i(1280, 720)

## 两种节奏：每按一次之间的墙钟间隔（秒）
const RHYTHM_SPAM := 0.30
const RHYTHM_READ := 1.40

## 拿到操纵权的上限。跑两遍，第二遍用 RHYTHM_READ，所以这个值要容得下人读那一遍。
const BUDGET_SEC := 60.0

var _t0 := 0
var _gm: Node = null
var _loc: Node = null
var _world: Node = null
var _log: Array[String] = []
var _fails := 0


func _ensure_autoloads() -> void:
	var paths := {
		"GameManager": "res://scripts/GameManager.gd",
		"AudioManager": "res://scripts/AudioManager.gd",
		"Localization": "res://scripts/Localization.gd",
	}
	for n in paths:
		if root.get_node_or_null(n) == null:
			var node: Node = load(paths[n]).new()
			node.name = n
			root.add_child(node)


func _elapsed() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0


func _say(s: String) -> void:
	var line := "[%6.2fs] %s" % [_elapsed(), s]
	print(line)
	_log.append(line)


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_fails += 1
		print("[FAIL] ", label + ("（" + detail + "）" if detail != "" else ""))


func _push_space() -> void:
	# 只用 parse_input_event。CLAUDE.md 记着一条：叠上 root.push_input() 会让
	# 一次按键被 GUI 收到两遍，于是空格一次推两句对白——量出来的时间凭空少一半。
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.keycode = KEY_SPACE
	up.physical_keycode = KEY_SPACE
	up.pressed = false
	Input.parse_input_event(up)


func _initialize() -> void:
	Engine.max_fps = 60
	_ensure_autoloads()
	_gm = root.get_node("GameManager")
	_loc = root.get_node("Localization")
	_gm._clear_save()
	_loc.set_language("zh")
	root.size = SHOT
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


## 一次冷启动。rhythm = 每按一次空格之间的墙钟间隔（秒）。
## 返回拿到操纵权的墙钟秒数，失败返回 -1。
func _cold_start(rhythm: float) -> float:
	_gm._clear_save()
	_gm.onboarding_shown = false
	_gm.prologue_done = false

	var gift: Control = load("res://scenes/GiftBox.tscn").instantiate()
	# 必须设成 current_scene：GiftBox._on_start_pressed() 走的是
	# get_tree().change_scene_to_packed()，而它换掉的是 current_scene。
	# 不设的话换出来的场景会被挂上去但 GiftBox 自己不走 free，
	# 于是"玩家按了按钮之后"那一段量到的就不是真实链路了。
	root.add_child(gift)
	current_scene = gift
	await process_frame
	await process_frame
	var t_title := _elapsed()
	_say("标题页就绪")

	# 玩家按下「开启旅程」——直接调按钮自己的 handler（不是调某个内部步骤）
	gift._on_start_pressed()
	var t_pressed := _elapsed()
	_say("按了「开启旅程」")

	# 等场景真的换掉（= 3D 世界建起来）
	while current_scene == gift or current_scene == null:
		if _elapsed() - t_pressed > 40.0:
			_say("!! 场景切换超时")
			return -1.0
		await process_frame
	var t_world := _elapsed()
	_world = current_scene
	_say("World3D 起来了（内部耗时 %.2fs）" % [t_world - t_pressed])

	while _world._onboarding == null or not _world._onboarding.visible:
		if _elapsed() - t_world > 30.0:
			_say("!! 操作说明没出来")
			return -1.0
		await process_frame
	var t_onb := _elapsed()
	_say("操作说明可见（内部 %.2fs）" % [t_onb - t_world])

	# 一路按空格到能动为止
	var dlg: Node = _world._dialogue_popup
	var next_at := 0.0
	var presses := 0
	var said_dlg := false
	var said_free := false
	while not bool(_world._player._can_move):
		var now := _elapsed()
		if now > next_at:
			_push_space()
			presses += 1
			next_at = now + rhythm
		if not said_dlg and dlg != null and dlg.visible:
			said_dlg = true
			_say("序章对白出现")
		if said_dlg and not said_free and (dlg == null or not dlg.visible):
			said_free = true
			_say("对白收完")
		if now - t_title > BUDGET_SEC:
			_say("!! 到点还没拿到操纵权")
			return -1.0
		await process_frame
	var t_move := _elapsed()
	_say("拿到操纵权（按了 %d 次空格）" % presses)
	_say("  ·标题页就绪      %6.2fs" % t_title)
	_say("  ·按钮按下→世界   %6.2fs" % (t_world - t_pressed))
	_say("  ·世界→操作说明   %6.2fs" % (t_onb - t_world))
	_say("  ·操作说明→能动   %6.2fs" % (t_move - t_onb))
	_say("  ·合计             %6.2fs" % t_move)

	if current_scene != null:
		current_scene.queue_free()
	await process_frame
	await process_frame
	_world = null
	return t_move


func _run() -> void:
	print("=== 冷启动墙钟测量（带窗口跑）===")
	var spam := await _cold_start(RHYTHM_SPAM)
	print("")
	var human := await _cold_start(RHYTHM_READ)
	print("")

	_ck("连打节奏下拿到操纵权", spam > 0.0, "%.1fs" % spam)
	_ck("人读节奏下拿到操纵权", human > 0.0, "%.1fs" % human)
	# 连打那一遍是"机器强加的等待"的真实下界：它已经假设玩家愿意一直狂按。
	# 20 秒是这次的目标线，判在这条上——人读那遍压不住的是内容长度，不是等待。
	_ck("连打到能动 %.1fs < 20s" % spam, spam > 0.0 and spam < 20.0, "%.1fs" % spam)

	# 真正会被改坏的是那五段过场的**总长**，而它藏在五个 tween/定时器的时长里：
	# 任何一次"这里再顺一点"都是把秒数悄悄加回去，而墙钟断言要连跑两遍、
	# 带着真实的场景切换才看得出慢了零点几秒。所以直接从常量表重算一遍。
	var cmap: Dictionary = load("res://scripts/GiftBox.gd").get_script_constant_map()
	var total := 0.0
	for k in ["BOX_OUT_SEC", "ROAD_IN_SEC", "ROAD_HOLD_SEC",
			"ROAD_OUT_SEC", "SWITCH_DELAY_SEC"]:
		_ck("GiftBox 有 %s" % k, cmap.has(k))
		total += float(cmap.get(k, 0.0))
	_ck("START_TRANSITION_SEC 等于五段之和", absf(float(cmap.get("START_TRANSITION_SEC", -1.0)) - total) < 0.001,
			"常量表写 %s，五段和 %.2f" % [str(cmap.get("START_TRANSITION_SEC")), total])
	_ck("标题页过场 %.2fs ≤ 1.5s" % total, total <= 1.5, "%.2fs" % total)
	print("    标题页过场合计 %.2fs（改了 GiftBox 那五个常量会红在这里）" % total)

	var p := "%s/cold_start.log" % SAVE_DIR
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f != null:
		for l in _log:
			f.store_line(l)
		f.close()
	print("\n日志目录: %s" % ProjectSettings.globalize_path(SAVE_DIR))
	print("[measure_cold_start] %s  (失败项 %d)" % [
			"PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)