extends SceneTree
## verify_grass_scatter.gd — 草皮放置与流式的无头回归
##
## 全部断言都打在 CPU 侧的 generate_cell() 输出上，**一个 GPU 状态都不读**：
## --headless 的 dummy renderer 不编译着色器，而且 MultiMesh.get_instance_transform()
## 一律返回单位矩阵，从那边回读出来的数全是假的。
##
## 覆盖：贴地高度 / 离路距离 / 避让广场与驿站 / 地形边界 / 格子 AABB /
##      逐格确定性 / 格子间独立性 / 各环产量与卡片尺寸 / 驻留环几何 / 池预算 /
##      焦点移动的进出集合 / **骑行中驻留格零重建零隐藏** / 骑行的构建预算。
##
## 用法： godot --headless --path . --script tools/verify_grass_scatter.gd

var _failures := 0

var _terrain: Node3D = null
var _grass: Node3D = null
var _terrain_size := 800.0
var _radius := 200.0
var _rings := 4

const CELL := 32.0
const DENSITY := 5.0
const RING_DIST := [30.0, 70.0, 130.0]
const RING_DENSITY := [DENSITY, 2.5, 1.0, 0.35]
const RING_SCALE := [1.0, 1.0, 1.8, 3.2]
const RING_COUNT := 4
const RING_CAP := [5120, 2560, 1024, 358]
const BUILD_LEAD := CELL * 0.70710678
const POOL_MARGIN := 1.15
const POOL_SLACK := 6
const ROAD_CLEAR := 8.0
const ROAD_INDEX_CELL := 16.0
const PLAZA_CLEAR_RADIUS := 14.0
const PLAZA_CENTER := Vector2(0.0, 43.0)
const STATION_CLEAR := 8.0
const TERRAIN_MARGIN := 20.0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_failures += 1
		print("[FAIL] ", label)


func _initialize() -> void:
	call_deferred("_run")


func _cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)


func _cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / CELL)), int(floor(z / CELL)))


## GrassScatter 自己的分环逻辑的独立复算。故意不共享代码。
## 最后一段到 _radius，所以走的是"越过几个分界"。
func _ring_of(dist: float, radius: float, rings: int) -> int:
	for i in range(rings - 1):
		if dist <= minf(RING_DIST[i], radius) + BUILD_LEAD:
			return i
	return rings - 1


## 暴力版"点离最近道路中心线多远"，用来独立复核 GrassScatter 自己的空间索引。
## 故意不共享任何代码：否则索引和被索引的同一份数据，错了会一起错。
func _brute_dist_to_road(p: Vector2, centerlines: Array) -> float:
	var best := 1e9
	for line in centerlines:
		for i in range(line.size() - 1):
			var a: Vector3 = line[i]
			var b: Vector3 = line[i + 1]
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var ap := p - Vector2(a.x, a.z)
			var l2 := ab.length_squared()
			var t := 0.0 if l2 < 1e-9 else clampf(ap.dot(ab) / l2, 0.0, 1.0)
			best = minf(best, ap.distance_to(ab * t))
	return best


func _run() -> void:
	print("=== 草皮放置 / 流式 回归 ===")
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

	# 拿真实的中心线，别拿假的：离路断言的意义全在"离真路多远"上。
	var centerlines: Array = rb.get_all_centerlines()
	print("    中心线 %d 条, 地形 %.0fm" % [centerlines.size(), _terrain_size])

	_grass = load("res://scripts/GrassScatter.gd").new()
	root.add_child(_grass)

	# 站点铺装：随便放几个，只要草确实让开了就行
	var station_pos: Array = [
		Vector3(30.0, 0.0, 30.0),
		Vector3(-120.0, 0.0, -60.0),
		Vector3(80.0, 0.0, -150.0),
	]
	_grass.setup(_terrain, centerlines, station_pos)
	await process_frame
	_radius = float(_grass.get("_radius"))
	_rings = int(_grass.ring_count())
	var reach := float(_grass.ring_reach(_rings - 1))
	print("    加载半径 %.0fm / %d 层环 / 最外盘 %.1fm / 池 %d 槽" % [
		_radius, _rings, reach, _grass.pool_size()])
	_check(absf(_radius - 200.0) < 1e-3,
		"本地（无 web/mobile feature）走 200m 档，实测 %.0fm" % _radius)
	_check(_rings == RING_COUNT, "200m 下四层环都非空（实测 %d 层）" % _rings)
	for r in range(_rings):
		var bound: float = _radius if r == _rings - 1 else minf(RING_DIST[r], _radius)
		_check(absf(float(_grass.ring_reach(r)) - (bound + BUILD_LEAD)) < 1e-3,
			"ring %d 的盘外沿 = %.1fm + 提前量" % [r, bound])

	# ---- 1. 卡片 mesh ----
	var mesh: ArrayMesh = _grass.build_card_mesh()
	var ma: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = ma[Mesh.ARRAY_VERTEX]
	var tris: PackedInt32Array = ma[Mesh.ARRAY_INDEX]
	_check(verts.size() == 12, "卡片是 12 顶点（两片各 3 排），实测 %d" % verts.size())
	_check(tris.size() == 24, "卡片是 8 三角形，索引 %d 个" % tris.size())
	_check(ma[Mesh.ARRAY_NORMAL] != null and (ma[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() == 12,
		"卡片带法线（着色器要拿它做双面翻转）")

	# ---- 2. 逐丛的放置属性 ----
	# 取焦点周围一圈格子，覆盖到路、广场、驿站、地形边界各一处。
	# 每层环至少各来一格，否则近/中/远三种放置规则只测到一种。
	var probe_cells: Array[Vector2i] = []
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			probe_cells.append(_cell_of(float(dx) * CELL, float(dz) * CELL))
	# 三个驿站各自脚下 / 旁边的格子（站点坐标换成 CELL=32 后的格号）
	probe_cells.append(_cell_of(30.0, 30.0))
	probe_cells.append(_cell_of(-120.0, -60.0))
	probe_cells.append(_cell_of(80.0, -150.0))
	# 广场盘（中心 (0,43)）
	probe_cells.append(_cell_of(PLAZA_CENTER.x, PLAZA_CENTER.y))
	# 地形边界外侧：TERRAIN_MARGIN 之内仍要有草
	probe_cells.append(_cell_of(360.0, 360.0))

	var total := 0
	var worst_ground := 0.0
	var worst_road := 1e9
	var worst_plaza := 1e9
	var worst_station := 1e9
	var worst_aabb := 0.0
	var bad_aabb := 0
	var bad_bounds := 0
	var bad_ground := 0
	var bad_road := 0
	var bad_plaza := 0
	var bad_station := 0
	var bad_index := 0
	var bad_clear := 0
	var half := 0.5 * _terrain_size - TERRAIN_MARGIN

	for c in probe_cells:
		var tufts: Dictionary = _grass.generate_cell(c, 0)
		var poss: PackedVector3Array = tufts["pos"]
		var center := _cell_center(c)
		for p in poss:
			total += 1
			var p2 := Vector2(p.x, p.z)

			# 贴地
			var gy: float = absf(p.y - float(_terrain.get_height_at(p.x, p.z)))
			worst_ground = maxf(worst_ground, gy)
			if gy >= 0.02:
				bad_ground += 1

			# 在自己格子的 AABB 内
			var ax := absf(p.x - center.x) - CELL * 0.5
			var az := absf(p2.y - center.y) - CELL * 0.5
			var aabb := maxf(ax, az)
			if aabb > 1e-4:
				bad_aabb += 1
			worst_aabb = maxf(worst_aabb, aabb)

			# 地形内
			if absf(p.x) > half or absf(p2.y) > half:
				bad_bounds += 1

			# 离路
			var rd: float = _grass.distance_to_road(p2)
			# 暴力复核很贵（每丛要扫全部约 912 段），每 40 丛抽一丛。
			# 这正是 GrassScatter 自己在运行时避开的那笔开销。
			# 索引只保证"真距离 <= ROAD_INDEX_CELL"时精确——扫 3×3 邻域
			# 最多覆盖这么远。再远的点索引会**偏大**（报 91m 而真值 61m），
			# 那是设计上接受的：让位判定只关心 <8m，那一段完全在精确区内。
			if total % 40 == 0:
				var rb_true: float = _brute_dist_to_road(p2, centerlines)
				if rb_true <= ROAD_INDEX_CELL:
					if absf(rd - rb_true) > 0.05:
						bad_index += 1
						print("    索引在精确区内却与暴力不一致 @%s: 索引 %.3f vs 暴力 %.3f"
							% [str(p2), rd, rb_true])
				elif rd <= ROAD_CLEAR:
					bad_index += 1
					print("    索引漏掉了路 @%s: 暴力只有 %.3fm" % [str(p2), rb_true])
				# clear_of_road 才是运行时的热点（只查本格），它必须和
				# "暴力距离 >= 半径"**逐点同号**。这是让位判定唯一依赖的性质。
				var co: bool = _grass.call("clear_of_road", p2, ROAD_CLEAR)
				if co != (rb_true >= ROAD_CLEAR):
					bad_clear += 1
					print("    clear_of_road 与暴力不一致 @%s: clear=%s 暴力=%.3fm"
						% [str(p2), str(co), rb_true])
			worst_road = minf(worst_road, rd)
			if rd < ROAD_CLEAR - 1e-3:
				bad_road += 1

			# 广场盘
			var pd := p2.distance_to(PLAZA_CENTER)
			worst_plaza = minf(worst_plaza, pd)
			if pd < PLAZA_CLEAR_RADIUS:
				bad_plaza += 1

			# 驿站铺装
			var sd := 1e9
			for sp in station_pos:
				sd = minf(sd, p2.distance_to(Vector2(sp.x, sp.z)))
			worst_station = minf(worst_station, sd)
			if sd < STATION_CLEAR:
				bad_station += 1

	print("    抽样 %d 丛 / %d 格" % [total, probe_cells.size()])
	_check(total > 0, "抽样确实产出了草")
	_check(bad_ground == 0,
		"每丛都贴地形高度（最大偏差 %.6fm）" % worst_ground)
	_check(bad_road == 0,
		"每丛离路 >= %.1fm（最近 %.3fm）" % [ROAD_CLEAR, worst_road])
	_check(bad_plaza == 0,
		"每丛避开广场盘 %.1fm（最近 %.3fm）" % [PLAZA_CLEAR_RADIUS, worst_plaza])
	_check(bad_station == 0,
		"每丛避开驿站铺装 %.1fm（最近 %.3fm）" % [STATION_CLEAR, worst_station])
	_check(bad_bounds == 0, "每丛都在地形内（|x|,|z| <= %.0f）" % half)
	_check(bad_aabb == 0,
		"每丛都在自己格子的 AABB 内（最多越界 %.6fm）" % worst_aabb)
	_check(bad_index == 0,
		"道路空间索引在 %.0fm 内与暴力最近段一致（抽样复核）" % ROAD_INDEX_CELL)
	_check(bad_clear == 0,
		"clear_of_road（热点路径，只查本格）与暴力让位判定逐点一致")

	# ---- 3. 密度 / 各环产量 ----
	# 找一格离路最远的空地来量"满密度"：路会把 8m 以内的草让开，
	# 挑中路边的一格量出来的数字是路肩，不是密度上限。
	var open_cell := Vector2i(0, 0)
	var open_d := -1.0
	for dx in range(-6, 7):
		for dz in range(-6, 7):
			var cc := Vector2i(dx, dz)
			var d: float = float(_grass.distance_to_road(_cell_center(cc)))
			if d > open_d:
				open_d = d
				open_cell = cc
	print("    最空的一格 %s，离路 %.1fm" % [str(open_cell), open_d])
	var full: Dictionary = _grass.generate_cell(open_cell, 0)
	var full_n: int = (full["pos"] as PackedVector3Array).size()
	_check(full_n <= int(CELL * CELL * DENSITY),
		"单格产量 <= CELL²*DENSITY（%d <= %d）" % [full_n, int(CELL * CELL * DENSITY)])
	_check(full_n > int(CELL * CELL * DENSITY * 0.9),
		"离路最远的一格产量接近满值（%d / %d）" % [full_n, int(CELL * CELL * DENSITY)])
	# 四个并行数组必须等长，否则下标对不上就是错位的草
	var lens := [(full["pos"] as PackedVector3Array).size(),
		(full["rot"] as PackedFloat32Array).size(),
		(full["scl"] as PackedFloat32Array).size(),
		(full["seed"] as PackedColorArray).size()]
	_check(lens[0] == lens[1] and lens[1] == lens[2] and lens[2] == lens[3],
		"四个并行数组等长（%s）" % str(lens))

	# 每层环：产量单调递减，都不超过该层的上限，池容量也装得下，
	# 而且越远的环卡片必须真的更大（否则"放大卡片换实例数"没发生）。
	var ring_n := []
	var ring_ok := true
	for r in range(_rings):
		var g: Dictionary = _grass.generate_cell(open_cell, r)
		var n: int = (g["pos"] as PackedVector3Array).size()
		ring_n.append(n)
		if n > int(CELL * CELL * RING_DENSITY[r]):
			ring_ok = false
		if n > RING_CAP[r]:
			ring_ok = false
		var smax := 0.0
		for s in (g["scl"] as PackedFloat32Array):
			smax = maxf(smax, s)
		if smax < 0.72 * RING_SCALE[r]:
			ring_ok = false
	print("    各环产量 %s（池容量 %s）" % [str(ring_n), str(RING_CAP)])
	_check(ring_ok,
		"各环产量不超 CELL²*RING_DENSITY、不超 RING_CAP，且卡片按 RING_SCALE 变大")
	var mono := true
	for r in range(1, _rings):
		if ring_n[r] > ring_n[r - 1]:
			mono = false
	_check(mono, "环号越大产量越少（%s）" % str(ring_n))
	# 同一格在不同环上必须是**不同**的草：叠加环各自持有独立的一份
	_check(not _same(_grass.generate_cell(open_cell, 0), _grass.generate_cell(open_cell, 3)),
		"同一格在不同环上生成的内容不同（各环是独立的份）")
	# 环分界就是 RING_DIST（外沿还要加上提前量）
	var edge_ok := true
	for r in range(_rings - 1):
		var b: float = minf(RING_DIST[r], _radius) + BUILD_LEAD
		if _ring_of(b - 0.01, _radius, _rings) != r:
			edge_ok = false
		if _ring_of(b + 0.01, _radius, _rings) != r + 1:
			edge_ok = false
	_check(edge_ok, "环边界落在 RING_DIST + 提前量上（%.0f/%.0f/%.0fm）"
		% [RING_DIST[0], RING_DIST[1], RING_DIST[2]])

	# ---- 4. 逐格确定性 + 格子间独立性 ----
	var a1: Dictionary = _grass.generate_cell(Vector2i(3, -4), 0)
	# 先访问另外 50 格，再回来
	for k in range(50):
		_grass.generate_cell(Vector2i(100 + k, -70 + k), 0)
	var a2: Dictionary = _grass.generate_cell(Vector2i(3, -4), 0)
	_check(_same(a1, a2), "同一格访问两次结果逐字节相同，且不受中间 50 格影响")
	# 反序访问
	for k in range(50, -1, -1):
		_grass.generate_cell(Vector2i(-200 + k, 130 - k), 0)
	var a3: Dictionary = _grass.generate_cell(Vector2i(3, -4), 0)
	_check(_same(a1, a3), "访问顺序打乱后同一格结果仍然相同")
	# 邻格互不干扰
	var n1: Dictionary = _grass.generate_cell(Vector2i(3, -3), 0)
	var n2: Dictionary = _grass.generate_cell(Vector2i(4, -4), 0)
	_check(not _same(n1, a1), "邻格内容确实不同（不是复制粘贴）")
	_check(not _same(n2, n1), "另一邻格内容也不同")

	# ---- 5. 驻留环几何（提前量） ----
	_grass.reset()
	_grass.set_focus(Vector3(0.0, 0.0, 0.0))
	_grass.tick(1.0)
	var keys: Array = _grass.live_cell_keys()
	var over := 0
	var worst_reach := 0.0
	var f2 := Vector2(0.0, 0.0)
	for c in keys:
		var d := _cell_center(c).distance_to(f2)
		worst_reach = maxf(worst_reach, d)
		if d > reach + 1e-4:
			over += 1
	_check(over == 0,
		"每个驻留格的中心距 <= 最外盘外沿 %.2fm（实测最远 %.2fm）"
		% [reach, worst_reach])
	_check(keys.size() > 0, "焦点在原点时确实驻留了 %d 个格子" % keys.size())
	# 面积合理性：驻留判据用的是最外盘（含提前量）的圆，不是 RADIUS 的圆——
	# 按后者算会低估 20% 然后误报。
	var expect_cells := int(PI * pow(reach, 2.0) / (CELL * CELL))
	_check(absi(keys.size() - expect_cells) <= expect_cells / 6 + 4,
		"驻留格数与 π·reach²/CELL² 相符（%d，实测 %d）"
		% [expect_cells, keys.size()])
	# 分环必须真的按距离铺开，每层都有人
	var ring_hist := {}
	for c in keys:
		var b: int = _ring_of(_cell_center(c).distance_to(f2), _radius, _rings)
		ring_hist[b] = int(ring_hist.get(b, 0)) + 1
	print("    驻留格按环分布 %s" % str(ring_hist))
	_check(ring_hist.size() == _rings,
		"半径 %.0fm 下 %d 层都有驻留格（分布 %s）" % [_radius, _rings, str(ring_hist)])
	# 驻留格记录的活动环必须和实测距离一致
	var want_ring: Dictionary = _grass.get("_want_ring")
	var ring_mismatch := 0
	for c in keys:
		if int(want_ring.get(c, -1)) != _ring_of(_cell_center(c).distance_to(f2), _radius, _rings):
			ring_mismatch += 1
	_check(ring_mismatch == 0,
		"每格记录的活动环与它的实际距离一致（不符 %d）" % ring_mismatch)
	# 叠加环：最内几层的盘更大，落进来的格必须**同时**占住外层的槽位
	var slot_of: Array = _grass.get("_slot_of_cell")
	var nest_ok := true
	var nest_n := 0
	for c in keys:
		var d := _cell_center(c).distance_to(f2)
		for r in range(_rings):
			var should: bool = d <= float(_grass.ring_reach(r))
			if slot_of[r].has(c) != should:
				nest_ok = false
		nest_n = slot_of[0].size()
	_check(nest_ok,
		"每格在它落进的每一层盘里各占一个槽位，层与层严格嵌套（最内层 %d 槽）" % nest_n)

	# 驻留格是"已分配槽位"，草是分 tick 灌进去的。开局要把整个环铺满，
	# 所以这里查的是"排干队列后每个驻留格都真的有草"。
	var fill_t0 := Time.get_ticks_msec()
	var fill_ticks := 1
	while _grass.get("_pending").size() > 0 and fill_ticks < 400:
		_grass.tick(0.2)
		fill_ticks += 1
	var fill_ms := Time.get_ticks_msec() - fill_t0
	var resident: int = keys.size()
	print("    驻留环 %d 格（%d 个槽位）铺满用了 %d 个 tick（%dms）"
		% [resident, _grass.live_buffer_tuft_count(), fill_ticks, fill_ms])
	_check(_grass.get("_pending").size() == 0, "队列已排干")
	# 铺满是 CPU 总预算的问题：按 BUILD_MS_BULK 一 tick 一 tick地花。
	_check(fill_ms < 2500,
		"开局铺满整个环 <= 2.5s（实测 %dms / %d tick）" % [fill_ms, fill_ticks])
	# 每个 MultiMesh 的实例数不能超过它自己开好的容量（近/远池容量不同）
	var over_cap := 0
	var pool: Array = _grass.get("_pool")
	for r in range(_rings):
		for c in slot_of[r].keys():
			var mm: MultiMesh = pool[slot_of[r][c]].multimesh
			if mm.visible_instance_count > mm.instance_count:
				over_cap += 1
	_check(over_cap == 0, "没有哪个 MultiMesh 的实例数超过它自己开好的容量")

	# ---- 6. 池预算 ----
	# 每层按自己的盘面积给槽位，不能一层容量通吃
	var pool_lo: PackedInt32Array = _grass.get("_ring_pool_lo")
	var pool_hi: PackedInt32Array = _grass.get("_ring_pool_hi")
	var pool_ok := true
	var buf_inst := 0
	for r in range(_rings):
		var rr: float = float(_grass.ring_reach(r))
		var want_slots := int(PI * rr * rr / (CELL * CELL) * POOL_MARGIN) + POOL_SLACK
		if pool_hi[r] - pool_lo[r] != want_slots:
			pool_ok = false
		print("    ring %d：盘 %.1fm，%d 槽 × %d 丛 = %d 个实例"
			% [r, rr, pool_hi[r] - pool_lo[r], RING_CAP[r],
				(pool_hi[r] - pool_lo[r]) * RING_CAP[r]])
		buf_inst += (pool_hi[r] - pool_lo[r]) * RING_CAP[r]
	_check(pool_ok, "每层槽位数 = π·reach²/CELL² × %.2f + %d" % [POOL_MARGIN, POOL_SLACK])
	_check(_grass.pool_size() == pool_hi[_rings - 1],
		"池大小就是最外层的上界（%d）" % _grass.pool_size())
	var buf_mb := float(buf_inst) * 64.0 / 1048576.0
	print("    MultiMesh buffer 约 %.1fMB（一层容量通吃会是 %.1fMB）"
		% [buf_mb, float(_grass.pool_size()) * 5120.0 * 64.0 / 1048576.0])
	_check(buf_mb < 32.0, "池 buffer < 32MB（实测 %.1fMB）" % buf_mb)
	# 一格只画它活动环那一份：draw call 数 = 有草的驻留格数
	var empty_cells := 0
	var active_ring: Dictionary = _grass.get("_active_ring")
	for c in keys:
		var ar: int = int(active_ring.get(c, -1))
		if ar < 0 or pool[slot_of[ar][c]].multimesh.visible_instance_count == 0:
			empty_cells += 1
	_check(_grass.live_draw_call_count() == resident - empty_cells,
		"每格只画活动环那一份（%d 格 / %d call / %d 格空）"
		% [resident, _grass.live_draw_call_count(), empty_cells])
	print("    可见 %d 丛，buffer 里 %d 丛"
		% [_grass.live_tuft_count(), _grass.live_buffer_tuft_count()])
	# 叠加环的代价：buffer 里每格最多 RING_COUNT 份，可见只有一份
	_check(_grass.live_buffer_tuft_count() < int(expect_cells * CELL * CELL * DENSITY * 0.5),
		"分环把 buffer 里的实例数压到全密度一半以下（%d）"
		% _grass.live_buffer_tuft_count())
	_check(_grass.live_tuft_count() < 200000,
		"可见丛数在 20 万以内（%d）" % _grass.live_tuft_count())

	# ---- 7. 移动焦点：进出集合 ----
	var before: Dictionary = {}
	for c in keys:
		before[c] = true
	# 期望的"必须仍然驻留"和"必须已经离开"
	var want: Dictionary = _grass.call("_desired_cells")
	for p in [Vector3(0.0, 0.0, 0.0), Vector3(40.0, 0.0, -30.0),
			Vector3(-200.0, 0.0, 150.0), Vector3(7.5, 0.0, 7.5)]:
		_grass.set_focus(p)
		_grass.tick(1.0)
		var w: Dictionary = _grass.call("_desired_cells")
		var live: Array = _grass.live_cell_keys()
		var missing := 0
		for c in w.keys():
			if not live.has(c):
				missing += 1
		var stale := 0
		for c in live:
			if not w.has(c):
				stale += 1
		_check(missing == 0 and stale == 0,
			"焦点在 %s 时驻留集合与期望完全一致（少 %d / 多 %d）" % [str(p), missing, stale])
	# 相邻格移动：不该整片重来
	_grass.set_focus(Vector3(0.0, 0.0, 0.0))
	_grass.tick(1.0)
	var k0: Dictionary = _grass.get("_slot_of_cell")[_rings - 1]
	_grass.set_focus(Vector3(CELL, 0.0, 0.0))   # 正好跨一格
	_grass.tick(1.0)
	var k1: Dictionary = _grass.get("_slot_of_cell")[_rings - 1]
	var kept := 0
	for c in k0.keys():
		if k1.has(c):
			kept += 1
	_check(kept >= int(k0.size() * 0.9),
		"跨一格移动保留了绝大多数格子（%d / %d），没有整片重建" % [kept, k0.size()])

	# ---- 8. 骑行中驻留格零重建、零隐藏 ----
	# 这是本次改动的核心断言。旧实现里每格记一个会变的档位，跨过档位边界
	# 就拆槽归零再排队重建，离玩家最近的格排在几十名之后——脚边的草会空掉
	# 一秒多再冒出来。现在每格在每一层盘里各有一份，切环只是显示/隐藏。
	_grass.reset()
	_grass.set_focus(Vector3(0.0, 0.0, 0.0))
	_grass.tick(1.0)
	var warm := 0
	while _grass.get("_pending").size() > 0 and warm < 400:
		_grass.tick(0.2)
		warm += 1
	var build_count: Dictionary = _grass.get("_build_count")
	_check(build_count.size() > 0, "开局建了 %d 个 (格,环) 份" % build_count.size())
	var start_slot: Dictionary = _grass.get("_slot_of_cell")[_rings - 1].duplicate()

	# 边骑边查：每一帧都要求"活动环的那份一定是亮的"
	var pos2 := Vector3.ZERO
	var step := 15.0 / 60.0     # 15m/s, 60Hz
	var t := 0.0
	var hidden_hits := 0
	var max_builds := 0
	var worst_frame_ms := 0.0
	var over_10ms := 0
	# 逐帧的耗时全存下来，算「削掉前 K 名之后的最慢帧」。
	#
	# 为什么不能只判最大值：最大值量的是**机器**不是代码。这台机器上后台跑着
	# 别的程序时，同一份代码连跑三次量到最慢帧 20.00 / 32.00 / 29ms，而单帧
	# 均值稳在 0.635 / 0.671 / 0.652ms、铺满 tick 47/47/45 —— 均值稳而最大值
	# 乱跳，就是外部噪声。同一份 CLAUDE.md 里已经写着这条判据
	# （"最慢的一帧这类极值断言量的是机器不是代码"），而这条断言当初守的
	# 回归是"ring 0 一格建不完就整帧丢出去"——那个 bug 的特征是**很多**帧
	# 超标，不是**三帧**超标。所以削掉最前面的少数几个尖峰再判，既守得住
	# 原来那个回归，又不会被调度器的一次抢占判红。
	#
	# 用 usec 而不是 msec：msec 分辨率下每帧耗时只能取整数，读出来永远是
	# 20.00 / 32.00 / 29.00 这种整数字，一点真实分布都看不出来。
	var frame_us: Array[int] = []
	var t0 := Time.get_ticks_msec()
	while t < 20.0:            # 20 秒 = 300m
		pos2 += Vector3(step, 0.0, 0.0)
		_grass.set_focus(pos2)
		var f0 := Time.get_ticks_usec()
		_grass.tick(1.0 / 60.0)
		var fus := Time.get_ticks_usec() - f0
		var fms := float(fus) / 1000.0
		frame_us.append(fus)
		worst_frame_ms = maxf(worst_frame_ms, fms)
		if fms >= 10.0:
			over_10ms += 1
		# 驻留中的格子，活动环那一份必须是可见且有内容的
		var act: Dictionary = _grass.get("_active_ring")
		var soc: Array = _grass.get("_slot_of_cell")
		for c in act.keys():
			var r: int = act[c]
			var mmi = pool[soc[r][c]]
			if mmi.multimesh.visible_instance_count > 0 and not mmi.visible:
				hidden_hits += 1
		t += 1.0 / 60.0
	var ride_ms := Time.get_ticks_msec() - t0
	# 削掉前 TRIM 个尖峰之后的最慢帧。TRIM=3 判的是"第 4 慢的那一帧"：
	# 三次抢占以内的尖峰放过去，成片超标照样红。
	const TRIM := 3
	var sorted_us := frame_us.duplicate()
	sorted_us.sort()
	var trimmed_worst_ms := 0.0
	if sorted_us.size() > TRIM:
		trimmed_worst_ms = float(sorted_us[sorted_us.size() - 1 - TRIM]) / 1000.0
	var over_20ms := 0
	var over_40ms := 0
	for u in frame_us:
		var f := float(u) / 1000.0
		if f >= 20.0:
			over_20ms += 1
		if f >= 40.0:
			over_40ms += 1
	_check(hidden_hits == 0,
		"骑行全程没有一格是「建好了却不显示」的（隐藏 %d 次）" % hidden_hits)

	# 排干队列再对账：最后几帧 _retarget 刚入队的新格还没建，不排干的话
	# 它们会以"驻留但构建次数 0"混进统计里。
	var tail := 1
	while _grass.get("_pending").size() > 0 and tail < 200:
		_grass.tick(0.2)
		tail += 1
	_check(_grass.get("_pending").size() == 0, "骑行后队列也能排干（%d tick）" % tail)

	# 驻留期间每份只建一次
	build_count = _grass.get("_build_count")
	var soc2: Array = _grass.get("_slot_of_cell")
	var rebuilt := 0
	var survivors := 0
	for r in range(_rings):
		for c in soc2[r].keys():
			survivors += 1
			var n: int = int(build_count.get(Vector3i(c.x, c.y, r), 0))
			max_builds = maxi(max_builds, n)
			if n != 1:
				rebuilt += 1
	# 300m 直线骑行，焦点单调移动，格心到焦点的距离沿线是凸的，
	# 所以"起终点都在最外盘内"的格子全程驻留——留存数可以精确算出来对照。
	_grass.set_focus(Vector3.ZERO)
	var d0: Dictionary = _grass.call("_desired_cells")
	_grass.set_focus(pos2)
	var d1: Dictionary = _grass.call("_desired_cells")
	var expect_stay := 0
	for c in d0.keys():
		if d1.has(c):
			expect_stay += 1
	var stayed := 0
	for c in start_slot.keys():
		if d1.has(c):
			stayed += 1
	var gone := start_slot.size() - stayed
	print("    300m 骑行：%d 格留存（几何上应 %d）/ %d 格出环销毁 / 共建 %d 份，单份最多建 %d 次"
		% [stayed, expect_stay, gone, build_count.size(), max_builds])
	_check(stayed == expect_stay,
		"留存格数与两圆交集相符（几何 %d，实测 %d）" % [expect_stay, stayed])
	_check(stayed > 20, "有足够多的格子横跨整段骑行（%d 格留存）" % stayed)
	_check(gone > 10, "确实有格子出环被销毁（%d 格）" % gone)
	_check(rebuilt == 0,
		"驻留中的 (格,环) 份一次都没有被重建（%d / %d 份构建次数 != 1）"
		% [rebuilt, survivors])
	_check(max_builds <= 1,
		"每一份的累计构建次数都 <= 1（实测最大 %d）" % max_builds)

	# ---- 9. 骑行的单 tick 构建预算 ----
	#
	# 判据是「削掉前 3 个尖峰之后的最慢帧」，不是绝对最大值：见上面 frame_us
	# 那段注释——绝对最大值量的是机器，成片超标才量的是代码。原始最大值照样
	# 打出来，但它只是**诊断信息**，判红判的是它削掉尖峰后的邻居。
	print("    1200 帧里 >=10ms %d 帧 / >=20ms %d 帧 / >=40ms %d 帧（绝对最慢 %.2fms，"
		% [over_10ms, over_20ms, over_40ms, worst_frame_ms]
			+ "削掉前 %d 个尖峰后最慢 %.2fms）" % [TRIM, trimmed_worst_ms])
	_check(trimmed_worst_ms < 20.0,
		"骑行中最慢的一帧 < 20ms（削掉前 %d 个尖峰后 %.2fms；绝对最慢 %.2fms "
		% [TRIM, trimmed_worst_ms, worst_frame_ms]
			+ "只作诊断）")
	#
	# 下面这条是"建格工作塌进少数几帧"的正面判据。阈值是 40ms 而不是 20ms，
	# 这不是随手挑的：把 BUILD_MS_STREAM 从 6 抬到 600（故意让一个 tick 建完
	# 整个环）之后量到的是**最慢帧 155.51ms、>=40ms 的只有 9 帧、
	# >=20ms 的 9 帧、>=10ms 的 9 帧**——也就是说 >=10ms / >=20ms 那两条
	# 计数在真出 bug 时反而**变绿**（干净跑是 23~25 帧）。
	#
	# 原因很直白：总工作量是恒定的（785ms vs 干净跑的 787ms，一模一样），
	# 预算掐开后工作只是从 24 帧摊开变成 9 帧堆在一处，**帧数下降、峰值暴涨**。
	# 所以判据不能数"慢帧有多少"，只能看"最慢的那几帧有多慢"——
	# 上面那条削尖峰后的最慢帧（干净 13~14ms vs 变异 97.61ms，差 7 倍）才是
	# 真正有分辨力的那一条。这条 40ms 的计数是它的备份：万一某天尖峰数超过
	# TRIM 而把真峰值削掉了，这条会先红。
	_check(over_40ms <= 2,
		"没有帧慢到 40ms 以上（实测 %d/1200）" % over_40ms)
	# 1200 帧模拟 20 秒骑行：均摊到每帧的 CPU 预算必须远低于 16.6ms 的帧时间
	print("    20s 骑行模拟（1200 帧, 15m/s, 300m）共 %dms，单帧均值 %.3fms，最慢 %.2fms"
		% [ride_ms, ride_ms / 1200.0, worst_frame_ms])
	_check(ride_ms / 1200.0 < 2.0,
		"草皮流式单帧 CPU 均值 < 2ms（实测 %.3fms）" % (ride_ms / 1200.0))
	# 半径 200m 时新格是按 2πR·v/CELL² ≈ 18 格/秒进来的，这是这一档的稳态成本
	_check(_grass.live_tuft_count() < 200000,
		"骑行稳态下的可见实例数在 20 万以内（%d）" % _grass.live_tuft_count())

	_shader_silhouette()
	_report()


## 草皮**画出来**的形状：卡片尺寸、草叶数、颜色退饱和程度。
##
## 放在这里而不是 `verify_terrain_shader.gd`，因为它量的是"这片草看起来像草吗"，
## 而那正是本文件守的另一半（另一半是放置与流式）。全是纯文本断言——
## `--headless` 用 dummy renderer，着色器根本不编译，所以**只有**文本这条
## 路拦得住它们被改回旧值。
##
## 每一条都对应一次真的看图翻车：
## · 卡片 0.34×0.15 + 7 片叶 → 定妆照拍出来是一地龙舌兰，半米高的一堵墙，
##   而玩家相机离地 1.6m，这堵墙正好挡住前方的路；
## · 循环上限硬编码 8 而 `hint_range` 上限也是 8 → 把 blade_count 调到 10
##   会被静默截断成 8，**看着像**"我调密了"，其实一片叶子都没多。两处必须同改。
## · 颜色纯度太高 → 远景接不上地形 shader（那边更灰），读成一块塑料草坪。
func _shader_silhouette() -> void:
	print("\n---- 草皮着色器：形状与颜色 ----")
	var path := "res://assets/shaders/grass.gdshader"
	if not FileAccess.file_exists(path):
		_check(false, "grass.gdshader 在磁盘上")
		return
	var src := FileAccess.get_file_as_string(path)

	var w := _uni(src, "card_width")
	var h := _uni(src, "card_height")
	_check(w > 0.0 and h > 0.0, "读到 card_width / card_height（%.3f / %.3f）" % [w, h])
	# 宽高比：草叶是**竖**的。旧值 0.34/0.15 = 2.27，读起来是宽叶植物；
	# 收到 0.24/0.085 = 2.82 之后才站得住，而绝对尺寸一起小了一半。
	_check(h > 0.0 and w / h < 3.2,
		"卡片宽高比 < 3.2，草叶是竖的而不是宽叶（%.3f / %.3f = %.2f）" % [w, h, w / h])
	_check(h <= 0.10,
		"卡片高 <= 0.10m：1.6m 高的相机看得过去（%.3f）" % h)
	_check(w <= 0.26,
		"卡片宽 <= 0.26m：一丛不该占掉半米见方（%.3f）" % w)

	var n := _uni(src, "blade_count")
	var loop_cap := _loop_cap(src)
	_check(n >= 10.0, "每丛草叶 >= 10 片，卡片小了一半要靠叶数补覆盖度（%.1f）" % n)
	_check(loop_cap >= 12, "fragment 循环上限 >= 12（实测 %d）" % loop_cap)
	_check(loop_cap >= int(n),
		"循环上限 %d >= blade_count %.1f，否则叶数被静默截断" % [loop_cap, n])
	var hr := _hint_hi(src, "blade_count")
	_check(hr >= n,
		"blade_count 的 hint_range 上限 %.1f >= 实际值 %.1f（否则编辑器里也调不上去）"
		% [hr, n])

	# 退饱和：绿通道与红通道的差要压住。旧值 tip=(0.40,0.55,0.24)，差 0.15。
	for uni in ["blade_base", "blade_tip"]:
		var c := _uni_color(src, uni)
		var spread: float = c.y - c.x
		_check(spread <= 0.10,
			"%s 的绿-红通道差 <= 0.10，不是塑料草坪（%.1f, %.1f, %.1f = %.3f）"
			% [uni, c.x, c.y, c.z, spread])
		_check(c.z <= c.x + 0.02,
			"%s 蓝通道没有塌到绿通道之下（%.1f vs %.1f）" % [uni, c.z, c.x])


## 取 `uniform float <name> ... = <v>;` 的默认值
func _uni(src: String, name: String) -> float:
	var rx := RegEx.new()
	rx.compile("uniform\\s+float\\s+%s\\s*:[^=]*=\\s*([0-9.]+)" % name)
	var m := rx.search(src)
	return float(m.get_string(1)) if m != null else -1.0


## 取 `uniform float <name> : hint_range(<lo>, <hi>)` 的**上界**
func _hint_hi(src: String, name: String) -> float:
	var rx := RegEx.new()
	rx.compile("uniform\\s+float\\s+%s\\s*:[^=]*hint_range\\([^)]*,\\s*([0-9.]+)\\)" % name)
	var m := rx.search(src)
	return float(m.get_string(1)) if m != null else -1.0


## fragment 里 `for (int i = 0; i < N; i++)` 的那个 N
func _loop_cap(src: String) -> int:
	var rx := RegEx.new()
	rx.compile("for\\s*\\(int\\s+i\\s*=\\s*0;\\s*i\\s*<\\s*([0-9]+)")
	var m := rx.search(src)
	return int(m.get_string(1)) if m != null else -1


## 取 `uniform vec4 <name> : source_color = vec4(r, g, b, a);` 的 rgb
func _uni_color(src: String, name: String) -> Vector3:
	var rx := RegEx.new()
	rx.compile("uniform\\s+vec4\\s+%s\\s*:[^=]*=\\s*vec4\\(\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*,\\s*([0-9.]+)"
		% name)
	var m := rx.search(src)
	if m == null:
		return Vector3(-1, -1, -1)
	return Vector3(float(m.get_string(1)), float(m.get_string(2)),
		float(m.get_string(3)))


## 逐字节比较两格草的内容
func _same(x: Dictionary, y: Dictionary) -> bool:
	var xa: PackedVector3Array = x["pos"]
	var ya: PackedVector3Array = y["pos"]
	if xa != ya:
		return false
	if (x["rot"] as PackedFloat32Array) != (y["rot"] as PackedFloat32Array):
		return false
	if (x["scl"] as PackedFloat32Array) != (y["scl"] as PackedFloat32Array):
		return false
	if (x["seed"] as PackedColorArray) != (y["seed"] as PackedColorArray):
		return false
	return true


func _report() -> void:
	print("\n[verify_grass_scatter] %s  (失败 %d)" % [
		"PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
