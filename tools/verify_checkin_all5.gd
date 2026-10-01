extends SceneTree
## verify_checkin_all5.gd — 5 个碎片驿站逐个验证「打卡收尾后按空格会不会重新打卡」
##
## 与 verify_bamboo_world.gd 的区别：那个只覆盖竹雨庭(14)的空格路径，
## 这个把 4/7/10/13/14 全部走一遍，并且额外盯一个怀疑点：
##   边界软回弹 _apply_boundary_force 在打卡期间也在跑（它的调用点在
##   _physics_process 的 interact 门控之前），如果玩家/驿站本来就压在
##   软边界外，回弹会把玩家一点点推开。推开超过 RECHECK_IN_MIN_DIST(8m) 后，
##   _recheck_armed 骑开闩锁会被"白送"成 true，
##   「必须骑开才允许再打卡」这道门就被绕过了 —— 表现就是收尾后按空格又重新打卡。
##
## 用法： godot --headless --path . --script tools/verify_checkin_all5.gd

const MG_RUNNING := -2
const SUCCESS := 0
const CANCELLED := 1
## 必须按碎片槽位顺序（= RoadData.FRAGMENT_SLOT_STATION_IDX）跑。
## 驿站 4 是第 5 张碎片，打卡成功会触发 all_fragments_collected →
## _on_all_collected()。它现在只播动画不放人（2.5 秒后把相机和操作还回来），
## 但仍会锁住玩家，所以 _test_station() 里要把 _all_done / 相机锁清干净。
## 把它排在第一个，后面 4 个驿站全部测不到（nearby=-1、玩家不能动）。
const STATIONS := [7, 10, 13, 14, 4]
## 与 World3D 保持一致的三个常量（实例访问 const 不稳，这里直接复刻）
const RECHECK_IN_MIN_DIST := 8.0
const SOFT_BOUND := 12.0
const HARD_BOUND := 25.0

var _world: Node = null
var _gm: Node = null
var _failures := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_failures += 1
		print("[FAIL] ", label)


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


func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var waited := 0.0
	while waited < timeout_sec:
		if cond.call():
			return true
		await create_timer(0.05).timeout
		waited += 0.05
	return false


## 碎片驿站打卡时先弹对白，没人点"下一句"就永远 await 在 _play_dialogue 里，
## 小游戏等不到注入。所有"等小游戏起来"的地方都必须走这里，顺带把对白点掉。
func _advance_to_mini_game(timeout_sec: float) -> bool:
	var t := 0.0
	var t_last_push := -1.0
	while t < timeout_sec and _world._mini_game_state != MG_RUNNING:
		var dlg: Node = _world._dialogue_popup
		if dlg != null and dlg.visible and t - t_last_push >= 0.3:
			t_last_push = t
			_push_space(true)
			_push_space(false)
		await create_timer(0.05).timeout
		t += 0.05
	return _world._mini_game_state == MG_RUNNING


## 把一次还在流程中的打卡彻底送走，否则它的协程会跟下一站的打卡并发，
## 把后面所有断言搅成 nearby=-1 / 打卡次数=0。
func _drain_check_in() -> void:
	if not _world._check_in_in_progress:
		return
	if await _advance_to_mini_game(20.0):
		_world._on_mini_game_done(CANCELLED)
	await _wait_until(func(): return not _world._check_in_in_progress, 20.0)


## 驿站离道路中心线最近点的距离 —— 直接决定软回弹是否在推玩家
func _dist_to_road_xz(p: Vector3) -> float:
	var pp := Vector2(p.x, p.z)
	var best := 9999.0
	for rp in _world._road_points_2d:
		best = minf(best, pp.distance_to(rp))
	return best


func _initialize() -> void:
	Engine.max_fps = 60
	_ensure_autoloads()
	_ensure_action()
	_gm = root.get_node("GameManager")
	_gm.reset()
	_gm.onboarding_shown = true
	# 这个测试没设 headless_mode（默认 false），序章和郑铎三场会真的弹出来抢按键。
	_gm.prologue_done = true
	_gm.seen_villain = 3   # = GameManager.VILLAIN_SCENE_COUNT
	_run.call_deferred()


func _run() -> void:
	print("=== 5 个碎片驿站：打卡收尾后按空格是否重新打卡 ===")
	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	await create_timer(2.5).timeout

	_gm.onboarding_shown = true
	_world._onboarding.visible = false
	_world._player.set_can_move(true)

	for idx in STATIONS:
		await _test_station(idx)

	print("\n================ 汇总 ================")
	print("[verify_checkin_all5] %s  (失败项 %d)" % [
		"PASS" if _failures == 0 else "FAIL", _failures])
	if _gm != null:
		_gm._clear_save()
	quit(0 if _failures == 0 else 1)


func _test_station(idx: int) -> void:
	print("\n---------- 驿站 %d ----------" % idx)
	# 每站重置：清打卡次数（避免 MAX_VISITS_PER_STATION=3 让提示消失），
	# 清 _all_done（避免第5站收满碎片后全局锁死），清上一站的收尾记录点
	_gm.reset()
	_gm.prologue_done = true      # reset() 会把它归零
	_gm.seen_villain = 3           # = GameManager.VILLAIN_SCENE_COUNT
	_world._all_done = false
	_world._check_in_in_progress = false
	_world._last_check_in_pos = Vector3(INF, INF, INF)
	_world._recheck_armed = true
	_world._interact_cooldown = 0.0
	_world._nearby_station_idx = -1
	_world._player.set_can_move(true)
	_world._player.set_camera_locked(false)

	var st_pos: Vector3 = _world._stations[idx].position
	var has_frag: bool = _world._road_builder.get_road_data().station_has_fragment(idx)
	var road_d := _dist_to_road_xz(st_pos)
	print("   驿站坐标=%s  有碎片=%s  距道路中心线=%.2fm (SOFT=%.0f HARD=%.0f) -> 软回弹%s" % [
		str(st_pos), str(has_frag), road_d, SOFT_BOUND, HARD_BOUND,
		"激活" if road_d > SOFT_BOUND else "未激活"])

	_world._player.position = st_pos + Vector3(0, 3, 6)
	await create_timer(0.4).timeout
	_check(_world._nearby_station_idx == idx,
		"驿站%d 靠近后 nearby=%d dist=%.1f" % [
			idx, _world._nearby_station_idx, _world._nearby_station_dist])

	# ---- 1. 空格触发打卡 ----
	_push_space(true)
	_push_space(false)
	var started := await _wait_until(
		func(): return _world._check_in_in_progress, 3.0)
	_check(started, "驿站%d 空格成功触发打卡" % idx)
	if not started:
		return

	# 碎片驿站进小游戏前还有一段对白弹窗，没人点"下一句"就会永远 await 在
	# _play_dialogue 里，小游戏永远等不到注入。
	var mg_ok := await _advance_to_mini_game(20.0)
	_check(mg_ok, "驿站%d 小游戏已注入" % idx)
	if not mg_ok:
		return

	# ---- 2. 小游戏期间玩家是否被边界回弹推走 ----
	var pos_at_mg: Vector3 = _world._player.position

	# ---- 3. 走完整条成功链路（弹窗 + 碎片飞入 + GameManager.check_in + 收尾） ----
	# 注意：不要在这里空等！竹雨庭 QTE 的砍竹窗口只有 1.2s，空等 2s 会先超时
	# 判失败走 CANCELLED 分支（碎片不会被记录），验证就失去意义了。
	_world._on_mini_game_done(SUCCESS)
	# 收尾过程中持续连按空格 —— 复刻"玩家手上还没松开空格"的真实情况
	var t_seq := 0.0
	while _world._check_in_in_progress and t_seq < 25.0:
		_push_space(true)
		_push_space(false)
		await create_timer(0.15).timeout
		t_seq += 0.15
	_check(not _world._check_in_in_progress,
		"驿站%d 打卡序列正常收尾（连按空格中收尾，耗时 %.1fs）" % [idx, t_seq])
	if _world._check_in_in_progress:
		return

	var drift_total: float = _world._player.position.distance_to(pos_at_mg)
	print("   序列全程漂移 = %.3fm" % drift_total)

	var fin_pos: Vector3 = _world._player.position
	var last_pos: Vector3 = _world._last_check_in_pos
	var cd: float = _world._interact_cooldown
	var gap := fin_pos.distance_to(last_pos)
	var cnt: int = _gm.get_station_count(idx)
	print("   收尾: 静默期=%.2fs  记录点与玩家距离=%.3fm  打卡次数=%d" % [cd, gap, cnt])
	_check(gap <= RECHECK_IN_MIN_DIST,
		"驿站%d 收尾时记录点=玩家位置（%.3fm ≤ %.0fm，没被回弹白送距离）" % [
			idx, gap, RECHECK_IN_MIN_DIST])
	_check(cnt == 1, "驿站%d 成功打卡已记录（打卡次数=%d）" % [idx, cnt])

	# ---- 4. 核心回归：原地狂按空格 3 秒，不得触发新一轮打卡 ----
	var retriggered := false
	var t := 0.0
	while t < 3.0:
		_push_space(true)
		_push_space(false)
		await create_timer(0.2).timeout
		t += 0.2
		if _world._check_in_in_progress:
			retriggered = true
			break
	_check(not retriggered,
		"驿站%d 收尾后原地连按空格 3s 未重新打卡" % idx)

	var pos_after: Vector3 = _world._player.position
	print("   连按期间漂移=%.3fm  收尾后 ctx: nearby=%d dist=%.1f cd=%.2f" % [
		pos_after.distance_to(fin_pos), _world._nearby_station_idx,
		_world._nearby_station_dist, _world._interact_cooldown])

	# ---- 5. 正对照：真骑开 10m 后必须能正常再打卡 ----
	if retriggered:
		await _drain_check_in()
		return
	_world._player.position = _world._player.position + Vector3(10, 0, 0)
	_world._interact_cooldown = 0.0
	await create_timer(0.3).timeout
	_push_space(true)
	_push_space(false)
	await create_timer(0.3).timeout
	var ok_pos: bool = _world._check_in_in_progress
	_check(ok_pos, "驿站%d 骑开 10m 后按空格正常再次打卡" % idx)
	# 抹掉这次正对照打卡，避免污染下一站：必须等小游戏真正注入后再发 CANCELLED
	# （_on_mini_game_done 只在 MG_RUNNING 时收结果），否则序列会一直挂着等到
	# 30s 兜底超时，协程还会跟下一站的打卡并发。
	await _drain_check_in()
