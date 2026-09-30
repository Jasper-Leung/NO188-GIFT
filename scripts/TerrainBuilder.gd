extends Node3D
## TerrainBuilder — 生成程序化3D地形mesh

const TERRAIN_SIZE := 800.0
const TERRAIN_RES := 128
const MAX_HEIGHT := 25.0
## 地面基色。terrain_grass.gdshader 和 grass.gdshader 都从这里取，
## 草皮的底色必须等于脚下那块地的颜色，否则草和地会明显分家。
const BASE_COLOR := Color(0.36, 0.55, 0.24, 1.0)
const SHADER_PATH := "res://assets/shaders/terrain_grass.gdshader"

var _mesh_instance: MeshInstance3D
var _height_grid: PackedFloat64Array = []
var _grid_cs: float = 0.0


func _ready() -> void:
	_build_terrain()


func _build_terrain() -> void:
	var res = TERRAIN_RES
	var size = TERRAIN_SIZE
	var cell_size = size / res
	_build_height_grid()

	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()

	for z in range(res + 1):
		for x in range(res + 1):
			var wx = (x as float) / res * size - size * 0.5
			var wz = (z as float) / res * size - size * 0.5
			verts.append(Vector3(wx, _height_grid[z * (res + 1) + x], wz))
			uvs.append(Vector2(x as float / res, z as float / res))

	for z in range(res):
		for x in range(res):
			var i = z * (res + 1) + x
			# Godot 4.6 cull_back: cross.y<0 为正面。顶点顺序 (i, i+1, i+res+1)
			# 让 cross.y = -cs^2 < 0，整张地形正面朝上。
			indices.append(i)
			indices.append(i + 1)
			indices.append(i + res + 1)
			indices.append(i + 1)
			indices.append(i + res + 2)
			indices.append(i + res + 1)

	# 顶点法线 = 相邻三角形法线平均
	# 上面为了 cull_back 把绕序定成 cross.y<0 为正面,所以朝上的法线是 cross 的反向。
	# 早先直接用 (v1-v0)×(v2-v0),法线全朝下,地形一点阳光都收不到,渲染成一片黑。
	var nrm := PackedVector3Array()
	nrm.resize(verts.size())
	for t in range(0, indices.size(), 3):
		var a = verts[indices[t]]
		var n = (verts[indices[t + 2]] - a).cross(verts[indices[t + 1]] - a).normalized()
		nrm[indices[t]] += n
		nrm[indices[t + 1]] += n
		nrm[indices[t + 2]] += n
	var normals := PackedVector3Array()
	for i in range(nrm.size()):
		normals.append(nrm[i].normalized())

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var colors := PackedColorArray()
	# 顶点色只做明暗扰动(0.82~1.0),绿色本体交给 shader 的 ground_color。
	# 早先把绿色同时写进顶点色和 albedo,两者相乘后地面亮度只剩 ~0.05,整片发黑。
	#
	# 用 _noise2d 而不是全局 randf():randf() 没播种,每次运行这层明暗都不一样,
	# 而且是逐顶点白噪声,在 6.25m 一格的地形上读起来是雪花而不是斑驳。
	# _noise2d 是连续场且确定,同一个世界坐标永远给同一个值。注意它经
	# _hash2d 输出的是 [-1,1],要先搬到 [0,1] 再映射到 0.82~1.0。
	var row: int = res + 1
	for i in range(verts.size()):
		var wx: float = (i % row) as float / res * size - size * 0.5
		var wz: float = (i / row) as float / res * size - size * 0.5
		var v := 0.82 + (_noise2d(wx * 0.09, wz * 0.09) * 0.5 + 0.5) * 0.18
		colors.append(Color(v * 1.02, v, v * 0.94, 1.0))
	arrays[Mesh.ARRAY_COLOR] = colors

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# vertex_color_use_as_albedo 是 BaseMaterial3D 专有标志,ShaderMaterial 上无效,
	# 那层 0.82~1.0 的顶点明暗改由 shader 里显式 col *= COLOR.rgb 乘回去。
	var shader: Shader = load(SHADER_PATH)
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("ground_color", BASE_COLOR)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = mat
	# 800m 见方的地面整体投影对阴影贴图毫无收益（几乎全平），却要每帧重绘整个
	# 阴影 pass。关掉后自行车/树的投影仍能落在地面上（那是 receive，不是 cast）。
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)


func _height(x: float, z: float) -> float:
	var h = 0.0
	h += _fbm(x * 0.008, z * 0.008, 3) * 8.0
	h += _fbm(x * 0.02, z * 0.02, 2) * 2.0
	h += _fbm(x * 0.06, z * 0.06, 1) * 0.5
	# 地形不在广场区下挖(避免中间凹陷感),改由 RoadBuilder 把广场盘抬到
	# 该区最高地形之上 0.5m,呈现圆形环岛而非凹陷坑。
	return clamp(h, -3.0, 6.0)


func _fbm(x: float, z: float, octaves: int) -> float:
	var val = 0.0
	var amp = 0.5
	var freq = 1.0
	for _i in range(octaves):
		val += _noise2d(x * freq, z * freq) * amp
		amp *= 0.5
		freq *= 2.0
	return val


func _noise2d(x: float, z: float) -> float:
	var ix = floori(x)
	var iz = floori(z)
	var fx = x - ix
	var fz = z - iz
	var ux = fx * fx * (3.0 - 2.0 * fx)
	var uz = fz * fz * (3.0 - 2.0 * fz)
	var a = _hash2d(ix, iz)
	var b = _hash2d(ix + 1, iz)
	var c = _hash2d(ix, iz + 1)
	var d = _hash2d(ix + 1, iz + 1)
	return lerp(lerp(a, b, ux), lerp(c, d, ux), uz)


func _hash2d(ix: int, iz: int) -> float:
	var n = ix * 127 + iz * 311
	n = (n << 13) ^ n
	n = n * (n * n * 15731 + 789221) + 1376312589
	return fmod(float(n & 0x7fffffff) / 1073741824.0, 1.0) * 2.0 - 1.0


## 可见地面高度。必须和 mesh 顶点一致：mesh 是 6.25m 网格 + 三角形线性插值，
## 而 _height() 是连续 FBM，两者最多差 ~0.3m。之前 get_height_at 返回连续值，
## 自行车/路面/植被全按连续值吸附，就会相对可见网格陷进去或浮起来。
func get_height_at(wx: float, wz: float) -> float:
	if _height_grid.is_empty():
		return _height(wx, wz)
	var res = TERRAIN_RES
	var cs = _grid_cs
	var gx = (wx + TERRAIN_SIZE * 0.5) / cs
	var gz = (wz + TERRAIN_SIZE * 0.5) / cs
	var x0 = clampi(int(floor(gx)), 0, res - 1)
	var z0 = clampi(int(floor(gz)), 0, res - 1)
	var fx = clampf(gx - float(x0), 0.0, 1.0)
	var fz = clampf(gz - float(z0), 0.0, 1.0)
	var r = res + 1
	var i00 = z0 * r + x0
	if fx + fz <= 1.0:
		return _tri_height_at(
			Vector3(x0 * cs - TERRAIN_SIZE * 0.5, _height_grid[i00], z0 * cs - TERRAIN_SIZE * 0.5),
			Vector3((x0 + 1) * cs - TERRAIN_SIZE * 0.5, _height_grid[i00 + 1], z0 * cs - TERRAIN_SIZE * 0.5),
			Vector3(x0 * cs - TERRAIN_SIZE * 0.5, _height_grid[i00 + r], (z0 + 1) * cs - TERRAIN_SIZE * 0.5),
			Vector3(wx, 0.0, wz))
	return _tri_height_at(
		Vector3((x0 + 1) * cs - TERRAIN_SIZE * 0.5, _height_grid[i00 + 1], z0 * cs - TERRAIN_SIZE * 0.5),
		Vector3((x0 + 1) * cs - TERRAIN_SIZE * 0.5, _height_grid[i00 + r + 1], (z0 + 1) * cs - TERRAIN_SIZE * 0.5),
		Vector3(x0 * cs - TERRAIN_SIZE * 0.5, _height_grid[i00 + r], (z0 + 1) * cs - TERRAIN_SIZE * 0.5),
		Vector3(wx, 0.0, wz))


func _tri_height_at(a: Vector3, b: Vector3, c: Vector3, p: Vector3) -> float:
	var bx = float(b.x) - float(a.x)
	var bz = float(b.z) - float(a.z)
	var cx = float(c.x) - float(a.x)
	var cz = float(c.z) - float(a.z)
	var px = float(p.x) - float(a.x)
	var pz = float(p.z) - float(a.z)
	var denom = bx * cz - bz * cx
	if absf(denom) < 1e-10:
		return a.y
	var v = (px * cz - pz * cx) / denom
	var w = (bx * pz - bz * px) / denom
	var u = 1.0 - v - w
	return a.y * u + b.y * v + c.y * w


func _build_height_grid() -> void:
	var res = TERRAIN_RES
	var size = TERRAIN_SIZE
	_grid_cs = size / res
	_height_grid.resize((res + 1) * (res + 1))
	for z in range(res + 1):
		for x in range(res + 1):
			var wx = (x as float) / res * size - size * 0.5
			var wz = (z as float) / res * size - size * 0.5
			_height_grid[z * (res + 1) + x] = _height(wx, wz)
