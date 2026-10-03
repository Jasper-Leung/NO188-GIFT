extends SceneTree
## 小地图「未收碎片站」回归 —— 验证小地图、顶栏、屏幕提示圈三处指的是同一批地方。
##
## 只测判据，不测像素。头的半径 / 金点 / 呼吸光晕是画出来的，headless 下
## draw_* 什么都不落盘，只有带窗口的 lookdev_journey.gd 能看出来那些。这里守住
## 真正会出事的那一半：**小地图高亮的那颗，必须就是顶栏"下一处"报的那颗**。
##
## 这条不变量不是洁癖。改之前 CheckInPrompt 就栽在同一个家族上：驿站那圈用
## station_has_fragment()（站的属性，静态）当"玩家还没收过"用，顶栏却用
## is_collected()。两处口径一错，回访时顶栏说"下一处 358m"、脚下的圈照亮，
## 玩家怎么按都不对劲，只能重开游戏。小地图是第三个会说"下一处在哪"的地方。
##
## 现在三处都不许自己抄判据了，统一问 GameManager.fragment_station_needs_visit()：
## 判据本身也从"还没收过"改成了"还欠一次到访"。完满评级要求五座碎片驿站各去过
## MAX_VISITS_PER_STATION 次，所以第一次拿到碎片之后这站还剩两次 —— 旧口径在这里
## 就把它从"下一处"里摘掉了，等于把全游戏最强的重玩钩子从导航上抹掉。
##
## 用法： godot --headless --path . --script tools/verify_minimap.gd --quit-after 30000
## 注意 --quit-after 单位是帧不是秒。

var _fails: Array = []
var _oks := 0
var _gm: Node = null
var _loc: Node = null
var _world: Node = null
var _mm: Node = null
var _hud = null
var _rd = null


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_oks += 1
		print("[OK]   ", label)
	else:
		var msg := label + ("（" + detail + "）" if detail != "" else "")
		_fails.append(msg)
		print("[FAIL] ", msg)


func _eq(label: String, got: Variant, want: Variant) -> void:
	_ck(label, got == want, "got=%s want=%s" % [str(got), str(want)])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== 小地图碎片站回归 ===")

	_gm = root.get_node_or_null("GameManager")
	_loc = root.get_node_or_null("Localization")
	if _gm == null or _loc == null:
		print("[ABORT] 拿不到 autoload")
		quit(1)
		return

	var backup := ""
	if FileAccess.file_exists(str(_gm.SAVE_PATH)):
		var rf = FileAccess.open(str(_gm.SAVE_PATH), FileAccess.READ)
		if rf != null:
			backup = rf.get_as_text()
			rf.close()

	_gm.reset()
	_gm.onboarding_shown = true
	_gm.headless_mode = true

	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	await create_timer(2.5).timeout
	_world._onboarding.visible = false

	_mm = _world._minimap
	_hud = _world._hud3d
	_rd = _world._road_builder.get_road_data()

	# ---- 1. 小地图在场 ----
	_ck("小地图在场", _mm != null)
	_ck("小地图拿到了 road_data", _mm.road_data != null)
	_ck("小地图拿到了 player", _mm.player != null)
	if _mm == null or _hud == null or _rd == null:
		_finish(backup)
		return

	# ---- 2. 开局：高亮的就是顶栏说的那一颗 ----
	_gm.reset()
	_gm.onboarding_shown = true
	var next: Dictionary = _hud._next_fragment_target()
	_ck("顶栏认得出下一处", not next.is_empty())
	_eq("小地图 = 顶栏（开局）", _mm._next_frag_idx(), int(next.get("idx", -1)))

	# ---- 3. 沿途每一段都同步 ----
	# 8 字环自闭合、两个方向都能到全部 5 站，所以位置是绕圈取的，不能只测起点。
	var pts: Array = _rd.points
	var frag_total := 0
	for i in range(_rd.stations.size()):
		if _rd.station_has_fragment(i):
			frag_total += 1
	_eq("一共 5 个碎片站", frag_total, 5)

	var mismatched := 0
	var checked := 0
	for k in range(0, pts.size(), 3):
		_world._player.global_position = pts[k]
		await physics_frame
		# HUD3D 每帧重算"下一处"，小地图每帧重画，两边都得先走一帧
		await process_frame
		var hud_idx := int(_hud._next_fragment_target().get("idx", -1))
		var mm_idx := int(_mm._next_frag_idx())
		checked += 1
		if hud_idx != mm_idx:
			mismatched += 1
			if mismatched <= 3:
				print("       位置 %d/%d: 顶栏=%d 小地图=%d" % [k, pts.size(), hud_idx, mm_idx])
	_eq("沿途 %d 个采样点两处完全一致" % checked, mismatched, 0)

	# ---- 4. 判据只有一个副本 ----
	# 顶栏 HUD3D 把 MAX_VISITS_PER_STATION 抄了一份成 const（static 函数读不到
	# autoload），两份一旦漂移，"还差 N 次"就会和实际存档对不上，而且没有任何
	# 断言拦得住 —— 所以这里直接量它俩相等。
	_eq("顶栏抄的到访上限 == GameManager 的",
			int(_hud.MAX_VISITS_PER_STATION), int(_gm.MAX_VISITS_PER_STATION))
	for i in range(_rd.stations.size()):
		if _rd.station_has_fragment(i):
			_eq("碎片站 %d 开局仍需到访" % i, bool(_gm.fragment_station_needs_visit(i)), true)
			break
	_ck("普通驿站永远不需到访", not bool(_gm.fragment_station_needs_visit(0)))
	_ck("开局还没全满", not bool(_gm.all_fragments_maxed()))
	_eq("开局每格碎片都还差满额",
			int(_gm.fragment_slot_visits_left(0)), int(_gm.MAX_VISITS_PER_STATION))
	_ck("越界的 slot 号不崩", int(_gm.fragment_slot_visits_left(99)) == 0
			and int(_gm.fragment_slot_visits_left(-1)) == 0)

	# ---- 5. 收过一次的站仍然是指向目标，差几次由存档说了算 ----
	# 完满评级要求每座碎片驿站去过 MAX_VISITS 次，所以"已经收过"从来不等于
	# "不用再去"。旧口径在这里就把站摘掉了，脚下提示圈还亮着 2 次，顶栏却开始
	# 指下一块还没拿的碎片 —— 两块指路牌互相打架。
	var order: Array = []
	for i in range(_rd.stations.size()):
		if _rd.station_has_fragment(i):
			order.append(i)
	var first := int(order[0])
	_gm.collected[first] = 1
	_world._player.global_position = _rd.get_station_world_pos(first)
	await physics_frame
	await process_frame
	_ck("刚收过一次的站仍被指为下一处（就站在它面前时）", _mm._next_frag_idx() == first,
			"got=%d want=%d" % [int(_mm._next_frag_idx()), first])
	_eq("收过一次后仍与顶栏一致", _mm._next_frag_idx(),
			int(_hud._next_fragment_target().get("idx", -1)))
	_ck("顶栏此时说的是「再访」而不是「下一处」",
			_hud._next_label.text.contains(_loc.t("visits_left_n") % 2),
			_hud._next_label.text)

	# ---- 6. 五块齐了 ≠ 没有下一处；刷满了才真的没有 ----
	for i in order:
		_gm.collected[i] = 1
	await physics_frame
	await process_frame
	_ck("五块齐了但都没刷满：仍不算满格", not bool(_gm.all_fragments_maxed()))
	_ck("五块齐了但都没刷满：小地图仍指人", _mm._next_frag_idx() >= 0,
			"got=%d" % int(_mm._next_frag_idx()))
	_eq("五块齐了但都没刷满：仍与顶栏一致", _mm._next_frag_idx(),
			int(_hud._next_fragment_target().get("idx", -1)))

	for i in order:
		_gm.collected[i] = int(_gm.MAX_VISITS_PER_STATION)
	await physics_frame
	await process_frame
	_ck("五座都刷满：GameManager 认满了", bool(_gm.all_fragments_maxed()))
	_eq("五座都刷满：小地图不再指任何站", _mm._next_frag_idx(), -1)
	_ck("五座都刷满：顶栏也没有下一处", _hud._next_fragment_target().is_empty())
	_eq("五座都刷满：每格碎片都不再欠到访", int(_gm.fragment_slot_visits_left(0)), 0)

	# 刷满 4/5 时仍要留一个目标
	_gm.reset()
	_gm.onboarding_shown = true
	_gm.collected[first] = int(_gm.MAX_VISITS_PER_STATION)
	await physics_frame
	await process_frame
	_ck("刷满四座时仍认还有一格欠着", not bool(_gm.all_fragments_maxed()))
	_ck("刷满四座时指的不是那座已满的", _mm._next_frag_idx() != first,
			"got=%d" % int(_mm._next_frag_idx()))

	# ---- 7. 普通驿站永远不占"下一处" ----
	# 16 站里只有 5 站有碎片。判据写成 station_has_fragment() 的话这一条自动成立，
	# 但写成"is_collected 就跳过"就会把 11 个普通驿站也标成目标——11 个脉冲金点
	# 在小地图上比 5 个还吵，等于地图废了。
	_gm.reset()
	_gm.onboarding_shown = true
	await physics_frame
	var picked := int(_mm._next_frag_idx())
	_ck("指到的站真的有碎片", _rd.station_has_fragment(picked), "idx=%d" % picked)
	_ck("指到的站还没收", not bool(_gm.is_collected(picked)))
	_ck("指到的站还欠到访", bool(_gm.fragment_station_needs_visit(picked)))

	# ---- 8. FragmentBar 的到访小点跟的是同一个数 ----
	# 小点画多少颗、亮几颗，全都读 GameManager.fragment_slot_visits_left()；
	# 这里守住"底栏真的读它"这条连线——万一有人改成读自己那份 visited 副本，
	# 底栏会和顶栏说不同的次数，而小点是 _draw() 画的，headless 一片空白看不出来。
	var fb = _world.find_child("FragmentBar", true, false)
	_ck("底栏碎片栏在场", fb != null)
	if fb != null:
		var done_mid: int = 2
		_gm.collected[first] = done_mid
		# 底栏的格子是 slot（0..4），驿站是 station（0..15），两者不是同一条轴
		var slot: int = _rd.FRAGMENT_SLOT_STATION_IDX.find(first)
		_ck("这一站确实对应某一格碎片", slot >= 0, "first=%d" % first)
		if slot >= 0:
			_eq("底栏那格的还差次数 == 存档里的到访次数",
					int(_gm.fragment_slot_visits_left(slot)),
					int(_gm.MAX_VISITS_PER_STATION) - done_mid)

	# ---- 8b. 玩家自己喊停的出口 ----
	# 结束条件改成"五站各刷满三次"之后，"集齐即结算"这条老路被拿掉了，
	# 如果不补一个出口，这一趟就只剩暂停面板里的「重新开始」——那会把存档
	# 直接 reset，玩家既拿不到明信片、PostcardVariant 的前四档也全成了死代码。
	# 所以这里盯住暂停面板那个「结束这一趟」按钮：它必须在场、文案对、
	# 且跟着"收过几块"显隐（零块时 EndCard 做出来的是一张空卡，没有任何说法）。
	var pause = _world._pause_panel
	_ck("暂停面板在场", pause != null)
	if pause != null:
		_ck("暂停面板有「结束这一趟」按钮", pause._finish_btn != null)
		if pause._finish_btn != null:
			_gm.reset()
			_gm.onboarding_shown = true
			pause.visible = true
			await process_frame
			_ck("一块碎片都没有：不许收工", not bool(pause._finish_btn.visible))
			_gm.check_in(first)
			_gm.check_in(order[1])
			pause.visible = false
			pause.visible = true
			await process_frame
			_ck("收过两块之后：出口出现", bool(pause._finish_btn.visible))
			_ck("按钮文案是那句", pause._finish_btn.text == _loc.t("finish_run"),
					pause._finish_btn.text)
			# 收工时评级必须按"真的走过几站"算，而不是一律完满
			_eq("只走过两站就收工：评级是探索者(1)",
					int(load("res://scripts/PostcardVariant.gd").compute_variant()), 1)
			pause.visible = false


	#
	# 结束条件从"五站各收过一次"改成"五站各刷满三次"之后，"五块碎片都拿齐了"
	# 从终局变成了**中局**——玩家要在这之后继续骑完八趟回访。而"下一处在哪"
	# 恰恰是在这一刻最该出错的：旧判据下集齐即完满，三处指示器一起消失，
	# 顶栏的「再访 · 还差 N 次」一个字都兑现不了。
	#
	# 所以这一节两件事：沿整条环把两处逐点对一遍；再站到每一座碎片驿站面前，
	# 核对顶栏和脚下的圈报的是同一个"还差几次"。
	_gm.reset()
	_gm.onboarding_shown = true
	# 走真实打卡流程而不是直接写 collected：这一节要量的正是
	# "集齐不再结束这一趟"，而只有 check_in() 才会发那两个信号。
	for i in order:
		_gm.check_in(i)
	# _on_all_collected 会锁住玩家 2.5 秒播合成动画，等它放人
	await create_timer(3.2).timeout
	await physics_frame
	await process_frame

	# 2.5 秒演完之后会弹集齐二选一面板，而面板开着的时候世界是冻住的
	# （`_synthesis_choice_open` 在 `_physics_process` 那张早退单子里，
	# `_nearby_*` 被清成 -1，脚下的圈照画不误才是 bug）。这一节接下来要
	# 逐站核对那个圈，所以得先走玩家会走的那条路：选「再骑一圈」。
	# 顺带钉一条"面板真的弹出来了"，不然这段代码将来可以悄悄失效
	# （比如那 2.5 秒变长）而断言数一条不少、全绿。
	_ck("集齐 2.5 秒后弹出了二选一面板", bool(_world._synthesis_choice_open))
	_ck("面板开着的时候世界是冻住的（不能边看面板边打卡）",
			not bool(_world._player._can_move))
	_world._on_synthesis_choice(false)
	await physics_frame
	await process_frame
	_ck("选「再骑一圈」之后世界解冻", bool(_world._player._can_move))

	_ck("五站各打一次卡后：不算满格", not bool(_gm.all_fragments_maxed()))
	_ck("五站各打一次卡后：这一趟**没有**结束", not bool(_world._all_done),
			"_all_done=%s" % str(bool(_world._all_done)))
	_ck("五站各打一次卡后：每格碎片还差 2 次",
			int(_gm.fragment_slot_visits_left(0)) == int(_gm.MAX_VISITS_PER_STATION) - 1)
	# PostcardVariant 里引了 RoadData/GameManager，--script 模式下按类名解析会
	# 踩 autoload 那个坑（编译期拉依赖、脚本永不执行），所以运行时 load。
	var pvar = load("res://scripts/PostcardVariant.gd")
	_eq("集齐但没刷满：评级是大师(3)", int(pvar.compute_variant()), 3)

	var lap_mismatch := 0
	var lap_blank := 0
	var lap_n := 0
	for k in range(0, pts.size(), 3):
		lap_n += 1
		_world._player.global_position = pts[k]
		await physics_frame
		await process_frame
		var hud_idx2 := int(_hud._next_fragment_target().get("idx", -1))
		var mm_idx2 := int(_mm._next_frag_idx())
		if hud_idx2 != mm_idx2 or mm_idx2 < 0:
			lap_mismatch += 1
			if lap_mismatch <= 3:
				print("       位置 %d/%d: 顶栏=%d 小地图=%d" % [k, pts.size(), hud_idx2, mm_idx2])
		if str(_hud._next_label.text).strip_edges() == "":
			lap_blank += 1
	_eq("集齐后整圈 %d 个采样点两处仍一致且都指人" % lap_n, lap_mismatch, 0)
	_eq("集齐后整圈顶栏没有一帧是空的", lap_blank, 0)

	# 站到每一座碎片驿站面前，核对顶栏和脚下的圈说的是同一个"还差几次"
	var prompt = _world._check_in_prompt
	_ck("屏幕提示圈在场", prompt != null)
	if prompt != null:
		_ck("提示圈不是触屏模式（本节断言的是键盘文案）", not bool(prompt._is_touch))
		var want_left := int(_gm.MAX_VISITS_PER_STATION) - 1
		for i in order:
			var st: Vector3 = _rd.get_station_world_pos(i)
			var p := st - _away_from_road(st) * 10.0
			p.y = _world._get_terrain_height(p.x, p.z)
			_world._player.global_position = p
			await physics_frame
			await process_frame
			var tgt: Array = prompt._prompt_target()
			_eq("站在碎片站 %d 面前，圈指的就是它" % i,
					int(tgt[0]) if tgt.size() == 3 else -1, i)
			_eq("碎片站 %d：脚下的圈说「还差 %d 次」" % [i, want_left],
					prompt._label(tgt), _loc.t("desktop_revisit_prompt") % want_left)
			_ck("碎片站 %d：顶栏说的次数和脚下的一致" % i,
					str(_hud._next_label.text).contains(_loc.t("visits_left_n") % want_left),
					str(_hud._next_label.text))
			_ck("碎片站 %d：这一站确实还欠到访" % i,
					bool(_gm.fragment_station_needs_visit(i)))

	# ---- 10. 刷满了才真的结束这一趟 ----
	# 放最后：check_in() 走满第五座时 _on_all_maxed 会在 2.5 秒后调
	# go_to_end_card() 换场景，插在中间会把后面所有断言的节点换掉。
	for i in order:
		_gm.check_in(i)
		_gm.check_in(i)
	_ck("五站各刷满：GameManager 认满了", bool(_gm.all_fragments_maxed()))
	_ck("五站各刷满：这一趟**才**结束", bool(_world._all_done),
			"_all_done=%s" % str(bool(_world._all_done)))
	_eq("刷满后评级是完满(4)", int(pvar.compute_variant()), 4)

	# 刷满之后顶栏那一行**不许空掉**。原来 `_update_next_label()` 在
	# `_next_fragment_target()` 返回空时写的是 `text = ""` ——于是这一栏
	# 整条消失，只剩衬底。而这恰好是玩家最该看着它的那两秒：屏幕中央
	# 正在演「五座驿站都走满了」，2.5 秒后就要跳去结算页，信息量最大的一刻
	# 导航栏先哑了；衬底又一直铺到屏右，于是那段空档读成一条什么都没有的黑带
	# （评审第一轮记的约 600px 死区就是它，"下一处"一空就整整翻倍）。
	# 上面对"集齐"那一段已经钉了"整圈没有一帧是空的"，这里是它的另一半：
	# 真的一个目标都没有的时候，那一栏仍然得说出一件真事。
	await process_frame
	_ck("刷满后顶栏那一行不是空的",
			str(_hud._next_label.text).strip_edges() != "",
			"text=%s" % str(_hud._next_label.text))
	_eq("刷满后顶栏报的是那句收尾的话",
			str(_hud._next_label.text), _loc.t("hud_all_done"))

	_finish(backup)


## 从站指回路中线方向的单位向量。驿站一律离路 18m，而提示圈只画 15m ——
## 玩家把车停在路心是**进不了圈**的，所以测试也得停到站前 10m 才行。
func _away_from_road(st: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var bd := 1e9
	for cl in _world._road_builder.get_all_centerlines():
		for q in cl:
			var d: float = Vector2(q.x - st.x, q.z - st.z).length()
			if d < bd:
				bd = d
				best = q
	var v := Vector3(st.x - best.x, 0.0, st.z - best.z)
	if v.length() < 0.001:
		return Vector3(0.0, 0.0, 1.0)
	return v.normalized()


func _finish(backup: String) -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	if backup != "":
		var wf = FileAccess.open(str(_gm.SAVE_PATH), FileAccess.WRITE)
		if wf != null:
			wf.store_string(backup)
			wf.close()
	else:
		_gm._clear_save()

	print("\n=== 结果：OK %d / FAIL %d ===" % [_oks, _fails.size()])
	for f in _fails:
		print("  [FAIL] ", f)
	quit(0 if _fails.is_empty() else 1)
