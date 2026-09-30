extends SceneTree
## verify_bamboo_done.gd — "砍完第5根竹子小游戏凭空消失"的回归
##
## 旧版 _next_bamboo 在 _current_bamboo >= BAMBOO_COUNT 时直接
## _on_mini_game_done(SUCCESS) + queue_free()，遮罩在同一帧就没了。玩家既
## 分不清自己是被踢出去还是砍赢了，报告上来的现象就是"按空格退出游戏"。
##
## 这里断言砍完第 5 根之后：
##   1. 进入 _succeeded 成功画面，节点还在树上、没有立刻被 free
##   2. 停留期间 mg_state 一直是 MG_RUNNING（不会同一帧就结算）
##   3. 停留期间狂按空格既不会提前结算，也不会把流程判成取消
##   4. 停留够久之后才以 SUCCESS 正常收尾
##
## 必须带窗口跑：headless 的 dummy display server 不做真焦点路由。
## 用法： godot --path . --script tools/verify_bamboo_done.gd --quit-after 900

const BAMBOO_STATION := 14
const MG_RUNNING := -2
const MG_SUCCESS := 0
const BAMBOO_COUNT := 5
## 允许的成功画面最短停留（秒）。要明显小于 SUCCESS_HOLD_SEC=1.6，
## 否则这条断言等于没测。
const MIN_HOLD_SEC := 0.6

var _world: Node = null
var _gm: Node = null
var _f := 0
var _mg: Node = null
var _last_push := -100
## 第 5 根砍倒的时刻，也是本脚本所有后续判定的起点。
var _last_cut_at := -1
var _last_cut_ms := 0
## 进入成功画面的时刻；0=整局没观测到，-1=被提前 free，-2=同上另一路径。
var _succeeded_at := 0
var _succeeded_ms := 0
var _settled_at := -1
var _settled_ms := 0
var _state_during_hold := MG_RUNNING
var _mashed_during_hold := 0


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
	_gm.reset()
	_gm.onboarding_shown = true
	# headless_mode=false 时 World3D 会把序章和郑铎三场真的播出来，没人点按钮就永久挂起。
	# 这两个测试只关心小游戏收尾，把叙事门全部关掉。
	_gm.prologue_done = true
	_gm.seen_villain = 3   # = GameManager.VILLAIN_SCENE_COUNT
	_gm.headless_mode = false
	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	await process_frame
	await process_frame
	_world._player.position = _world._stations[BAMBOO_STATION].position + Vector3(0, 1.0, 3)
	_world._nearby_station_idx = BAMBOO_STATION
	_world._do_check_in(BAMBOO_STATION)


func _push_space(pressed: bool) -> void:
	var ev = InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _process(_d: float) -> bool:
	_f += 1
	if _world == null:
		return false   # _initialize 还在 await 世界加载

	var mg_alive: bool = _world._mini_game_node != null \
			and is_instance_valid(_world._mini_game_node)

	# 砍到第 5 根：旧版 bug 的触发点。必须在"节点还活着"的那 0.4s 空档里采样——
	# 旧版是进成功画面的同一帧就 free，靠 _succeeded 标志去抓根本来不及。
	if mg_alive and _last_cut_at < 0 and _mg_current() >= BAMBOO_COUNT:
		_last_cut_at = _f
		_last_cut_ms = Time.get_ticks_msec()
		print("[%d] 第5根已砍倒，等待成功画面" % _f)

	# 结算时刻要在对话弹窗短路之前采样：成功后 World3D 立刻弹碎片对白，
	# 弹窗期间本函数会提前 return，漏采的话 hold 会被算成"成功画面+整段对白"。
	if _settled_at < 0 and _last_cut_at > 0 and _world._mini_game_state != MG_RUNNING:
		_settled_at = _f
		_settled_ms = Time.get_ticks_msec()

	# 遮罩没了但流程还悬在 MG_RUNNING —— 玩家看到的正是"凭空消失回到 3D"。
	if _settled_at < 0 and _last_cut_at > 0 and not mg_alive \
			and _world._mini_game_state == MG_RUNNING:
		_succeeded_at = -1   # 标记"被提前 free"
		_settled_at = _f
		_settled_ms = Time.get_ticks_msec()

	if _settled_at > 0 and _f > _settled_at + 30:
		_report()
		return true

	var dlg: Node = _world._dialogue_popup
	if dlg != null and dlg.visible:
		if _f - _last_push >= 20:
			_last_push = _f
			_push_space(true)
			_push_space(false)
		return false

	if mg_alive:
		_mg = _world._mini_game_node
		# 分支条件是"进没进成功画面"，不是"结没结算"：成功画面期间 _settled_at
		# 仍然是 -1，用它当条件会永远走砍竹分支、按键风暴根本没跑起来。
		if _succeeded_at == 0:
			# 正常砍：每换一根重置节流，30 帧一次
			if _mg.get_meta("seen", -1) != _mg._current_bamboo:
				_mg.set_meta("seen", _mg._current_bamboo)
				_last_push = _f
			if _f - _last_push >= 30:
				_last_push = _f
				_push_space(true)
				_push_space(false)
		else:
			# 已经进成功画面：狂按空格，看会不会被提前结算/判取消
			if _f - _last_push >= 4:
				_last_push = _f
				_mashed_during_hold += 1
				_push_space(true)
				_push_space(false)

		if _mg._succeeded and _succeeded_at == 0:
			_succeeded_at = _f
			_succeeded_ms = Time.get_ticks_msec()
			_state_during_hold = _world._mini_game_state
			print("[%d] 进入成功画面" % _f)
	return false


func _mg_current() -> int:
	if _world._mini_game_node == null or not is_instance_valid(_world._mini_game_node):
		return -1
	return _world._mini_game_node._current_bamboo


func _report() -> void:
	print("==== verify_bamboo_done ====")
	if _succeeded_at == -1:
		print("[FAIL] 砍完第5根后遮罩凭空消失，mg_state 还停在 MG_RUNNING")
		_finish(false)
		return
	if _settled_at < 0:
		print("[FAIL] 迟迟没有收尾")
		_finish(false)
		return
	if _succeeded_at == 0:
		print("[FAIL] 整局都没观测到成功画面")
		_finish(false)
		return
	var ok := true
	# 必须按墙钟算：这台机器带窗口能跑到 280+ FPS，拿帧数当秒数会把
	# 1.6s 的停留算成 7s，断言直接失去意义。
	var hold: float = float(_settled_ms - _succeeded_ms) / 1000.0
	print("[OK]   成功画面停留 %.2fs（%d 帧），期间狂按空格 %d 次"
		% [hold, _settled_at - _succeeded_at, _mashed_during_hold])
	if hold < MIN_HOLD_SEC:
		print("[FAIL] 停留 %.2fs < %.2fs，等于没有成功画面" % [hold, MIN_HOLD_SEC])
		ok = false
	if _state_during_hold != MG_RUNNING:
		print("[FAIL] 进入成功画面时 mg_state 已经是 %d（-2 才表示还在跑）" % _state_during_hold)
		ok = false
	if _world._mini_game_state != MG_SUCCESS:
		print("[FAIL] 收尾时 mg_state=%d（0 才是成功）" % _world._mini_game_state)
		ok = false
	_finish(ok)


func _finish(ok: bool) -> void:
	print("[verify_bamboo_done] %s" % ("PASS" if ok else "FAIL"))
	# 打卡会写 user://gift188.cfg，跑完清掉，别让玩家下次进游戏时驿站已 exhausted
	if _gm != null and _gm.has_method("_clear_save"):
		_gm._clear_save()
