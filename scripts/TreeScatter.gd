extends Node3D
## TreeScatter — 路两侧的行道树，走草皮（GrassScatter）那套「格子流式」进出场
##
## 为什么不用 VegBuilder 那套：VegBuilder 是"沿路按 chunk 铺植物"，chunk 跟着**路**
## 走、按玩家在路上的编号开窗。行道树虽然也是沿路排的，但 tree.glb 单棵就有
## 52709 三角面，96 棵全在场是 5.1M 三角面**全程**渲染，Web/移动端直接爆。
## 所以这里要的是草皮那套"以玩家为中心的格子"：格子的内容确定、驻留期间零重建、
## 出格即隐藏，进场/出场只发生在玩家看不见或已淡成 0 的地方。
##
## 与 GrassScatter 的三处不同，都是被树的性质逼出来的：
##
## **1. 树的位置在 setup() 里一次算出来，不按格子随机生成。**
##    草是"整片草原"，数量太大（十几万丛）没法预先列出来，只能让每格内容由
##    格子整数坐标当随机种子现算。树反过来：只有 96 棵，而且是**沿路等间距**
##    排的——位置由弧长决定，本来就不是格子的函数。所以 setup() 里沿闭合中心线
##    按 SPACING 走一遍解出所有树，再按格分桶。位置仍然完全确定（同一个种子、
##    同一条路，每次跑逐点相同），"骑开再骑回来一模一样"这条性质照样成立。
##
## **2. 不分同心环。** 草分四层环是因为 200m 半径下同密度要 62 万丛，密度必须
##    随距离掉。树只有一种尺寸、一种密度，分环没有意义。
##
## **3. 淡出交给引擎的 visibility_range，不写 shader。** 草的淡出写在
##    grass.gdshader 里（草有自己的 ShaderMaterial）；树用的是 GLB 自带的
##    贴图材质，为一棵树再写一套采样 basecolor + 距离淡出的着色器不划算。
##    引擎的 visibility_range + FADE_SELF 就是干这个的（抖动淡出，不要求材质
##    带透明）。它是**每帧按真实相机位置**算的，比我们在 tick 里算的驻留集合准。
##
## 于是分工是：**visibility_range 管"多远看不见"（精确、每帧、跟相机），
## 格子驻留集合管"哪些节点存在"（粗粒度、跟焦点、有余量）**。
## 驻留判据刻意比 range 宽出 CELL + BUILD_LEAD，所以焦点在同一格内移动时
## 驻留集合的滞后不会让任何一棵树提前消失。

## 沿路弧长间距（左右两侧各自按这个间距排，右侧错开半个间距）。
## 1223m 的路 → 每侧 48 棵、两侧 96 棵。
const SPACING := 25.0
## 离中心线的横向距离。路面半宽 6.5m（RoadBuilder.TOTAL_HALF_WIDTH），
## 草在 8m 内让位，11m 正好压在路肩外沿的草里。
const SIDE_OFFSET := 11.0
## 右侧相对左侧错开半个间距，免得两排树整齐对脸。
const STAGGER := 0.5
## 横向抖动量（米）。等间距 + 零抖动看起来像栅栏，±1.5m 就够自然了。
const OFFSET_JITTER := 1.5

## 格子边长。**必须和 GrassScatter.CELL 一致**——两套流式用同一张格子，
## 焦点跨格时它们一起重算，不会出现"草换了格、树还在旧格"的错位观感。
const CELL := 32.0
## 格的提前量 = CELL/√2：格子里最靠里的那棵树距格心只有这么远。
## 和草皮同一个道理——驻留判据按格心算，不算提前量的话，格边那几棵树会在
## 刚进环时就已经贴到淡出带末端。
const BUILD_LEAD := CELL * 0.70710678

## 加载半径。树模型重（单棵 52709 三角面），所以比草的 200m 收一档：
## 150m 内约 30~40 棵可见，约 1.6~2.0M 三角面。Web/移动端再砍到 100m。
const RADIUS_DESKTOP := 150.0
const RADIUS_MOBILE := 100.0
## 淡出带宽度。visibility_range 的 end_margin，40m 足够长，肉眼看不到硬边。
const FADE_BAND := 40.0

## 树必须离**任何**中心线 >= 这个距离。11m 是标称值，但 8 字交叉点附近
## 法线偏移会把树推到另一条 ribbon 上；过弯处也一样。这条是硬闸。
const ROAD_CLEAR := 9.0
## 两棵树之间的最小距离。交叉点两侧、过弯内侧都可能有两条候选挤在一起。
const MIN_GAP := 8.0
## 与 GrassScatter 保持一致：广场盘与驿站铺装都要让开。
## 树比草大，所以半径各多给几米。
const PLAZA_CENTER := Vector2(0.0, 43.0)
const PLAZA_CLEAR := 16.0
const STATION_CLEAR := 10.0
const TERRAIN_MARGIN := 20.0

## tree.glb 只有 1.0m 高（AABB 0.44 × 1.00 × 0.46，底面正好在 y=0），
## 所以缩放值就是"树高（米）"。
const SCALE_MIN := 6.0
const SCALE_MAX := 9.0

const SEED := 188
const MESH_PATH := "res://assets/models/tree.glb"
## 离路判定用的中心线抽稀间距。树只在 setup() 里算一次，暴力量到线段就够了，
## 不需要 GrassScatter 那套空间索引（那是给一格 5120 丛草的热路径用的）。
const ROAD_POLY_STEP := 1.0

var _terrain: Node3D = null
var _radius := RADIUS_DESKTOP
var _vis_factor := 1.0                 # 心神×灯笼×香囊，只收可见边界、不动 _radius
var _last_end := 0.0                   # 上一次推给各格的 range_end，用于去抖
var _focus := Vector3.ZERO
var _focus2 := Vector2.ZERO
var _focus_cell := Vector2i(999999, 999999)
var _protected: PackedVector3Array = PackedVector3Array()
var _road_polys: Array[PackedVector2Array] = []
var _loop_pts: PackedVector3Array = PackedVector3Array()    # 闭合中心线
var _loop_cum: PackedFloat32Array = PackedFloat32Array()    # 累计弧长
var _cells: Dictionary = {}        # Vector2i -> MultiMeshInstance3D（未驻留时 visible=false）
var _trees: Array = []             # {pos, yaw, scale, side, arc}
var _mesh: Mesh = null
## 相机到焦点的距离。游戏里约 1.6m 可以忽略；编辑模式的俯视相机离地 100m，
## 不补进去的话所有树都被判定在 range 之外、整片消失。
var _cam_extra := 0.0


## Web 与移动端砍到 100m。OS.has_feature 在导出时才为真，本地编辑器/桌面跑的是
## RADIUS_DESKTOP——回归脚本里量的就是 150m 那档。
static func target_radius() -> float:
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return RADIUS_MOBILE
	return RADIUS_DESKTOP


func setup(terrain: Node3D, centerlines: Array, protected_positions: Array = []) -> void:
	_terrain = terrain
	_radius = target_radius()
	_protected.clear()
	for p in protected_positions:
		if p is Vector3:
			_protected.append(p)
	_build_road_polys(centerlines)
	_build_loop(centerlines)
	place_trees()
	_build_cells()
	reset()


func _build_road_polys(centerlines: Array) -> void:
	_road_polys = []
	var lines: Array = centerlines
	if not lines.is_empty() and not (lines[0] is Array):
		lines = [centerlines]
	for line in lines:
		var poly := PackedVector2Array()
		var last := Vector2.INF
		for q in line:
			var v := Vector2((q as Vector3).x, (q as Vector3).z) if q is Vector3 \
				else Vector2(q)
			if poly.is_empty() or v.distance_to(last) >= ROAD_POLY_STEP:
				poly.append(v)
				last = v
		if poly.size() >= 2:
			_road_polys.append(poly)


## 第一条中心线就是主路（RoadData.branch_points 是空的，没有支路）。
## 采成闭合折线 + 累计弧长表，之后按弧长取值都靠它。
func _build_loop(centerlines: Array) -> void:
	_loop_pts = PackedVector3Array()
	_loop_cum = PackedFloat32Array()
	var lines: Array = centerlines
	if not lines.is_empty() and not (lines[0] is Array):
		lines = [centerlines]
	if lines.is_empty():
		return
	for q in lines[0]:
		_loop_pts.append(q if q is Vector3 else Vector3(q.x, 0.0, q.y))
	if _loop_pts.size() < 2:
		return
	# 路径天然闭合（RoadData 索引 48 回到索引 0），但重采样后的首尾未必逐点相等，
	# 不补这一段的话弧长表会少掉最后一小截、末尾几棵树落在环外。
	if _loop_pts[0].distance_to(_loop_pts[_loop_pts.size() - 1]) > 0.01:
		_loop_pts.append(_loop_pts[0])
	_loop_cum.resize(_loop_pts.size())
	_loop_cum[0] = 0.0
	for i in range(1, _loop_pts.size()):
		_loop_cum[i] = _loop_cum[i - 1] + _loop_pts[i - 1].distance_to(_loop_pts[i])


# ---------------------------------------------------------------- 放置（一次性、确定）

## 沿闭合中心线按弧长排树。左右两侧各自从 0 和 SPACING*STAGGER 起步，
## 每 SPACING 米出一棵候选；候选过不了净空/边界/间距检查就丢掉。
##
## 每棵候选的抖动种子是 **hash(弧长, 侧别)**，不是一条贯穿全场的随机流——
## 这样某个候选被拒不会影响后面任何一棵的抖动，位置就成了弧长的纯函数，
## 与地形/驿站怎么变、检查顺序怎么排都无关。
func place_trees() -> void:
	_trees.clear()
	if _loop_cum.is_empty():
		return
	var total: float = _loop_cum[_loop_cum.size() - 1]
	if total < SPACING * 2.0:
		return
	var accepted := PackedVector2Array()
	for side in [1, -1]:
		var a := 0.0 if side > 0 else SPACING * STAGGER
		while a < total:
			var cand := _candidate_at(a, side)
			a += SPACING
			if cand.is_empty():
				continue
			var p2: Vector2 = cand["p2"]
			if _too_close(p2, accepted):
				continue
			accepted.append(p2)
			_trees.append(cand)


func _candidate_at(arc: float, side: int) -> Dictionary:
	var p := _point_at_arc(arc)
	var t := _tangent_at_arc(arc)
	# 水平法线。方向本身无所谓，正负就是"两侧"。
	var perp := Vector3(-t.z, 0.0, t.x)
	if perp.length_squared() < 1e-9:
		return {}
	perp = perp.normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(round(arc * 10.0)), side)) ^ SEED
	var off := SIDE_OFFSET + rng.randf_range(-OFFSET_JITTER, OFFSET_JITTER)
	var pos := p + perp * (off * float(side))
	# pos.y 先归零量净空：中心线点是 2D 采样出来的，y 不可信
	var p2 := Vector2(pos.x, pos.z)
	var half := 0.5 * _terrain_size() - TERRAIN_MARGIN
	if absf(pos.x) > half or absf(pos.z) > half:
		return {}
	if _dist_to_road(p2) < ROAD_CLEAR:
		return {}
	if p2.distance_to(PLAZA_CENTER) < PLAZA_CLEAR:
		return {}
	for pp in _protected:
		if p2.distance_to(Vector2(pp.x, pp.z)) < STATION_CLEAR:
			return {}
	if _terrain != null:
		pos.y = _terrain.get_height_at(pos.x, pos.z)
	else:
		pos.y = 0.0
	return {
		"pos": pos,
		"p2": p2,
		"yaw": rng.randf() * TAU,
		"scale": rng.randf_range(SCALE_MIN, SCALE_MAX),
		"side": side,
		"arc": arc,
	}


func _too_close(p2: Vector2, accepted: PackedVector2Array) -> bool:
	for q in accepted:
		if p2.distance_to(q) < MIN_GAP:
			return true
	return false


func _point_at_arc(arc: float) -> Vector3:
	var total: float = _loop_cum[_loop_cum.size() - 1]
	var a := fposmod(arc, total)
	var lo := 0
	var hi := _loop_cum.size() - 1
	while lo < hi - 1:
		var mid := (lo + hi) / 2
		if _loop_cum[mid] <= a:
			lo = mid
		else:
			hi = mid
	var seg: float = _loop_cum[lo + 1] - _loop_cum[lo]
	var t := 0.0 if seg < 1e-6 else (a - _loop_cum[lo]) / seg
	return _loop_pts[lo].lerp(_loop_pts[lo + 1], t)


## 弧长处的切线。中心线本身是 0.5m 重采样的，直接取相邻两点的差就够；
## 只有在弧长落点极靠近折点时才用 ±0.5m 的中心差分，免得切线抖。
func _tangent_at_arc(arc: float) -> Vector3:
	var t := _point_at_arc(arc + 0.5) - _point_at_arc(arc - 0.5)
	if t.length_squared() < 1e-9:
		t = _point_at_arc(arc + 0.5) - _point_at_arc(arc)
	if t.length_squared() < 1e-9:
		return Vector3(1.0, 0.0, 0.0)
	t.y = 0.0
	return t.normalized()


## 到任何中心线的距离。暴力量到线段——setup() 里只跑约 100 次，每次扫约
## 1200 段，总共十万次量级，一次性成本可以忽略。
func _dist_to_road(p: Vector2) -> float:
	var best := 1e9
	for poly in _road_polys:
		for i in range(poly.size() - 1):
			best = minf(best, _point_seg_dist(p, poly[i], poly[i + 1]))
	return best


func _point_seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-9:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ---------------------------------------------------------------- 分桶 / 流式

## 每格一个 MultiMeshInstance3D，节点位置放在**格心**上。这不是为了好看：
## visibility_range 量的是"相机到实例原点"的距离，原点放在格心，
## range_end 只要按 BUILD_LEAD 补一格的对角线提前量，格边那几棵树就不会
## 在还没淡完的时候被整格藏掉。
##
## 全部节点在 setup() 里一次建好、默认 visible=false，之后只切 visible——
## "驻留期间零重建"就是这么来的：进场是切一个 bool，不是重新写 buffer。
func _build_cells() -> void:
	for mmi in _cells.values():
		mmi.queue_free()
	_cells.clear()
	if _trees.is_empty():
		return
	var mesh := _load_tree_mesh()
	if mesh == null:
		push_error("TreeScatter: 载入 " + MESH_PATH + " 失败，不栽树")
		return
	_mesh = mesh
	var aabb := mesh.get_aabb()
	var by_cell := {}
	for i in range(_trees.size()):
		var c := _cell_of(_trees[i]["pos"])
		if not by_cell.has(c):
			by_cell[c] = []
		by_cell[c].append(i)

	var end_dist := _range_end()
	for c in by_cell.keys():
		var idxs: Array = by_cell[c]
		var center := _cell_center(c)
		var mm := MultiMesh.new()
		# MultiMesh 的标志"只能在 instance_count == 0 时设置"：
		# transform_format → mesh → instance_count，顺序错了标志被静默丢弃。
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = idxs.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "TreeCell_%d_%d" % [c.x, c.y]
		mmi.multimesh = mm
		mmi.visible = false
		mmi.visibility_range_end = end_dist
		mmi.visibility_range_end_margin = FADE_BAND
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
		mmi.global_position = Vector3(center.x, 0.0, center.y)

		var box := AABB()
		for k in range(idxs.size()):
			var tr: Dictionary = _trees[idxs[k]]
			var s: float = tr["scale"]
			var basis := Basis().rotated(Vector3.UP, tr["yaw"])
			var local: Vector3 = mmi.to_local(tr["pos"])
			# 缩放只进 basis，origin 原封不动 —— 见 VegBuilder.instance_transform
			# 的注释：Transform3D(basis, pos).scaled() 会把 pos 一起缩放。
			mm.set_instance_transform(k, Transform3D(basis.scaled(Vector3(s, s, s)), local))
			var one := AABB(local + aabb.position * s, aabb.size * s)
			box = one if k == 0 else box.merge(one)
		mm.custom_aabb = box
		_cells[c] = mmi


func _load_tree_mesh() -> Mesh:
	if not ResourceLoader.exists(MESH_PATH):
		return null
	var res = load(MESH_PATH)
	if res == null:
		return null
	if res is Mesh:
		return res
	if res is PackedScene:
		var node = res.instantiate()
		var mi := _find_mesh_instance(node)
		var mesh: Mesh = mi.mesh if mi != null else null
		node.free()
		return mesh
	return null


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.mesh != null:
		return node
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null


func reset() -> void:
	for mmi in _cells.values():
		mmi.visible = false
	_focus_cell = Vector2i(999999, 999999)


func set_focus(world_pos: Vector3) -> void:
	_focus = world_pos
	_focus2 = Vector2(world_pos.x, world_pos.z)


## 编辑模式的俯视相机离地 100m，而 visibility_range 量的是"到相机的距离"，
## 不补这一截的话整片树都判在 150m 之外、直接消失。相机一直在动，所以每帧调。
func set_fade_for_camera(cam_pos: Vector3) -> void:
	_cam_extra = maxf(0.0, _focus.distance_to(cam_pos))
	_push_range()


## 把新的可见边界推给每一格。比的是**算出来的边界**而不是相机距离：
## 心神系数一变、相机没动，也必须把新的 range_end 送下去。
func _push_range() -> void:
	var end_dist := _range_end()
	if absf(end_dist - _last_end) < 0.5:
		return
	_last_end = end_dist
	for c in _cells:
		_cells[c].visibility_range_end = end_dist
	_focus_cell = Vector2i(999999, 999999)   # 逼下一次 tick 重算驻留集合


## 心神系数。只收**可见边界**，不动 `_radius`：树全部在 setup() 里一次建好，
## 后面只切 visible，所以收窄驻留判据是纯 bool 切换，零重建零流式成本。
func set_visibility_factor(f: float) -> void:
	_vis_factor = clampf(f, 0.0, 1.0)
	_push_range()


func visibility_factor() -> float:
	return _vis_factor


## 树的可见边界（量的是"相机到格心"的距离）。补 BUILD_LEAD 是因为格心到格内
## 最靠里那棵树的距离最多有半格对角线；不补的话，格边上的树会还没淡完就被
## 整格掐掉（看着像"还有二十米树突然没了"）。
##
## 代价是按"到树"的距离看，淡出带从 [RADIUS, RADIUS+FADE_BAND] 拉宽成
## [RADIUS - BUILD_LEAD, RADIUS + FADE_BAND + BUILD_LEAD]（桌面 = [127.4, 192.9]m），
## 树排远端在格心之间会参差 ±BUILD_LEAD。每棵树自己仍然连续淡出，不会 pop。
## 回归验证：verify_tree_scatter.gd 第 8b 节的 bad_cull 不变式。
func _range_end() -> float:
	return _radius * _vis_factor + BUILD_LEAD + _cam_extra


## 驻留判据比可见边界再宽一格。焦点在同一格内移动最多 32m，驻留集合要等
## 跨格才重算——宽出来的这一格保证"滞后"永远不会让一棵本该可见的树丢节点。
## 反正宽出来的那些格早被 visibility_range 淡成 0 了，不多花一个 draw call。
func _reside_reach() -> float:
	return _range_end() + CELL


func tick(_delta: float) -> void:
	if _cells.is_empty():
		return
	var c := _world_to_cell(_focus)
	if c == _focus_cell:
		return
	_focus_cell = c
	_refresh()


func _refresh() -> void:
	var reach := _reside_reach()
	# 必须遍历**全部**格，不能只扫焦点附近的一圈：上一次驻留、这次出环的格要在这里
	# 被关掉。只扫焦点附近的话那些格永远不会被访问到，会一直挂在 visible=true 上
	# ——骑开几公里再回头，旧位置还留着一堆树。全量遍历是 64 次距离比较，可忽略。
	for c in _cells:
		var d := _cell_center(c).distance_to(_focus2)
		_cells[c].visible = d <= reach


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


func _cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)


func _world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


func _terrain_size() -> float:
	if _terrain != null:
		var v = _terrain.get("TERRAIN_SIZE")
		if v != null:
			return float(v)
	return 800.0


# ---------------------------------------------------------------- 观测接口

func tree_count() -> int:
	return _trees.size()


func trees() -> Array:
	return _trees


func cell_count() -> int:
	return _cells.size()


func live_cell_count() -> int:
	var n := 0
	for c in _cells:
		if _cells[c].visible:
			n += 1
	return n


## 真正画出来的棵数 = 驻留格的实例数之和。visibility_range 会在更近处把它们
## 淡掉，所以这是**上界**，不是屏幕上的棵数。
func live_tree_count() -> int:
	var n := 0
	for c in _cells:
		if _cells[c].visible:
			n += _cells[c].multimesh.instance_count
	return n


func radius() -> float:
	return _radius


func range_end() -> float:
	return _range_end()


func reside_reach() -> float:
	return _reside_reach()


func tree_mesh() -> Mesh:
	return _mesh
