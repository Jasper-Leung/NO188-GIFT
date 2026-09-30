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
## 玩家怎么按都不对劲，只能重开游戏。小地图是第三个会说"下一处在哪"的地方，
## 它的判据必须再抄一遍前两处的作业。
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

	# ---- 4. 收过的站必须被跳过 ----
	var order: Array = []
	for i in range(_rd.stations.size()):
		if _rd.station_has_fragment(i):
			order.append(i)
	var first := int(order[0])
	_gm.collected[first] = 1
	_world._player.global_position = _rd.get_station_world_pos(first)
	await physics_frame
	await process_frame
	_ck("收过的站不再被指为下一处", _mm._next_frag_idx() != first,
			"still=%d" % int(_mm._next_frag_idx()))
	_eq("收过一颗后仍与顶栏一致", _mm._next_frag_idx(),
			int(_hud._next_fragment_target().get("idx", -1)))

	# ---- 5. 全收齐：两处都得说"没有下一处" ----
	for i in order:
		_gm.collected[i] = 1
	await physics_frame
	await process_frame
	_eq("五块齐了：小地图不再指任何站", _mm._next_frag_idx(), -1)
	_ck("五块齐了：顶栏也没有下一处", _hud._next_fragment_target().is_empty())

	# ---- 6. 普通驿站永远不占"下一处" ----
	# 16 站里只有 5 站有碎片。判据写成 station_has_fragment() 的话这一条自动成立，
	# 但写成"is_collected 就跳过"就会把 11 个普通驿站也标成目标——11 个脉冲金点
	# 在小地图上比 5 个还吵，等于地图废了。
	_gm.reset()
	_gm.onboarding_shown = true
	await physics_frame
	var picked := int(_mm._next_frag_idx())
	_ck("指到的站真的有碎片", _rd.station_has_fragment(picked), "idx=%d" % picked)
	_ck("指到的站还没收", not bool(_gm.is_collected(picked)))

	_finish(backup)


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
