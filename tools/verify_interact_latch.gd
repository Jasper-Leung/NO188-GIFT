extends SceneTree
## verify_interact_latch.gd — 交互闩锁 / 对白抢占 的回归
##
## 这组断言拦的是玩家报上来的那一屏：顶栏「下一处 → 358m」、脚下的铺子提示圈
## 还在亮、按空格毫无反应、只有重开游戏才恢复。
##
## 根因是一条 await 链挂死了：郑铎三场和驿站打卡共用同一个对白弹窗，而
## `interact`（空格）和 `ui_accept`（推进对白）是同一个键。DialoguePopup 的
## set_input_as_handled() 只挡事件传播，Input.is_action_just_pressed() 早就
## 被 OS 输入管线写进单例了——于是"推进对白的那一下空格"顺手开了一场打卡，
## 打卡那边的 setup() 把郑铎正在播的那一轮顶掉，郑铎的协程就此永远挂着，
## `_villain_playing` 再也回不到 false。
##
## 那个闩锁最阴的地方：它只挡 `_can_open_shop`，而 644 行那个早退列表里
## **没有**它，所以 `_nearby_shop_idx` 照算、提示圈照画。玩家看到的就是
## "圈在那儿、怎么按都没反应"，唯一的解法是重开游戏。
##
## 四道断言，分头钉住这个链路：
##   1  闸：郑铎在播时按空格不该开打卡
##   2  释放：setup() 顶掉一轮未收尾的对白时，必须把旧等待者放出去
##   3  收尾：被顶掉的郑铎戏必须自己把 `_villain_playing` 清掉
##   4  口径：回访站不再重播对白/小游戏、不再谎报"获得碎片"，提示圈说实话
##
## 5/6 两条后来补的，都是同一个键在两处说话：
##   5  贴脸时提示文字不许掉出屏外（63 点网格扫）
##   6  **反派戏期间脚下的圈不许还在推销打卡** —— 打卡被 ① 挡掉了，
##      可 `CheckInPrompt._prompt_target()` 只读 `_nearby_station_idx`、
##      不知道 `_villain_playing`，于是圈一边写着「空格 · 完成乐事」，
##      一边在同一次按键里变灰成「这里现在进不去」，而那一次按键正在推进对白。
##      7  铺子最终可达（这条回归的终点：不再需要重开游戏）
##
## 第 6 节要注入真空格，但**加不加 --headless 都跑得过**（两种都实测过）：
## `DialoguePopup` 推进对白走的是 `Node._input()`，不走焦点路由，注入的空格照样到得了。
## 与「headless 收不到按键」那条结论不冲突——那边卡住的是 `Button` 的 `ui_accept`，
## 那才是 GUI 焦点路由的范围。

const SHOT_DIR := "user://lookdev_journey"

var _fails := 0
var _gm: Node = null
var _world: Node = null


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_fails += 1
		print("[FAIL] ", label + ("（" + detail + "）" if detail != "" else ""))


func _ensure_autoloads() -> void:
	for n in {"GameManager": "res://scripts/GameManager.gd",
			"AudioManager": "res://scripts/AudioManager.gd",
			"Localization": "res://scripts/Localization.gd"}:
		if root.get_node_or_null(n) == null:
			var node: Node = load(n).new()
			node.name = n
			root.add_child(node)


func _initialize() -> void:
	Engine.max_fps = 60
	_ensure_autoloads()
	_gm = root.get_node("GameManager")
	_gm._clear_save()
	_gm.headless_mode = true
	_gm.onboarding_shown = true
	_gm.prologue_done = true
	root.size = Vector2i(1280, 720)
	root.add_child(load("res://scenes/World3D.tscn").instantiate())
	_run.call_deferred()


func _teleport(station_idx: int) -> void:
	_world._close_shop()
	_world._player.position = _world._stations[station_idx].position + Vector3(0, 1.0, 3.0)
	_world._last_global_pos = _world._player.global_position
	_world._has_last_pos = true
	_world._interact_cooldown = 0.0
	_world._recheck_armed = true
	_world._check_in_in_progress = false
	_world._mini_game_state = -1


## 带窗口跑这一节才对：`CheckInPrompt` 靠真实按键事件驱动，而 headless 用的是
## dummy display server，不做真焦点路由，注入进去的空格到不了 `_input`。
## 完整事件（keycode + physical_keycode），桌面键盘两个码都填得上。
func _push_space() -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_SPACE
		ev.physical_keycode = KEY_SPACE
		ev.pressed = pressed
		Input.parse_input_event(ev)


## 按墙钟等，不是按帧数——窗口模式下这台机器 280+ FPS，
## 拿帧数当秒数会把"没等到"直接判成"等到了"。
func _until(cond: Callable, what: String) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		if cond.call():
			return true
		await process_frame
	_ck("等不到：%s" % what, false)
	return false


func _run() -> void:
	await process_frame
	_world = root.get_child(root.get_child_count() - 1)
	_gm._clear_save()

	var shop_data = load("res://scripts/shop_data.gd")
	var shop_idx := -1
	for i in range(16):
		if shop_data.shop_at_station(i) != "":
			shop_idx = i
			break

	# ---------- 1 闸：郑铎在播时按空格不许开打卡 ----------
	_teleport(4)
	await process_frame
	await process_frame
	_ck("起始：站在碎片站 4 旁，按空格能打卡", _world._can_start_check_in(4))
	_world._villain_playing = true
	await process_frame
	_ck("郑铎在播时按空格被拦住", not _world._can_start_check_in(4),
			"这条漏了就会同时推进对白和打卡，两条协程抢同一个弹窗")
	_world._villain_playing = false

	# ---------- 2 释放：顶掉一轮未收尾的对白必须把旧等待者放出去 ----------
	var dp = _world._dialogue_popup
	var stolen: Array = []
	dp.dialogue_done.connect(func(r): stolen.append(r), CONNECT_ONE_SHOT)
	dp.setup("郑铎", ["一", "二"], false)
	dp.visible = true
	await process_frame
	_ck("第一轮对白开着、还没收到 dialogue_done",
			stolen.is_empty(), "不该这么早就发信号")
	# 模拟打卡那边在同一帧接管了同一个弹窗。
	# 第二个监听必须在这次 setup() **之后**才接：那一次 setup() 自己会发出
	# 抢占信号，先接上的话会被它吃掉，测的就不是"新那轮"了。
	dp.setup("云台", ["驿站对白"], false)
	await process_frame
	_ck("被顶掉的那一轮拿到了 dialogue_done", stolen.size() == 1,
			"拿不到的话 await 在这里的协程就永远挂着")
	_ck("信号里带 was_stolen=true",
			stolen.size() == 1 and bool(stolen[0].get("was_stolen", false)),
			str(stolen))
	var fresh: Array = []
	dp.dialogue_done.connect(func(r): fresh.append(r), CONNECT_ONE_SHOT)
	_ck("抢占信号不误伤新那轮", fresh.is_empty(), "还没轮到它")
	dp.visible = false
	await process_frame
	dp._on_skip_pressed()
	await process_frame
	# 正常收尾的两个 emit 点都不带 was_stolen 键，所以判据的缺省必须是 false
	# ——和 World3D 里 result.get("was_stolen", false) 的缺省一致，
	# 含义是"没被顶掉，按正常流程往下走"。
	_ck("正常收尾（跳过）也放出了信号",
			fresh.size() == 1 and not bool(fresh[0].get("was_stolen", false)),
			str(fresh))

	# ---------- 3 收尾：被顶掉的郑铎戏自己把闩锁清掉 ----------
	# 必须先把 World3D 自己的 headless 关掉：_play_villain_scene() 开头就
	# `if _headless_mode: return`，留着它这条链根本不会挂起，测的就等于没测。
	_gm._clear_save()
	_world._headless_mode = false
	_teleport(4)
	await process_frame
	_world._villain_playing = true
	_world._play_villain_scene(0)      # 挂起在第一段对白上
	await process_frame
	await process_frame
	_ck("郑铎第一段对白正在播",
			_world._dialogue_popup.visible and _world._villain_playing,
			"对白没起来的话这一节是空测")
	# 打卡那边抢走弹窗（真实世界里就是那一下空格同时干了两件事）
	_world._dialogue_popup.setup("云台", ["驿站对白"], false)
	await create_timer(0.5).timeout
	_ck("被顶掉的郑铎戏把 _villain_playing 清掉了", not _world._villain_playing,
			"漏了这一句，铺子从此再也开不了，提示圈却还照画")
	_world._dialogue_popup._on_skip_pressed()
	await process_frame
	_world._headless_mode = true

	# ---------- 4 口径：回访不再重播、不再谎报碎片 ----------
	_gm._clear_save()
	_teleport(4)
	await process_frame
	_gm.check_in(4)                   # 第 1 次：拿到碎片
	_teleport(4)
	await process_frame
	# 旧口径在这里会把这一站从"下一处"里摘掉。可完满评级要求每座碎片驿站
	# 去过 3 次，第一次拿到碎片之后还剩两次 —— 摘掉它等于把最强的重玩钩子
	# 从顶栏上抹了，而脚下的圈还照亮 2 次。
	_ck("首次到访后：顶栏仍指这一站（还欠 2 次到访）",
			_world._hud3d._next_fragment_target().get("idx", -1) == 4,
			"顶栏指的是 %s" % str(_world._hud3d._next_fragment_target().get("idx", -1)))
	_ck("首次到访后：顶栏说的是「再访」不是「下一处」",
			_world._hud3d._next_label.text != ""
			and not _world._hud3d._next_label.text.contains(
					_root_loc().t("hud_next_target").split("%s")[0]),
			"顶栏写着：%s" % _world._hud3d._next_label.text)
	_ck("首次到访后：顶栏写出了还差几次",
			_world._hud3d._next_label.text.contains(
					(_root_loc().t("visits_left_n") % 2)),
			"顶栏写着：%s" % _world._hud3d._next_label.text)
	_ck("回访站仍可打卡（还差两次到访，不是死路）", _world._can_start_check_in(4),
			"环数上限 3 次，回访是设计内的")
	# 回访只给旅币不给碎片，所以不能说"完成乐事"；但也不能一直说"歇一脚"——
	# 第三次到访是完满评级的最后一格，对着它劝退就等于把钩子自己掐了。
	_ck("回访时提示圈写的是还差几次，不是「完成乐事」也不是「歇一脚」",
			_visit_prompt_label().contains(
					(_root_loc().t("desktop_revisit_prompt") % 2)),
			"圈上写着：%s" % _visit_prompt_label())
	# 跑一遍完整回访序列：1.0s 运镜 + 1.5s 定格 + 0.4s 收尾 ≈ 2.9s，
	# 面板在 ~2.5s 亮起、~2.9s 自己收掉，所以按墙钟等到序列结束再断言。
	var lvbi_before: int = _gm.lvbi
	_world._do_check_in(4)
	await create_timer(4.0).timeout
	_ck("回访序列跑完了", not _world._check_in_in_progress)
	_ck("回访没有重播小游戏", _world._mini_game_node == null
			and _world._mini_game_state != _world.MG_RUNNING,
			"回访是歇一脚，不该再考一次")
	# _popup_text 在面板收掉之后仍然留着最后写的字，所以断字比断可见性稳
	_ck("回访面板说的是「已经收过了」",
			_world._popup_text.text == _root_loc().t("revisit_note"),
			"面板上写着：%s" % _world._popup_text.text)
	_ck("回访不再谎报「获得碎片」", not _world._popup_fragment.visible)
	_ck("回访照样发旅币", _gm.lvbi > lvbi_before,
			"%d → %d" % [lvbi_before, _gm.lvbi])
	_ck("回访打卡次数累到 2", _gm.get_station_count(4) == 2,
			"实际 %d" % _gm.get_station_count(4))

	# ---------- 5 提示文字不许掉出屏外 ----------
	# 玩家越骑越近，站点的投影就越往画面下方跑，贴着站停下时圈已经压在 720 上，
	# 那行"空格 · 完成乐事"整个在屏外——恰恰是最该读到它的一刻。
	# 真相机走贴脸那一档 + 全屏 63 点网格扫：只测真相机碰上的那一个点，
	# 镜头一改就又漏了。
	var cp = _world._check_in_prompt
	_ck("提示圈铺满视口", cp.size.x > 1000.0 and cp.size.y > 500.0,
			"size=%s" % str(cp.size))
	var st_pos: Vector3 = _world._stations[4].position
	_teleport(4)
	_world._player.position = st_pos + Vector3(0, 1.0, 1.2)   # 贴脸，投影落进画面下半
	_world._last_global_pos = _world._player.global_position
	await process_frame
	await process_frame
	var cam: Camera3D = _world._player_cam
	var sp: Vector2 = cam.unproject_position(st_pos)
	var fs := 16 if _root_loc().is_english() else 18
	var tw: float = ThemeDB.fallback_font.get_string_size(
			_cp_label(), HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	var lp: Vector2 = cp._label_pos(sp, 46.0, tw, fs)
	_ck("贴脸时提示文字在屏内",
			lp.y >= float(fs) and lp.y + float(fs) <= cp.size.y
			and lp.x >= 0.0 and lp.x + tw <= cp.size.x,
			"站投影 y=%.0f → 文字 y=%.0f，屏高 %.0f" % [sp.y, lp.y, cp.size.y])
	var off := []
	for gx in 9:
		for gy in 7:
			var probe := Vector2(float(gx) * cp.size.x / 8.0, float(gy) * cp.size.y / 6.0)
			var p: Vector2 = cp._label_pos(probe, 46.0, tw, fs)
			if p.y < float(fs) or p.y + float(fs) > cp.size.y \
					or p.x < 0.0 or p.x + tw > cp.size.x:
				off.append(str(probe))
	_ck("全屏 63 个取样点上文字都在屏内", off.is_empty(), "越界于 %s" % str(off))

	# ---------- 6 反派戏期间脚下不许还在推销打卡 ----------
	# 第 1 节量的是"郑铎在播时**打卡**进不去"，这一节量的是同一次按键的**另一半**：
	# 圈还在推销。按键把打卡挡掉了，可 `_on_interact_blocked()` 照跑，而
	# `CheckInPrompt._prompt_target()` 只读 `_nearby_station_idx`、不知道
	# `_villain_playing`，于是圈一边画着「空格 · 完成乐事」，一边在同一次按键里
	# 变灰成「这里现在进不去」。玩家看着对白在推进、脚下的圈在同时说他按错了。
	# 这一节只测"那一圈和那句话该不该存在"，不测对白推进本身（第 3 节测了）。
	_gm._clear_save()
	_gm.headless_mode = false
	_world._headless_mode = false
	# 前面的第 3 节在 headless 下碰过一次 `_play_villain_scene`，那一次已经把
	# 第 0 场 consume 掉了（armed 清空 + claim 成功 + 立即 return）。这里复位，
	# 否则这一节等的是一个已经放过的场，测的是空气。
	_gm.seen_villain = 0
	# 先按住不放，等基线量完再上膛。`_try_villain_scene()` 每帧轮询，
	# 一起播就晚了——上一版把基线断言写在 `_teleport` 后面两帧，那两帧里
	# 反派戏已经起来，`_can_start_check_in` 自然 false，量到的不是"戏前"，
	# 而且这条断言会一直红，看起来像被测代码坏了。
	var cp6 = _world._check_in_prompt
	_world._villain_armed = [false, false, false]
	_teleport(4)
	await process_frame
	await process_frame
	_ck("起始：反派戏之前圈是亮的（这一节不是在测一个本来就不亮的圈）",
			not cp6._prompt_target().is_empty()
			and _world._can_start_check_in(4),
			"圈目标=%s can_start=%s" % [str(cp6._prompt_target()),
					str(_world._can_start_check_in(4))])

	# 上膛。触发条件是"路过 4 座驿"（VILLAIN_SCENES[0].seen = 4）；回归是瞬移的，
	# 前面几节路过几座全看瞬移顺序，所以这里显式补足，不靠巧合。
	# 前面第 3 节在 headless 下碰过一次 `_play_villain_scene`，那一次已经把第 0 场
	# consume 掉了（armed 清空 + claim 成功 + 立即 return），所以 seen_villain 也要复位。
	for i in [0, 1, 2, 3]:
		_gm.on_station_pass(i)
	_world._villain_armed = [true, true, true]

	if await _until(func(): return _world._villain_playing, "郑铎第 0 场起播"):
		# 必须再等两个物理帧：`_try_villain_scene()` 是在 `_physics_process` 的
		# **末尾**把 `_villain_playing` 置上的，而清 `_nearby_*` 的那张早退单子在
		# **开头**——所以起播那一帧过后还差一帧才清完。立刻断言就量到了那一帧的
		# 中间态（带窗口跑时碰巧赶上了，带 headless 跑时就赶上不到了，
		# 同一份代码两种模式结论相反）。
		await process_frame
		await process_frame
		_ck("反派戏起播后脚下不再有可交互目标",
				cp6._prompt_target().is_empty(),
				"圈还指着 %s —— 它在推销一个这一趟按不出来的交互" % str(cp6._prompt_target()))
		_ck("反派戏期间按空格不给「进不去」那句",
				_world._interact_blocked_reason() == "",
				"报的是 %s" % _world._interact_blocked_reason())
		var dp6 = _world._dialogue_popup
		# 打字机没走完时按空格只是把这一行补全（`_on_next_pressed` 的第一个分支），
		# 不换行。所以这里等它走完再量"空格推进了一行"，否则量的是补字。
		await _until(func(): return dp6._typewriter_done, "第一行打字机走完")
		var line_before: int = dp6._line_idx
		_push_space()
		await process_frame
		await process_frame
		await process_frame
		_ck("这一次空格仍然是在推进对白（不是被吃掉了）",
				dp6._line_idx > line_before,
				"对白行 %d → %d" % [line_before, dp6._line_idx])
		_ck("推进对白的这一次空格没有顺手开打卡",
				not _world._check_in_in_progress)
		_ck("推进对白的这一次空格没有把圈变灰",
				cp6._blocked_key == "",
				"圈上写着 %s" % cp6._blocked_key)
		# 推到整场结束：验它自己收尾，也验它没有把这一趟永久锁死
		var guard := Time.get_ticks_msec()
		while _world._villain_playing and Time.get_ticks_msec() - guard < 15000:
			_push_space()
			await process_frame
			await process_frame
		_ck("整场推完后 _villain_playing 归位",
				not _world._villain_playing,
				"漏了这一句，铺子从此再也开不了")
		_ck("反派戏记进了进度",
				_gm.seen_villain == 1, "seen_villain=%d" % _gm.seen_villain)
	_teleport(4)
	await process_frame
	await process_frame
	_ck("反派戏散场后圈重新亮起（不是被永久收走了）",
			not cp6._prompt_target().is_empty(),
			"圈目标=%s" % str(cp6._prompt_target()))
	_ck("反派戏散场后这一站还能打卡",
			_world._can_start_check_in(4))
	_world._headless_mode = true
	_gm.headless_mode = true

	# ---------- 7 铺子最终可达 ----------
	_teleport(shop_idx)
	await process_frame
	await process_frame
	_ck("铺子能开（回归的终点：不再需要重开游戏）",
			_world._can_open_shop(_world._nearby_shop_idx))

	_gm._clear_save()
	print("\n[verify_interact_latch] %s  (失败 %d)" % [
			"PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)


func _root_loc() -> Node:
	return root.get_node("Localization")


## 问提示圈自己现在打算写哪句话（走的是它自己的 _label()，不是重演一遍逻辑）
func _visit_prompt_label() -> String:
	var cp = _world._check_in_prompt
	var t: Array = cp._prompt_target()
	return "" if t.is_empty() else str(cp._label(t))


## 只为量字宽：拿到一条真实的提示句，走的仍然是提示圈自己的 _label()
func _cp_label() -> String:
	var cp = _world._check_in_prompt
	var t: Array = cp._prompt_target()
	return _root_loc().t("desktop_checkin_prompt") if t.is_empty() else str(cp._label(t))
