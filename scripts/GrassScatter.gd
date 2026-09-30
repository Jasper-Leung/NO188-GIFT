extends Node3D
## GrassScatter — 玩家周围流式实例化草皮（Web/Compatibility 友好）
##
## 为什么不用 VegBuilder 的路子：那是"沿路按 chunk 放植物"，密度低、跟着路走。
## 草是"跟着玩家走的一整片草原"，半径外要能完全消失，否则既贵又看不出效果。
## 所以这里自己一套：以玩家（或编辑模式下的自由相机）为中心铺一圈格子。
##
## 桌面铺 200m、Web/移动端铺 100m（见 RADIUS_DESKTOP / RADIUS_MOBILE）。
## 半径放大 6.7 倍不是把密度乘上去——那要 62 万丛——而是靠 RING_DIST /
## RING_DENSITY / RING_SCALE 那几层同心环：近处真草，远处放大卡片、降密度，
## 覆盖度大致守恒而实例数按面积比掉下来（见 RING_DIST 的注释）。
##
## **环是叠加的，不是互斥的档位——这一版最要紧的一条。**
## 旧版每格只记一个"当前档位"，格子一跨过档位边界就得重建：拆槽、
## visible_instance_count 归零、进队列排队，排到了才重新显示。15m/s 骑过
## 32m 一格就有约五十个格换档排队，离玩家最近的那几个排在几十名之后，
## 于是脚边的草空掉一秒多再冒出来——玩家报的就是这个。
##
## 现在第 r 环的驻留判据是"格子中心距 <= RING_DIST[r] + BUILD_LEAD"，
## 也就是**一整个圆盘**，层层包含：同一格在它落进的每一层盘里各有一份
## MultiMesh，只有最小的、也就是包含它的那层可见。于是：
##   - 一格一生只被建 RING_COUNT 次，每次都发生在它刚跨进某层盘的外沿，
##     那时它还很远（最近的第 0 层外沿也在 30m）；
##   - 走进更小的环时，那一份早就躺在池子里等着了，切环是一次纯粹的
##     显示/隐藏切换，没有重建、没有空帧；
##   - 格子只在出环时被真正销毁。
## 玩家脚边的草一旦建成就再也不会被重建、也不会被藏起来。
##
## 每格草的位置是格子整数坐标 + 环号 的纯函数（_cell_rng），所以骑开再骑回来
## 生成的是逐字节相同的草，不会重排、不会闪。
##
## 离路判定走一张道路折线的空间索引（_seg_index）。不要对每丛草直接调
## VegBuilder._min_dist_to_road_2d()：那个要遍历约 650 条折线段，
## 一格 5120 个候选就是 ~330 万次 GDScript 迭代，一个卡顿。

const CELL := 32.0                     # 固定半径下 draw call 数 ∝ 1/CELL²，越大越少
const DENSITY := 5.0                   # ring 0 的丛/m²；每丛 7 片叶 ≈ 35 叶/m²

## 草皮的加载半径。200m 桌面上把近景之外的全景交给草皮，100m 是 Web/移动端
## 的上限——那边是 Compatibility/WebGL2，实例数直接等于顶点数，翻倍就是翻倍地疼。
const RADIUS_DESKTOP := 200.0
const RADIUS_MOBILE := 100.0

## 环的分界（米）。第 r 环的盘是"格子中心距 <= RING_DIST[r] + BUILD_LEAD"的
## 整个圆盘，**不是**一条壳——所以 RING_DIST[0] 是"最近的那层草到哪结束"，
## RING_DIST[1] 是"次近那层到哪结束"，以此类推，一格的可见层是最小的
## 那个包含它的盘。
##
## 半径放大 6.7 倍（30→200m）之后，"全半径同密度"意味着 62 万丛，没人跑得动；
## "全半径同稀疏"又会让脚边的草退化成稀稀拉拉的几丛。所以按距离分层：
## **近处真草、远处大卡片**——同一块地面上覆盖度大致守恒，实例数按面积比掉下来。
##
## ring 0 是唯一"能看清单根草叶"的层，所以保持真实卡片尺寸和真实密度；
## 从 ring 2 起（70m 外）单片草叶已经不到一个像素，再按真实尺寸画纯属浪费，
## 改成把卡片放大 RING_SCALE 倍、密度按 1/scale² 掉，覆盖度不变而实例数变成
## 1/scale²。ring 3 的卡片有 1.1m 宽，在 165m 外约合 6 像素，正好糊成一层草色的绒。
const RING_DIST := [30.0, 70.0, 130.0]         # 每层盘的外沿，最外一层到 RADIUS
const RING_DENSITY := [DENSITY, 2.5, 1.0, 0.35]  # 丛/m²
const RING_SCALE := [1.0, 1.0, 1.8, 3.2]         # 卡片尺寸倍数
const RING_COUNT := 4
## 每层一个格子的实例上限 = CELL²*RING_DENSITY[r]。instance_count 是槽位建好时
## 定死的，所以各层必须按自己的密度分开开，不能一层容量通吃。
const RING_CAP := [5120, 2560, 1024, 358]

## 提前量 = CELL/√2：格子是正方形，它自己最靠里的那丛草距中心只有 CELL/√2。
## 驻留判据若按 RADIUS 算，新格子里**最近**的草一出现就已经在淡出带中间，
## 会以全不透明度凭空冒出来。见 _desired_cells。
const BUILD_LEAD := CELL * 0.70710678
const TICK_INTERVAL := 0.1

## 建格预算是**墙钟**不是丛数。一格的成本按环差 14 倍（ring 0 的 5120 丛
## 约 10ms，ring 3 的 358 丛约 0.5ms），丛数预算兜不住两端：按 5120 给，
## 一个远格就超预算；按 358 给，开局要铺的十几万个实例要铺 5 秒。
const BUILD_MS_STREAM := 6.0           # 骑行中：新格零星进来
const BUILD_MS_BULK := 16.0            # 开局：整环一次性铺满

## 槽位按环分池。ring 0 的盘最小（π·52.6²/1024 ≈ 8.5 格），但每格要按
## TUFT_CAP 开；ring 3 的盘有 152 格，每格却只要 358 丛。开成一个容量就是
## 32MB 级别的 buffer，Web 上直接爆，所以每层按自己的盘面积 + 15% 余量分配。
const POOL_MARGIN := 1.15
const POOL_SLACK := 6

const ROAD_CLEAR := 8.0                # RoadBuilder.TOTAL_HALF_WIDTH(6.5) + 1.5 路肩
const ROAD_INDEX_CELL := 16.0          # 道路段索引的格子边长（米）。越小每格段数越少：
                                       # 实测 32m 时每格 31 段（最多 77），
                                       # 16m 时降到 ~8 段，热点快 4 倍
const ROAD_POLY_STEP := 1.0            # 中心线抽稀间距。抽稀是弦近似，间距越大
                                       # 量出来的"离路距离"越大（实测 2.0m 间距
                                       # 会系统性高报 0.2~0.5m，1.0m 收到 0.05m 内），
                                       # 而 8.0m 的让位半径只比 6.5m 的路面半宽
                                       # 多 1.5m 路肩，误差不能白吃掉。
const PLAZA_CLEAR_RADIUS := 14.0       # RoadBuilder.PLAZA_RADIUS(12) + 2
const PLAZA_CENTER := Vector2(0.0, 43.0)   # RoadBuilder.PLAZA_CENTER_X/Z，全场只有这一个盘
const STATION_CLEAR := 8.0             # 驿站脚下铺装，别让草穿出来
const TERRAIN_MARGIN := 20.0           # 与 VegBuilder 一致
const SEED := 188
const SHADER_PATH := "res://assets/shaders/grass.gdshader"

var _terrain: Node3D = null
var _focus := Vector3.ZERO
var _focus2 := Vector2.ZERO
var _focus_cell := Vector2i(999999, 999999)
var _radius := RADIUS_DESKTOP          # 实际加载半径，setup() 按平台定
var _vis_factor := 1.0                 # 心神×灯笼×香囊，只收淡出带、不动 _radius
var _protected: PackedVector3Array = PackedVector3Array()
var _road_segs: PackedVector2Array = PackedVector2Array()   # 每段 2 个点：[2i]=a, [2i+1]=b
var _seg_index: Dictionary = {}        # Vector2i -> PackedInt32Array(段号)

# 环状态。槽位表是「每环一张」，一格在它落进的每一层盘里各占一个槽。
var _ring_reach := PackedFloat32Array()   # 每层盘的外沿（含 BUILD_LEAD）
var _ring_count := RING_COUNT             # 实际用到的层数（小半径下最外层是空的）
var _ring_pool_lo := PackedInt32Array()   # 该层槽位在 _pool 里的下界
var _ring_pool_hi := PackedInt32Array()
var _pool: Array[MultiMeshInstance3D] = []
var _cell_of_slot: Array = []            # 槽位 -> Vector2i，未占用为 null
var _slot_of_cell: Array[Dictionary] = []  # 环 -> {Vector2i -> 槽位}
var _active_ring: Dictionary = {}        # Vector2i -> 当前**可见**的环
var _want_ring: Dictionary = {}          # Vector2i -> 应当可见的环（_retarget 算）
var _built: Dictionary = {}              # Vector3i(x,y,环) -> 已建好
var _build_count: Dictionary = {}        # Vector3i(x,y,环) -> 建过几次（回归查"只建一次"）

var _pending: Array = []                 # Vector3i(x,y,环) 队列，活动环先、同距离内由近及远
var _pending_set: Dictionary = {}
var _bulk := true                        # 开局整环一次铺满走大预算；队列排干后转流式
var _starved := false                    # 有格子没抢到槽位，焦点没动也要重试
var _tick_acc := 0.0
var _mat: ShaderMaterial = null


## Web 与移动端砍半。OS.has_feature 在导出时才为真，本地编辑器/桌面跑的是
## RADIUS_DESKTOP——回归脚本里量的就是 200m 那档。
static func target_radius() -> float:
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return RADIUS_MOBILE
	return RADIUS_DESKTOP


## 该距离属于哪一环。RING_DIST 带上界，所以是"越过几个分界"。
## 返回的环同时也是该格**唯一可见**的那一层。
func _ring_of(dist: float) -> int:
	for r in range(_ring_count):
		if dist <= _ring_reach[r]:
			return r
	return _ring_count - 1


func setup(terrain: Node3D, centerlines: Array, protected_positions: Array = []) -> void:
	_terrain = terrain
	_radius = target_radius()
	_protected.clear()
	for p in protected_positions:
		if p is Vector3:
			_protected.append(p)
	_build_road_index(centerlines)
	_compute_rings()
	_build_pool()
	reset()
	# 淡出带贴着**最外一层的起点**放：桌面上最外层（ring 3）从 130m 起，
	# Web 半径只有 100m、从 65m 起淡。写成 RADIUS 的固定比例会在小半径上
	# 把整个环淡成 0。
	apply_ground_fade()


## 每层盘的外沿，以及实际有几层。半径小于某一层的外沿时那一层是空的
## （Web 的 100m 就没有 ring 3），既不该建槽位也不该分配那层的 buffer。
func _compute_rings() -> void:
	_ring_reach = PackedFloat32Array()
	_ring_reach.resize(RING_COUNT)
	for r in range(RING_COUNT):
		# RING_DIST 只存相邻层之间的分界，最外一层的盘到 _radius 为止
		var rr: float = _radius if r == RING_COUNT - 1 else minf(RING_DIST[r], _radius)
		_ring_reach[r] = rr + BUILD_LEAD
	_ring_count = 1
	for r in range(1, RING_COUNT):
		if _ring_reach[r] > _ring_reach[r - 1] + 0.001:
			_ring_count = r + 1


# ---------------------------------------------------------------- 道路空间索引

func _build_road_index(centerlines: Array) -> void:
	_road_segs = PackedVector2Array()
	_seg_index.clear()
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
		if poly.size() < 2:
			continue
		for i in range(poly.size() - 1):
			var seg := _road_segs.size() / 2
			var a := poly[i]
			var b := poly[i + 1]
			_road_segs.append(a)
			_road_segs.append(b)
			# 把这一段登记到它 AABB 外扩 ROAD_CLEAR 覆盖的所有索引格
			var x0 := int(floor((minf(a.x, b.x) - ROAD_CLEAR) / ROAD_INDEX_CELL))
			var x1 := int(floor((maxf(a.x, b.x) + ROAD_CLEAR) / ROAD_INDEX_CELL))
			var z0 := int(floor((minf(a.y, b.y) - ROAD_CLEAR) / ROAD_INDEX_CELL))
			var z1 := int(floor((maxf(a.y, b.y) + ROAD_CLEAR) / ROAD_INDEX_CELL))
			for gz in range(z0, z1 + 1):
				for gx in range(x0, x1 + 1):
					var key := Vector2i(gx, gz)
					if not _seg_index.has(key):
						_seg_index[key] = PackedInt32Array()
					_seg_index[key].append(seg)


## 该点是否离任何道路中心线都 >= radius。这是 generate_cell 的热点，
## 一格最多要问 5120 次，所以只查**本索引格**，不扫邻域。
##
## 这样是精确的（不是近似）：登记时每段路都进了它 AABB 外扩 ROAD_CLEAR
## 的所有格子，所以"离 p 不超过 radius"的那一段一定登记在 p 本格里。
## 邻域只对"要一个精确的距离**数值**"才有意义，那是 distance_to_road 的活。
## 实测这一处从 64.6us/次降到 ~0.6us/次，是草皮能不能上 Web 的关键。
func clear_of_road(p: Vector2, radius: float) -> bool:
	var key := Vector2i(int(floor(p.x / ROAD_INDEX_CELL)), int(floor(p.y / ROAD_INDEX_CELL)))
	if not _seg_index.has(key):
		return true
	var segs: PackedInt32Array = _seg_index[key]
	for s in segs:
		if _point_seg_dist(p, _road_segs[s * 2], _road_segs[s * 2 + 1]) < radius:
			return false
	return true


## 该点到最近道路中心线的距离（只给工具/回归用，不在运行时热点上）。
##
## 扫 3×3 邻域而不是只查本格：登记只覆盖各段 AABB 外扩 ROAD_CLEAR 的格子，
## 所以"最近的那一段"可能落在隔壁格——只查本格会把 22.26m 报成比真值多 0.4m
## （近处准、远处偏大）。扫 3×3 后，只要真距离 <= ROAD_INDEX_CELL(16m)，
## 结果就是精确的；再远会**偏大**，让位判定只关心 <8m，那一段完全在精确区内。
func distance_to_road(p: Vector2) -> float:
	var cx := int(floor(p.x / ROAD_INDEX_CELL))
	var cz := int(floor(p.y / ROAD_INDEX_CELL))
	var best := 1e9
	for gz in range(cz - 1, cz + 2):
		for gx in range(cx - 1, cx + 2):
			if not _seg_index.has(Vector2i(gx, gz)):
				continue
			var segs: PackedInt32Array = _seg_index[Vector2i(gx, gz)]
			for s in segs:
				best = minf(best,
					_point_seg_dist(p, _road_segs[s * 2], _road_segs[s * 2 + 1]))
	return best


func _point_seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-9:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ---------------------------------------------------------------- 卡片 mesh / 材质

static func build_card_mesh() -> ArrayMesh:
	## 两片交叉的立牌。每片沿高度切 2 段（3 排顶点，底边收到 0.5/0.36/0.13），
	## 共 8 三角形 / 12 顶点。交叉是为了在任意视角下都有一片正对相机——
	## 自行车相机几乎与地面平行，单片立牌会直接从视野里消失。
	## 建的是**单位宽**卡片（底边半宽 0.5），实际尺寸由 shader 的 card_width 缩放，
	## 这样调草的大小不用重建 mesh。
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var quads := [Vector3(0, 0, 1), Vector3(1, 0, 0)]   # 两片牌子的朝向
	var rows := [0.0, 0.5, 1.0]                         # 沿高度的位置，UV.y
	var halfw := [0.5, 0.36, 0.13]                      # 对应的半宽（单位卡）
	for q in quads:
		var n: Vector3 = q
		var right: Vector3 = n.cross(Vector3.UP).normalized()
		var base := verts.size()
		for r in range(3):
			var vh: float = rows[r]
			var hw: float = halfw[r]
			verts.append(-right * hw + Vector3.UP * vh)
			verts.append(right * hw + Vector3.UP * vh)
			norms.append(n)
			norms.append(n)
			uvs.append(Vector2(0.0, vh))
			uvs.append(Vector2(1.0, vh))
		for r in range(2):
			var a := base + r * 2
			idx.append(a)
			idx.append(a + 1)
			idx.append(a + 2)
			idx.append(a + 1)
			idx.append(a + 3)
			idx.append(a + 2)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func grass_material() -> ShaderMaterial:
	if _mat != null:
		return _mat
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	# 底色必须和地形取自同一个常量，否则草和地会明显分家
	var TB = load("res://scripts/TerrainBuilder.gd")
	_mat.set_shader_parameter("ground_color", TB.BASE_COLOR)
	_mat.set_shader_parameter("mottle_scale", 0.35)
	return _mat


## 槽位按环分池，每层按自己的盘面积给。ring 0 的盘只有 8.5 格但每格要 5120 丛，
## ring 3 的盘有 152 格但每格只要 358 丛——开成同一个容量就是 30MB+ 的 buffer。
## 15% 余量 + 6 格是因为驻留判据量的是"格心落在圆里"，而格心是 32m 的格点，
## 焦点落在格内不同位置时圆里格点数会抖几个。
func _build_pool() -> void:
	var mesh: ArrayMesh = build_card_mesh()
	_pool.clear()
	_cell_of_slot = []
	_ring_pool_lo = PackedInt32Array()
	_ring_pool_hi = PackedInt32Array()
	_slot_of_cell = []
	for r in range(_ring_count):
		_ring_pool_lo.append(_pool.size())
		_slot_of_cell.append({})
		var reach: float = _ring_reach[r]
		var need := int(PI * reach * reach / (CELL * CELL) * POOL_MARGIN) + POOL_SLACK
		for _i in range(need):
			var mm := MultiMesh.new()
			# MultiMesh 的这些标志"只能在 instance_count == 0 时设置"，
			# 顺序错了会报 ERROR: Condition "instance_count > 0" is true，
			# 而且标志被静默丢弃，INSTANCE_CUSTOM 读出来全是 0。
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.use_custom_data = true
			mm.instance_count = RING_CAP[r]
			mm.visible_instance_count = 0
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			# 草不投影：这是 Web 上最大的一笔节省，干掉整个阴影 pass。
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# 卡片包围盒很薄，默认剔除边距会让草在屏幕边缘突然炸掉
			mmi.extra_cull_margin = 0.5
			mmi.material_override = grass_material()
			mmi.visible = false
			add_child(mmi)
			_pool.append(mmi)
			_cell_of_slot.append(null)
		_ring_pool_hi.append(_pool.size())


# ---------------------------------------------------------------- 流式

func set_focus(world_pos: Vector3) -> void:
	_focus = world_pos
	_focus2 = Vector2(world_pos.x, world_pos.z)


## 改淡出带。默认按"相机贴着地面"给：焦点的地面高度和相机只差 1.6m，
## 所以 distance(origin, CAMERA_POSITION_WORLD) 约等于"离焦点多远"。
## 编辑模式的俯视相机在 100m 高空，这个等式就断了，必须用 set_fade_for_camera。
func set_fade_range(start_m: float, end_m: float) -> void:
	var m := grass_material()
	m.set_shader_parameter("fade_start", start_m)
	m.set_shader_parameter("fade_end", end_m)


## 相机贴着地面那版淡出带。正常玩法相机离焦点只 1.6m，d 当成 0。
func apply_ground_fade() -> void:
	var r := _radius * _vis_factor
	set_fade_range(minf(RING_DIST[RING_COUNT - 2], r * 0.65), r)


## 心神系数。只收**淡出带**，不动 `_radius`：驻留半径一动，环分界、槽位池子、
## 驻留不变式全得重算，那是 verify_grass_scatter.gd 守着的那套东西。
## 淡出带只是 shader 的两个 uniform，改它零流式成本——远处草照样驻留，
## 只是被淡成 0，和今天 visibility_range 之外那圈树的行为一样。
func set_visibility_factor(f: float) -> void:
	var c := clampf(f, 0.0, 1.0)
	if absf(c - _vis_factor) < 0.001:
		return
	_vis_factor = c
	apply_ground_fade()


func visibility_factor() -> float:
	return _vis_factor


## 驻留半径。只读：setup() 按平台定一次，之后绝不改——一动就连环分界、
## 槽位池子和驻留不变式全得重算。可见半径的变化全走 `_vis_factor`。
func radius() -> float:
	return _radius


## 把淡出带外扩到"盖住相机到焦点的距离"。俯视相机下 shader 量的距离是
## 100m 起步，fade_end 若还是 RADIUS，整圈草会全淡成 0。
func set_fade_for_camera(cam_pos: Vector3) -> void:
	var d := _focus.distance_to(cam_pos)
	var r := _radius * _vis_factor
	set_fade_range(d + r * 0.35, d + r * 1.05)


func reset() -> void:
	for mmi in _pool:
		mmi.visible = false
		mmi.multimesh.visible_instance_count = 0
	for r in range(_ring_count):
		_slot_of_cell[r].clear()
	for i in range(_cell_of_slot.size()):
		_cell_of_slot[i] = null
	_pending.clear()
	_pending_set.clear()
	_built.clear()
	_build_count.clear()
	_active_ring.clear()
	_want_ring.clear()
	_bulk = true
	_starved = false
	_focus_cell = Vector2i(999999, 999999)


func tick(delta: float) -> void:
	if _terrain == null or _pool.is_empty():
		return
	_tick_acc += delta
	if _tick_acc < TICK_INTERVAL:
		return
	_tick_acc = 0.0

	# _starved 是为了兜住"上一次有格没抢到槽位"：焦点停在原地时不会跨格，
	# 光靠跨格触发就会把那几格永远漏掉，环上留一个洞。
	if _world_to_cell(_focus) != _focus_cell or (_starved and _pending.is_empty()):
		_focus_cell = _world_to_cell(_focus)
		_retarget()

	if _pending.is_empty():
		_bulk = false
		return
	# 大预算只给"reset 之后第一次铺满整环"。别拿队列长度当开关：15m/s 骑过
	# 一格（32m）本来就会让几十个格进环，队列长度和开局一个量级，
	# 按长度判会在骑行途中一直走大预算，最慢一帧直接顶到 25ms。
	var budget_ms := BUILD_MS_BULK if _bulk else BUILD_MS_STREAM
	var t0 := Time.get_ticks_msec()
	while not _pending.is_empty():
		# 掐在**建之前**：格子的成本按环差 14 倍（ring 0 一格约 10ms，
		# ring 3 一格约 0.5ms），掐在建之后最坏一 tick 就是「预算 + 一整格」。
		if Time.get_ticks_msec() - t0 >= budget_ms:
			break
		var k: Vector3i = _pending.pop_front()
		_pending_set.erase(k)
		var c := Vector2i(k.x, k.y)
		var r: int = k.z
		if not _slot_of_cell[r].has(c):
			continue    # 入队之后焦点又移走了，这个格已经不算数
		_build_cell_into(_slot_of_cell[r][c], c, r)
	if _pending.is_empty():
		_bulk = false


## 重算驻留集合。**只处理两类格子**：完全出了最外盘的（销毁），和
## 某一层盘里还没有自己那份的（申请槽位并排队）。已经驻留的格子
## 无论焦点怎么动都不会被碰到——这就是"骑过去不重新加载"。
func _retarget() -> void:
	_want_ring = _desired_cells()
	var outer: Dictionary = _slot_of_cell[_ring_count - 1]

	# 出环：不在最外盘里的格，把它在各层的份一起销毁
	for c in outer.keys():
		if _want_ring.has(c):
			continue
		for r in range(_ring_count):
			if _slot_of_cell[r].has(c):
				_release(c, r)

	# 入环：新出现的格，或者刚跨进某一层盘的格
	var entering: Array = []
	for c in _want_ring.keys():
		var d := _cell_center(c).distance_to(_focus2)
		for r in range(_ring_count):
			if d > _ring_reach[r] or _slot_of_cell[r].has(c):
				continue
			var slot := _free_slot(r)
			if slot < 0:
				continue   # 该层的池子满了，剩下的等下一次 _retarget
			_slot_of_cell[r][c] = slot
			_cell_of_slot[slot] = c
			entering.append(Vector3i(c.x, c.y, r))

	_starved = false
	for c in _want_ring.keys():
		if not outer.has(c):
			_starved = true
			break

	if not entering.is_empty():
		_enqueue_all(entering)
	# 目标层已经建好的立刻切显示；还在队列里的等建完再切（见 _refresh_visible）
	for c in _want_ring.keys():
		_refresh_visible(c)


## 活动环的活排在同距离的隐藏层前面（格子一进来就得看得见），其余按距焦点
## 由近及远：保证你要骑过去的草先存在。
func _enqueue_all(entering: Array) -> void:
	var dist_of := {}
	for k in entering:
		dist_of[k] = _cell_center(Vector2i(k.x, k.y)).distance_to(_focus2)
	entering.sort_custom(func(a, b):
		var pa: int = 0 if int(_want_ring.get(Vector2i(a.x, a.y), -1)) == a.z else 1
		var pb: int = 0 if int(_want_ring.get(Vector2i(b.x, b.y), -1)) == b.z else 1
		if pa != pb:
			return pa < pb
		return float(dist_of[a]) < float(dist_of[b]))
	for k in entering:
		if _pending_set.has(k):
			continue
		_pending_set[k] = true
		_pending.append(k)


## 把格子切到它的活动环。**只在目标环那份已经建好时才切**，否则旧的那份
## 继续顶着。所以"切环"永远是一次显示/隐藏切换，不会让格子空掉哪怕一帧。
func _refresh_visible(c: Vector2i) -> void:
	var want: int = int(_want_ring.get(c, -1))
	if want < 0:
		return
	var old: int = int(_active_ring.get(c, -1))
	if want == old:
		return
	if not _built.has(Vector3i(c.x, c.y, want)):
		return
	_set_ring_visible(c, want, true)
	if old >= 0:
		_set_ring_visible(c, old, false)
	_active_ring[c] = want


func _set_ring_visible(c: Vector2i, r: int, on: bool) -> void:
	if not _slot_of_cell[r].has(c):
		return
	var mmi := _pool[_slot_of_cell[r][c]]
	mmi.visible = on and mmi.multimesh.visible_instance_count > 0


## 期望驻留的格子，值是每格当前的活动环号。
##
## 这里必须带 BUILD_LEAD 提前量：格子是正方形，它自己最靠里的那丛草距中心
## 只有 CELL/√2。若按 RADIUS 判驻留，新格子里**最近**的草一出现就已经在
## RADIUS - CELL/√2，正好在淡出带中间，会以全不透明度凭空冒出来。
func _desired_cells() -> Dictionary:
	var out := {}
	var reach: float = _ring_reach[_ring_count - 1]
	var c0 := _world_to_cell(_focus)
	var span := int(ceil(reach / CELL))
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var c := c0 + Vector2i(dx, dz)
			var d := _cell_center(c).distance_to(_focus2)
			if d <= reach:
				out[c] = _ring_of(d)
	return out


func _release(c: Vector2i, r: int) -> void:
	var slot: int = _slot_of_cell[r][c]
	_pool[slot].multimesh.visible_instance_count = 0
	_pool[slot].visible = false
	_cell_of_slot[slot] = null
	_slot_of_cell[r].erase(c)
	var k := Vector3i(c.x, c.y, r)
	_built.erase(k)
	_build_count.erase(k)
	_drop_pending(k)
	if int(_active_ring.get(c, -1)) == r:
		_active_ring.erase(c)


func _drop_pending(k: Vector3i) -> void:
	if not _pending_set.has(k):
		return
	_pending_set.erase(k)
	var i := _pending.find(k)
	if i >= 0:
		_pending.remove_at(i)


## ring r 只能借自己那一段槽位。分池不是为了省 draw call（可见的槽位 1:1），
## 是为了让远处的 MultiMesh 不必按近处的容量开 buffer。
func _free_slot(r: int) -> int:
	for i in range(_ring_pool_lo[r], _ring_pool_hi[r]):
		if _cell_of_slot[i] == null:
			return i
	return -1


func _build_cell_into(slot: int, c: Vector2i, r: int) -> void:
	var g: Dictionary = generate_cell(c, r)
	var pos: PackedVector3Array = g["pos"]
	var n := pos.size()
	var mm: MultiMesh = _pool[slot].multimesh
	mm.visible_instance_count = n
	var rot: PackedFloat32Array = g["rot"]
	var scl: PackedFloat32Array = g["scl"]
	var seed: PackedColorArray = g["seed"]
	for i in range(n):
		var s: float = scl[i]
		# 缩放只进 basis，origin 必须原封不动 —— 见 VegBuilder.instance_transform
		# 的注释：Transform3D(basis, pos).scaled() 会把 pos 一起缩放。
		var basis := Basis().rotated(Vector3.UP, rot[i])
		mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3(s, s, s)), pos[i]))
		mm.set_instance_custom_data(i, seed[i])
	var k := Vector3i(c.x, c.y, r)
	_built[k] = true
	_build_count[k] = int(_build_count.get(k, 0)) + 1
	_refresh_visible(c)


# ---------------------------------------------------------------- 放置（纯函数）

## 生成一格在某一层环上的草。纯函数：只依赖格子整数坐标与环号，与访问顺序、
## 当前焦点无关。默认 0 是最近的一层，回归脚本直接调它做放置断言，
## 不必先摆一个焦点。
##
## 环决定这一格的密度和卡片尺寸（见 RING_DENSITY / RING_SCALE）。
##
## 返回**并行的 Packed 数组**而不是 Array[Dictionary]。这不是洁癖：
## 一格最多 5120 丛，半径 200m 铺满就是十几万个 Dictionary，光对象分配就够
## 吃掉一整个帧预算。并行 Packed 数组零逐丛对象分配，索引要对齐看。
##
## 四个键：pos(PackedVector3Array) / rot / scl (PackedFloat32Array) /
##         seed(PackedColorArray)，下标 i 是同一丛草。
func generate_cell(c: Vector2i, r: int = 0) -> Dictionary:
	var pos := PackedVector3Array()
	var rot := PackedFloat32Array()
	var scl := PackedFloat32Array()
	var seed := PackedColorArray()
	if _terrain == null:
		return {"pos": pos, "rot": rot, "scl": scl, "seed": seed}
	var rr := clampi(r, 0, RING_COUNT - 1)
	var density: float = RING_DENSITY[rr]
	var card_scale: float = RING_SCALE[rr]
	var half := 0.5 * _terrain_size() - TERRAIN_MARGIN
	var rng := _cell_rng(c)
	var center := _cell_center(c)
	for _i in range(int(CELL * CELL * density)):
		var x := center.x + rng.randf_range(-CELL * 0.5, CELL * 0.5)
		var z := center.y + rng.randf_range(-CELL * 0.5, CELL * 0.5)
		if absf(x) > half or absf(z) > half:
			continue
		var p2 := Vector2(x, z)
		if p2.distance_to(PLAZA_CENTER) < PLAZA_CLEAR_RADIUS:
			continue
		var near_station := false
		for pp in _protected:
			if p2.distance_to(Vector2(pp.x, pp.z)) < STATION_CLEAR:
				near_station = true
				break
		if near_station:
			continue
		if not clear_of_road(p2, ROAD_CLEAR):
			continue
		pos.append(Vector3(x, _terrain.get_height_at(x, z), z))
		rot.append(rng.randf() * TAU)
		scl.append(rng.randf_range(0.72, 1.35) * card_scale)
		# 只放归一化的 [0,1]：Compatibility 下 INSTANCE_CUSTOM 是 16-bit 半精度
		seed.append(Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	return {"pos": pos, "rot": rot, "scl": scl, "seed": seed}


func _cell_rng(c: Vector2i) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(Vector2i(c.x, c.y)) ^ SEED
	return r


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

## 实际用到的层数（小半径下最外层是空的）
func ring_count() -> int:
	return _ring_count


## 第 r 层盘的外沿（含 BUILD_LEAD）
func ring_reach(r: int) -> float:
	return _ring_reach[r]


func pool_size() -> int:
	return _pool.size()


## 驻留的格子 = 落在最外盘里的全部格子。活动环是哪一层不看这里。
func live_cell_keys() -> Array:
	return _slot_of_cell[_ring_count - 1].keys()


## 真正画出来的丛数：每格只算它活动环那一份。
func live_tuft_count() -> int:
	var n := 0
	for c in _active_ring.keys():
		var r: int = _active_ring[c]
		n += _pool[_slot_of_cell[r][c]].multimesh.visible_instance_count
	return n


## 已经上传到 GPU buffer 的丛数：包含各格的隐藏层。这是显存开销的上界。
func live_buffer_tuft_count() -> int:
	var n := 0
	for r in range(_ring_count):
		for c in _slot_of_cell[r].keys():
			n += _pool[_slot_of_cell[r][c]].multimesh.visible_instance_count
	return n


func live_draw_call_count() -> int:
	var n := 0
	for mmi in _pool:
		if mmi.visible and mmi.multimesh.visible_instance_count > 0:
			n += 1
	return n
