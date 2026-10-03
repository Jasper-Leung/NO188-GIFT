extends SceneTree
## 路碑回归 —— 守住「188」在世界里真的存在、真的被读到。
##
## 这条回归守的是一个此前根本没有实例的主题答案。题眼是「给 ______ 的礼物」，
## 本作答的是「188 号」，可 188 在整个世界里只活在文案里：一块石头都没有、
## 一个数字都没刻。序章里最好的那句「守驿人记路，不记己」也只播一次就再没被
## 提起。评审看见的是一个没有主题的世界。
##
## 量的四件事：
##   1. 四块碑真的建出来了、碑面刻的真的是 188；
##   2. 落点合法（不压沥青、不和驿站石台糊成一坨）；
##   3. **碑面朝路而不是朝世界原点**——8 字环的中心在 (0, 43)，按原点算朝向
##      会歪掉几十度。第一版就是这么错的，而它在任何"看它是不是 188"的
##      断言下都照样是绿的；
##   4. 路过只浮一次，停在碑前不动不会每秒重弹。
##
## 用法： godot --headless --path . --script tools/verify_road_steles.gd --quit-after 30000
## 注意 --quit-after 单位是帧不是秒。

var _fails: Array = []
var _oks := 0
var _gm: Node = null
var _loc: Node = null
var _world: Node = null
var _steles: Node = null
var _hud = null
var _rd = null
var _backup := ""
var _WANT := 4
## HUD3D.PASS_HOLD_SEC —— 浮字在屏上停留多久。这里抄一份而不是引 HUD3D 的
## 常量：`--script` 模式下按 class_name 引会拉编译期依赖（见 CLAUDE.md）。
## HUD3D 改了这个数，这条会红，那正是它该做的。
const HUD_PASS_HOLD := 3.2


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
	_gm = root.get_node_or_null("GameManager")
	_loc = root.get_node_or_null("Localization")
	if _gm == null or _loc == null:
		print("[ABORT] 拿不到 autoload")
		quit(1)
		return

	_backup = ""
	if FileAccess.file_exists(str(_gm.SAVE_PATH)):
		var rf = FileAccess.open(str(_gm.SAVE_PATH), FileAccess.READ)
		if rf != null:
			_backup = rf.get_as_text()
			rf.close()

	_gm.reset()
	_gm.onboarding_shown = true
	_gm.prologue_done = true
	_gm.headless_mode = true
	root.size = Vector2i(1280, 720)

	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	_run.call_deferred()


func _park(xz: Vector3) -> void:
	_world._player.position = Vector3(xz.x, _world._road_builder.get_road_ribbon_height(xz.x, xz.z) + 0.8, xz.z)
	_world._last_global_pos = _world._player.global_position
	_world._has_last_pos = true


func _nearest_road_dist(p: Vector2) -> float:
	var best := 1e9
	for c in _rd.points:
		var d := Vector2(c.x, c.z).distance_to(p)
		if d < best:
			best = d
	return best


func _run() -> void:
	print("=== 路碑回归 ===")
	await create_timer(2.5).timeout
	_world._onboarding.visible = false

	_steles = _world._steles
	_hud = _world._hud3d
	_rd = _world._road_builder.get_road_data()

	# ---- 1. 碑在场 ----
	_ck("RoadSteles 节点建出来了", _steles != null)
	if _steles == null:
		_finish("")
		return
	_eq("四块碑都建出来了", _steles.get_child_count(), _WANT)
	_eq("stele_line_keys 逐条对齐", _steles.stele_line_keys.size(), _WANT)
	_eq("stele_positions 逐条对齐", _steles.stele_positions.size(), _WANT)

	# ---- 2. 碑面刻的是 188 ----
	for i in range(_steles.get_child_count()):
		var mark = _steles.get_child(i).get_node_or_null("Mark")
		_ck("碑 %d 碑面是 Label3D" % i, mark is Label3D)
		if mark is Label3D:
			_eq("碑 %d 刻的是 188" % i, mark.text, "188")

	# ---- 3. 落点合法 ----
	# 3.1 不压沥青：RoadBuilder.TOTAL_HALF_WIDTH = 6.5m。碑是 11m，
	#     所以这一条要防的是有人把 STELE_OFFSET 改小到 5。
	for i in range(_steles.get_child_count()):
		var p: Vector3 = _steles.stele_positions[i]
		var d := _nearest_road_dist(Vector2(p.x, p.z))
		_ck("碑 %d 不压在沥青上（离中心线 %.1fm）" % [i, d], d > 6.5)
	# 3.2 不和驿站石台糊成一坨
	for i in range(_steles.get_child_count()):
		var p: Vector3 = _steles.stele_positions[i]
		var near := 1e9
		for st in _world._stations:
			near = min(near, Vector2(st.position.x, st.position.z).distance_to(Vector2(p.x, p.z)))
		_ck("碑 %d 离最近的驿站 %.1fm" % [i, near], near >= 16.0)
	# 3.3 **从路上看得见**。这条不是"离树多远"——离得近也可能在视线的另一侧。
	#     量的是：从碑正对的中心线点到碑，画一条线段，任何行道树都不许
	#     站进这条线段 2.5m 以内。第一版碑取 11.0m、正好落在行道树那条
	#     9.5~12.5m 的带子里，"被凿平的那块"被一棵树整个挡死；挪到 15m
	#     挪到树行后面也照样有一棵立在视线中间——碑是给路上的人看的。
	var trees: Array = []
	if _world._tree_scatter != null:
		trees = _world._tree_scatter._trees
	_ck("拿得到行道树的落点（%d 棵）" % trees.size(), trees.size() > 0)
	for i in range(_steles.get_child_count()):
		var p: Vector3 = _steles.stele_positions[i]
		var here := Vector2(p.x, p.z)
		var road_pt := _nearest_road_point(here)
		var blockers: Array = []
		for t in trees:
			var tp: Vector3 = t["pos"]
			if _seg_dist(Vector2(tp.x, tp.z), road_pt, here) < 2.5:
				blockers.append(tp)
		_ck("碑 %d 视线没被行道树挡住（挡住的 %d 棵）" % [i, blockers.size()], blockers.is_empty())

	# ---- 4. 碑面朝路，不朝世界原点 ----
	# 逐块量 dot（每块都得朝着路）。至于"按原点算的那条路在这儿长什么样"
	# 则**不能逐块量**——8 字环的某一段恰好落在从碑指向 (0, 43) 的延长线上时，
	# 两种算法会给出几乎一样的答案（实测碑 1 只差 5°），那条断言于是变成永远
	# 绿的空跑。真正有牙齿的是"整组里最大的一条差多少"：只要有一块差得够多，
	# 就不可能是按原点算的。
	var max_off := 0.0
	for i in range(_steles.get_child_count()):
		var mark = _steles.get_child(i).get_node_or_null("Mark") as Label3D
		if mark == null:
			continue
		var here := Vector2(mark.global_position.x, mark.global_position.z)
		# 碑只绕 Y 转，所以碑面法线的水平分量就是它实际朝的方向。
		var fwd := Vector2(mark.global_transform.basis.z.x, mark.global_transform.basis.z.z).normalized()
		var want := (_nearest_road_point(here) - here).normalized()
		var dot: float = fwd.dot(want)
		_ck("碑 %d 碑面朝向路（dot=%.3f）" % [i, dot], dot > 0.9)
		var origin_dir := (Vector2(0, 43) - here).normalized()
		max_off = maxf(max_off, rad_to_deg(acos(clampf(origin_dir.dot(want), -1.0, 1.0))))

		# 字得**刻在碑的正面那块宽板上**。第一版只转了 Mark 和 Chip 两个子节点，
		# 石板自己还朝着世界 +Z——「188」确实正对着路，却浮在柱子的一条 0.26m
		# 窄边上，从路边看是个挂在侧棱上的数字。而当时所有断言都是绿的：
		# 上面那条量的是 Mark 的朝向，从来没问过"字在不在正面那块板上"。
		var slab = _steles.get_child(i).get_node_or_null("Slab") as CSGBox3D
		_ck("碑 %d 有碑身石板" % i, slab != null)
		if slab == null:
			continue
		var slab_n := Vector2(slab.global_transform.basis.z.x, slab.global_transform.basis.z.z).normalized()
		_ck("碑 %d 石板正面也朝着路（dot=%.3f）" % [i, slab_n.dot(want)], slab_n.dot(want) > 0.9)
		var root_xz := Vector2(slab.global_position.x, slab.global_position.z)
		var offset := Vector2(mark.global_position.x, mark.global_position.z) - root_xz
		var depth: float = offset.dot(slab_n)
		_ck("碑 %d 字在石板正面那一侧（沿法线偏 %.2fm）" % [i, depth], depth > 0.05)
	_ck("朝向确实不是按世界原点算的（最大差 %.0f°）" % max_off, max_off > 30.0)

	# ---- 5. 第四块是"被人凿平的那块" ----
	# 郑铎在 villain_2_1 点名"我们从上面挖出一块刻字的石头"。这是反派说的
	# 一件具体的事，世界里得找得到——所以第四块必须有崩口，且字得比前三块浅。
	for i in range(_WANT):
		var chipped := _steles.get_child(i).get_node_or_null("Chip") != null
		_ck("碑 %d %s崩口" % [i, "有" if i == _WANT - 1 else "没有"], chipped == (i == _WANT - 1))
	var worn_mark = _steles.get_child(_WANT - 1).get_node_or_null("Mark") as Label3D
	var whole_mark = _steles.get_child(0).get_node_or_null("Mark") as Label3D
	if worn_mark != null and whole_mark != null:
		_ck("被凿的那块字更浅（%.2f vs %.2f）" % [worn_mark.modulate.v, whole_mark.modulate.v],
			worn_mark.modulate.v > whole_mark.modulate.v + 0.1)

	# ---- 6. 四句浮字中英都在，且不是同一句 ----
	# Localization.t() 查不到 key 时返回 key 自己、不报错也不返回空串 ——
	# 漏了英文的话中文界面一路正常，只有切到英文的那一屏露 key。
	for i in range(_steles.stele_line_keys.size()):
		var key: String = _steles.stele_line_keys[i]
		var zh: String = _loc.STRINGS.get("zh", {}).get(key, "")
		var en: String = _loc.STRINGS.get("en", {}).get(key, "")
		_ck("浮字 %d 有中文" % i, str(zh) != "")
		_ck("浮字 %d 有英文" % i, str(en) != "")
		_ck("浮字 %d 中英不是同一句" % i, str(zh) != str(en))
		_ck("浮字 %d 不是露出来的 key 本身" % i, str(zh) != key and str(en) != key)

	# ---- 7. 路过浮一次，停着不重弹 ----
	# 和 16 座驿站的 _pass_inside 同一个边沿触发。停在碑前一直看同一句话
	# 重弹，是"提示"变成"噪音"最快的办法。
	var s0: Vector3 = _steles.stele_positions[0]
	var line0: String = _loc.t(_steles.stele_line_keys[0])
	_park(Vector3(s0.x, 0, s0.z))
	await create_timer(0.3).timeout
	_eq("骑到碑前浮出那一句", _hud._pass_label.text, line0)
	_ck("浮字那一行是可见的（alpha=%.2f）" % _hud._pass_holder.modulate.a, _hud._pass_holder.modulate.a > 0.5)
	await create_timer(HUD_PASS_HOLD + 1.0).timeout
	_eq("3.2 秒后这句自己收走", _hud._pass_label.text, "")
	# 停在原地不动，不许再冒出来
	await create_timer(2.5).timeout
	_eq("停在碑前不动不重弹", _hud._pass_label.text, "")
	# 骑开再骑回来，必须还能再读到一次
	_park(Vector3(s0.x + 200.0, 0, s0.z + 200.0))
	await create_timer(0.3).timeout
	_park(Vector3(s0.x, 0, s0.z))
	await create_timer(0.3).timeout
	_eq("骑开再骑回来还能再读到", _hud._pass_label.text, line0)

	# ---- 8. 碑不是驿站 ----
	# 路过石碑不发旅币、不进"下一处"、不画打卡圈：它是一块石头。
	var coins_before: int = _gm.lvbi
	_park(Vector3(s0.x, 0, s0.z))
	await create_timer(0.3).timeout
	_eq("路过碑不发旅币", _gm.lvbi, coins_before)
	_ck("路过碑不进 _nearby_station_idx", _world._nearby_station_idx == -1,
		"idx=%d" % _world._nearby_station_idx)
	_ck("路过碑不画打卡圈", _world._check_in_prompt._prompt_target().is_empty(),
		"target=%s" % str(_world._check_in_prompt._prompt_target()))

	_finish(_backup)


func _nearest_road_point(p: Vector2) -> Vector2:
	var best := 1e9
	var at := Vector2.ZERO
	for c in _rd.points:
		var d := Vector2(c.x, c.z).distance_squared_to(p)
		if d < best:
			best = d
			at = Vector2(c.x, c.z)
	return at


## 点到线段的最短距离（XZ 平面）。树的 y 不参与——挡不挡视线是水平问题。
func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 1e-9:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / len2, 0.0, 1.0))


func _finish(backup: String) -> void:
	if backup != "":
		var wf = FileAccess.open(str(_gm.SAVE_PATH), FileAccess.WRITE)
		if wf != null:
			wf.store_string(backup)
			wf.close()
	print("=== [%s] PASS=%d FAIL=%d ===" % [
		"verify_road_steles" if _fails.is_empty() else "verify_road_steles",
		_oks, _fails.size()])
	for f in _fails:
		print("  FAILED: ", f)
	quit(0 if _fails.is_empty() else 1)
