extends Node3D
## VegBuilder — 路边植被批量铺 (PRD §7.1) + 流式加载
## 数据驱动：PLANTS 定义植被种类、颜色桶、距离范围
## 每种植植被可有多个 part（如 tree = canopy + trunk），共享位置/缩放
## 流式：按路网点分 CHUNKS_PER_PLANT 块，启动只建起点附近，走近才建其余
## 可见：仅渲染玩家前后 VISIBLE_WINDOW 块内的实例，远处 chunk 隐藏（降 draw/vertex）
## 未来替换 3D 模型：part.mesh_path 填资源路径即 load 替代 PrimitiveMesh
## 未来加纹理：part.material_path 填资源路径即 load 替代 StandardMaterial3D
## 距离基于渲染中心线（主路 + 支路），rejection sampling 防止压到路面
## (RoadBuilder: TOTAL_HALF_WIDTH=6.5m, min_off 已考虑缓冲)
## 注意：同一 plant 的 parts 必须用相同数量的 colors（当前 3 色桶）

@export var seed_value: int = 2180911

const CHUNKS_PER_PLANT = 16
const BUILD_WINDOW = 3
const VISIBLE_WINDOW = 2
const MAX_NEW_CHUNKS_PER_TICK = 3
const TICK_INTERVAL = 0.25
## 横向避让用的折线间距。2m 对 min_off>=25 的判断足够精确，
## 段数只有渲染中心线的 1/4，400 棵植物的拒绝采样不会卡启动。
const ROAD_POLY_STEP = 2.0
## 植被必须落在地形 mesh 内：地形只有 800×800，越界处没有地面，
## 物体就悬在虚空里（路的南北端最明显，中心线距地形边缘只有 ~44m）。
const TERRAIN_MARGIN = 20.0
const STATION_BUSH_CLEAR_RADIUS := 35.0

var _road_sample_2d: PackedVector2Array = []
var _road_polys_2d: Array[PackedVector2Array] = []
var _terrain: Node3D = null
var _player: Node3D = null
var _protected_positions: PackedVector3Array = []
var _rng = RandomNumberGenerator.new()
var _chunks_plants: Array = []
var _mesh_cache: Dictionary = {}
var _player_chunk = 0
var _tick_interval = 0.0
# 编辑模式 / res://layout.json 提供的植物覆盖:{type_name: Array of {pos, rot_y_deg, scale, seg_idx}}
var _plant_overrides: Dictionary = {}

const PLANTS: Array = [
	# bush — 灌木丛 (GLB + 程序化回退)
	{
		"name": "bush",
		"count": 320,
		"min_off": 25.0,
		"max_off": 180.0,
		"scale_range": [0.6, 2.0],
		"extra_rotation": false,
		"parts": [
			{
				"kind": "sphere",
				"size": Vector3(0.85, 0.7, 6.0),
				"y_offset": 0.0,
				"colors": [
					Color(0.20, 0.32, 0.16),
					Color(0.26, 0.40, 0.20),
					Color(0.30, 0.44, 0.22),
				],
				"mesh_path": "res://assets/models/bush.glb",
				"material_path": "",
			}
		],
	},
	# tree — 树 (GLB + 程序化回退)
	{
		"name": "tree",
		"count": 80,
		"min_off": 45.0,
		"max_off": 240.0,
		"scale_range": [4.0, 7.0],
		"extra_rotation": false,
		"parts": [
			{
				"kind": "sphere",
				"size": Vector3(2.2, 2.8, 8.0),
				"y_offset": 0.0,
				"colors": [
					Color(0.16, 0.30, 0.12),
					Color(0.20, 0.34, 0.14),
					Color(0.24, 0.38, 0.16),
				],
				"mesh_path": "res://assets/models/tree.glb",
				"material_path": "",
			},
		],
	},
]


func setup(points: Array, terrain: Node3D, player: Node3D, centerlines: Array = [], protected_positions: Array = [], plant_overrides: Dictionary = {}) -> void:
	_terrain = terrain
	_player = player
	_rng.seed = seed_value
	_road_sample_2d.clear()
	_road_polys_2d.clear()
	_chunks_plants.clear()
	_mesh_cache.clear()
	_protected_positions.clear()
	_plant_overrides.clear()
	for pos in protected_positions:
		if pos is Vector3:
			_protected_positions.append(pos)
	# 接受来自 LayoutData 的植物覆盖(按 type -> Array 分组)
	for k in plant_overrides.keys():
		var v = plant_overrides[k]
		if v is Array:
			_plant_overrides[String(k)] = v
	_player_chunk = 0
	_tick_interval = 0.0

	if centerlines.is_empty():
		_road_polys_2d.append(_build_road_polyline(points))
	else:
		var normalized: Array = centerlines
		if typeof(centerlines[0]) == TYPE_ARRAY:
			normalized = centerlines
		else:
			normalized = [centerlines]
		for line in normalized:
			_road_polys_2d.append(_build_road_polyline(line))
	if not _road_polys_2d.is_empty():
		for p in _road_polys_2d[0]:
			_road_sample_2d.append(p)
	if _road_sample_2d.is_empty():
		for p in points:
			_road_sample_2d.append(Vector2(p.x, p.z))
		if _road_polys_2d.is_empty():
			_road_polys_2d.append(_build_road_polyline(points))

	_player_chunk = _pos_to_chunk(player.global_position) if player != null else 0

	for plant in PLANTS:
		_prepare_plant(plant)

	# 启动时只建起点附近的 chunk
	for pdata in _chunks_plants:
		for c in range(CHUNKS_PER_PLANT):
			if _chunk_distance(c, _player_chunk) <= BUILD_WINDOW:
				_build_chunk(pdata, c)


func _idx_to_chunk(idx: int) -> int:
	var n = _road_sample_2d.size()
	if n <= 0:
		return 0
	return clampi(int(idx * CHUNKS_PER_PLANT / float(n)), 0, CHUNKS_PER_PLANT - 1)


func _pos_to_chunk(pos: Vector3) -> int:
	if _road_sample_2d.is_empty():
		return 0
	var pp = Vector2(pos.x, pos.z)
	var min_d = 9999.0
	var min_idx = 0
	for i in range(_road_sample_2d.size()):
		var d = pp.distance_to(_road_sample_2d[i])
		if d < min_d:
			min_d = d
			min_idx = i
	return _idx_to_chunk(min_idx)


func _chunk_distance(a: int, b: int) -> int:
	var d = absi(a - b)
	return mini(d, CHUNKS_PER_PLANT - d)


func tick(delta: float) -> void:
	if _player == null:
		return
	_tick_interval += delta
	if _tick_interval < TICK_INTERVAL:
		return
	_tick_interval = 0.0

	var new_chunk = _pos_to_chunk(_player.global_position)
	if new_chunk == _player_chunk:
		return
	_player_chunk = new_chunk

	for pdata in _chunks_plants:
		for c in range(CHUNKS_PER_PLANT):
			if not pdata.built[c]:
				continue
			var vis = _chunk_distance(c, new_chunk) <= VISIBLE_WINDOW
			for mmi in pdata.mmis[c]:
				if mmi.visible != vis:
					mmi.visible = vis

	var to_build = []
	for pdata in _chunks_plants:
		for c in range(CHUNKS_PER_PLANT):
			if pdata.built[c]:
				continue
			var d = _chunk_distance(c, new_chunk)
			if d <= BUILD_WINDOW:
				to_build.append({"pdata": pdata, "c": c, "d": d})

	if to_build.is_empty():
		return
	to_build.sort_custom(func(a, b): return a.d < b.d)
	for i in range(mini(to_build.size(), MAX_NEW_CHUNKS_PER_TICK)):
		_build_chunk(to_build[i].pdata, to_build[i].c)


func _prepare_plant(cfg: Dictionary) -> void:
	var count = cfg.count
	var items = []
	var type_name: String = cfg["name"]
	if _plant_overrides.has(type_name):
		# 覆盖路径:把 LayoutData 的覆盖项转成 item,跳过程序化生成
		var ovs: Array = _plant_overrides[type_name]
		for ov in ovs:
			var pos: Vector3 = ov["pos"]
			# 重新贴齐地形:editor 保存的 Y 在运行时地形变化时仍能正确放置
			if _terrain != null and _terrain.has_method("get_height_at"):
				pos.y = _terrain.get_height_at(pos.x, pos.z)
			var rot_y_deg: float = float(ov.get("rot_y_deg", 0.0))
			var scale: float = float(ov.get("scale", 1.0))
			var seg_idx: int = int(ov.get("seg_idx", 0))
			var b = Basis().rotated(Vector3.UP, deg_to_rad(rot_y_deg))
			items.append({"pos": pos, "scale": scale, "basis": b, "seg_idx": seg_idx})
	else:
		for i in range(count):
			var prefer_north = i % 2 == 0
			var result = _rand_pos_near_road(cfg.min_off, cfg.max_off, prefer_north, cfg.name)
			if not result.valid:
				continue
			var pos = result.pos
			var seg_idx = result.seg_idx
			var scale = _rng.randf_range(cfg.scale_range[0], cfg.scale_range[1])
			var b = Basis().rotated(Vector3.UP, _rng.randf() * TAU)
			if cfg.extra_rotation:
				b = b.rotated(Vector3.RIGHT, deg_to_rad(_rng.randf_range(-25, 25)))
				b = b.rotated(Vector3.FORWARD, deg_to_rad(_rng.randf_range(-25, 25)))
			items.append({"pos": pos, "scale": scale, "basis": b, "seg_idx": seg_idx})

	var chunk_defs = []
	for _c in range(CHUNKS_PER_PLANT):
		chunk_defs.append([])
	for item in items:
		var c = _idx_to_chunk(item.seg_idx)
		chunk_defs[c].append(item)

	var chunk_mmis = []
	var chunk_built = []
	for _c in range(CHUNKS_PER_PLANT):
		chunk_mmis.append([])
		chunk_built.append(false)

	_chunks_plants.append({
		"name": cfg.name,
		"config": cfg,
		"chunk_defs": chunk_defs,
		"mmis": chunk_mmis,
		"built": chunk_built,
	})


## 组装 part 的实例变换。缩放只作用于 basis，不作用于原点——
## Transform3D.scaled() 会把 origin 一起缩放（origin.y * s），
## 那正是灌木平均浮 0.74m、树平均浮 7.79m 的根因。
## static 是刻意的：tools/ 的无头回归要能在不实例化节点的情况下调用它
## （--headless 的 dummy renderer 回读 MultiMesh.get_instance_transform()
##   一律返回单位矩阵，没法从 GPU 侧验证）。
static func instance_transform(item_basis: Basis, part_pos: Vector3, y_offset: float, s: float) -> Transform3D:
	var p: Vector3 = part_pos + Vector3(0.0, y_offset * s, 0.0)
	return Transform3D(item_basis.scaled(Vector3(s, s, s)), p)


func _build_chunk(pdata: Dictionary, chunk_idx: int) -> void:
	var items = pdata.chunk_defs[chunk_idx]
	if items.is_empty():
		pdata.built[chunk_idx] = true
		return

	var cfg = pdata.config
	var parts = cfg.parts
	var all_mmis = []

	for part in parts:
		var mesh_path: String = part.get("mesh_path", "")
		var mat_path: String = part.get("material_path", "")
		var use_external = not mesh_path.is_empty() and ResourceLoader.exists(mesh_path)

		if use_external:
			var ext_mesh = _get_cached_mesh(mesh_path, mat_path)
			if ext_mesh != null:
				var mm = MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = ext_mesh
				mm.instance_count = items.size()
				var mmi = MultiMeshInstance3D.new()
				mmi.multimesh = mm
				add_child(mmi)
				all_mmis.append(mmi)
				for i in range(items.size()):
					var item = items[i]
					mm.set_instance_transform(i,
						instance_transform(item.basis, item.pos, part.y_offset, item.scale))
			else:
				print("[VegBuilder] GLB mesh failed for " + mesh_path + ", falling back to procedural")
				use_external = false

		if not use_external:
			var colors = part.colors
			var B = colors.size()
			var bucket_counts = []
			for _b in range(B):
				bucket_counts.append(0)
			for i in range(items.size()):
				bucket_counts[i % B] += 1

			var bucket_mms = []
			for _b in range(B):
				bucket_mms.append(null)

			for b in range(B):
				if bucket_counts[b] == 0:
					continue
				var mesh = _create_mesh(part.kind, part.size, colors[b])
				var mm = MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = mesh
				mm.instance_count = bucket_counts[b]
				var mmi = MultiMeshInstance3D.new()
				mmi.multimesh = mm
				add_child(mmi)
				all_mmis.append(mmi)
				bucket_mms[b] = mm

			var bucket_slots = []
			for _b in range(B):
				bucket_slots.append(0)

			for i in range(items.size()):
				var item = items[i]
				var b = i % B
				var slot = bucket_slots[b]
				bucket_slots[b] += 1
				bucket_mms[b].set_instance_transform(slot,
					instance_transform(item.basis, item.pos, part.y_offset, item.scale))

	var vis = _chunk_distance(chunk_idx, _player_chunk) <= VISIBLE_WINDOW
	for mmi in all_mmis:
		mmi.visible = vis

	pdata.mmis[chunk_idx] = all_mmis
	pdata.built[chunk_idx] = true


func _get_cached_mesh(mesh_path: String, mat_path: String) -> Mesh:
	if _mesh_cache.has(mesh_path):
		return _mesh_cache[mesh_path]
	var mesh = _load_external_mesh(mesh_path, mat_path)
	_mesh_cache[mesh_path] = mesh
	return mesh


func _create_mesh(kind: String, size: Vector3, color: Color) -> Mesh:
	var m: Mesh
	match kind:
		"box":
			var bm = BoxMesh.new()
			bm.size = size
			m = bm
		"sphere":
			var sm = SphereMesh.new()
			sm.radius = size.x
			sm.height = size.y
			sm.radial_segments = int(size.z)
			sm.rings = int(size.z * 0.6)
			m = sm
		"cylinder":
			var cm = CylinderMesh.new()
			cm.top_radius = size.x
			cm.bottom_radius = size.y
			cm.height = size.z
			cm.radial_segments = 8
			m = cm
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mat.metallic = 0.0
	m.material = mat
	return m


func _load_external_mesh(mesh_path: String, mat_path: String) -> Mesh:
	var resource = load(mesh_path)
	if resource == null:
		push_warning("load() returned null for " + mesh_path)
		return null
	var mesh: Mesh
	if resource is PackedScene:
		var node = resource.instantiate()
		var mi = _find_mesh_instance(node)
		if mi == null or mi.mesh == null:
			print("[VegBuilder] No mesh found in " + mesh_path + " — node tree:")
			_print_tree(node, 1)
			node.free()
			return null
		mesh = mi.mesh
		node.free()
		var aabb = mesh.get_aabb()
		print("[VegBuilder] Loaded mesh from " + mesh_path + " — AABB: " + str(aabb))
	elif resource is Mesh:
		mesh = resource
	else:
		push_warning("Unsupported resource type for " + mesh_path)
		return null
	if mesh == null:
		return null
	if not mat_path.is_empty() and ResourceLoader.exists(mat_path):
		var mat = load(mat_path)
		for surface in range(mesh.get_surface_count()):
			mesh.set_surface_override_material(surface, mat)

	return mesh


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.mesh != null:
		return node
	for child in node.get_children():
		var result = _find_mesh_instance(child)
		if result:
			return result
	return null


func _print_tree(node: Node, depth: int) -> void:
	var indent = "  ".repeat(depth)
	print(indent + str(node.name) + " (" + str(node.get_class()) + ")")
	for child in node.get_children():
		_print_tree(child, depth + 1)


func _rand_pos_near_road(min_off: float, max_off: float, prefer_north: bool, plant_name: String) -> Dictionary:
	var n = _road_sample_2d.size()
	if n < 2:
		return {"valid": false, "pos": Vector3.ZERO, "seg_idx": 0}
	var max_attempts = 48
	var pos = Vector3.ZERO
	var idx = 0
	for _attempt in range(max_attempts):
		idx = int(_rng.randf() * (n - 1))
		var p1 = Vector3(_road_sample_2d[idx].x, 0.0, _road_sample_2d[idx].y)
		var p2 = Vector3(_road_sample_2d[idx + 1].x, 0.0, _road_sample_2d[idx + 1].y)
		var t = _rng.randf()
		pos = p1.lerp(p2, t)
		var dir = (p2 - p1).normalized()
		var perp = Vector3(-dir.z, 0, dir.x)
		var off = _rng.randf_range(min_off, max_off)
		if _rng.randf() < 0.5:
			off = -off
		pos = pos + perp * off
		if prefer_north and pos.z >= 0.0:
			continue
		if not prefer_north and pos.z <= 0.0:
			continue
		if _terrain != null and _terrain.has_method("get_height_at"):
			pos.y = _terrain.get_height_at(pos.x, pos.z)
		if plant_name == "bush" and _near_protected_position(pos):
			continue
		if _in_terrain(pos) and _min_dist_to_road_2d(pos) >= min_off:
			return {"valid": true, "pos": pos, "seg_idx": idx}
	return {"valid": false, "pos": Vector3.ZERO, "seg_idx": 0}


func _near_protected_position(pos: Vector3) -> bool:
	for protected_pos in _protected_positions:
		if pos.distance_to(protected_pos) <= STATION_BUSH_CLEAR_RADIUS:
			return true
	return false


## 到路的真实距离：量到折线“线段”，不是量到离散的点云。
## 原来量点云（487 点、间距 0.3~9m）时，稀疏段之间的“假距离”远大于
## 真实横向偏移，min_off 基本失效——植被会压到路边。
func _min_dist_to_road_2d(pos: Vector3) -> float:
	var pp = Vector2(pos.x, pos.z)
	var best = 1e9
	for poly in _road_polys_2d:
		for i in range(poly.size() - 1):
			var a = poly[i]
			var ab = poly[i + 1] - a
			var l2 = ab.length_squared()
			if l2 < 1e-9:
				best = minf(best, pp.distance_to(a))
				continue
			var t := clampf((pp - a).dot(ab) / l2, 0.0, 1.0)
			best = minf(best, pp.distance_to(a + ab * t))
	return best


## 把渲染中心线抽稀成 ROAD_POLY_STEP 间距的折线，只用于距离判断。
## 没拿到中心线时退回原始点位，行为同旧版。
func _build_road_polyline(centerline: Array) -> PackedVector2Array:
	var src: Array = centerline
	var poly := PackedVector2Array()
	var last := Vector2.INF
	for p in src:
		var v := Vector2(p.x, p.z)
		if poly.is_empty() or v.distance_to(last) >= ROAD_POLY_STEP:
			poly.append(v)
			last = v
	return poly


func _in_terrain(pos: Vector3) -> bool:
	if _terrain == null:
		return true
	var v = _terrain.get("TERRAIN_SIZE")
	if v == null:
		return true
	var half = float(v) * 0.5 - TERRAIN_MARGIN
	return absf(pos.x) <= half and absf(pos.z) <= half


## 编辑器读:把当前 chunk_defs 全部扁平化为 {type, pos, rot_y_deg, scale, seg_idx}
## 用于编辑器侧栏列表 / Ctrl+S 快照 / editor 重置功能。
## 只含程序化已生成的项;覆盖路径生成的项同源(走同一个 chunk_defs),
## 所以编辑器既能编辑"程序化布局"也能编辑"覆盖布局"。
func get_all_items() -> Array:
	var out := []
	for pdata in _chunks_plants:
		var type_name: String = pdata["name"]
		for chunk_idx in range(pdata.chunk_defs.size()):
			for item in pdata.chunk_defs[chunk_idx]:
				out.append({
					"type": type_name,
					"pos": item["pos"],
					"scale": item["scale"],
					"rot_y_deg": rad_to_deg(_basis_y_rotation(item["basis"])),
					"seg_idx": item["seg_idx"],
					"_pdata": pdata,
					"_chunk": chunk_idx,
					"_item": item,
				})
	return out


## 给定一个 Basis(我们只产生绕 Y 轴旋转),提取 Y 轴旋转角(弧度)
func _basis_y_rotation(basis: Basis) -> float:
	# 仅 Y 旋转时 basis.x = (cos θ, 0, -sin θ),从 x 推导 θ
	var x: Vector3 = basis.x
	if x.length_squared() < 1e-9:
		return 0.0
	return atan2(-x.z, x.x)


## 编辑模式用:把指定类型 chunk 的所有 instance transform 重写为当前 chunk_defs 状态。
## chunk 未构建(玩家远离)时 no-op,等下次构建会自动用最新 data。
func rewrite_chunk_transforms(plant_name: String, chunk_idx: int) -> void:
	var pdata = null
	for p in _chunks_plants:
		if p["name"] == plant_name:
			pdata = p
			break
	if pdata == null:
		return
	if not pdata["built"][chunk_idx]:
		return
	var items: Array = pdata["chunk_defs"][chunk_idx]
	var mmis: Array = pdata["mmis"][chunk_idx]
	if items.is_empty() or mmis.is_empty():
		return
	# 多 mesh instance 内每个 item 对应一个 instance index
	# _build_chunk 把同色桶放进不同 MultiMesh,索引按"按 part,按颜色桶,按 slot"
	# 简化:重写整个 chunk — 遍历所有 mmis,清空 instance_count,按 part 重写
	var cfg: Dictionary = pdata["config"]
	var parts = cfg["parts"]
	# 用 _build_chunk 同样的 bucket 规则,但这次只 set_instance_transform
	for part_idx in range(parts.size()):
		var part: Dictionary = parts[part_idx]
		var mmi: MultiMeshInstance3D = mmis[part_idx] if part_idx < mmis.size() else null
		if mmi == null or mmi.multimesh == null:
			continue
		var mm: MultiMesh = mmi.multimesh
		var n_inst := mm.instance_count
		for i in range(mini(n_inst, items.size())):
			var item: Dictionary = items[i]
			mm.set_instance_transform(i,
				instance_transform(item["basis"], item["pos"],
					part.get("y_offset", 0.0), item["scale"]))
