extends SceneTree
## probe_station14.gd — 只追 14 号(竹雨庭)的成功链路，定位"打卡次数=0"
## 用法： godot --headless --path . --script tools/probe_station14.gd

const MG_RUNNING := -2
const SUCCESS := 0

var _world: Node = null
var _gm: Node = null
var _signal_hits: Array = []


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


func _ensure_action() -> void:
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var ev = InputEventKey.new()
		ev.physical_keycode = KEY_SPACE
		InputMap.action_add_event("interact", ev)


func _push_space(pressed: bool) -> void:
	var ev = InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = pressed
	Input.parse_input_event(ev)
	root.push_input(ev)


func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var waited := 0.0
	while waited < timeout_sec:
		if cond.call():
			return true
		await create_timer(0.05).timeout
		waited += 0.05
	return false


func _initialize() -> void:
	Engine.max_fps = 60
	_ensure_autoloads()
	_ensure_action()
	_gm = root.get_node("GameManager")
	_gm.reset()
	_gm.onboarding_shown = true
	_run.call_deferred()


func _run() -> void:
	print("=== 探针：14 号竹雨庭成功链路 ===")
	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	await create_timer(2.5).timeout
	_world._onboarding.visible = false
	_world._player.set_can_move(true)

	_gm.fragment_collected.connect(func(i): _signal_hits.append(i))

	var rd = _world._road_builder.get_road_data()
	print("stations[14]: name=%s fragment='%s' has_fragment=%s" % [
		rd.stations[14].get("name", "?"), rd.stations[14].get("fragment", "?"),
		str(rd.station_has_fragment(14))])
	print("World3D._station_fragment(14) = '%s'" % _world._station_fragment(14))
	print("World3D._fragment_slot_idx('竹') = %d" % _world._fragment_slot_idx("竹"))
	# --script 模式下 autoload 全局名/class_name 可能还没注册，用 load 取常量
	var rd_script: GDScript = load("res://scripts/road_data.gd")
	print("FRAGMENT_SLOT_STATION_IDX = %s" % str(rd_script.FRAGMENT_SLOT_STATION_IDX))
	print("is_english() = %s" % str(root.get_node("Localization").is_english()))
	print("初始 collected = %s" % str(_gm.collected))

	var st_pos: Vector3 = _world._stations[14].position
	_world._player.position = st_pos + Vector3(0, 3, 6)
	await create_timer(0.4).timeout
	print("nearby=%d dist=%.1f" % [_world._nearby_station_idx, _world._nearby_station_dist])

	_push_space(true)
	_push_space(false)
	var started := await _wait_until(func(): return _world._check_in_in_progress, 3.0)
	print("打卡已触发 = %s" % str(started))

	var mg_ok := await _wait_until(
		func(): return _world._mini_game_state == MG_RUNNING, 15.0)
	print("小游戏注入 = %s  节点=%s" % [str(mg_ok), str(_world._mini_game_node)])

	_world._on_mini_game_done(SUCCESS)
	print("已发 SUCCESS；state=%d" % _world._mini_game_state)

	var finished := await _wait_until(
		func(): return not _world._check_in_in_progress, 20.0)
	print("序列收尾 = %s" % str(finished))
	print("collected = %s" % str(_gm.collected))
	print("get_station_count(14) = %d" % _gm.get_station_count(14))
	print("is_collected(14) = %s" % str(_gm.is_collected(14)))
	print("fragment_collected 信号命中 = %s" % str(_signal_hits))

	if _gm != null:
		_gm._clear_save()
	quit(0)
