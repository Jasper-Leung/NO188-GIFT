extends Node3D
## RoadSteles — 路碑。「188」与「守驿人记路不记己」在世界里的实体。
##
## 这个节点存在的原因：题眼是「给 ______ 的礼物」，本作答的是「188 号」，
## 而在这之前 188 只活在文案里——README 花了整节解释「它是编号不是里程」，
## 世界里却没有任何一处写着这个数。序章里那句最好的台词「守驿人记路，不记己」
## 也只播一次就再没被提起过。这里补四块碑：
##
##   · 前三块刻着 188，背面是守驿人的信条（对白交给 HUD 的浮字，见 World3D）
##   · 第四块的字被人凿平了，只剩一道浅坑和半个 188
##
## 第四块就是郑铎第二场里那句「我们从上面挖出一块刻字的石头」——反派点了名的
## 实物第一次真的存在于世界里，玩家不必凭空相信他。
##
## 全部 CSG 图元 + Label3D，零新 GLB、零纹理，和 FarRidge / _build_station_generic
## 用的是同一套工具。

## 碑面离路中心线的横向距离。
##
## 这条位置是被定妆照逼出来的，试过两处：
##  · 11.0m —— 和 TreeScatter.SIDE_OFFSET(11.0) **正好撞上**。行道树沿
##    9.5~12.5m 那一条带子排，于是每块碑都种在树行里。
##  · 15.0m —— 挪到树行**后面**了，可是从路面上望过去，一棵行道树正好
##    立在视线中间，"被凿平的那块"又一次整个被挡死。碑是给路上的人看的，
##    自己站得再开阔、看不见就等于没有。
## 现在落在 9.0m：路肩外侧的草地上、树行**前面**。底座 1.5m 深，靠路那侧
## 的边在 8.25m（> 8.0m 的 GrassScatter.ROAD_CLEAR，> 6.5m 的沥青半宽），
## 碑身最近的一面在 8.87m，离沥青还有 2.4m。
const STELE_OFFSET := 9.0
## 碑与任何一座驿站的最小间距。太近会和驿站的石台糊成一坨。
const CLEAR_OF_STATION := 16.0
## 沿路找落点时最多试几个候选下标（太窄的话整段路都放不下一块碑）。
const PLACE_TRIES := 24
## 视线上留多少净空给行道树。行道树冠幅约 4m，2.5m 意味着树干中心离视线
## 这么远时，它的树冠仍然会擦到碑面——宁可滑到下一段路去。
const SIGHT_CLEAR := 2.5

## 四块碑。at 是沿环路弧长的比例（0 = 出发点，1 = 跑完一圈）。
## worn = 字被凿过：188 画成半瞎的暗色，正面再盖一块「崩口」。
const STELE_TABLE := [
	{"at": 0.020, "worn": false, "line": "stele_1_line"},
	{"at": 0.270, "worn": false, "line": "stele_2_line"},
	{"at": 0.545, "worn": false, "line": "stele_3_line"},
	{"at": 0.815, "worn": true, "line": "stele_4_line"},
]

## 四个色都是 **sRGB 口径**，和 `World3D.STATION_ROOF_TINT` 同一套写法：
## `StandardMaterial3D.albedo_color` 在着色器里当线性值用，所以直接写 0.60
## 渲出来是 sRGB 0.80 —— 一块近白的崭新水泥柱，不是风化多年的路碑。
## `_mat()` 里过一道 linear_to_srgb，方向反了就会暗成一块黑。
const STONE := Color(0.50, 0.485, 0.445)
const STONE_DARK := Color(0.34, 0.33, 0.305)
const CARVED := Color(0.20, 0.18, 0.16)
const CARVED_WORN := Color(0.46, 0.44, 0.41)

## 每块碑在世界里的落点（y 取地形高度）。World3D 靠它做「路过」边沿触发。
var stele_positions: Array[Vector3] = []
## 每块碑对应的那句浮字 key，和 STELE_TABLE 逐条对齐。
var stele_line_keys: Array[String] = []


## rd          —— RoadData，用来取中心线与 16 座驿站的落点
## terrain_builder —— 贴地的唯一出处（植物 pos.y 不可信，同一条规矩）
## blockers    —— 行道树的 XZ 落点。见 _clear_sight_line()：碑是给路上的人看的，
##                 所以"离树几米"不是判据，"有没有树站在路到碑的视线上"才是。
##                 所以这一项必须由 World3D 在 TreeScatter 建完之后传进来。
func setup(rd, terrain_builder: Node3D, blockers: Array = []) -> void:
	if rd == null or rd.points.size() < 3:
		return
	var station_pts: Array[Vector2] = []
	for i in range(rd.stations.size()):
		var sp: Vector3 = rd.get_station_world_pos(i)
		station_pts.append(Vector2(sp.x, sp.z))

	for spec in STELE_TABLE:
		var hit := _place(rd, station_pts, blockers, float(spec["at"]))
		if hit.is_empty():
			continue
		var xz: Vector2 = hit["xz"]
		var road_pt: Vector2 = hit["road_pt"]
		_build_stele(xz, road_pt, terrain_builder, bool(spec["worn"]))
		stele_positions.append(Vector3(xz.x, 0.0, xz.y))
		stele_line_keys.append(str(spec["line"]))


## 沿弧长比例找一块地：先在目标比例上取两侧法线各试一个位置，
## 两个都不合格就沿路往前挪，挪 PLACE_TRIES 次为止。
## 返回 {"xz": 碑的落点, "road_pt": 对应的中心线点}——后者用来把碑面转向路。
func _place(rd, station_pts: Array[Vector2], blockers: Array, frac: float) -> Dictionary:
	var pts: Array[Vector3] = rd.points
	var cum: Array = rd.compute_cumulative_arclength()
	var total: float = cum[cum.size() - 1]
	if total <= 0.0:
		return {}
	var start := _index_at_arclen(cum, total * frac)
	for k in range(PLACE_TRIES):
		# 半个采样点一挪。960 个点里挪 24 个 ≈ 30m，足够躲开一座驿站又不会
		# 把碑推到"这块碑明明属于下一个 8 字分支"的位置上去。
		var i := (start + k) % (pts.size() - 1)
		var tangent := _tangent_at(pts, i)
		if tangent == Vector2.ZERO:
			continue
		var n := Vector2(-tangent.y, tangent.x)
		var road_pt := Vector2(pts[i].x, pts[i].z)
		for side in [1.0, -1.0]:
			var p: Vector2 = road_pt + n * STELE_OFFSET * side
			if _clear_of_stations(p, station_pts) and _clear_sight_line(road_pt, p, blockers):
				return {"xz": p, "road_pt": road_pt}
	return {}


func _index_at_arclen(cum: Array, target: float) -> int:
	var lo := 0
	var hi := cum.size() - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if float(cum[mid]) < target:
			lo = mid + 1
		else:
			hi = mid
	return lo


## XZ 平面上的单位切线。首尾各取单侧，与 road_data._canvas_tangent 同做法。
func _tangent_at(pts: Array[Vector3], i: int) -> Vector2:
	var n := pts.size()
	var a: Vector3 = pts[maxi(i - 1, 0)]
	var b: Vector3 = pts[mini(i + 1, n - 1)]
	var t := Vector2(b.x - a.x, b.z - a.z)
	return t.normalized() if t.length_squared() > 1e-9 else Vector2.ZERO


func _clear_of_stations(p: Vector2, station_pts: Array[Vector2]) -> bool:
	for sp in station_pts:
		if p.distance_to(sp) < CLEAR_OF_STATION:
			return false
	return true


## 骑在路中心线的人到碑之间，得没有行道树站在视线上。
##
## 判据不是"碑离最近的树几米"——近也可能在视线的另一侧，远也可能在正中间。
## 量的是**点到线段**的距离：线段的一端是碑正对的那个中心线点，另一端是碑。
## 第一版取 11.0m、正好落在行道树那条 9.5~12.5m 的带子里；挪到 15m 挪到
## 树行后面也照样有一棵立在视线中间，定妆照里"被凿平的那块"整个被挡死。
func _clear_sight_line(road_pt: Vector2, p: Vector2, blockers: Array) -> bool:
	var ab := p - road_pt
	var len2 := ab.length_squared()
	if len2 < 1e-9:
		return true
	for b in blockers:
		var t := clampf((Vector2(b) - road_pt).dot(ab) / len2, 0.0, 1.0)
		if (road_pt + ab * t).distance_to(Vector2(b)) < SIGHT_CLEAR:
			return false
	return true


func _build_stele(xz: Vector2, road_pt: Vector2, terrain_builder: Node3D, worn: bool) -> void:
	var y := 0.0
	if terrain_builder != null and terrain_builder.has_method("get_height_at"):
		y = terrain_builder.get_height_at(xz.x, xz.y)
	var root := Node3D.new()
	root.name = "Stele"
	root.position = Vector3(xz.x, y, xz.y)
	add_child(root)

	# 底座：踩平了的一块石板，压住"碑是从地里长出来的"而不是浮在上面
	var base := CSGBox3D.new()
	base.name = "Base"
	base.size = Vector3(1.9, 0.32, 1.5)
	base.position = Vector3(0, 0.16, 0)
	base.material = _mat(STONE_DARK)
	root.add_child(base)

	# 碑身
	var slab := CSGBox3D.new()
	slab.name = "Slab"
	slab.size = Vector3(1.1, 2.1, 0.26)
	slab.position = Vector3(0, 0.32 + 1.05, 0)
	slab.material = _mat(STONE)
	root.add_child(slab)

	# 碑顶收一个尖，别是一块光板。
	# 属性名别照 CylinderMesh 抄：CSGCylinder3D 上是 `sides` 和 `cone`，
	# 没有 `radial_segments` / `top_radius`。写错名字不只是这一行不生效——
	# GDScript 在运行时属性赋值失败会**中止整个函数**，于是碑面那个 "188"
	# 根本没被 add_child，而"碑在不在、落点合不合法"这些断言全绿。
	# 拦住它的是一条"Mark 节点必须存在"——所以每加一个子节点都得能被点名。
	var cap := CSGCylinder3D.new()
	cap.name = "Cap"
	cap.sides = 4
	cap.cone = true
	cap.radius = 0.55
	cap.height = 0.55
	cap.rotation_degrees = Vector3(0, 45, 0)
	cap.position = Vector3(0, 0.32 + 2.1, 0)
	cap.material = _mat(STONE)
	root.add_child(cap)

	# 刻在碑面上的 188。不开 billboard —— 它得是刻上去的字，不是飘着的 UI。
	# 它跟着碑身一起由 _face_road() 转向，所以不用自己再转一次。
	var mark := Label3D.new()
	mark.name = "Mark"
	mark.text = "188"
	mark.font_size = 72
	mark.pixel_size = 0.0068
	mark.outline_size = 14
	mark.outline_modulate = Color(0.10, 0.09, 0.08, 0.9)
	mark.modulate = (CARVED_WORN if worn else CARVED).linear_to_srgb()
	mark.double_sided = true
	mark.position = Vector3(0, 0.32 + 1.22, 0.16)
	root.add_child(mark)

	if worn:
		# 崩口：一块斜插在碑面上的薄片，把 188 啃掉一半。
		# 这是全项目唯一一处「被弄坏的东西」，所以它得是几何而不是贴图。
		var chip := CSGBox3D.new()
		chip.name = "Chip"
		chip.size = Vector3(0.62, 0.5, 0.30)
		chip.position = Vector3(0.17, 0.32 + 1.12, 0.14)
		chip.rotation_degrees = Vector3(0, 0, 24)
		chip.material = _mat(STONE)
		root.add_child(chip)

	_face_road(root, xz, road_pt)


## 绕 Y 转整块碑，让碑的正面垂直于路、正对骑过来的人。
##
## 转的是 **root**，不是 Mark 和 Chip 两个子节点。第一版只转了那两个，
## 于是石板自己还朝着世界 +Z——「188」确实正对着路，却浮在柱子的一条
## **窄边**上（slab 是 1.1 宽 × 0.26 厚），从路边看过去是一个挂在柱子
## 侧棱上的数字。而当时所有断言都是绿的：朝向那条量的是 Mark 的朝向，
## 没量"字是不是在碑的正面那块宽板上"。所以现在多量一条：Slab 的法线
## 也得朝着路，而且 Mark 必须在 Slab 的正面那一侧。
##
## 朝向还必须由**最近的那一段中心线**算，不能由"世界原点"算：8 字环的中心在
## (0, 43) 而不是 (0, 0)，指着原点转会让碑面歪掉几十度。
func _face_road(root: Node3D, xz: Vector2, road_pt: Vector2) -> void:
	var dir := road_pt - xz
	if dir.length_squared() < 1e-9:
		return
	dir = dir.normalized()
	root.rotation.y = atan2(dir.x, dir.y)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.linear_to_srgb()
	m.roughness = 0.95
	return m
