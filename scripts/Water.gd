extends Node3D
## Water — 三处水（南溪 / 湖湾 / 西湾）的水面。
##
## 碗由 `water_data.gd` 定义、地形由 `TerrainBuilder` 按同一份定义挖出，
## 这里只负责**沿碗把水面画出来**，外加一件地形做不到的事：岸线。
##
## 岸线是逐角度**在真实地形上步进求交**出来的，不是"以碗心为圆心画个圆"。
## 圆盘会在两处出错：碗边的地形本来就起伏，圆的边要么压在土上（水断在半路，
## 像一块蓝玻璃斜插进坡里），要么悬在土上（水铺过岸、漫到岸外变成一张蓝纸）。
## 步进法得到的半径天然跟着地形走，岸线因此和碗口严丝合缝。

const WaterDataRef = preload("res://scripts/water_data.gd")
const SHADER_PATH := "res://assets/shaders/water.gdshader"

## 逐角度求交时的步长。2m 对 6.25m 的地形格来说已经够细——再细也只是
## 在同两个格之间插值，而地形本身在格内是线性的。
const EDGE_STEP := 2.0
## 求交时的二分次数。只为了把"跨过水位的那一步"收进厘米级，6 次足够。
const EDGE_REFINE := 6
const SEGMENTS := 64
const RINGS := 5
## 水面比水位低这么多，让地形在岸线那一像素上赢。
## 不写的话水面和地形在交线上同高，掠射角下会闪出一圈 z-fighting 的锯齿。
const MESH_DROP := 0.04
## 某个方向上找不到交点（碗心就已经在水位之上）时给的最小半径。
const MIN_RADIUS := 3.0

var _bodies: Array = []


func setup(terrain_builder: Node, sun: DirectionalLight3D) -> void:
	if terrain_builder == null or not terrain_builder.has_method("get_height_at"):
		return
	for b in WaterDataRef.basins():
		var body := _build_body(b, terrain_builder, sun)
		if body != null:
			_bodies.append(body)
			add_child(body)


## 黄昏染色。`DayCycle` 和 `FarRidge` 一起调，否则水在正午和黄昏是两个世界。
func set_tint(tint: Color) -> void:
	for b in _bodies:
		var mat: ShaderMaterial = b.material_override
		mat.set_shader_parameter("dusk_tint", tint)
		mat.set_shader_parameter("dusk_mix", clampf((1.0 - tint.r) * 1.6, 0.0, 1.0))


func bodies() -> Array:
	return _bodies


func _build_body(b: Dictionary, tb: Node, sun: DirectionalLight3D) -> MeshInstance3D:
	var c: Vector2 = b["center"]
	# 水位是全场统一的常数（water_data.WATER_LEVEL），不是"碗底 + 一点"。
	# 之所以敢这么定，是因为它压在自然地形下限 -3.0 之下——见 water_data.gd
	# 文件头。这里**不许**再按地形回推：碗心落在 6.25m 的格上，回推出来的
	# 是那一格的高程，会把水位钉死在 ±0.3m 的量化误差上，顺坡的一侧就漫出去了。
	var level: float = b["level"]

	var radii: PackedFloat32Array = _shoreline(b, level, tb)
	var max_r: float = 0.0
	for r in radii:
		max_r = maxf(max_r, r)
	if max_r <= 0.0:
		return null

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.append(Vector3(c.x, level - MESH_DROP, c.y))
	uvs.append(Vector2(0.5, 0.5))
	for ring in range(1, RINGS + 1):
		var t := float(ring) / float(RINGS)
		for s in range(SEGMENTS):
			var a := TAU * float(s) / float(SEGMENTS)
			var r: float = radii[s] * t
			verts.append(Vector3(c.x + cos(a) * r, level - MESH_DROP, c.y + sin(a) * r))
			uvs.append(Vector2(0.5 + cos(a) * t * 0.5, 0.5 + sin(a) * t * 0.5))
	for s in range(SEGMENTS):
		indices.append(0)
		indices.append(1 + s)
		indices.append(1 + (s + 1) % SEGMENTS)
	for ring in range(RINGS - 1):
		var base := 1 + ring * SEGMENTS
		var nxt := base + SEGMENTS
		for s in range(SEGMENTS):
			var s1 := (s + 1) % SEGMENTS
			indices.append(base + s)
			indices.append(nxt + s)
			indices.append(nxt + s1)
			indices.append(base + s)
			indices.append(nxt + s1)
			indices.append(base + s1)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	mat.set_shader_parameter("center", c)
	mat.set_shader_parameter("radius", max_r)
	if sun != null:
		mat.set_shader_parameter("sun_dir", -sun.global_transform.basis.z.normalized())

	var mi := MeshInstance3D.new()
	mi.name = "Water%d" % int(b["station"])
	mi.mesh = mesh
	mi.material_override = mat
	# 水面要接阴影（岸上的树会在水面上落影），自己不投影——一张平片投影
	# 只会把整片水的自阴影算成噪声。
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("station", int(b["station"]))
	mi.set_meta("level", level)
	mi.set_meta("radius", max_r)
	return mi


## 逐角度找出"地形高过水位"的那个半径。
##
## 步进而不是解方程：碗形是解析的，但**建出来的地形网格**是三角面线性插值，
## 水位落在哪一格上有 ±0.3m 的量化误差，没有闭式解。
## 步进 2m 找到跨过去的那一格，再二分 6 次收进厘米。
##
## 每个角度的搜索上限**不是 `radius`**：碗是沿路拉长的椭圆（`squash`），
## 所以同一半径在长轴方向上落在碗**里面**、在短轴方向上落在碗**外面**。
## 拿 `radius` 当上限的话，溪那种 squash=3.2 的碗会被齐腰剪断——水面在
## 22m 处收边，而碗其实一直伸到 70m，于是水面边缘是一条悬在半空里的直线。
## 正确的上限是"沿这个方向走到碗沿还有多远"，即 `r / |(dir·along)/squash, dir·away|`。
##
## 找不到交点时退回那个上限：真出现这种角说明碗根本没挖到那儿去，
## 而水面总得有个东西——留一个满盆沿的半径，至少水还是压在土里的，
## 而不是 MIN_RADIUS 那个小圆（那才会变成半空中的一块蓝片）。
func _shoreline(b: Dictionary, level: float, tb: Node) -> PackedFloat32Array:
	var c: Vector2 = b["center"]
	var r_max: float = float(b["radius"])
	var along := Vector2(float(b["ax"]), float(b["az"]))
	var away := Vector2(along.y, -along.x)
	var squash: float = float(b["squash"])
	var out := PackedFloat32Array()
	out.resize(SEGMENTS)
	for s in range(SEGMENTS):
		var a := TAU * float(s) / float(SEGMENTS)
		var dir := Vector2(cos(a), sin(a))
		var u: float = (dir.x * along.x + dir.y * along.y) / squash
		var v: float = dir.x * away.x + dir.y * away.y
		var span: float = r_max / maxf(sqrt(u * u + v * v), 1e-6)
		var prev_r := 0.0
		var edge := span
		var r := EDGE_STEP
		while r <= span:
			var p := c + dir * r
			if tb.get_height_at(p.x, p.y) - level >= 0.0:
				# 跨过水位了：二分这一格
				var lo := prev_r
				var hi := r
				for _i in range(EDGE_REFINE):
					var mid := (lo + hi) * 0.5
					var pm := c + dir * mid
					if tb.get_height_at(pm.x, pm.y) - level >= 0.0:
						hi = mid
					else:
						lo = mid
				edge = lo
				break
			prev_r = r
			r += EDGE_STEP
		out[s] = maxf(edge, MIN_RADIUS)
	return out
