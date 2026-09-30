extends SceneTree
## verify_mini_game_fail.gd — 小游戏失败之后的两件事
##
## 1. 失败必须有交代。5 个小游戏失败时都是 _on_mini_game_done(CANCELLED)
##    + queue_free() 同帧收工，遮罩一没了玩家就被扔回 3D 世界——既不知道
##    是输了还是被踢出去，也不知道这个驿站还能不能再玩。World3D 统一补一屏
##    失败面板并停留 MINI_GAME_FAIL_HOLD_SEC。
##
## 2. 失败之后必须还能再玩。旧版"必须骑开"这道门每帧拿当前位置和收尾点比
##    距离：玩家骑开一圈折回驿站、停在和刚才同一个点，距离又变回 0，
##    这个驿站从此再也点不动——报上来的现象就是"失败后再也没办法交互"。
##    现在是闩锁：骑开过一次就一直允许，直到下一次打卡结束才重新上锁。
##
## 覆盖竹(14，窗口过期)与琴(13，输入超时)两条自带超时的失败路径；
## 云/禽/茶没有自带超时，只会走取消按钮或 30 秒兜底，共用同一条收尾逻辑。
##
## 全程不需要输入，所以可以 headless 跑。
## 用法： godot --headless --path . --script tools/verify_mini_game_fail.gd

const MG_RUNNING := -2
const CANCELLED := 1
const BAMBOO_STATION := 14
const ZITHER_STATION := 13
## 失败面板最短停留（秒）。要明显小于 MINI_GAME_FAIL_HOLD_SEC=1.8。
const MIN_FAIL_HOLD_SEC := 0.8

var _world: Node = null
var _results: Array[String] = []


func _ensure_autoloads() -> void:
	for n in {
		"GameManager": "res://scripts/GameManager.gd",
		"AudioManager": "res://scripts/AudioManager.gd",
		"Localization": "res://scripts/Localization.gd",
	}:
		if root.get_node_or_null(n) == null:
			var node: Node = load(n).new()
			node.name = n
			root.add_child(node)


func _check(ok: bool, msg: String) -> void:
	_results.append(("[OK]   " if ok else "[FAIL] ") + msg)


func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var t := 0.0
	while t < timeout_sec:
		if cond.call():
			return true
		await create_timer(0.05).timeout
		t += 0.05
	return false


func _initialize() -> void:
	_ensure_autoloads()
	var gm = root.get_node("GameManager")
	gm.reset()
	gm.onboarding_shown = true
	# headless_mode 让 _play_dialogue 直接返回，否则没人点对白按钮会永久挂起
	gm.headless_mode = true
	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	_run.call_deferred()


func _fail_once(idx: int, tag: String) -> Dictionary:
	## 完整跑一遍"打卡 -> 故意玩砸 -> 收尾"，返回失败面板的观测结果
	gm_reset()
	var st_pos: Vector3 = _world._stations[idx].position
	_world._player.position = st_pos + Vector3(0, 3, 6)
	_world._recheck_armed = true
	_world._interact_cooldown = 0.0
	await create_timer(0.3).timeout

	_world._do_check_in(idx)
	# 先等小游戏真的注入，否则 _mini_game_state 还是 -1，会被误当成"已结束"
	var started := await _wait_until(func(): return _world._mini_game_state == MG_RUNNING, 20.0)
	_check(started, "%s 小游戏已注入" % tag)
	if not started:
		return {}

	# 什么都不按 → 竹子窗口过期 / 琴输入超时，都会判 CANCELLED
	var t0 := Time.get_ticks_msec()
	while _world._mini_game_state == MG_RUNNING and Time.get_ticks_msec() - t0 < 25000:
		await create_timer(0.05).timeout
	_check(_world._mini_game_state == CANCELLED,
		"%s 未操作即判取消（mg_state=%d）" % [tag, _world._mini_game_state])

	# 失败面板：必须在 _check_in_in_progress 还为 true 的时候就看得见，
	# 而且要停够时间——遮罩同帧消失正是要回归的 bug
	var t1 := Time.get_ticks_msec()
	var seen := false
	var text_ok := false
	while _world._check_in_in_progress and Time.get_ticks_msec() - t1 < 15000:
		if _world._check_in_popup.visible:
			seen = true
			text_ok = _world._popup_event.text == root.get_node("Localization").t("mg_failed")
		await create_timer(0.05).timeout
	var hold: float = float(Time.get_ticks_msec() - t1) / 1000.0
	_check(seen, "%s 失败时有面板告知结果（visible=%s）" % [tag, str(seen)])
	_check(text_ok, "%s 面板文案是失败提示而非驿站正文（event=%s）"
		% [tag, _world._popup_event.text])
	# 停留里还混着收尾流程本身，只要求下限
	_check(hold >= MIN_FAIL_HOLD_SEC, "%s 失败后停留 %.2fs（>= %.2fs）"
		% [tag, hold, MIN_FAIL_HOLD_SEC])
	_check(not _world._check_in_popup.visible, "%s 停留结束后面板已收起" % tag)
	_check(not _world._check_in_in_progress, "%s 序列已收尾" % tag)
	_check(_world._player._can_move, "%s 失败后玩家重新可以骑行" % tag)
	return {"hold": hold, "st_pos": st_pos}


func gm_reset() -> void:
	var gm = root.get_node("GameManager")
	gm.reset()
	_world._all_done = false
	_world._check_in_in_progress = false


func _run() -> void:
	print("==== verify_mini_game_fail ====")
	await create_timer(1.5).timeout
	_world._onboarding.visible = false
	_world._player.set_can_move(true)

	await _fail_once(BAMBOO_STATION, "竹(14)")
	await _fail_once(ZITHER_STATION, "琴(13)")

	# —— 失败之后还能不能再玩：绕一圈折回同一个点，按空格必须还能打卡 ——
	# 旧版在这里永久卡死，因为距离又变回 0。
	gm_reset()
	var st_pos: Vector3 = _world._stations[BAMBOO_STATION].position
	_world._recheck_armed = true
	_world._player.position = st_pos + Vector3(0, 3, 6)
	await create_timer(0.3).timeout
	_world._do_check_in(BAMBOO_STATION)
	await _wait_until(func(): return _world._mini_game_state == MG_RUNNING, 20.0)
	await _wait_until(func(): return _world._mini_game_state != MG_RUNNING, 25.0)
	await _wait_until(func(): return not _world._check_in_in_progress, 15.0)

	# 原地：必须仍被闩锁挡住（挡住连按空格）
	await create_timer(1.3).timeout
	_check(not _world._can_start_check_in(_world._nearby_station_idx),
		"原地不动时仍被挡下（防连按空格）")

	# 骑开 → 折回同一个点 → 必须解锁
	_world._player.position = st_pos + Vector3(0, 3, 18)
	await create_timer(0.4).timeout
	_world._player.position = st_pos + Vector3(0, 3, 6)
	await create_timer(0.4).timeout
	var rearmed: bool = _world._can_start_check_in(_world._nearby_station_idx)
	_check(rearmed, "骑开并折回后可以再次打卡（旧代码在这里永久卡死）")

	# 不只看标志位：真的再开一轮，确认整条流程可重复
	if rearmed:
		_world._do_check_in(BAMBOO_STATION)
		var again := await _wait_until(
			func(): return _world._mini_game_state == MG_RUNNING, 20.0)
		_check(again, "再次打卡能重新进入小游戏（整条流程可重复）")

	_report()


func _report() -> void:
	for r in _results:
		print(r)
	var bad := 0
	for r in _results:
		if r.begins_with("[FAIL]"):
			bad += 1
	print("[verify_mini_game_fail] %s  (失败 %d)" % ["PASS" if bad == 0 else "FAIL", bad])
	var gm = root.get_node_or_null("GameManager")
	if gm != null and gm.has_method("_clear_save"):
		gm._clear_save()
	quit(0 if bad == 0 else 1)
