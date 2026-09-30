extends SceneTree
## verify_mini_game_keys.gd — 三个靠键盘操作的小游戏在"只有 physical_keycode"
## 的键盘事件下还能不能玩。
##
## 背景：本项目 InputMap 用 physical_keycode 注册 interact（GameManager._add_action），
## 而 Web 导出下 keycode 可能填不上。小游戏原来只判 event.keycode，于是按键
## 既不生效、也不被吃掉，超时/窗口一过就判 CANCELLED，_finish_check_in 把玩家
## 踢出打卡 —— 表现就是"按空格会退出游戏"。
##
## 覆盖：竹(14) 空格、琴(13) 数字键 1-4、茶(10) 长按空格、
## 云(7) 方向键 + 空格落笔、禽(4) 数字键 1-4。
##
## 云和禽是后补的：原来两个的 _gui_input 里一个 InputEventKey 分支都没有，
## 取消按钮又是 _draw() 画的假按钮（键盘够不着），键盘玩家唯一的出路是干等
## World3D 的 30s 超时判 CANCELLED。而它们各占 5 块碎片里的一块，键盘玩家
## 因此永远到不了 5/5 —— 不是难玩，是玩不到通关。
##
## 判定口径：盯的不是"按键有没有被记进 interact"（set_input_as_handled 撤不掉
## Input 单例里已写下的值，见 CLAUDE.md 老坑），而是这次命中会不会通过
## _can_start_check_in 的门，也就是会不会真的重新打卡。
##
## 必须带窗口跑：headless 的 dummy display server 不做真焦点路由。
## --quit-after 要给足:带窗口在这台机器上能跑到 280+ FPS,五个小游戏加起来约
## 65 秒墙钟,给小了会在中途被掐掉、只剩一串 warning 看着像通过。
## 用法： godot --path . --script tools/verify_mini_game_keys.gd --quit-after 60000

const MG_RUNNING := -2
const STATIONS := [
	{"idx": 13, "kind": "zither", "name": "Zither"},
	{"idx": 10, "kind": "tea", "name": "Tea"},
	{"idx": 14, "kind": "bamboo", "name": "Bamboo"},
	{"idx": 4, "kind": "bird", "name": "Bird"},
	{"idx": 7, "kind": "cloud", "name": "Cloud"},
]
const ZITHER_STATE_INPUT := 1
const BIRD_STATE_CHOICE := 1

enum { PH_DIALOGUE, PH_DRIVE, PH_SETTLE }

var _world: Node = null
var _probe: Probe = null
var _gm: Node = null

var _si := 0                 # 当前测到第几个小游戏
var _phase := PH_DIALOGUE
var _f := 0
var _mg: Node = null
var _mg_at := -1
var _last_act_f := -100
var _zither_typed := 0
var _space_down := false
var _cloud_t := 1                # 云：光标当前要走到 _path_world 的第几个点
var _results: Array[String] = []


class Probe:
	extends Node
	var raw: int = 0
	var through: int = 0
	var _world: Node = null
	func setup(w: Node) -> void:
		_world = w
	func _physics_process(_d: float) -> void:
		if not Input.is_action_just_pressed("interact"):
			return
		raw += 1
		if _world != null and _world._can_start_check_in(_world._nearby_station_idx):
			through += 1


func _initialize() -> void:
	for n in {
		"GameManager": "res://scripts/GameManager.gd",
		"AudioManager": "res://scripts/AudioManager.gd",
		"Localization": "res://scripts/Localization.gd",
	}:
		if root.get_node_or_null(n) == null:
			var node: Node = load(n).new()
			node.name = n
			root.add_child(node)
	_gm = root.get_node("GameManager")
	_gm.onboarding_shown = true
	# headless_mode=false 时序章和郑铎三场会真的弹出来，没人点按钮就永久挂起。
	# 必须在实例化 World3D 之前设：_villain_armed 在 _ready() 里按当时
	# 的 seen_villain 一次性武装，事后再改不会再算。
	_gm.prologue_done = true
	_gm.seen_villain = 3   # = GameManager.VILLAIN_SCENE_COUNT
	_gm.headless_mode = false
	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	_probe = Probe.new()
	_probe.setup(_world)
	root.add_child(_probe)
	await process_frame
	await process_frame
	_start_station()


func _start_station() -> void:
	_gm.reset()   # 同一驿站打满 3 次就 exhausted，不重置会随机测不出来
	# reset() 把 seen_villain 归零，会把三场郑铎对白重新武装；骑站间距离够长时会
	# 在测试中途弹出来。这两个测试只关心按键路由，关掉叙事门。
	_gm.seen_villain = 3   # = GameManager.VILLAIN_SCENE_COUNT
	_gm.prologue_done = true
	var st: Dictionary = STATIONS[_si]
	var idx: int = st["idx"]
	_world._player.position = _world._stations[idx].position + Vector3(0, 1.0, 3)
	_world._nearby_station_idx = idx
	_world._interact_cooldown = 0.0
	_probe.raw = 0
	_probe.through = 0
	_mg = null
	_mg_at = -1
	_zither_typed = 0
	_space_down = false
	_cloud_t = 1
	_phase = PH_DIALOGUE
	_world._do_check_in(idx)


## 完整事件（keycode + physical_keycode）。只有这种能推进对话弹窗——
## 内建 ui_accept 认的是 keycode。
func _push_key_full(key: int) -> void:
	for pressed in [true, false]:
		_push(key, pressed, true)


## 只填 physical_keycode，keycode 留 0 —— 复刻 Web 导出下的键盘事件
func _push_key_physical_only(key: int, pressed: bool) -> void:
	_push(key, pressed, false)


## 只用 Input.parse_input_event，不要再 root.push_input：parse 自己就已经把事件
## 投递进 GUI 了，两条路都走会让一次按键被 _gui_input 收到两遍。竹子小游戏有
## _window_active 挡着看不出来，琴小游戏每按一下就记两个音符，直接判错音取消。
func _push(key: int, pressed: bool, with_keycode: bool) -> void:
	var ev = InputEventKey.new()
	if with_keycode:
		ev.keycode = key
	ev.physical_keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _process(_d: float) -> bool:
	_f += 1
	if _si >= STATIONS.size():
		_report()
		return true

	var st: Dictionary = STATIONS[_si]
	var name: String = st["name"]

	if _phase == PH_DIALOGUE:
		var dlg: Node = _world._dialogue_popup
		if dlg != null and dlg.visible and _f - _last_act_f >= 20:
			_last_act_f = _f
			_push_key_full(KEY_SPACE)
		elif _world._mini_game_node != null and is_instance_valid(_world._mini_game_node):
			_mg = _world._mini_game_node
			_mg_at = _f
			_phase = PH_DRIVE
		elif _f > _mg_at + 300 and _mg_at >= 0:
			pass
		return false

	if _phase == PH_DRIVE:
		_drive(st)
		return false

	# PH_SETTLE：结果已出，等打卡收尾走完再切下一个
	if _f - _last_act_f > 120:
		_advance(name)
	return false


func _drive(st: Dictionary) -> void:
	# 琴和竹在结算时会自己 queue_free()，_mg 随即失效
	if not is_instance_valid(_mg):
		_phase = PH_SETTLE
		return
	var kind: String = st["kind"]
	match kind:
		"zither":
			# 等它把序列放完进入 STATE_INPUT，再照着 _sequence 敲 1-4
			if _mg._state != ZITHER_STATE_INPUT:
				return
			if _zither_typed >= _mg._sequence.size():
				return
			if _f - _last_act_f < 6:
				return
			_last_act_f = _f
			var note: int = _mg._sequence[_zither_typed]
			_zither_typed += 1
			_push_key_physical_only(KEY_1 + note, true)
			_push_key_physical_only(KEY_1 + note, false)
			if _world._mini_game_state != MG_RUNNING:
				_phase = PH_SETTLE
		"tea":
			# 长按 3 秒：只发按下，靠 _process 累加 _hold_time
			if _space_down:
				if _world._mini_game_state != MG_RUNNING:
					_push_key_physical_only(KEY_SPACE, false)
					_phase = PH_SETTLE
				return
			if _f - _last_act_f >= 10:
				_last_act_f = _f
				_space_down = true
				_push_key_physical_only(KEY_SPACE, true)
		"bamboo":
			# 每 8 帧按一次：既落在 1.2s 窗口里，也必然落进 0.4s 空档
			if _f - _last_act_f >= 8:
				_last_act_f = _f
				_push_key_physical_only(KEY_SPACE, true)
				_push_key_physical_only(KEY_SPACE, false)
			if _f - _mg_at > 150:
				_phase = PH_SETTLE
		"bird":
			# 等它把 0.8s 的观察阶段放完进入 STATE_CHOICE，再照 _correct_choice 敲数字
			if _mg._state != BIRD_STATE_CHOICE:
				return
			if _f - _last_act_f < 6:
				return
			_last_act_f = _f
			_push_key_physical_only(KEY_1 + _mg._correct_choice, true)
			_push_key_physical_only(KEY_1 + _mg._correct_choice, false)
			_phase = PH_SETTLE
		"cloud":
			# 空格落笔（光标初始就落在第一个轨迹点上），然后照着 _path_world 推着走。
			# _update_draw 每调一次记一段路长的 0.1，绕一圈攒不到 0.75，
			# 所以绕满一圈后要接着绕第二圈，到 0.95 才松手——留够余量。
			if not _space_down:
				_last_act_f = _f
				_space_down = true
				_cloud_t = 1
				_push_key_physical_only(KEY_SPACE, true)
				return
			if _world._mini_game_state != MG_RUNNING:
				_push_key_physical_only(KEY_SPACE, false)
				_phase = PH_SETTLE
				return
			if _mg._drawn_ratio >= 0.95:
				_push_key_physical_only(KEY_SPACE, false)
				return
			var pts: Array = _mg._path_world
			if _cloud_t >= pts.size():
				_cloud_t = 0
			var tgt: Vector2 = pts[_cloud_t]
			if _mg._key_cursor.distance_to(tgt) <= 6.0:
				_cloud_t += 1
				return
			if _f - _last_act_f < 2:
				return
			_last_act_f = _f
			# 一次只推一个轴：一次推 KEY_STEP 再重新判方向，走的是曼哈顿路径，
			# 步数比直线多，但和 _gui_input_key 里的挪动规则完全一致，
			# 不会推过头又被 clamp 回来。
			var d: Vector2 = tgt - _mg._key_cursor
			var key: int = KEY_RIGHT
			if absf(d.x) >= absf(d.y):
				key = KEY_RIGHT if d.x > 0.0 else KEY_LEFT
			else:
				key = KEY_DOWN if d.y > 0.0 else KEY_UP
			_push_key_physical_only(key, true)
			_push_key_physical_only(key, false)


func _advance(name: String) -> void:
	var state: int = _world._mini_game_state
	var through: int = _probe.through
	var done := state == 0
	if done and through == 0:
		_results.append("[OK]   %-7s physical_keycode 可用，小游戏成功完成，无按键穿过门" % name)
	else:
		_results.append("[FAIL] %-7s mg_state=%s（0=成功 1=取消 -2=还在跑）穿过门=%d"
			% [name, state, through])
	_si += 1
	if _si < STATIONS.size():
		_f = -200   # 让 _last_act_f 的节流立刻放行
		_start_station()


func _report() -> void:
	print("==== verify_mini_game_keys ====")
	for r in _results:
		print(r)
	var bad := 0
	for r in _results:
		if r.begins_with("[FAIL]"):
			bad += 1
	print("[verify_mini_game_keys] %s  (失败 %d)" % ["PASS" if bad == 0 else "FAIL", bad])
	# 打卡会写 user://gift188.cfg。跑完必须清掉，否则玩家下次进游戏
	# 这三个驿站可能已经 exhausted，再也进不去小游戏。
	if _gm != null and _gm.has_method("_clear_save"):
		_gm._clear_save()
