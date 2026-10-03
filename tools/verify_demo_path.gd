extends SceneTree
## verify_demo_path.gd — 给评审的 90 秒演示路径
##
## 两节：
##   1. 数据层（秒级）——演示摆的那份存档必须真的算成**完满**评级，
##      `reset()` 必须把 `demo_mode` 收回去，标题页按钮上写的秒数不许和
##      `GameManager.DEMO_BUDGET_SEC` 漂。
##   2. 端到端（**约 90 秒，不能加 --headless**）——真的点「演示 · 90 秒」，
##      真的骑，真的等到结算页真的自己出现，并断言二选一停在屏上。
##      这一节不能 headless：演示走的是 `Input.parse_input_event`，
##      dummy display server 不做焦点路由，对白收不到按键，
##      驾驶员会一路顶到墙上直到超时——量出来的"演示能跑完"是假的。
##
## 用法： godot --path . --script tools/verify_demo_path.gd

var _fails := 0
var _ck_n := 0
var _gm: Node = null
var _loc: Node = null

## 这条回归一共应有的断言数。**必须有它**：本函数中途抛一次脚本错误，
## 协程就被掐断、后面的断言一行都不跑，而汇总照样打「PASS 失败 0」——
## 第 2 节第一次跑就是这样跑出假绿的（换场之后 `world` 已经 free，
## 下一帧再读 `world._player` 直接抛，第 6 条之后的断言全没了）。
const EXPECTED_CKS := 28


func _ck(label: String, cond: bool, detail: String = "") -> void:
	_ck_n += 1
	if cond:
		print("[OK]   ", label)
	else:
		_fails += 1
		print("[FAIL] ", label + ("（" + detail + "）" if detail != "" else ""))


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


# ---------------------------------------------------------------- 第 1 节
func _section_data() -> void:
	print("\n---- 1. 演示摆的那份存档 ----")
	var pv = load("res://scripts/PostcardVariant.gd")

	_ck("默认不是演示模式", _gm.demo_mode == false)
	_gm.enter_demo()
	_ck("enter_demo 打开演示模式", _gm.demo_mode == true)
	_ck("enter_demo 跳过操作说明与序章",
			_gm.onboarding_shown and _gm.prologue_done)
	_ck("enter_demo 从干净存档起（0 驿 0 碎片）",
			_gm.get_seen_station_count() == 0 and _gm.get_collected_count() == 0,
			"%d 驿 %d 碎片" % [_gm.get_seen_station_count(), _gm.get_collected_count()])

	_gm.fill_finished_run()
	_ck("补齐后十六驿全到过", _gm.get_seen_station_count() == 16,
			"got %d" % _gm.get_seen_station_count())
	_ck("补齐后五块碎片都拿到", _gm.get_collected_count() == 5,
			"got %d" % _gm.get_collected_count())
	var rd: RefCounted = load("res://scripts/road_data.gd").new()
	var all_max := true
	for si in rd.FRAGMENT_SLOT_STATION_IDX:
		if _gm.get_station_count(si) != _gm.MAX_VISITS_PER_STATION:
			all_max = false
	_ck("补齐后每座碎片站都刷满三次", all_max)
	_ck("补齐后算成完满评级（variant 4）", pv.compute_variant() == 4,
			"got %d" % pv.compute_variant())
	_ck("补齐后是珍藏笺 + 四件散件",
			_gm.get_postcard_tier() == 3
			and _gm.has_item("paper") and _gm.has_item("ink")
			and _gm.has_item("seal") and _gm.has_item("env"))

	# 补齐走的是直写字段而不是 check_in()：check_in() 会把
	# all_fragments_maxed_reached 那个闩锁翻过来，于是 World3D 的
	# _on_all_maxed() 当场锁死操纵权、2.5 秒后自己跳去结算页——
	# 而那时候演示还在半路。
	_ck("补齐不翻 all_fragments_maxed 闩锁（演示要自己掌握何时收工）",
			_gm._maxed_fired == false)
	# 集齐二选一面板在演示里同样不能弹：它开着的时候世界是冻住的、玩家
	# 没法操作，症状就是"演示后半段卡住不动"。
	# `_collected_fired` 此刻是 **false** —— 补齐是直写字段，而信号只在
	# `check_in()` 里发。所以挡住它的**不是**闩锁，是"演示里根本打不了卡"：
	# 刷满的碎片站被 `is_station_exhausted` 挡在 `_nearby_station_idx` 之外，
	# 于是 `_can_start_check_in()` 恒假、`check_in()` 一次都走不到。
	# 钉的是这条结构性理由，不是那个闩锁——闩锁是碰巧成立的那一半。
	var any_visit_left := false
	for si in rd.FRAGMENT_SLOT_STATION_IDX:
		if _gm.fragment_station_needs_visit(si):
			any_visit_left = true
	_ck("补齐后没有碎片站还欠到访（演示里打不了卡，够不到集齐面板）",
			not any_visit_left)

	_gm.reset()
	_ck("reset 收回演示模式", _gm.demo_mode == false)

	# 标题页按钮上写着的秒数就是 `GameManager.DEMO_BUDGET_SEC`。
	# 两处各写一份的话，改了常量按钮上还写着 90，而评审等的其实是别的数。
	_loc.set_language("zh")
	var zh: String = _loc.t("demo_start")
	_loc.set_language("en")
	var en: String = _loc.t("demo_start")
	_ck("中英按钮文案都写着 %d 秒" % int(_gm.DEMO_BUDGET_SEC),
			zh.contains(str(int(_gm.DEMO_BUDGET_SEC)))
			and en.contains(str(int(_gm.DEMO_BUDGET_SEC))),
			"zh=%s en=%s" % [zh, en])
	_ck("收工时刻早于总长（明信片要留出时间）",
			_gm.DEMO_END_AT_SEC < _gm.DEMO_BUDGET_SEC - 10.0,
			"%.0f / %.0f" % [_gm.DEMO_END_AT_SEC, _gm.DEMO_BUDGET_SEC])


# ---------------------------------------------------------------- 第 2 节
func _push_space() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)


func _section_end_to_end() -> void:
	print("\n---- 2. 真的点一次演示（约 %.0f 秒）----" % _gm.DEMO_BUDGET_SEC)
	_gm._clear_save()
	_loc.set_language("zh")
	root.size = Vector2i(1280, 720)

	var gift: Control = load("res://scenes/GiftBox.tscn").instantiate()
	root.add_child(gift)
	current_scene = gift
	await process_frame
	await process_frame
	_ck("标题页上有「演示」按钮", gift.get_node_or_null("DemoBtn") != null)

	gift._on_demo_pressed()
	var t_press := Time.get_ticks_msec()
	while current_scene == gift or current_scene == null:
		if Time.get_ticks_msec() - t_press > 40000:
			_ck("演示进了 3D 世界", false, "场景切换超时")
			return
		await process_frame
	var world: Node = current_scene
	await process_frame
	await process_frame

	_ck("演示模式确实生效", _gm.demo_mode == true)
	_ck("操作说明被跳过", world._onboarding.visible == false)
	_ck("序章没播（prologue_done 已经是真）", _gm.prologue_done == true)
	_ck("DemoDirector 挂上了", world.get_node_or_null("DemoDirector") != null)
	_ck("操纵权在演示开始时就给了", bool(world._player._can_move))

	# 等演示自己收工。它不该靠我们按任何键。
	#
	# 这一段必须同时**证明车真的在骑**。只断言"62 秒后到了结算页"的话，
	# DemoDirector 一行都不执行、驾驶员在起点站到时间到，照样全绿——
	# 那是拿自己测自己。判据是累计路程、到访数、以及**小游戏有没有真的弹出来**，
	# 都必须在收工**之前**采样，因为 `fill_finished_run()` 随后就把存档补齐了。
	#
	# 这里断言的是"弹出来过"而不是"碎片 ≥1"：`GameManager.check_in()` 要等小游戏
	# 做完才调，而演示是每个小游戏放 4 秒就 ESC 走人的。**试过让它真赢一次**：
	# 茶是长按空格三秒，一条通用按键序列就能通吃，于是写了一段按住不放的逻辑。
	# 量出来是**一次都没走到**——62 秒只够停两站，而起点最近的那座碎片站是
	# 禽（槽位 4 / 驿站 4），茶在更远的环上；而禽要数字键认图、答错立刻判失败，
	# 没有通用序列。所以碎片确实全由 `fill_finished_run()` 补，拿它当判据等于
	# 拿自己测自己；补齐这件事改由下面那条"收工前在屏上交代了一句"来守。
	var waited := 0.0
	var ridden := 0.0
	var last_pos: Vector3 = world._player.global_position
	var frags := -1
	var seen := -1
	var mg_seen := 0
	var mg_names := {}
	var notice_shown := ""
	while current_scene == world:
		await process_frame
		waited = (Time.get_ticks_msec() - t_press) / 1000.0
		# 换场那一帧 `world` 就被 free 了，还读 `world._player` 会抛
		# "Invalid access ... previously freed"，而那一次抛就把整个协程掐断。
		if is_instance_valid(world) and world._player != null:
			var p: Vector3 = world._player.global_position
			ridden += Vector2(p.x - last_pos.x, p.z - last_pos.z).length()
			last_pos = p
			if world._mini_game_state == world.MG_RUNNING:
				mg_seen += 1
				var mg: Node = world._mini_game_node
				if mg != null and is_instance_valid(mg):
					var sc: Script = mg.get_script()
					if sc != null:
						mg_names[str(sc.resource_path).get_file()] = true
			# 收工那一拍留在屏上的字。判据量的是**玩家看得见的那一半**：
			# `fill_finished_run()` 之后卡上十六驿全到过、五件乐事各三次，
			# 而评审亲眼看的是 2 座驿加一个小游戏。补齐不是谎，闷声补齐才是。
			# 只在收工那一拍采样：平时那一行浮的是路过驿站的旁白和开场那句
			# `demo_hint`，量它们等于没量。
			var dd: Node = world.get_node_or_null("DemoDirector")
			if notice_shown == "" and dd != null and bool(dd.get("_handed_off")):
				notice_shown = String(world._hud3d._pass_label.text)
		if frags < 0 and waited > _gm.DEMO_END_AT_SEC - 12.0:
			frags = _gm.get_collected_count()
			seen = _gm.get_seen_station_count()
		if waited > _gm.DEMO_BUDGET_SEC + 30.0:
			break
	var card: Node = current_scene
	var took := (Time.get_ticks_msec() - t_press) / 1000.0
	var mg_list := ", ".join(PackedStringArray(mg_names.keys()))
	print("    （收工前采样：累计骑行 %.0fm，到过 %d 驿，碎片 %d/5，小游戏在跑 %d 帧：%s）"
			% [ridden, seen, frags, mg_seen, mg_list])
	_ck("车真的骑了一段（≥200m，不是站在起点等时间到）", ridden > 200.0,
			"%.0fm" % ridden)
	# 门槛是 1 不是 2：连跑两次量到的是 1 驿/466m 与 2 驿/677m，而它随"第二座
	# 碎片站落在 62 秒窗口的哪一段"摆动（一次停站吃掉约 13 秒：进圈 + 对白 +
	# 4 秒小游戏 + ESC + 失败面板 + 静默期 + 骑开重新武装）。钉 2 就是钉一个
	# 摆动量，回归会随机红，而随机红的回归等于没有回归。
	# 这一族真正的判据是"车真的在骑而且真的骑到亭子跟前了"——由上面那条里程
	# 和下面那条小游戏兜着，原来那个 0 驿/0m 的 DemoDirector 就是这么被抓住的。
	_ck("真的路过驿站（≥1 座）", seen >= 1, "%d（实测在 1~2 之间摆动）" % seen)
	_ck("真的把车骑到亭子跟前、打卡开出了一场小游戏", mg_seen > 0,
			"%d 帧" % mg_seen)

	# 卡上那些数是补的，而"补"这件事必须在换场**之前**被说出来。
	# 判据量的是玩家看得见的那一半（`HUD3D._pass_label` 的正文），不是
	# `DemoDirector` 某个字段为真——字段翻了而那行字没画出来，症状是
	# 评审照样拿到一张他没挣来的满卡、而没人对他说过一句话。
	_ck("收工前在屏上交代了一句（补齐的那趟不是他骑的）",
			notice_shown == _loc.t("demo_card_notice"),
			"got=%s" % notice_shown)

	_ck("演示在预算内自己走到了结算页", card != world and card != null,
			"%.1fs" % took)
	if card == world or card == null:
		return
	_ck("收工时刻接近 DEMO_END_AT_SEC（%.0f ± 12s）" % _gm.DEMO_END_AT_SEC,
			absf(took - _gm.DEMO_END_AT_SEC) < 12.0, "%.1fs" % took)

	await process_frame
	await process_frame
	_ck("停在了终局二选一上（评审自己选，我们不替他按）",
			card._ending_overlay != null)
	_ck("抵达时演示模式仍然开着（回执/重开要知道自己在演示里）",
			_gm.demo_mode == true)

	current_scene.queue_free()
	await process_frame
	_gm.reset()


func _initialize() -> void:
	Engine.max_fps = 60
	_ensure_autoloads()
	_gm = root.get_node("GameManager")
	_loc = root.get_node("Localization")
	_run.call_deferred()


func _run() -> void:
	print("=== 90 秒演示路径回归（带窗口跑）===")
	_section_data()
	await _section_end_to_end()
	# 计数放在最后：中途抛错的话 quit() 走不到，而收尾这一条正是为了
	# 认出那种「后面一半断言根本没跑」的假绿。
	_ck("确实跑完了 %d 条断言" % EXPECTED_CKS, _ck_n == EXPECTED_CKS,
			"只跑了 %d 条" % _ck_n)
	print("\n[verify_demo_path] %s  (失败项 %d)" % [
			"PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)