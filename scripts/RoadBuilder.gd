extends Node3D
## RoadBuilder — 沥青双车道3D路面
##
## 真实GPS点位(487点)展开的横截面网格 + 程序化沥青 ShaderMaterial
## - 弧线长参数化 UV：U=横向位置，V=沿路距离 → 颗粒/标线沿路均匀，不受点位疏密影响
## - 4点横截面：路肩外缘 / 左路缘 / 右路缘 / 路肩外缘 → 路肩自然下沉到地面
## - 顶点法线由三角形法线平均计算（不再硬编码 (0,1,0)）
## - 颗粒、胎痕、路缘起灰、潮斑、路肩泥土、白色路缘线、双黄虚线全部在 shader 内生成
##   零贴图资产，适合 WebGL 导出
##
## 支路渲染：road_data.branch_points 定义的三岔路口第三臂在 3D 中同样生成路面
## 高度查询：get_road_ribbon_height() 用三角形质心插值+空间网格，
##   直接读取 mesh 几何，与 GPU 深度缓冲一致，交叉处取 max 无跳变。

const LANE_WIDTH := 4.0
const ROAD_WIDTH := LANE_WIDTH * 2.0
const ROAD_HALF_WIDTH := ROAD_WIDTH * 0.5
const SHOULDER_WIDTH := 2.5
const TOTAL_HALF_WIDTH := ROAD_HALF_WIDTH + SHOULDER_WIDTH
const TOTAL_WIDTH := TOTAL_HALF_WIDTH * 2.0
const ROAD_LIFT := 0.15
const SHOULDER_SINK := 0.15
const UV_SCALE := 16.0
## 重采样间距。GPS点间距0.3~9m且含近90°急弯，直接用会让相邻横截面
## 旋转过大、连接三角形翻到路面下方。1m间距把急弯摊平到每个截面
## 只旋转几度，路面才不会自相交。
const RESAMPLE_STEP := 0.5

const SHADER_PATH := "res://assets/shaders/asphalt.gdshader"
const GRID_CELL := 8.0

## 8 字 lemniscate 几何中心。世界坐标 = (canvas 400, 800) 经 road_data 变换
## (x=(sx-CX)*0.5, z=(sy-CY)*0.5, CX=400 CY=714) → (0, 43)。
## 高斯平滑把两条 ribbon 在 2D 上拉到 (15, 6) 最近,但在 (0, 43) 附近
## 两条 ribbon 仍以 ~0.5m 高度差并排,Z-fighting。圆形广场覆盖此区,
## 视觉上变成一个清晰的环形交叉,玩家过路依然连续。
## PLAZA_LIFT: 广场顶面比盘内最高地形抬升的余量,呈现圆形环岛而非凹陷坑
const PLAZA_CENTER_X := 0.0
const PLAZA_CENTER_Z := 43.0
const PLAZA_RADIUS := 12.0
const PLAZA_LIFT := 0.5
const PLAZA_THICKNESS := 0.4

var _road_data: RoadData
var _terrain_builder: Node3D
var _road_mesh: MeshInstance3D
var _main_centerline: Array[Vector3] = []
var _branch_centerlines: Array = []
var _main_road_ys: PackedFloat64Array = []

var _tri_data: Array = []
var _tri_grid: Dictionary = {}


func _ready() -> void:
	_road_data = RoadData.new()
	if _terrain_builder == null:
		_terrain_builder = get_node_or_null("../TerrainBuilder")
	_build_all_roads()


func set_terrain_builder(tb: Node3D) -> void:
	_terrain_builder = tb


func _get_terrain_height(wx: float, wz: float) -> float:
	if _terrain_builder and _terrain_builder.has_method("get_height_at"):
		return _terrain_builder.get_height_at(wx, wz)
	return 0.0


func _build_all_roads() -> void:
	var smoothed := _smooth(_road_data.points, 5)
	smoothed = _smooth(smoothed, 5)
	smoothed = _smooth(smoothed, 5)
	var res := _resample(smoothed, RESAMPLE_STEP)
	_main_centerline = res
	_main_road_ys = _add_road_line(res)

	for branch in _road_data.branch_points:
		var branch_arr: Array[Vector3] = []
		for p in branch:
			branch_arr.append(p)
		var b_res := _resample(branch_arr, RESAMPLE_STEP)
		_branch_centerlines.append(b_res)
		_add_road_line(b_res)

	_build_center_plaza()


func _add_road_line(centerline: Array[Vector3]) -> PackedFloat64Array:
	var count = centerline.size()
	if count < 2:
		return PackedFloat64Array()

	var arc := PackedFloat64Array()
	arc.resize(count)
	for i in range(1, count):
		arc[i] = arc[i - 1] + (centerline[i] - centerline[i - 1]).length()

	var tangents := PackedVector3Array()
	tangents.resize(count)
	for i in range(count):
		var t: Vector3
		if i == 0:
			t = (centerline[1] - centerline[0]).normalized()
		elif i == count - 1:
			t = (centerline[i] - centerline[i - 1]).normalized()
		else:
			t = (centerline[i + 1] - centerline[i - 1]).normalized()
		tangents[i] = t if t.length_squared() > 1e-6 else Vector3(1.0, 0.0, 0.0)

	var sides := PackedVector3Array()
	for i in range(count):
		sides.append(Vector3(-tangents[i].z, 0.0, tangents[i].x).normalized())

	var road_ys := PackedFloat64Array()
	road_ys.resize(count)
	for i in range(count):
		var p = centerline[i]
		var side = sides[i]
		var h_center = _get_terrain_height(p.x, p.z)
		var h_left = _get_terrain_height(p.x + side.x * ROAD_HALF_WIDTH, p.z + side.z * ROAD_HALF_WIDTH)
		var h_right = _get_terrain_height(p.x - side.x * ROAD_HALF_WIDTH, p.z - side.z * ROAD_HALF_WIDTH)
		road_ys[i] = max(h_center, max(h_left, h_right)) + ROAD_LIFT

	var mi = _build_mesh(centerline, sides, arc, road_ys)
	if _road_mesh == null:
		_road_mesh = mi
	add_child(mi)
	return road_ys


func _build_mesh(centerline: Array, sides: Array, arc: Array, road_ys: Array) -> MeshInstance3D:
	var count = centerline.size()
	var u_edge := (ROAD_HALF_WIDTH + TOTAL_HALF_WIDTH) / TOTAL_WIDTH

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for i in range(count):
		var p = centerline[i]
		var side = sides[i]

		var left_outer = p + side * TOTAL_HALF_WIDTH
		var right_outer = p - side * TOTAL_HALF_WIDTH
		var road_y = road_ys[i]
		var sink = -SHOULDER_SINK

		var v = arc[i] / UV_SCALE
		var base = verts.size()
		verts.append(Vector3(left_outer.x, _get_terrain_height(left_outer.x, left_outer.z) + sink, left_outer.z))
		verts.append(Vector3(p.x + side.x * ROAD_HALF_WIDTH, road_y, p.z + side.z * ROAD_HALF_WIDTH))
		verts.append(Vector3(p.x - side.x * ROAD_HALF_WIDTH, road_y, p.z - side.z * ROAD_HALF_WIDTH))
		verts.append(Vector3(right_outer.x, _get_terrain_height(right_outer.x, right_outer.z) + sink, right_outer.z))
		uvs.append(Vector2(0.0, v))
		uvs.append(Vector2(u_edge, v))
		uvs.append(Vector2(1.0 - u_edge, v))
		uvs.append(Vector2(1.0, v))
		for _k in range(4):
			normals.append(Vector3.ZERO)

		if i < count - 1:
			indices.append(base); indices.append(base + 4); indices.append(base + 1)
			indices.append(base + 1); indices.append(base + 4); indices.append(base + 5)
			indices.append(base + 1); indices.append(base + 5); indices.append(base + 2)
			indices.append(base + 2); indices.append(base + 5); indices.append(base + 6)
			indices.append(base + 2); indices.append(base + 6); indices.append(base + 3)
			indices.append(base + 3); indices.append(base + 6); indices.append(base + 7)

	for t in range(0, indices.size(), 3):
		var pa = verts[indices[t]]
		var na = (verts[indices[t + 1]] - pa).cross(verts[indices[t + 2]] - pa)
		if na.y > 0.0:
			var tmp = indices[t]
			indices[t] = indices[t + 1]
			indices[t + 1] = tmp

	# 上面的绕序修正把每个三角形的 cross.y 压到 <=0,所以朝上的法线要取 cross 的反向。
	# 直接用正向 cross 会得到一片朝下的法线,沥青路面收不到任何阳光,渲染成纯黑。
	for t in range(0, indices.size(), 3):
		var a = verts[indices[t]]
		var n = (verts[indices[t + 2]] - a).cross(verts[indices[t + 1]] - a).normalized()
		normals[indices[t]] += n
		normals[indices[t + 1]] += n
		normals[indices[t + 2]] += n
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()

	for t in range(0, indices.size(), 3):
		var v0: Vector3 = verts[indices[t]]
		var v1: Vector3 = verts[indices[t + 1]]
		var v2: Vector3 = verts[indices[t + 2]]
		var tri_idx = _tri_data.size()
		_tri_data.append([v0, v1, v2])
		var min_x = int(floorf(minf(v0.x, minf(v1.x, v2.x)) / GRID_CELL))
		var max_x = int(floorf(maxf(v0.x, maxf(v1.x, v2.x)) / GRID_CELL))
		var min_z = int(floorf(minf(v0.z, minf(v1.z, v2.z)) / GRID_CELL))
		var max_z = int(floorf(maxf(v0.z, maxf(v1.z, v2.z)) / GRID_CELL))
		for cx in range(min_x, max_x + 1):
			for cz in range(min_z, max_z + 1):
				var key = Vector2i(cx, cz)
				if not _tri_grid.has(key):
					_tri_grid[key] = []
				_tri_grid[key].append(tri_idx)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	mat.set_shader_parameter("road_half_width", ROAD_HALF_WIDTH)
	mat.set_shader_parameter("total_half_width", TOTAL_HALF_WIDTH)
	mat.set_shader_parameter("total_width", TOTAL_WIDTH)
	mat.set_shader_parameter("tile_size", UV_SCALE)

	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func get_road_data() -> RoadData:
	return _road_data


func get_nearest_point_index(pos: Vector3) -> int:
	var pts = _road_data.points
	var best_i = 0
	var best_d = 1e9
	for i in range(pts.size()):
		var d = pos.distance_to(pts[i])
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


func get_centerline() -> Array:
	return _main_centerline


func get_all_centerlines() -> Array:
	var result: Array = [_main_centerline]
	for cl in _branch_centerlines:
		result.append(cl)
	return result


func get_road_height_at_index(idx: float) -> float:
	if _main_road_ys.is_empty():
		return 0.0
	var n = _main_road_ys.size()
	var t = clampf(idx, 0.0, float(n - 1))
	var i = int(floorf(t))
	if i >= n - 1:
		return _main_road_ys[n - 1]
	var f = t - float(i)
	return lerpf(_main_road_ys[i], _main_road_ys[i + 1], f)


func get_road_height_at_xy(wx: float, wz: float) -> float:
	if _main_road_ys.is_empty() or _main_centerline.size() < 2:
		return -INF
	var best_d := 1e9
	var best_t := 0.0
	var cl = _main_centerline
	var step = RESAMPLE_STEP
	for i in range(cl.size() - 1):
		var p0 = cl[i]
		var p1 = cl[i + 1]
		var dx = p1.x - p0.x
		var dz = p1.z - p0.z
		var len_sq = dx * dx + dz * dz
		if len_sq < 1e-8:
			continue
		var t = ((wx - p0.x) * dx + (wz - p0.z) * dz) / len_sq
		t = clampf(t, 0.0, 1.0)
		var cx = p0.x + dx * t
		var cz = p0.z + dz * t
		var d = (wx - cx) * (wx - cx) + (wz - cz) * (wz - cz)
		if d < best_d:
			best_d = d
			best_t = float(i) + t
	if best_d > TOTAL_HALF_WIDTH * TOTAL_HALF_WIDTH:
		return -INF
	return get_road_height_at_index(best_t)


## 路面高度查询。三角形质心插值法：找到所有覆盖查询点的 mesh 三角形，
## 取最大高度。8字交叉处多条三角形的 max 天然连续（max 函数在交点连续），
## 直接读取 mesh 几何与 GPU 深度缓冲一致，不需要梯度限制器。
## 路面外返回 -INF，调用方用 is_finite 判断。
func get_road_ribbon_height(wx: float, wz: float) -> float:
	var cell_x = int(floorf(wx / GRID_CELL))
	var cell_z = int(floorf(wz / GRID_CELL))
	var best_y := -INF

	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key = Vector2i(cell_x + dx, cell_z + dz)
			if not _tri_grid.has(key):
				continue
			for tri_idx in _tri_grid[key]:
				var tri = _tri_data[tri_idx]
				var v0: Vector3 = tri[0]
				var v1: Vector3 = tri[1]
				var v2: Vector3 = tri[2]

				var bx = v1.x - v0.x
				var bz = v1.z - v0.z
				var cx = v2.x - v0.x
				var cz = v2.z - v0.z
				var px = wx - v0.x
				var pz = wz - v0.z

				var denom = bx * cz - bz * cx
				if absf(denom) < 1e-10:
					continue

				var v = (px * cz - pz * cx) / denom
				var w = (bx * pz - bz * px) / denom
				var u = 1.0 - v - w

				if u < -1e-6 or v < -1e-6 or w < -1e-6:
					continue

				var y = v0.y * u + v1.y * v + v2.y * w
				if y > best_y:
					best_y = y

	return best_y


## 高斯加权平滑。窗口 9 点抹掉 GPS 抖动和 <8m 内的 180° 折返，
## 高斯权重让中心点影响更大，保留真实弯道形状。
## 端点用有效窗口归一化，避免漂移。
func _smooth(pts: Array[Vector3], window: int) -> Array[Vector3]:
	var n = pts.size()
	if n < window:
		return pts
	var half = window / 2
	var sigma = float(half) / 2.0
	var two_sigma_sq = 2.0 * sigma * sigma

	var out: Array[Vector3] = []
	for i in range(n):
		var acc := Vector3.ZERO
		var weight_sum := 0.0
		for j in range(max(0, i - half), min(n, i + half + 1)):
			var offset = float(j - i)
			var w = exp(-offset * offset / two_sigma_sq)
			acc += pts[j] * w
			weight_sum += w
		if weight_sum > 1e-8:
			acc /= weight_sum
		out.append(acc)
	return out


func _smooth_heights(heights: PackedFloat64Array, window: int) -> PackedFloat64Array:
	var n = heights.size()
	if n < window:
		return heights
	var half = window / 2
	var sigma = float(half) / 2.0
	var two_sigma_sq = 2.0 * sigma * sigma
	var out := PackedFloat64Array()
	out.resize(n)
	for i in range(n):
		var acc := 0.0
		var weight_sum := 0.0
		for j in range(max(0, i - half), min(n, i + half + 1)):
			var offset = float(j - i)
			var w = exp(-offset * offset / two_sigma_sq)
			acc += heights[j] * w
			weight_sum += w
		out[i] = acc / weight_sum if weight_sum > 1e-8 else heights[i]
	return out


## 按固定间距重采样折线（线性插值）。只用于生成路面网格，
## 不影响 RoadData.points（迷你地图、驿站定位仍用原始点位）。
func _resample(pts: Array[Vector3], step: float) -> Array[Vector3]:
	var out: Array[Vector3] = [pts[0]]
	var next_at = step
	var acc = 0.0
	for i in range(pts.size() - 1):
		var p0 = pts[i]
		var p1 = pts[i + 1]
		var seg_len = p0.distance_to(p1)
		if seg_len < 1e-4:
			continue
		var dir = (p1 - p0) / seg_len
		while next_at <= acc + seg_len:
			out.append(p0 + dir * (next_at - acc))
			next_at += step
		acc += seg_len
	out.append(pts[pts.size() - 1])
	return out


## 在 8 字中心 (world 0, _, 43) 放一个圆形沥青广场，覆盖两条 ribbon 的重叠区，
## 消除 Z-fighting。圆柱侧面朝下(看不见),顶面用主路面 shader(无中线/路缘)。
## 顶面 Y = 广场半径内 ribbon 最高点,确保视觉上不凸起,Z-fight 安全余量 0.01m。
## 顶面三角形同时注册到 _tri_data / _tri_grid,bike get_road_ribbon_height 查询
## 自动返回广场顶面,与底下 ribbon 的 max 取最高点,跨过去不会有台阶。
func _build_center_plaza() -> void:
	# 广场顶面：圆形环岛,边缘与 ribbon 平滑衔接(无台阶),中心抬到
	# 广场盘内最高地形 + PLAZA_LIFT 余量处,呈现中央高、边缘低的缓坡圆盘。
	# 不下挖地形 → 不会显得"中间凹陷";抬高中心 → 圆盘从远处也清晰可见。
	# 顶点 Y = max(ribbon, lerp(ribbon, plaza_top, smoothstep(rim, center, dist_ratio)))
	# 这样 bike 跨过圆环岛边缘时高度连续 (无悬崖),中心区盖住两条 ribbon 重叠。
	var max_terrain_in_plaza: float = -INF
	var n_radial := 5
	var n_angular := 36
	var ring_r: Array[float] = []
	for ri in range(n_radial + 1):
		ring_r.append(PLAZA_RADIUS * float(ri) / float(n_radial))
	for ri in range(n_radial + 1):
		var r: float = ring_r[ri]
		for aj in range(n_angular):
			var theta := float(aj) * TAU / float(n_angular)
			var sx: float = PLAZA_CENTER_X + cos(theta) * r
			var sz: float = PLAZA_CENTER_Z + sin(theta) * r
			var th: float = _get_terrain_height(sx, sz)
			if th > max_terrain_in_plaza:
				max_terrain_in_plaza = th
	var plaza_top_y: float = max_terrain_in_plaza + PLAZA_LIFT

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# 中心点:用 plaza_top_y(此时 ribbon 通常覆盖不到中心,fallback 到地形+抬升)
	var center_ribbon: float = get_road_ribbon_height(PLAZA_CENTER_X, PLAZA_CENTER_Z)
	var center_terrain: float = _get_terrain_height(PLAZA_CENTER_X, PLAZA_CENTER_Z)
	var center_baseline: float = center_ribbon if is_finite(center_ribbon) else center_terrain
	var center_y: float = plaza_top_y if plaza_top_y > center_baseline else center_baseline + PLAZA_LIFT
	verts.append(Vector3(PLAZA_CENTER_X, center_y + 0.01, PLAZA_CENTER_Z))
	uvs.append(Vector2(0.5, 0.5))
	# 同心环顶点:Y 在 ribbon 与 plaza_top 之间按距离比例混合
	# dist_ratio = 0 at rim, 1 at center → 边缘跟 ribbon,中心接近 plaza_top
	# 关键:baseline 不能落到 ribbon shoulder(terrain-0.15),否则广场边缘埋进山头。
	# 用 max(ribbon, terrain+ROAD_LIFT) 作为 baseline 保证广场始终高于地形。
	for ri in range(1, n_radial + 1):
		var r: float = ring_r[ri]
		for aj in range(n_angular):
			var theta := float(aj) * TAU / float(n_angular)
			var sx: float = PLAZA_CENTER_X + cos(theta) * r
			var sz: float = PLAZA_CENTER_Z + sin(theta) * r
			var rh: float = get_road_ribbon_height(sx, sz)
			var th: float = _get_terrain_height(sx, sz)
			# baseline: ribbon 在路面区取 ribbon,肩带区或无 ribbon 取 terrain+ROAD_LIFT
			var baseline: float = maxf(rh if is_finite(rh) else -INF, th + ROAD_LIFT)
			# dist_ratio: rim=0, center=1
			var dist_ratio: float = 1.0 - r / PLAZA_RADIUS
			# smoothstep 让边缘过渡平缓,中心区快速抬升
			var smooth: float = dist_ratio * dist_ratio * (3.0 - 2.0 * dist_ratio)
			var target: float = lerpf(baseline, plaza_top_y, smooth)
			# 保证不低于 baseline(bike 跨边缘无台阶)
			var h: float = target if target > baseline else baseline
			verts.append(Vector3(sx, h + 0.01, sz))
			uvs.append(Vector2(0.5 + cos(theta) * 0.5 * float(ri) / float(n_radial),
				0.5 + sin(theta) * 0.5 * float(ri) / float(n_radial)))
	# 中心 → 第一环三角形 fan
	for aj in range(n_angular):
		var a := 1 + aj
		var b := 1 + (aj + 1) % n_angular
		indices.append(0); indices.append(a); indices.append(b)
	# 环间 quad strip 切两三角形
	for ri in range(1, n_radial):
		var ring_start := 1 + (ri - 1) * n_angular
		var next_start := 1 + ri * n_angular
		for aj in range(n_angular):
			var a := ring_start + aj
			var b := ring_start + (aj + 1) % n_angular
			var c := next_start + aj
			var d := next_start + (aj + 1) % n_angular
			indices.append(a); indices.append(c); indices.append(b)
			indices.append(b); indices.append(c); indices.append(d)

	# 计算法线。绕序同样是 cross.y<0 为正面,朝上法线取 cross 的反向(同 _build_road)。
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in range(normals.size()):
		normals[i] = Vector3.ZERO
	for t in range(0, indices.size(), 3):
		var pa = verts[indices[t]]
		var n = (verts[indices[t + 2]] - pa).cross(verts[indices[t + 1]] - pa).normalized()
		normals[indices[t]] += n
		normals[indices[t + 1]] += n
		normals[indices[t + 2]] += n
	for i in range(normals.size()):
		if normals[i].length_squared() > 1e-8:
			normals[i] = normals[i].normalized()
		else:
			normals[i] = Vector3.UP

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh

	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	# plaza_mode=1 关掉中线/车道线/路缘起灰,广场看起来就是干净沥青圆盘
	mat.set_shader_parameter("road_half_width", PLAZA_RADIUS)
	mat.set_shader_parameter("total_half_width", PLAZA_RADIUS)
	mat.set_shader_parameter("total_width", PLAZA_RADIUS * 2.0)
	mat.set_shader_parameter("tile_size", UV_SCALE)
	mat.set_shader_parameter("plaza_mode", 1.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	# 注册广场顶面三角形到 _tri_data / _tri_grid,bike 高度查询用广场面
	for t in range(0, indices.size(), 3):
		var a = verts[indices[t]]
		var b = verts[indices[t + 1]]
		var c = verts[indices[t + 2]]
		var tri_idx = _tri_data.size()
		_tri_data.append([a, b, c])
		var min_x = int(floorf(minf(a.x, minf(b.x, c.x)) / GRID_CELL))
		var max_x = int(floorf(maxf(a.x, maxf(b.x, c.x)) / GRID_CELL))
		var min_z = int(floorf(minf(a.z, minf(b.z, c.z)) / GRID_CELL))
		var max_z = int(floorf(maxf(a.z, maxf(b.z, c.z)) / GRID_CELL))
		for cx in range(min_x, max_x + 1):
			for cz in range(min_z, max_z + 1):
				var key = Vector2i(cx, cz)
				if not _tri_grid.has(key):
					_tri_grid[key] = []
				_tri_grid[key].append(tri_idx)
