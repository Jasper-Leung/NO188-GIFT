extends SceneTree
## verify_bamboo_world.gd — 用真实 World3D 场景定位
## "竹雨庭小游戏按空格 → 变成和驿站交互" 的确切机制
##
## 探针回答三个问题：
##   A. 小游戏里按空格，是否同时被记进全局 interact 动作（事件没被吃掉）
##   B. _run_mini_game 的 600 帧轮询在 60FPS 下实际是多少秒 —— 会不会把
##      进行中的小游戏强行判成取消
##   C. 小游戏被取消后，紧接着的一次空格是否会立刻重新打卡（= 相机飞回驿站）
##
## 用法： godot --headless --path . --script tools/verify_bamboo_world.gd

const BAMBOO_STATION := 14
const MG_RUNNING := -2

var _world: Node = null
var _probe: Node = null


class Probe:
	extends Node
	## 计数"裸"的全局 interact 命中 —— 不管 World3D 的门控是否拦下
	var raw_hits: int = 0
	var frames: int = 0
	var ms_since_start: int = 0
	var _t0: int = 0

	func reset(t0: int) -> void:
		_t0 = t0
		raw_hits = 0
		frames = 0

	func _physics_process(_d: float) -> void:
		frames += 1
		ms_since_start = Time.get_ticks_msec() - _t0
		if Input.is_action_just_pressed("interact"):
			raw_hits += 1


func _reset_save() -> void:
	## 打卡会写 user://gift188.cfg；同一驿站打满 3 次就 exhausted、不再触发
	## 小游戏，会让本验证变成"随机失败"。跑完再把存档删掉，不留痕迹。
	var gm = root.get_node("GameManager")
	if gm != null:
		gm.reset()
		gm.onboarding_shown = true
		gm.headless_mode = true  # 跳过对话弹窗，避免 headless 无人点击按钮导致永久挂起


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


## 复刻真实 OS 输入管线：先喂 Input 单例（决定 is_action_just_pressed），
## 再 push 到 viewport（走 GUI / _gui_input）
func _push_space(pressed: bool) -> void:
	var ev = InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = pressed
	Input.parse_input_event(ev)
	root.push_input(ev)


## echo=true 模拟长按产生的连发事件
func _push_space_echo() -> void:
	var ev = InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	ev.echo = true
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


## 诊断上下文：能触发打卡需要 nearby>=0、静默期归零、没在打卡中
func _ctx() -> String:
	return "nearby=%d dist=%.1f cd=%.2f in_prog=%s mgstate=%d paused=%s exhausted=%s pos=%s" % [
		_world._nearby_station_idx, _world._nearby_station_dist,
		_world._interact_cooldown, str(_world._check_in_in_progress),
		_world._mini_game_state, str(_world._paused),
		str(root.get_node("GameManager").is_station_exhausted(BAMBOO_STATION)),
		str(_world._player.position)]


func _initialize() -> void:
	Engine.max_fps = 60   # 与真实桌面运行一致，600 帧 = 10 秒
	_ensure_autoloads()
	_reset_save()         # 必须在 autoload _ready 之后，覆盖它 _load_save 的结果
	_ensure_action()
	_run.call_deferred()


func _run() -> void:
	print("=== 真实场景复现：竹雨庭空格 -> 驿站交互 ===")
	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	_probe = Probe.new()
	_world.add_child(_probe)
	await create_timer(2.0).timeout

	var gm = root.get_node("GameManager")
	gm.onboarding_shown = true
	_world._onboarding.visible = false
	_world._player.set_can_move(true)

	var rd = _world._road_builder.get_road_data()
	var sp = rd.get_station_world_pos(BAMBOO_STATION)
	var st_pos = _world._stations[BAMBOO_STATION].position
	# layout.json 可能覆盖过驿站坐标，站位要跟着实际的 _stations 走
	_world._player.position = st_pos + Vector3(0, 3, 6)
	await create_timer(0.2).timeout
	print("   rd 位置=%s  _stations 位置=%s  玩家=%s" % [
		str(sp), str(st_pos), str(_world._player.position)])

	print("1. 站在竹雨庭: nearby=%d dist=%.1f 有碎片=%s" % [
		_world._nearby_station_idx, _world._nearby_station_dist,
		str(rd.station_has_fragment(BAMBOO_STATION))])

	# —— 按空格进入打卡流程 ——
	_push_space(true)
	_push_space(false)
	await create_timer(0.2).timeout
	print("2. 打卡已开始: in_progress=%s" % str(_world._check_in_in_progress))

	var ok := await _wait_until(
		func(): return _world._mini_game_state == MG_RUNNING, 15.0)
	print("3. 小游戏已注入: %s (镜头+定格 %.1fs)" % [str(ok), _probe.ms_since_start / 1000.0])
	if not ok:
		print("[verify_bamboo_world] FAIL (小游戏未注入)")
		_clear_save()
		quit(1)

	# —— 4a: 引导期提前按空格必须算数（不能让玩家第一眼就按的那一下被吃掉） ——
	var mg0 = _world._mini_game_node
	var intro_seen: bool = mg0.get("_intro_active")
	# 只发按下、不发抬起，排除抬起事件参与
	_push_space(true)
	for k in range(4):
		await create_timer(0.05).timeout
		print("    4a[press-only %d] intro=%s window=%s cur=%d" % [
			k, str(mg0.get("_intro_active")), str(mg0.get("_window_active")),
			mg0.get("_current_bamboo")])
	_push_space(false)
	var intro_accepted: bool = not mg0.get("_intro_active")
	print("4a. 引导期提前按空格: 进入时 intro_active=%s -> 引导已跳过=%s（应为 true）" % [
		str(intro_seen), str(intro_accepted)])

	# —— 4b: 长按连发(echo)不能砍竹，否则按住空格就能秒过 ——
	var cur_before_echo: int = mg0.get("_current_bamboo")
	_push_space_echo()
	await create_timer(0.2).timeout
	var cur_after_echo: int = mg0.get("_current_bamboo")
	var echo_ignored: bool = cur_after_echo == cur_before_echo
	print("4b. 长按连发(echo) %d->%d 被忽略=%s（应为 true）" % [
		cur_before_echo, cur_after_echo, str(echo_ignored)])

	# —— 5: 逐个砍掉 5 根竹子 ——
	_probe.reset(Time.get_ticks_msec())
	var n_presses := 0
	for i in range(8):
		_push_space(true)
		_push_space(false)
		n_presses += 1
		await create_timer(0.9).timeout
		var mg = _world._mini_game_node
		if mg == null:
			break
		print("   砍第%d次: mg_cur=%s  raw_interact_hits=%d  state=%d" % [
			n_presses, str(mg.get("_current_bamboo")), _probe.raw_hits, _world._mini_game_state])
		if _world._mini_game_state != MG_RUNNING:
			break
	print("5. 空格泄漏判定：砍了 %d 次，全局 interact 命中 %d 次（>0 = 事件没被吃掉）" % [
		n_presses, _probe.raw_hits])
	await _wait_until(
		func(): return _world._mini_game_state != MG_RUNNING, 25.0)
	print("6. 小游戏退出: state=%d (0=成功,1=取消)  经历 %.1fs" % [
		_world._mini_game_state, _probe.ms_since_start / 1000.0])

	# —— 打卡序列真正收尾那一刻才起算（popup 1.0s + 0.4s 在 _finish_check_in 之前） ——
	await _wait_until(
		func(): return not _world._check_in_in_progress, 10.0)
	_probe.reset(Time.get_ticks_msec())
	var cd0: float = _world._interact_cooldown
	print("7. 序列收尾，interact 静默期 = %.2fs" % cd0)

	# —— 8: 静默期内按空格，必须被挡住 ——
	_push_space(true)
	_push_space(false)
	await create_timer(0.3).timeout
	var ok8: bool = not _world._check_in_in_progress
	print("8.  静默期内按空格 -> 新打卡=%s（应为 false）  ctx=%s" % [
		str(not ok8), _ctx()])

	# —— 9: 静默期过期、但玩家还没离开站点，连按空格也不得触发新一轮打卡 ——
	await create_timer(1.3).timeout
	var cd_after: float = _world._interact_cooldown
	_world._recheck_armed = false  # 复位骑开闩锁，等价于"玩家还没骑开"
	_push_space(true)
	_push_space(false)
	await create_timer(0.3).timeout
	var ok9: bool = not _world._check_in_in_progress
	print("9.  静默期过期(%.2f)仍在原地按空格 -> 新打卡=%s（应为 false：没骑开）  ctx=%s" % [
		cd_after, str(not ok9), _ctx()])

	# —— 10: 对照组。打开骑开闩锁（= 旧代码的"距离恒远"），同样时机必须立刻触发 ——
	_world._recheck_armed = true
	await create_timer(0.05).timeout
	_push_space(true)
	_push_space(false)
	await create_timer(0.3).timeout
	var ok10: bool = _world._check_in_in_progress
	print("10. 关掉骑开门（旧代码）后按空格 -> 新打卡=%s（应为 true：证明这道门在起作用）" %
		str(ok10))

	# —— 11: 骑开一段距离后，合法再次打卡必须正常触发 ——
	await _wait_until(func(): return not _world._check_in_in_progress, 40.0)
	_world._player.position = _world._player.position + Vector3(10, 0, 0)
	_world._interact_cooldown = 0.0
	await create_timer(0.2).timeout
	_push_space(true)
	_push_space(false)
	await create_timer(0.3).timeout
	var ok11: bool = _world._check_in_in_progress
	print("11. 骑开 %.1fm 后按空格 -> 新打卡=%s（应为 true：正常打卡不受影响）  ctx=%s" % [
		10.0, str(ok11), _ctx()])

	var ok_all: bool = intro_accepted and echo_ignored and ok8 and ok9 and ok10 and ok11
	print("[verify_bamboo_world] %s  (4a=%s 4b=%s 8=%s 9=%s 10=%s 11=%s)" % [
		"PASS" if ok_all else "FAIL", intro_accepted, echo_ignored, ok8, ok9, ok10, ok11])
	_clear_save()
	quit(0 if ok_all else 1)


func _clear_save() -> void:
	var gm = root.get_node_or_null("GameManager")
	if gm != null:
		gm._clear_save()
