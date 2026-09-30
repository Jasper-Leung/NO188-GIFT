extends SceneTree
## verify_tree_scatter.gd — 行道树放置与流式的无头回归
##
## 全部断言都打在 CPU 侧的 tree 列表上，**一个 GPU 状态都不读**：
## --headless 的 dummy renderer 下 MultiMesh.get_instance_transform() 一律返回
## 单位矩阵，从那边回读实例变换得到的数全是假的（草皮那套也是这么绕的）。
## 所以逐棵的位置/朝向/尺寸全部查 trees() 这个 CPU 侧的源，实例化本身只查
## "每格的 instance_count 等于该格的树数、节点位置等于格心"这种册子对账。
##
## 覆盖：贴地 / 离路净空（两侧都贴路肩）/ 弧长等间距 / 左右两侧 / 避让广场与驿站 /
##      地形边界 / 最小株距 / 逐次确定性 / 驻留集合与可见性 / 每格只建一次 /
##      节点位置与实例容量对账 / 半径与淡出带的关系 / 三角面预算。
##
## 用法： godot --headless --path . --script tools/verify_tree_scatter.gd

var _failures := 0

var _terrain: Node3D = null
var _trees_node: Node3D = null
var _centerlines: Array = []
var _terrain_size := 800.0

## 与 TreeScatter.gd 逐字一致的常量。故意各写一份：共享常量的话，
## "把常量改错"这类回归会两边一起错、测不出来。
const SPACING := 25.0
const SIDE_OFFSET := 11.0
const STAGGER := 0.5
const OFFSET_JITTER := 1.5
const CELL := 32.0
const BUILD_LEAD := CELL * 0.70710678
const RADIUS_DESKTOP := 150.0
const FADE_BAND := 40.0
const ROAD_CLEAR := 9.0
const MIN_GAP := 8.0
const PLAZA_CENTER := Vector2(0.0, 43.0)
const PLAZA_CLEAR := 16.0
const STATION_CLEAR := 10.0
const TERRAIN_MARGIN := 20.0
const SCALE_MIN := 6.0
const SCALE_MAX := 9.0
const TREE_TRIS := 52709


func _check(cond: bool, label: String) -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_failures += 1
		print("[FAIL] ", label)


func _initialize() -> void:
	call_deferred("_run")


## 暴力版"点到最近中心线线段的距离"。故意不共享 TreeScatter 自己的实现。
func _brute_dist_to_road(p: Vector2) -> float:
	var best := 1e9
	for line in _centerlines:
		for i in range(line.size() - 1):
			var a: Vector3 = line[i]
			var b: Vector3 = line[i + 1]
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var ap := p - Vector2(a.x, a.z)
			var l2 := ab.length_squared()
			var t := 0.0 if l2 < 1e-9 else clampf(ap.dot(ab) / l2, 0.0, 1.0)
			best = minf(best, ap.distance_to(ab * t))
	return best


func _road_loop_length() -> float:
	var line: Array = _centerlines[0]
	var total := 0.0
	for i in range(line.size() - 1):
		total += (line[i] as Vector3).distance_to(line[i + 1])
	total += (line[line.size() - 1] as Vector3).distance_to(line[0])
	return total


func _cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


func _make_trees(protected: Array) -> Node3D:
	var t = load("res://scripts/TreeScatter.gd").new()
	root.add_child(t)
	t.setup(_terrain, _centerlines, protected)
	return t


func _run() -> void:
	print("=== 行道树放置 / 流式 回归 ===")
	var TB = load("res://scripts/TerrainBuilder.gd")
	var RB = load("res://scripts/RoadBuilder.gd")

	_terrain = TB.new()
	root.add_child(_terrain)
	await process_frame
	var rb = RB.new()
	root.add_child(rb)
	rb.set_terrain_builder(_terrain)
	await process_frame
	_terrain_size = float(_terrain.get("TERRAIN_SIZE"))
	_centerlines = rb.get_all_centerlines()
	print("    中心线 %d 条, 地形 %.0fm, 环路长 %.1fm"
		% [_centerlines.size(), _terrain_size, _road_loop_length()])

	# 驿站铺装：随便放几个，只要树确实让开了就行
	var station_pos: Array = [
		Vector3(30.0, 0.0, 30.0),
		Vector3(-120.0, 0.0, -60.0),
		Vector3(80.0, 0.0, -150.0),
	]
	_trees_node = _make_trees(station_pos)
	await process_frame

	var radius: float = _trees_node.radius()
	var reach: float = _trees_node.reside_reach()
	var range_end: float = _trees_node.range_end()
	var items: Array = _trees_node.trees()
	print("    半径 %.0fm / 可见边界 %.1fm / 驻留半径 %.1fm / %d 格 / %d 棵"
		% [radius, range_end, reach, _trees_node.cell_count(), items.size()])

	_check(absf(radius - RADIUS_DESKTOP) < 1e-3,
		"本地（无 web/mobile feature）走 150m 档，实测 %.0fm" % radius)
	_check(range_end > radius and range_end <= radius + BUILD_LEAD + 1e-3,
		"可见边界 = 半径 + 格对角线提前量（%.1fm）" % range_end)
	_check(reach > range_end,
		"驻留半径比可见边界宽（%.1f > %.1f），焦点同格内移动不会漏节点" % [reach, range_end])

	# ---- 1. mesh 来源 ----
	var mesh: Mesh = _trees_node.tree_mesh()
	_check(mesh != null, "tree.glb 载入成功")
	if mesh != null:
		var aabb := mesh.get_aabb()
		var tris := 0
		for s in range(mesh.get_surface_count()):
			var arr: Array = mesh.surface_get_arrays(s)
			tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		print("    tree.glb: AABB %s size %s, %d 面, %d 三角面"
			% [str(aabb.position), str(aabb.size), mesh.get_surface_count(), tris])
		_check(absf(aabb.position.y) < 1e-3,
			"模型底面正好在 y=0（%.4f），所以实例原点放地面高度就等于贴地" % aabb.position.y)
		_check(absf(aabb.size.y - 1.0) < 0.01,
			"模型高 1.0m，所以 scale 值就是树高（实测 %.3f）" % aabb.size.y)

	# ---- 2. 数量与两侧 ----
	var loop_len := _road_loop_length()
	var per_side_expect: int = int(loop_len / SPACING)
	print("    环路 %.1fm / 间距 %.0fm → 每侧最多 %d 棵" % [loop_len, SPACING, per_side_expect])
	_check(items.size() > 0, "真的种出了树（%d 棵）" % items.size())

	var n_left := 0
	var n_right := 0
	for t in items:
		if int(t["side"]) > 0:
			n_left += 1
		else:
			n_right += 1
	print("    左侧 %d 棵 / 右侧 %d 棵" % [n_left, n_right])
	_check(n_left > 0 and n_right > 0, "左右两侧都种上了")
	_check(absi(n_left - n_right) <= 2,
		"左右数量基本对称（差 %d 棵）" % absi(n_left - n_right))
	_check(items.size() <= per_side_expect * 2,
		"总数不超过弧长允许的上限（%d <= %d）" % [items.size(), per_side_expect * 2])
	_check(items.size() >= int(per_side_expect * 2 * 0.85),
		"绝大多数候选都留下了（%d >= %.0f，被拒的只有交叉点/广场/驿站那几处）"
		% [items.size(), per_side_expect * 2 * 0.85])

	# ---- 3. 逐棵的放置属性 ----
	var worst_ground := 0.0
	var bad_ground := 0
	var worst_road := 1e9
	var far_road := -1e9
	var bad_road := 0
	var bad_plaza := 0
	var worst_plaza := 1e9
	var bad_station := 0
	var worst_station := 1e9
	var bad_bounds := 0
	var bad_scale := 0
	var bad_yaw := 0
	var half := 0.5 * _terrain_size - TERRAIN_MARGIN

	for t in items:
		var pos: Vector3 = t["pos"]
		var p2 := Vector2(pos.x, pos.z)

		var gy: float = absf(pos.y - float(_terrain.get_height_at(pos.x, pos.z)))
		worst_ground = maxf(worst_ground, gy)
		if gy >= 0.02:
			bad_ground += 1

		var rd: float = _brute_dist_to_road(p2)
		worst_road = minf(worst_road, rd)
		far_road = maxf(far_road, rd)
		if rd < ROAD_CLEAR - 1e-3:
			bad_road += 1

		var pd := p2.distance_to(PLAZA_CENTER)
		worst_plaza = minf(worst_plaza, pd)
		if pd < PLAZA_CLEAR - 1e-3:
			bad_plaza += 1

		var sd := 1e9
		for sp in station_pos:
			sd = minf(sd, p2.distance_to(Vector2(sp.x, sp.z)))
		worst_station = minf(worst_station, sd)
		if sd < STATION_CLEAR - 1e-3:
			bad_station += 1

		if absf(pos.x) > half or absf(pos.z) > half:
			bad_bounds += 1

		var s: float = t["scale"]
		if s < SCALE_MIN - 1e-3 or s > SCALE_MAX + 1e-3:
			bad_scale += 1
		var yaw: float = t["yaw"]
		if yaw < 0.0 or yaw >= TAU:
			bad_yaw += 1

	_check(bad_ground == 0, "每棵都贴地形高度（最大偏差 %.6fm）" % worst_ground)
	_check(bad_road == 0,
		"每棵离**任何**中心线 >= %.1fm（最近 %.3fm）" % [ROAD_CLEAR, worst_road])
	# 上界同样重要：树是"沿路等间距"排的，若某棵离路 40m 就说明法线算错了。
	_check(far_road <= SIDE_OFFSET + OFFSET_JITTER + 1.0,
		"每棵都压在路肩外沿那一圈（最远 %.3fm，标称 %.1f±%.1f）"
		% [far_road, SIDE_OFFSET, OFFSET_JITTER])
	_check(bad_plaza == 0, "每棵避开广场盘 %.1fm（最近 %.3fm）" % [PLAZA_CLEAR, worst_plaza])
	_check(bad_station == 0, "每棵避开驿站铺装 %.1fm（最近 %.3fm）" % [STATION_CLEAR, worst_station])
	_check(bad_bounds == 0, "每棵都在地形内（|x|,|z| <= %.0f）" % half)
	_check(bad_scale == 0, "每棵高度落在 [%.0f, %.0f]m" % [SCALE_MIN, SCALE_MAX])
	_check(bad_yaw == 0, "每棵朝向都是 [0, TAU) 里的合法角")

	# ---- 4. 弧长等间距 ----
	# 每侧的候选都落在 start + k*SPACING 这条格子上，被拒的只是从格子上消失，
	# 不会让幸存的树偏离格子。这就是"间隔一段距离"的准确含义。
	var off_grid := 0
	var side_arc := {}
	for t in items:
		var side: int = t["side"]
		var start: float = 0.0 if side > 0 else SPACING * STAGGER
		var r: float = fposmod(float(t["arc"]) - start, SPACING)
		if r > SPACING - 1e-3:
			r = 0.0
		if r > 1e-3:
			off_grid += 1
		if not side_arc.has(side):
			side_arc[side] = []
		side_arc[side].append(float(t["arc"]))
	_check(off_grid == 0,
		"每棵树都落在自己那一侧的弧长格点上（偏离 %d 棵）" % off_grid)
	var spacing_ok := true
	for side in side_arc:
		var arcs: Array = side_arc[side]
		arcs.sort()
		for i in range(1, arcs.size()):
			var d: float = float(arcs[i]) - float(arcs[i - 1])
			# 被拒的候选会在弧长上留下整数倍的空档，但绝不能小于一个间距
			var k := d / SPACING
			if d < SPACING - 1e-3 or absf(k - roundf(k)) > 1e-3:
				spacing_ok = false
	_check(spacing_ok, "同侧相邻两棵的弧长差是间距的整数倍（被拒处留空档，不会挤近）")

	# ---- 5. 最小株距 ----
	var clustered := 0
	var min_pair := 1e9
	for i in range(items.size()):
		var a: Vector3 = items[i]["pos"]
		var pa := Vector2(a.x, a.z)
		for j in range(i + 1, items.size()):
			var b: Vector3 = items[j]["pos"]
			var d := pa.distance_to(Vector2(b.x, b.z))
			min_pair = minf(min_pair, d)
			if d < MIN_GAP - 1e-3:
				clustered += 1
	_check(clustered == 0,
		"任意两棵都不小于 %.0fm（最近一对 %.3fm）" % [MIN_GAP, min_pair])

	# ---- 6. 逐次确定性 ----
	var t2 := _make_trees(station_pos)
	await process_frame
	var items2: Array = t2.trees()
	var same := items2.size() == items.size()
	if same:
		for i in range(items.size()):
			if items[i]["pos"] != items2[i]["pos"] \
					or absf(float(items[i]["scale"]) - float(items2[i]["scale"])) > 1e-9 \
					or absf(float(items[i]["yaw"]) - float(items2[i]["yaw"])) > 1e-9 \
					or int(items[i]["side"]) != int(items2[i]["side"]):
				same = false
				break
	_check(same, "同一份输入重跑一次，逐棵的位置/朝向/尺寸完全相同（%d 棵）" % items2.size())
	t2.queue_free()

	# ---- 7. 册子对账：每格的 instance_count == 该格的树数，节点在格心上 ----
	var by_cell := {}
	for t in items:
		var c := _cell_of(t["pos"])
		by_cell[c] = int(by_cell.get(c, 0)) + 1
	_check(_trees_node.cell_count() == by_cell.size(),
		"格数 == 有树的格子数（%d == %d）" % [_trees_node.cell_count(), by_cell.size()])
	var inst_total := 0
	var bad_cell_node := 0
	var bad_range := 0
	var bad_pos := 0
	for child in _trees_node.get_children():
		if not (child is MultiMeshInstance3D):
			continue
		var mmi: MultiMeshInstance3D = child
		var pos := Vector2(mmi.global_position.x, mmi.global_position.z)
		var c := Vector2i(int(floor(pos.x / CELL)), int(floor(pos.y / CELL)))
		if not by_cell.has(c):
			bad_cell_node += 1
			continue
		var want: int = by_cell[c]
		if mmi.multimesh.instance_count != want:
			bad_pos += 1
		inst_total += mmi.multimesh.instance_count
		if absf(pos.distance_to(_cell_center(c))) > 1e-3:
			bad_cell_node += 1
		if absf(mmi.visibility_range_end - range_end) > 1e-3:
			bad_range += 1
		if mmi.visibility_range_end_margin != FADE_BAND:
			bad_range += 1
		if mmi.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF:
			bad_range += 1
	_check(bad_cell_node == 0, "每个 MultiMeshInstance3D 都坐在自己格的格心上")
	_check(bad_pos == 0, "每格的 instance_count 等于该格的树数")
	_check(inst_total == items.size(),
		"所有格的实例数之和 == 总棵数（%d == %d）" % [inst_total, items.size()])
	_check(bad_range == 0,
		"每个节点都挂着可见边界 %.1fm + %.0fm 淡出带 + FADE_SELF" % [range_end, FADE_BAND])

	# ---- 8. 流式：驻留集合与可见性 ----
	# 驻留判据只可能命中"真的有树的格"：没有树的格从不建节点。所以期望集合
	# 按"有节点的格"逐格独立复算（格心距焦点 <= reside_reach），不去枚举那片
	# 邻域里几百个从没建过节点的空格——那样会把每个空格都误记成"少一格"。
	var node_of_cell := {}
	for child in _trees_node.get_children():
		if child is MultiMeshInstance3D:
			var mmi: MultiMeshInstance3D = child
			var q := Vector2(mmi.global_position.x, mmi.global_position.z)
			node_of_cell[Vector2i(int(floor(q.x / CELL)), int(floor(q.y / CELL)))] = mmi
	var probes := [
		Vector3(0.0, 0.0, 0.0),
		Vector3(40.0, 0.0, -30.0),
		Vector3(-200.0, 0.0, 150.0),
		Vector3(7.5, 0.0, 7.5),
		Vector3(300.0, 0.0, 0.0),
	]
	for p in probes:
		_trees_node.set_focus(p)
		_trees_node.tick(1.0)
		var f2 := Vector2(p.x, p.z)
		var wrong_vis := 0
		var want_n := 0
		var seen_n := 0
		for c in node_of_cell:
			var should: bool = _cell_center(c).distance_to(f2) <= reach
			if should:
				want_n += 1
			var vis: bool = node_of_cell[c].visible
			if vis:
				seen_n += 1
			if vis != should:
				wrong_vis += 1
		_check(wrong_vis == 0,
			"焦点在 %s 时驻留集合与判据逐格一致（错 %d，应有 %d / 实有 %d 格）"
			% [str(p), wrong_vis, want_n, seen_n])

	# ---- 8b. 加载半径内的树不能被整格 cull 掉 ----
	# visibility_range 量的是"相机到**格心**（MultiMesh 节点原点）"的距离，
	# 不是到树。格心比格内离相机最近的那棵树最多多出半个格对角线（BUILD_LEAD），
	# 所以必须保证：任何一棵还在加载半径内的树，它的格心都没越过可见边界。
	# 不然那棵树会在淡出带里被整格掐掉，看着就像"还有二十米树突然没了"。
	# 这就是 _range_end() 里 + BUILD_LEAD 那道补偿存在的理由，值得单独立一条。
	var bad_cull := 0
	for p in probes:
		_trees_node.set_focus(p)
		_trees_node.tick(1.0)
		for t in items:
			var tp: Vector3 = t["pos"]
			if p.distance_to(tp) > radius:
				continue
			var c3 := Vector3(_cell_center(_cell_of(tp)).x, 0.0,
				_cell_center(_cell_of(tp)).y)
			if p.distance_to(c3) > range_end + 1e-3:
				bad_cull += 1
	_check(bad_cull == 0,
		"加载半径 %.0fm 内的每棵树，其所在格心都没越过可见边界 %.1fm（越界 %d 棵）"
		% [radius, range_end, bad_cull])

	# 可见棵数不能超过总数，且骑到路上时应该确实有一批
	_trees_node.set_focus(Vector3(0.0, 0.0, 0.0))
	_trees_node.tick(1.0)
	var live: int = _trees_node.live_tree_count()
	print("    焦点在原点：%d 格驻留 / %d 棵在场（上界）/ 总计 %d 棵"
		% [_trees_node.live_cell_count(), live, items.size()])
	_check(live <= items.size(), "在场棵数不超过总数")
	_check(live > 0, "焦点在原点时确实有一批树在场（%d 棵）" % live)
	# 焦点骑到很远处时，近处的树必须全撤掉
	_trees_node.set_focus(Vector3(1000.0, 0.0, 1000.0))
	_trees_node.tick(1.0)
	_check(_trees_node.live_tree_count() == 0,
		"焦点在离场 1000m 外时一棵都不留（%d）" % _trees_node.live_tree_count())

	# ---- 9. 驻留期间零重建 ----
	# 节点是 setup() 里一次建好的，tick 只切 visible。会重建的话节点数会变。
	_trees_node.set_focus(Vector3(0.0, 0.0, 0.0))
	_trees_node.tick(1.0)
	var n_nodes := 0
	for child in _trees_node.get_children():
		if child is MultiMeshInstance3D:
			n_nodes += 1
	var hue := 0
	var pos2 := Vector3.ZERO
	var step := 15.0 / 60.0
	for i in range(1200):       # 20 秒 = 300m
		pos2 += Vector3(step, 0.0, 0.0)
		_trees_node.set_focus(pos2)
		_trees_node.tick(1.0 / 60.0)
		var n := 0
		for child in _trees_node.get_children():
			if child is MultiMeshInstance3D:
				n += 1
		if n != n_nodes:
			hue += 1
	_check(hue == 0,
		"300m 骑行全程节点数不变（%d 格，一次都没重建）" % n_nodes)
	print("    300m 骑行后：%d 格驻留 / %d 棵在场（上界）"
		% [_trees_node.live_cell_count(), _trees_node.live_tree_count()])

	# ---- 10. 三角面预算 ----
	_trees_node.set_focus(Vector3(0.0, 0.0, 0.0))
	_trees_node.tick(1.0)
	var live_tris: int = _trees_node.live_tree_count() * TREE_TRIS
	var total_tris: int = items.size() * TREE_TRIS
	print("    总三角面 %.1fM；焦点在原点在场上界 %.1fM（可见边界内还会被淡掉一批）"
		% [total_tris / 1000000.0, live_tris / 1000000.0])
	_check(live_tris <= total_tris, "在场三角面不超过总量")
	_check(total_tris <= 6000000,
		"全量三角面在 6M 以内（%.1fM）" % (total_tris / 1000000.0))

	_report()


func _report() -> void:
	print("\n[verify_tree_scatter] %s  (失败 %d)" % [
		"PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
