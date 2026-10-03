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
## 中间路点骑到多近算过。终点（站前那一点）要 4m，中间路点只是导航线上的
## 引导，12m 就够——收得太紧反而会在路点周围画小圈出不来。
const WAYPOINT_RADIUS := 12.0
## 沿路几个路点取一个（`_road_points_2d` 一路 200+ 点）
const WAYPOINT_STRIDE := 8

## 五个碎片驿站，按碎片槽位顺序（= RoadData.FRAGMENT_SLOT_STATION_IDX）
const FRAG_STATIONS := [7, 10, 13, 14, 4]

## 小游戏注入成功结果，而不是按 ESC 走掉。
##
## 取消一个小游戏走的是 `_on_mini_game_done(CANCELLED)` → `_show_failed_panel()`
## → `return`，`check_in()` 一次都不调，于是五块碎片永远是 0、信号发不出去、
## **集齐二选一面板永远不弹**——而那一趟的落点就是那个面板。
## 代打五个小游戏等于把这五个玩法重写一遍，写出来的那份不是玩家玩的那个，
## 量它就是拿尺子量自己。所以只注入"结果"，把这一趟的**下限**量出来：
## 上限 = 下限 + 玩家自己花在五局上的时间。
const FORCE_MINI_GAME_SUCCESS := true

var _t0 := 0
## 拿到操纵权 / 骑到第五座碎片站的墙钟秒（从 `_t0` 起算）。
## 为什么记这两个而不是记"跑完用了多久"：跑完还包含了五个小游戏各自的
## 放弃与收尾，那几秒量的是本脚本的节奏而不是游戏的长度。
var _t_move := 0.0
var _t_last := 0.0
var _gm: Node = null
var _loc: Node = null
var _world: Node = null
var _pulse_ms := 0
var _pulse_on := false
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


## 一次完整的按键：按下、跨几帧、**松开**。
##
## 三处都踩过同一个坑，所以收成一个函数：
##   · 空格原来是 `_push_space(true); _push_space(false)` **写在同一帧里**，
##     挤掉之后 `Input.is_action_just_pressed("interact")` 判定时这一帧已经松手，
##     打卡分支一次都进不去（CLAUDE.md「按和放必须分在两帧里」）。
##   · ESC 原来**只按不放**。键一直按在输入单例里，后续任何一次"要一个干净的
##     ESC"的判断都不成立。
##   · 油门原来走 `Input.action_press()` 合成动作，而空格/ESC 走真按键事件——
##     两条输入管线混着用。`tools/probe_stuck.gd` 量过：A 冷启动真按键峰值
##     15.00m/s、B 小游戏→ESC(按+放)→真按键峰值 5.73m/s，两腿都"能骑"，
##     所以产品没有把玩家冻住，"第二次骑不动 165 秒"是量法自己松了油门。
##     现在**全部**走真按键事件。
func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


## 敲一下：按下 → 等两帧 → 松开。返回时这一帧键已经不在按着。
func _tap(code: int) -> void:
	_key(code, true)
	await process_frame
	await process_frame
	_key(code, false)
	await process_frame


## 骑车的油门与转向。全部是真按键事件，理由见 `_key()` 上面那段。
##
## **只在状态变化时发一次事件**，不是每帧重发：真按键是"按下那一刻"的事，
## 每帧重发一个 `pressed=true` 是合成动作才有的写法，按住期间等价的只是
## `get_action_strength()` 一直读到 1。`probe_stuck.gd` 那两条量到 15.00 /
## 5.73 m/s 的腿用的正是"按一次、一直按住"这一种。
var _held := {"move_up": false, "move_down": false, "move_left": false,
		"move_right": false}


func _hold(action: String, on: bool) -> void:
	if bool(_held.get(action, false)) == on:
		return
	_held[action] = on
	match action:
		"move_up":
			_key(KEY_W, on)
		"move_down":
			_key(KEY_S, on)
		"move_left":
			_key(KEY_A, on)
		"move_right":
			_key(KEY_D, on)


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
	# 必须 call()，不能 get()：get() 取到的是 Function 对象本身，
	# 于是这行永远打印「Control(DialoguePopup.gd)::_current_line」，
	# 看起来像"序章第一句读不出来"，其实只是取法不对。
	_say("序章第一句：「%s」" % str(dlg.call("_current_line") if dlg else "?"))

	# 一个新玩家会怎么做？看到字就按空格，一路按到能动为止。
	#
	# 这里原来还带着一个更隐蔽的错：空格**只在 `dlg.visible` 时才发**，而操作说明
	# 面板不是 DialoguePopup —— 于是玩家站在操作说明前面的那几秒里一次空格都没
	# 发出去，`_can_move` 也不可能变真，这个循环注定跑满 40 秒预算然后报
	# "按了 0 次空格、40.0 秒"。冷启动一直"慢到离谱"就是这么来的。
	# 现在不看是谁挡着，只看能不能动：挡住了就按。
	#
	# 计时用墙钟而不是"t += 0.016"——后者在帧率不等于 60 时是假的（本机带窗口
	# 能跑 280+ FPS，会**低报**）。同理别用"t % 0.3 == 0"判等，浮点累加永远撞不上。
	var t_dlg := Time.get_ticks_msec()
	var n_clicks := 0
	var next_click := 0
	while not bool(_world._player._can_move):
		var now_ms := Time.get_ticks_msec()
		if now_ms >= next_click:
			next_click = now_ms + 350
			await _tap(KEY_SPACE)
			n_clicks += 1
		elif now_ms - t_dlg > 40000:
			_say("!! 40 秒还没拿到操纵权")
			break
		await process_frame
	var dlg_sec := (Time.get_ticks_msec() - t_dlg) / 1000.0
	_t_move = (Time.get_ticks_msec() - _t0) / 1000.0
	_say("按了 %d 次空格、%.1f 秒之后才拿到操纵权（冷启动起算 %.1f 秒）" % [
			n_clicks, dlg_sec, _t_move])
	await _snap("prologue_序章结束")
	_world._player.set_can_move(true)
	_world._player.set_camera_locked(false)

	# ---- 真骑：自动驾驶去第一座碎片站 ----
	# 油门和转向走**真按键事件**（`Input.parse_input_event`），不是直接把玩家
	# 挪过去 —— 直接挪的话测的是"瞬移过去要多久"，测不出玩家在生疏操作下
	# 到底骑得到哪、会不会撞边界；也不是 `Input.action_press()` 那种合成动作，
	# 理由见 `_key()` 上面那段。
	var rd = _world._road_builder.get_road_data()
	var total: float = rd.total_arclength()
	_say("环路全长 %.1fm，满速 %.0fm/s —— 骑满一圈 %.0f 秒" % [
		total, float(_world._player.MAX_SPEED), total / float(_world._player.MAX_SPEED)])

	for si in range(FRAG_STATIONS.size()):
		var idx: int = FRAG_STATIONS[si]
		# 目标不是站心，是**站心的路边那一点**。
		#
		# 16 座站全都摆在离路心线 18m 处，而 `World3D._apply_boundary_force()`
		# 只要玩家离路心线超过 `SOFT_BOUND`(12m) 就往回推。于是"径直骑向站心"
		# 是一次**永远赢不了的对拉**：油门往站心推、边界力往路心拉，合成速度
		# 在两头之间来回，`get_speed()` 长期读出 0.0——症状正是"车不动"，
		# 而闩锁现场每一条都是放行的（`_can_move=true`、面板全关）。
		# 玩家真人不会这样骑：他们拐下路、停在亭子跟前，那正是打卡圈（15m）
		# 覆盖的地方。所以这里照玩家做：停在离路心线 8m 的那一侧。
		var st: Vector3 = rd.get_station_world_pos(idx)
		var tgt: Vector3 = st - _away_from_road(st) * 10.0
		tgt.y = _world._get_terrain_height(tgt.x, tgt.z)
		_say("→ 去第 %d 座碎片驿站（%s），直线距离 %.0fm（站心在路外 %.0fm，" % [
			si + 1, _world._station_name(idx),
			Vector2(_world._player.position.x - tgt.x,
					_world._player.position.z - tgt.z).length(),
			Vector2(st.x - tgt.x, st.z - tgt.z).length()] +
			"骑的是路边那一点，不是站心）")
		# 沿路点过去，不是一条直线冲过去。
		#
		# `World3D._apply_boundary_force()` 在离路心线 `SOFT_BOUND`(12m) 之外
		# 往回推，而 `Player3D.ACCEL` 只有 8.0 —— 推力在 21m 之外就压过油门了。
		# 于是"横穿草地直奔下一站"在 27m 处会**顶成一辆钉住的自行车**：
		# 满速 15m/s、每帧被往回搬 0.25m，两者正好抵消，距离一分钟不变。
		# 真人不会这样骑——小地图上画的就是路，玩家沿路拐到站前再下去。
		# 所以这里走路点：性能上不更差（草地是斜着切进去的，路是绕着走的），
		# 而量到的是玩家真的会走的那条路。
		var via := _road_waypoints(_world._player.global_position, tgt)
		_say("   沿路 %d 个路点过去" % (via.size() - 1))
		var got := true
		for wi in range(via.size()):
			var last_wp := wi == via.size() - 1
			got = await _ride_to(_world._player, via[wi], LOST_SEC,
					4.0 if last_wp else WAYPOINT_RADIUS)
			if not got:
				break
		_say("   骑到了：%s（用时见上）" % str(got))
		if not got:
			break
		_t_last = (Time.get_ticks_msec() - _t0) / 1000.0
		await _snap("arrive_%d_到站" % (si + 1))

		# 到站之后一个新人会看到什么
		_say("   脚下提示圈：%s" % str(_world._check_in_prompt.visible))
		_say("   顶栏下一处：%s" % str(_world._hud3d._next_label.text))
		if si == 0:
			await _snap("prompt_到站提示")

		# 打卡 → 对白 → 小游戏
		var t0 := Time.get_ticks_msec()
		await _tap(KEY_SPACE)
		await create_timer(0.4).timeout
		# 对白一段段点掉。同一批墙钟节拍器的教训：这里也用 next_click，
		# 别用浮点取模判等——判不中就等于没人点，对白会一直挂在屏上。
		var t := Time.get_ticks_msec()
		var next_click2 := 0
		while _world._mini_game_state != -2:
			var now_ms := Time.get_ticks_msec()
			if now_ms - t > 25000:
				_say("   !! 25 秒小游戏还没弹出来")
				break
			if dlg != null and dlg.visible and now_ms >= next_click2:
				next_click2 = now_ms + 350
				await _tap(KEY_SPACE)
			await process_frame
		_say("   从按空格到小游戏弹出来：%.1f 秒" % [
			(Time.get_ticks_msec() - t0) / 1000.0])
		if si == 0:
			await _snap("minigame_第1个小游戏")

		# 小游戏不代打（五个玩法各不相同，代打就等于重写一遍），
		# 只记录它把玩家晾在什么界面上、多久没动静。
		_say("   小游戏状态=%d，晾 %.1f 秒" % [
			_world._mini_game_state, _world.MINI_GAME_TIMEOUT_SEC])
		await create_timer(0.5).timeout
		if FORCE_MINI_GAME_SUCCESS:
			# 量"一趟"的下限，而不是代打。代打五个玩法等于把这五个小游戏
			# 重写一遍——写出来的那份不是玩家玩的那个，量它就是拿尺子量自己。
			# 这里只把结果**注入**成成功，于是量到的是"除掉五局小游戏本身的
			# 全部时间"，也就是这一趟的下限；上限是下限加上玩家自己的手速。
			_world._on_mini_game_done(0)
		else:
			# 按 ESC 走掉（每个小游戏都必须能放弃）。**按完必须放**：
			# 只按不放的话键一直按在输入单例里，收尾面板那一下 ESC 就不成立了，
			# 而"车不动 165 秒"就是这么来的。
			await _tap(KEY_ESCAPE)
		await create_timer(1.0).timeout
		var st_end: int = int(_world._mini_game_state)
		_say("   小游戏收尾之后小游戏状态=%d（-2 还在跑就是没接上，0=成功，1=取消）" % st_end)
		if st_end == 1 and FORCE_MINI_GAME_SUCCESS:
			# 注入败了：那就是这个小游戏自己放的——引导期（1.6s）超过之后开的判定窗口（1.2s）自己过了。
			# 把注入时机放后 0.5s 就不会赶上它的自己收尾；此刻抢着去才是正确的，
			# 而让它自己收尾就是代打了一个玩家会按的键。
			_say("   !! 小游戏自己取消了（引导期过后的判定窗口到了），这一座收不到碎片")
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
	# 集齐之后还有 2.5 秒的合成动画，然后弹二选一面板。面板是这一趟的落点，
	# 量它得等它真的弹出来——不等就只量到「第五块碎片到手」，而那还不是一趟。
	var t_panel := Time.get_ticks_msec()
	# 循环里**每帧重读**闩锁。第一版把它读进局部变量再拿来判退出，
	# 于是循环永远跑满 12 秒才停——量出来的是"等了多久才放弃"，不是"等了多久才到"。
	while Time.get_ticks_msec() - t_panel < 12000:
		if bool(_world.get("_synthesis_choice_open")):
			break
		await process_frame
	var panel_sec := (Time.get_ticks_msec() - t_panel) / 1000.0
	var got_panel := bool(_world.get("_synthesis_choice_open"))
	if got_panel:
		_t_last = (Time.get_ticks_msec() - _t0) / 1000.0
		await _snap("synthesis_集齐二选一")
	await _snap("after_跑完")
	# collected 是预置了 5 个 0 键的字典，size() 恒等于 5，量它等于没量。
	_say("最终：已过驿 %d，碎片 %d/5，心神 %d，旅币 %d" % [
		_gm.get_seen_station_count(), _gm.get_collected_count(), _gm.mood, _gm.lvbi])
	_say("集齐二选一面板弹出来了：%s（第五块碎片到手之后 %.1f 秒）" % [
		str(got_panel), panel_sec])

	# ---- 一趟有多长 ----
	# 下面报的是这一趟的**下限**：五个小游戏各自的答案直接注入成了成功，
	# 所以这份数里没有玩家自己的手速。写清楚这一点——「5~6 分钟」是量出来的
	# 那几段之和，不是实测的一趟全程。
	_say("")
	_say("=== 一趟有多长（诚实的口径）===")
	_say("  冷启动 → 第一次拿到操纵权 ：%.1f 秒" % _t_move)
	_say("  冷启动 → 集齐二选一面板：%.1f 秒" % _t_last)
	_say("  上面这条**不含**五局小游戏本身（本作五个玩法各不相同，代打等于")
	_say("  重写一遍，写出来的不是玩家玩的那份）。玩家的上限 = 这条下限 +")
	_say("  五局小游戏 + 每局之间的往返与读对白的时间。")

	print("\n截图目录: %s" % ProjectSettings.globalize_path(SAVE_DIR))
	_gm._clear_save()
	quit(0)


## 从站指回路中线方向的单位向量。
##
## 驿站一律离路心线 18m，而边界力从 12m 就开始往回推——所以"骑向站心"是一场
## 赢不了的对拉。测试得跟玩家一样停在路边，理由见 `_run()` 里那段。
func _away_from_road(st: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var bd := 1e9
	for cl in _world._road_builder.get_all_centerlines():
		for q in cl:
			var d: float = Vector2(q.x - st.x, q.z - st.z).length()
			if d < bd:
				bd = d
				best = q
	if bd < 1e-8:
		return Vector3.ZERO
	var v := Vector3(st.x - best.x, 0.0, st.z - best.z)
	return v.normalized()


## 此刻是不是有人正在说话（郑铎戏 / 驿站对白 / 序章）。
##
## 只有真的有人说话时才按空格把对话点掉。`_can_move == false` 不能当判据——
## 那是"被冻住"的**结果**，而冻住的原因有好几种（过场、小游戏、暂停），
## 只按结果不按原因的话，路过驿站时也会被顺手开一场打卡。
func _villain_talking() -> bool:
	if bool(_world.get("_villain_playing")):
		return true
	var dlg: Node = _world.get("_dialogue_popup")
	return dlg != null and is_instance_valid(dlg) and bool(dlg.visible)


## 骑到目标点。返回 true = 到了，false = 超时（玩家迷路/卡住）。
##
## 速度归零时把 World3D 的每一个闩锁都打一遍：不打的话"骑不动"和"被冻住"
## 看起来一模一样，而这两件事的修法完全不同。
func _ride_to(player: Node3D, tgt: Vector3, timeout_sec: float,
		arrive: float = 4.0) -> bool:
	var t := Time.get_ticks_msec()
	var last_log := 0
	var stuck := 0
	var unblock_ms := 0
	while (Time.get_ticks_msec() - t) / 1000.0 < timeout_sec:
		var to := tgt - player.global_position
		to.y = 0.0
		# 终点要 4m 而不是 7m：目标点离站心 10m，停在 4m 处就落在打卡圈（15m）里侧，
		# 站到 7m 外沿的话只剩 3m 余量，一次边界回弹就够退到圈外。
		if to.length() < arrive:
			_hold("move_up", false)
			_hold("move_left", false)
			_hold("move_right", false)
			return true
		# 被人拦住就先按空格把话听完 —— 真人就是这么做的。
		#
		# 郑铎三场的闸在驿数 4/8/12，而这一趟是从头骑的，所以第一场必然在
		# 半路上起播；起播时 `_can_move` 是 false，车纹丝不动。不按空格的话，
		# 对白一直挂在屏上，这一条 `_ride_to` 注定超时——量出来的是
		# "车不动 165 秒"，而真正的量法缺陷是"被剧情拦住时不会点对话"。
		#
		# 判据要**窄**：只在真的有人说话时按空格。宽一点（"任何时候顺手按一下"）
		# 就会在路过驿站时顺手开一场打卡，这一趟的路线整个走偏。
		if _villain_talking():
			var now2 := Time.get_ticks_msec()
			if now2 - unblock_ms > 350:
				unblock_ms = now2
				_hold("move_up", false)
				await _tap(KEY_SPACE)
			else:
				await process_frame
			continue
		# 油门每帧都确认一次。`_hold()` 只在状态变化时才发事件，所以这不是
		# 每帧重发按键——它补的是**推完对白之后那一脚油门**：上面那个分支
		# 把 `move_up` 放了，出来若不补上，车就永远停在这儿，
		# 而症状与"被冻住"一模一样。
		var diff := wrapf(_bearing(to) - _bearing(-player.global_basis.z), -PI, PI)
		# 满油门在 15m/s 上的转弯半径约 132m（实测：目标在正后方时它会绕着目标
		# 画一个直径 264m 的圈，"距目标 132m" 三分钟一动不动）。所以**拐不过去的
		# 时候要收油**——真玩家也是这么骑的，而死盯着目标猛踩只会原地转圈。
		if absf(diff) > 0.6:
			_pulse_throttle(0.35 if absf(diff) > 2.0 else 0.6)
		else:
			_hold("move_up", true)
		# 转得比走得少：新手是"歪一点就拧一把"，死盯着目标反而原地打转
		_hold("move_left", diff < -0.12)
		_hold("move_right", diff > 0.12)
		await process_frame
		if player.get_speed() < 0.05:
			stuck += 1
			if stuck == 1:
				_dump_latches(to.length())
		else:
			stuck = 0
		if Time.get_ticks_msec() - last_log >= 15000:
			last_log = Time.get_ticks_msec()
			_say("   ……骑了 %.0fs，距目标 %.0fm，速度 %.1fm/s" % [
				(Time.get_ticks_msec() - t) / 1000.0, to.length(), player.get_speed()])
	_hold("move_up", false)
	_hold("move_left", false)
	_hold("move_right", false)
	# 超时时把终点摆出来。骑不到和走不到是两回事：骑不到多半是坐标/控速，
	# 走不到是路本身的问题——而「距目标 132m 一动不动、速度满速」这种症状
	# 两种都像，不摆位置就只能猜。
	var d := tgt - player.global_position
	_say("   !! 骑了 %.0fs 还没到：玩家 (%.0f, %.0f, %.0f)，目标 (%.0f, %.0f, %.0f)，直线 %.0fm" % [
			(Time.get_ticks_msec() - t) / 1000.0,
			player.global_position.x, player.global_position.y, player.global_position.z,
			tgt.x, tgt.y, tgt.z, Vector2(d.x, d.z).length()])
	return false


## 沿路点把"从这儿到那儿"拆成一串贴着路心线的中间点。
##
## 环路是自闭合的 8 字，所以从起点下标走到终点下标有两个方向，取点数少的那个。
## 每 `WAYPOINT_STRIDE` 个路点取一个（`_road_points_2d` 一路 200 多个点，
## 一个一个追会把自动驾驶变成一列蚂蚁），首尾都精确落在起终点上。
func _road_waypoints(from: Vector3, to: Vector3) -> Array:
	var pts: PackedVector2Array = _world._road_points_2d
	var out: Array = []
	var a := 0
	var b := 0
	var da := 9999.0
	var db := 9999.0
	for i in range(pts.size()):
		var dd: float = Vector2(from.x - pts[i].x, from.z - pts[i].y).length()
		if dd < da:
			da = dd
			a = i
		var de: float = Vector2(to.x - pts[i].x, to.z - pts[i].y).length()
		if de < db:
			db = de
			b = i
	var fwd := b - a
	if fwd < 0:
		fwd += pts.size()
	var back := pts.size() - fwd
	var step := 1 if fwd <= back else -1
	var span: int = mini(fwd, back)
	for k in range(0, span + 1, WAYPOINT_STRIDE):
		var i2: int = posmod(a + k * step, pts.size())
		out.append(Vector3(pts[i2].x, _world._get_terrain_height(pts[i2].x, pts[i2].y), pts[i2].y))
	# 最后一段要精确落在目标上（上一跳是按步长取的，可能差十几米）
	out.append(to)
	return out


## 按占空比踩油门。转弯半径正比于速度（`Player3D` 的转向速率是
## `clamp(|speed|/3, 0, 1)`），所以收油真的能把圈画小，而不只是慢下来。
## 用墙钟节拍而不是帧计数——本机带窗口能跑到 280+ FPS，按帧算出来的占空比
## 跟着帧率变。
func _pulse_throttle(duty: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _pulse_ms >= 250:
		_pulse_ms = now
		_pulse_on = not _pulse_on
	_hold("move_up", _pulse_on)
	if not _pulse_on:
		_hold("move_up", false)


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
	_say("        %-24s = %s" % ["W 键真的按着吗",
			str(Input.is_key_pressed(KEY_W))])
	_say("        %-24s = %s" % ["对白弹窗 visible",
			str(w._dialogue_popup.visible if w._dialogue_popup else false)])
	_say("        %-24s = %s" % ["暂停面板 visible", str(w._pause_panel.visible)])
	_say("        %-24s = %s" % ["打卡面板 visible", str(w._check_in_popup.visible)])
	_say("        %-24s = %s" % ["商店 visible", str(w._shop_panel.visible)])
	_say("        %-24s = %s" % ["对白是否可见（玩家看得见提示吗）",
			str(w._dialogue_popup.visible if w._dialogue_popup else false)])
