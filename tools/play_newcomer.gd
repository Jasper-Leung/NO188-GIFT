extends SceneTree
## play_newcomer.gd — 以「完全不了解这个游戏」的玩家身份真玩一遍头十分钟
##
## 和 lookdev_journey.gd 的分工：那边量的是"每一屏排版对不对"，
## 这边量的是"从头到尾玩下来是什么体验"——每一段花了多久、玩家在���个时刻
## 知不知道该干什么、有没有卡住或者迷路。**不能加 --headless**：
## 对白弹窗和小游戏要靠真焦点路由才收得到按键，dummy renderer 下量出来的
## "玩得通"是假的。
##
## 它不做断言，只**记时间、记位置、记玩家在每一刻看到的东西**，把数字和
## 截图留给看图的人。判分是人的事，脚本只负责诚实地跑。
##
## 用法： godot --path . --script tools/play_newcomer.gd

const SAVE_DIR := "user://play_newcomer"
const SHOT := Vector2i(1280, 720)
## 多久没到站就判定玩家迷路了（一圈只要 82 秒，两圈还不到就是有问题）
const LOST_SEC := 180.0

## 五个碎片驿站，按碎片槽位顺序（= RoadData.FRAGMENT_SLOT_STATION_IDX）
const FRAG_STATIONS := [7, 10, 13, 14, 4]

var _t0 := 0
var _gm: Node = null
var _loc: Node = null
var _world: Node = null
var _shot_n := 0
var _log: Array[String] = []


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


func _initialize() -> void:
	Engine.max_fps = 60
	_ensure_autoloads()
	_gm = root.get_node("GameManager")
	_loc = root.get_node("Localization")
	_gm._clear_save()          # 冷启动：磁盘上没有存档
	_gm.set_language("zh") if _gm.has_method("set_language") else _loc.set_language("zh")
	root.size = SHOT
	_run.call_deferred()


func _say(s: String) -> void:
	var line := "[%6.1fs] %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, s]
	print(line)
	_log.append(line)


func _snap(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	_shot_n += 1
	img.save_png("%s/%02d_%s.png" % [SAVE_DIR, _shot_n, name])
	_say("        拍了一张 %02d_%s" % [_shot_n, name])


func _push_space(pressed: bool) -> void:
	var ev = InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = pressed
	Input.parse_input_event(ev)
	root.push_input(ev)


func _hold(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _bearing(v: Vector3) -> float:
	# 和 HUD 的箭头同一套约定：正前方 (-Z) 是 0、正右方 (+X) 是 +PI/2
	return atan2(v.x, -v.z)


func _run() -> void:
	_t0 = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_say("=== 冷启动：磁盘上没有存档，中文界面 ===")

	# ---- 标题页 ----
	var gift = load("res://scenes/GiftBox.tscn").instantiate()
	root.add_child(gift)
	await create_timer(2.0).timeout
	await _snap("title_标题页")
	_say("标题页上能看到「开始」吗：%s" % str(gift.get_node_or_null("StartButton") != null))
	gift.queue_free()
	await process_frame

	# ---- 序章 / 操作说明 / 第一次拿到操纵 ----
	# onboarding_shown 保持 false：新玩家一定会看到操作说明和序章，
	# 这一段是"玩了十分钟才拿到操纵权"里最贵的部分，要单独计时。
	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	await create_timer(2.5).timeout

	_say("操作说明弹出来了：%s" % str(_world._onboarding.visible))
	if _world._onboarding.visible:
		await _snap("onboarding_操作说明")
	var dlg: Node = _world._dialogue_popup
	_say("序章第一句：「%s」" % str(dlg.get("_current_line") if dlg else "?"))

	# 一个新玩家会怎么做？看到字就按空格，一路按到能动为止。
	# 计时用墙钟而不是"t += 0.05"再判 t % 0.3 == 0 —— 浮点累加永远撞不上那个
	# 精确等号，前两版这里一次空格都没发出去，序章和对白全靠自动播放蒙混过关，
	# 量出来的"玩了 23 秒才拿到操纵权"其实是没人点。
	var t_dlg := 0.0
	var n_clicks := 0
	var next_click := 0.0
	while t_dlg < 40.0 and not bool(_world._player._can_move):
		if dlg != null and dlg.visible and t_dlg >= next_click:
			next_click = t_dlg + 0.35
			_push_space(true)
			_push_space(false)
			n_clicks += 1
		await process_frame
		t_dlg += 0.016
	_say("按了 %d 次空格、%.1f 秒之后才拿到操纵权" % [n_clicks, t_dlg])
	await _snap("prologue_序章结束")
	_world._player.set_can_move(true)
	_world._player.set_camera_locked(false)

	# ---- 真骑：自动驾驶去第一座碎片站 ----
	# 用 Input.action_press 走 Player3D 的真输入管线（`Input.get_action_strength`），
	# 不是直接把玩家挪过去 —— 直接挪的话测的是"瞬移过去要多久"，
	# 测不出玩家在生疏操作下到底骑得到哪、会不会撞边界。
	var rd = _world._road_builder.get_road_data()
	var total: float = rd.total_arclength()
	_say("环路全长 %.1fm，满速 %.0fm/s —— 骑满一圈 %.0f 秒" % [
		total, float(_world._player.MAX_SPEED), total / float(_world._player.MAX_SPEED)])

	for si in range(FRAG_STATIONS.size()):
		var idx: int = FRAG_STATIONS[si]
		var tgt: Vector3 = rd.get_station_world_pos(idx)
		_say("→ 去第 %d 座碎片驿站（%s），直线距离 %.0fm" % [
			si + 1, _world._station_name(idx),
			Vector2(_world._player.position.x - tgt.x,
					_world._player.position.z - tgt.z).length()])
		var got := await _ride_to(_world._player, tgt, LOST_SEC)
		_say("   骑到了：%s（用时见上）" % str(got))
		if not got:
			break
		await _snap("arrive_%d_到站" % (si + 1))

		# 到站之后一个新人会看到什么
		_say("   脚下提示圈：%s" % str(_world._check_in_prompt.visible))
		_say("   顶栏下一处：%s" % str(_world._hud3d._next_label.text))
		if si == 0:
			await _snap("prompt_到站提示")

		# 打卡 → 对白 → 小游戏
		var t0 := Time.get_ticks_msec()
		_push_space(true)
		_push_space(false)
		await create_timer(0.4).timeout
		# 对白一段段点掉。同一批墙钟节拍器的教训：这里也用 next_click，
		# 别用浮点取模判等——判不中就等于没人点，对白会一直挂在屏上。
		var t := 0.0
		var next_click2 := 0.0
		while t < 25.0 and _world._mini_game_state != -2:
			if dlg != null and dlg.visible and t >= next_click2:
				next_click2 = t + 0.35
				_push_space(true)
				_push_space(false)
			await process_frame
			t += 0.016
		_say("   从按空格到小游戏弹出来：%.1f 秒" % [
			(Time.get_ticks_msec() - t0) / 1000.0])
		if si == 0:
			await _snap("minigame_第1个小游戏")

		# 小游戏不代打（五个玩法各不相同，代打就等于重写一遍），
		# 只记录它把玩家晾在什么界面上、多久没动静。
		_say("   小游戏状态=%d，晾 %.1f 秒" % [
			_world._mini_game_state, _world.MINI_GAME_TIMEOUT_SEC])
		await create_timer(2.0).timeout
		# 按 ESC 走掉（每个小游戏都必须能放弃）
		var ev = InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		ev.pressed = true
		Input.parse_input_event(ev)
		root.push_input(ev)
		await create_timer(1.0).timeout
		_say("   按 ESC 之后小游戏状态=%d（-2 还在跑就是没接上）" % _world._mini_game_state)
		# 等收尾面板过去
		t = 0.0
		while t < 8.0 and _world._check_in_in_progress:
			await create_timer(0.1).timeout
			t += 0.1
		if _world._check_in_in_progress:
			_say("   !! 8 秒后打卡流程还没收尾，闩锁留在 true 上：%s" %
					str(_world._check_in_in_progress))
		await create_timer(0.5).timeout

	# ---- 收尾 ----
	await _snap("after_跑完")
	# collected 是预置了 5 个 0 键的字典，size() 恒等于 5，量它等于没量。
	_say("最终：已过驿 %d，碎片 %d/5，心神 %d，旅币 %d" % [
		_gm.get_seen_station_count(), _gm.get_collected_count(), _gm.mood, _gm.lvbi])
	print("\n截图目录: %s" % ProjectSettings.globalize_path(SAVE_DIR))
	_gm._clear_save()
	quit(0)


## 骑到目标点。返回 true = 到了，false = 超时（玩家迷路/卡住）。
##
## 速度归零时把 World3D 的每一个闩锁都打一遍：不打的话"骑不动"和"被冻住"
## 看起来一模一样，而这两件事的修法完全不同。
func _ride_to(player: Node3D, tgt: Vector3, timeout_sec: float) -> bool:
	var t := 0.0
	var last_log := 0.0
	var stuck := 0
	_hold("move_up", true)
	while t < timeout_sec:
		var to := tgt - player.global_position
		to.y = 0.0
		if to.length() < 7.0:
			_hold("move_up", false)
			_hold("move_left", false)
			_hold("move_right", false)
			return true
		var diff := wrapf(_bearing(to) - _bearing(-player.global_basis.z), -PI, PI)
		# 转得比走得少：新手是"歪一点就拧一把"，死盯着目标反而原地打转
		_hold("move_left", diff < -0.12)
		_hold("move_right", diff > 0.12)
		await process_frame
		t += 0.016
		if player.get_speed() < 0.05:
			stuck += 1
			if stuck == 1:
				_dump_latches(to.length())
		else:
			stuck = 0
		if t - last_log >= 15.0:
			last_log = t
			_say("   ……骑了 %.0fs，距目标 %.0fm，速度 %.1fm/s" % [
				t, to.length(), player.get_speed()])
	_hold("move_up", false)
	_hold("move_left", false)
	_hold("move_right", false)
	return false


## 速度归零那一帧的现场。玩家看到的只是"按着 W 不动"，这里要能回答为什么。
func _dump_latches(dist: float) -> void:
	var w = _world
	_say("   !!! 速度归零（距目标 %.0fm），闩锁现场：" % dist)
	for k in ["_paused", "_check_in_in_progress", "_all_done", "_shop_open",
			"_recheck_armed", "_villain_playing"]:
		_say("        %-24s = %s" % [k, str(w.get(k))])
	_say("        %-24s = %d" % ["_mini_game_state", w._mini_game_state])
	_say("        %-24s = %d" % ["_nearby_station_idx", w._nearby_station_idx])
	_say("        %-24s = %s" % ["_can_move", str(_world._player._can_move)])
	_say("        %-24s = %.3f" % ["move_up strength",
			Input.get_action_strength("move_up")])
	_say("        %-24s = %s" % ["对白弹窗 visible",
			str(w._dialogue_popup.visible if w._dialogue_popup else false)])
	_say("        %-24s = %s" % ["暂停面板 visible", str(w._pause_panel.visible)])
	_say("        %-24s = %s" % ["打卡面板 visible", str(w._check_in_popup.visible)])
	_say("        %-24s = %s" % ["商店 visible", str(w._shop_panel.visible)])
	_say("        %-24s = %s" % ["对白是否可见（玩家看得见提示吗）",
			str(w._dialogue_popup.visible if w._dialogue_popup else false)])
