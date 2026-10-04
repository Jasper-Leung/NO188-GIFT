extends Node3D
## HomeBase — 主角的家。整条 1229m 的环路上唯一的「家」，以及回得去的据点。
##
## 为什么要有它：这一趟的叙事是「出门 → 沿路收五件乐事 → 合成一份礼物」。
## 而在这之前，**出发地和回家的地方在世界里是同一个抽象概念**——玩家从
## World3D.tscn 里那个写死的出生变换出现在 8 字自交点旁边，那儿除了那块
## 「路自此复」的碑什么都没有。于是「出门」没有门，「回家」没有家。
## 这里补一栋房子：它让「这一趟」在空间上有个起点和终点。
##
## 两条纪律（都写在下面该量的地方）：
##  · **落点是搜出来的，不是猜出来的。** `HOME_AT` 只是偏好的弧长比例，
##    合不合格由 `_place()` 按实测的硬条件筛（广场 / 驿站 / 地形 / 四角平不平）。
##    改 road_data 之后房子会自己挪到一处仍然合法的地方，而不是变成一个
##    压在沥青上或者泡在水里的常量。
##  · **不建第 17 座驿站。** `verify_stations.gd` 与 `verify_story.gd` 各有一条
##    断言全工程恰好 16 座驿站，而"碑不是驿站"那套规矩（不加旅币、不进
##    `_nearby_*`、不能打卡）在这里原样适用。家比碑多的只有一样：它是据点，
##    所以多一条「骑到家门口浮一句」的边沿触发，和小地图上一枚钉。

## 房子沿环路弧长的偏好位置（0 = 出发点，1 = 跑完一圈）。
##
## 这个 0.033 是 `tools/_probe_home.gd` 量出来的，不是估的。那份探针沿环路
## 逐点铺开候选点报六个量，结论有三条：
##  · **出生点那一侧全是驿站。** 8 字环的 16 座驿站全在中心线的同一侧，
##    出生点往前 20~30m 那一段的另一侧最近的一座只有 5.0m —— 把家放在
##    起点旁边会直接糊在「起程驿楼」上。
##  · **对侧空着，而且地更高。** 反侧那一带最近驿站 31~33m，地面比起点高
##    2.4m，正好是个能从路面望过去的小台子。
##  · **广场要躲开。** 8 字自交点在 `rd.points[0]`（实测 (0, 43)，离原点
##    43m），而那块被 `plaza_mode` 扩成 12m 半径的沥青圆盘就盖在上面。
##    `PLAZA_CLEAR` 量的是到 `points[0]` 的距离，所以它跟着数据走，不抄 (0,43)。
const HOME_AT := 0.033
## 房子中心离中心线的横向距离。
##
## 三个数把它夹在中间，每一个都是量出来的：
##  · **下限 14.5m**：`RoadVerge` 那道看得见的软边界带子是 6.5→14.5m，
##    `SOFT_BOUND`(12.0m) 那一档刷成粉线。11m 的房子横跨 8.3~13.8m，
##    **粉线会从屋子中间穿过去**；15m 的房子落在 12.3~17.8m，粉线正好在
##    门前那道坎上——「骑到这里就骑不动了」被画成了一条线，而线那边就是家。
##  · **上限 ~20.7m**：`_apply_boundary_force()` 的推力在 `SOFT_BOUND` 之上
##    按 `PUSH_STRENGTH * over/(HARD_BOUND-SOFT_BOUND)` 涨，而 `Player3D.ACCEL`
##    是 8.0 —— 满油门平衡点实测在 20.7m。再远就骑不到了。
##  · **树那一行在 9.5~12.5m**（`TreeScatter.SIDE_OFFSET` 11.0 ± 抖动）。
##    15m 的房子虽然还擦着它，但 `World3D` 会把落点也塞进 TreeScatter 的
##    让位表，`STATION_CLEAR`(10m) 一清就干净了。
const HOME_OFFSET := 15.0
## 与任何一座驿站的最小间距。比 `RoadSteles.CLEAR_OF_STATION`(16) 大：
## 碑只有 1.1m 宽，房子的 8×6m 底子比它大一个量级。
const CLEAR_OF_STATION := 20.0
## 与任何一块路碑的最小间距。
##
## **这一条是事后量的，不是选址时量的**，见下面 `check_steles()` 的说明。
## 选址发生在 TreeScatter 之前（房子要让树给它腾地方），而路碑的落点要
## 树建好了才排得出来 —— 两者互为前提，只能拆成两步。所以这里记录一个
## `clear_of_steles` 交给回归去断，而不是假装选址时就管过了。实测 15.6m。
const CLEAR_OF_STELE := 14.0
## 离 8 字自交点那块广场圆盘的最小距离（量到 `rd.points[0]` 的距离）。
const PLAZA_CLEAR := 30.0
## 地面高程下限。全场统一水位 -3.40，而地形高程下限 clamp 在 -3.0，
## 所以 -1.0 足够把「泡在水里」和「压在被 clamp 出来的平地上」一起挡掉。
const MIN_GROUND := -1.0
## 房子四角（±4.0 × ±3.0）之间允许的最大高差。
##
## 房子不像碑可以歪着放——墙是竖的，屋脊是横的，底下这块地不平的话
## 玩家一眼就看出它是"贴"在地形上的。实测 −侧那一带 0.17~0.21m。
const FLAT_MAX := 0.8
## 沿路找落点时最多试几个候选下标。
const PLACE_TRIES := 24

## 房子底面 8.0 × 6.0（进深方向是 6.0）。四角高差就是按这四个角量的。
const HALF_W := 4.0
const HALF_D := 3.0
## 玩家不许骑进去的半径（半对角线 + 余量）。`Player3D` 没有碰撞求解器，
## 15m/s 一帧走 0.25m，力推拦不住，所以只能像 `_apply_station_keepout()`
## 那样直接把位置摆回边界。
##
## 5.0 + 1.6 = 6.6m，比 `STATION_PASS_RADIUS`(15) 小得多——家和驿站不同，
## 它背后没有一圈 15m 的打卡圈，所以这条不适用那套"墙不能比圈大"的约束；
## 真正的约束是玩家**够得到门**：站在 6.6m 外时离中心线还有 8.4m，
## 那儿 `_apply_boundary_force()` 的推力恰好是 0。
const KEEPOUT_PAD := 1.6

## 牌子字号折成米。**必须和 `World3D.STATION_LABEL_PIXEL_SIZE` 相等**——
## 两处各写一份是这一族最常见的病（手抄的常量会长出第二套预算），
## 所以 `verify_home_base.gd` 里有一条把两份对拍的断言。
const HOME_LABEL_PIXEL_SIZE := 0.012
const HOME_LABEL_FONT_PX := 48

## 「骑到家门口」的那一圈半径。和 `STELE_PASS_RADIUS` 一样按 XZ 量，
## 家坐在地形上、门朝着路，两边高差能到两米多。
const PASS_RADIUS := 12.0

## 五个色都是 **sRGB 口径**，和 `RoadSteles` / `World3D.STATION_ROOF_TINT`
## 同一套写法：`_mat()` 里过一道 `linear_to_srgb`，方向反了就暗成一块黑。
const PLINTH := Color(0.40, 0.385, 0.35)
const WALL := Color(0.76, 0.72, 0.63)
const TIMBER := Color(0.33, 0.245, 0.175)
const ROOF := Color(0.34, 0.265, 0.225)
const DOOR := Color(0.29, 0.19, 0.13)
const WINDOW := Color(0.96, 0.80, 0.47)

## 落点（y 由地形填）。World3D 拿它去：①喂 TreeScatter 让位、
## ②当玩家不许骑进去的那一圈的圆心、③小地图上那枚钉。
var site := Vector3.ZERO
## 房子正对的那个中心线点。朝向和「小地图钉在哪一侧」都由它决定。
var road_pt := Vector2.ZERO
## 房子建起来没有。选址失败时为 false —— 那时**必须**在回归里红，
## 因为一座没建出来的家会让整段叙事悬空，而画面上只是"少了一栋房子"。
var placed := false
## 见 `CLEAR_OF_STELE`：选址早于路碑，所以这条是事后量的。
var clear_of_steles := false


## rd             —— RoadData，中心线与 16 座驿站的落点
## terrain_builder —— 贴地的唯一出处（植物 pos.y 不可信，同一条规矩）
## station_pts     —— 驿站中心点的 XZ（World3D 在 `_setup_stations()` 之后传）
## plate_text      —— 门牌上那两个字。**由 World3D 用 `Localization.t()` 译好再传进来**，
##                    和 `_station_name()` 走的是同一条路：本文件不引用任何 autoload，
##                    否则 `--script` 下的回归会在编译期去解析 `Localization`、
##                    报 `Identifier not found` 然后整个 SceneTree 挂死不退出
##                    （CLAUDE.md 已知陷阱）。
func setup(rd, terrain_builder: Node3D, station_pts: Array, plate_text: String) -> void:
	if rd == null or rd.points.size() < 3:
		return
	var cross := Vector2(rd.points[0].x, rd.points[0].z)
	var hit := _place(rd, terrain_builder, station_pts, cross)
	if hit.is_empty():
		return
	var xz: Vector2 = hit["xz"]
	road_pt = hit["road_pt"]
	var y := 0.0
	if terrain_builder != null and terrain_builder.has_method("get_height_at"):
		y = terrain_builder.get_height_at(xz.x, xz.y)
	site = Vector3(xz.x, y, xz.y)
	placed = true
	_build_house(xz, road_pt, y, plate_text)


## 房子落地之后、路碑建好之后，World3D 再调一次。**只记录，不搬家**——
## 落点那时候已经喂给 TreeScatter 了（行道树是围着它种的），挪走的话
## 树就白让了。所以这里是"发现不合规就报出来"，靠回归去断。
func check_steles(stele_positions: Array) -> void:
	clear_of_steles = true
	var p := Vector2(site.x, site.z)
	for sp in stele_positions:
		if p.distance_to(Vector2(sp.x, sp.z)) < CLEAR_OF_STELE:
			clear_of_steles = false
			push_warning("[HomeBase] 落点离一块路碑只有 %.1fm（门槛 %.1fm）"
					% [p.distance_to(Vector2(sp.x, sp.z)), CLEAR_OF_STELE])


## 玩家不许骑进屋子的半径。见 `KEEPOUT_PAD`。
func keepout_radius() -> float:
	if not placed:
		return 0.0
	return sqrt(HALF_W * HALF_W + HALF_D * HALF_D) + KEEPOUT_PAD


## 沿弧长比例找一块地：先在目标比例上取两侧法线各试一个位置，
## 两个都不合格就沿路往前挪，挪 PLACE_TRIES 次为止。
## 返回 {"xz": 房子的落点, "road_pt": 对应的中心线点}。
func _place(rd, terrain_builder: Node3D, station_pts: Array, cross: Vector2) -> Dictionary:
	var pts: Array = rd.points
	var cum: Array = rd.compute_cumulative_arclength()
	var total: float = cum[cum.size() - 1]
	if total <= 0.0:
		return {}
	var start := _index_at_arclen(cum, total * HOME_AT)
	for k in range(PLACE_TRIES):
		var i := (start + k) % (pts.size() - 1)
		var tangent := _tangent_at(pts, i)
		if tangent == Vector2.ZERO:
			continue
		var n := Vector2(-tangent.y, tangent.x)
		var road_pt := Vector2(pts[i].x, pts[i].z)
		for side in [1.0, -1.0]:
			var p: Vector2 = road_pt + n * HOME_OFFSET * side
			if _clear_of_stations(p, station_pts) and _ground_ok(p, terrain_builder, cross):
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
##
## 三个局部变量都**必须写死类型**：`pts` 声明成 `Array`（元素类型未知），
## 于是 `pts[i]` 是 Variant，`var a := …` 推不出类型而在**加载期**报
## "Cannot infer the type"，整份脚本编译不过——而 `World3D._ready()` 里那句
## `HomeBaseRef.new()` 随之报 "Nonexistent function 'new' in base 'GDScript'"，
## **画面上只是"少了一栋房子"**，其余一切照常。这条是 `verify_home_base.gd`
## 第一次跑就撞出来的，写在这里免得下一个人把类型标注"清理"掉。
func _tangent_at(pts: Array, i: int) -> Vector2:
	var n: int = pts.size()
	var a: Vector3 = pts[maxi(i - 1, 0)]
	var b: Vector3 = pts[mini(i + 1, n - 1)]
	var t := Vector2(b.x - a.x, b.z - a.z)
	return t.normalized() if t.length_squared() > 1e-9 else Vector2.ZERO


func _clear_of_stations(p: Vector2, station_pts: Array) -> bool:
	for sp in station_pts:
		if p.distance_to(sp) < CLEAR_OF_STATION:
			return false
	return true


## 地面这一侧合不合格：不在广场上、不在水里、四角站得住。
func _ground_ok(p: Vector2, terrain_builder: Node3D, cross: Vector2) -> bool:
	if terrain_builder == null or not terrain_builder.has_method("get_height_at"):
		return false
	if p.distance_to(cross) < PLAZA_CLEAR:
		return false
	var y: float = terrain_builder.get_height_at(p.x, p.y)
	if y < MIN_GROUND:
		return false
	for c in [Vector2(HALF_W, HALF_D), Vector2(HALF_W, -HALF_D),
			Vector2(-HALF_W, HALF_D), Vector2(-HALF_W, -HALF_D)]:
		if absf(float(terrain_builder.get_height_at(p.x + c.x, p.y + c.y)) - y) > FLAT_MAX:
			return false
	return true


## 一栋 CSG 的农舍：石台 + 墙 + 两片坡屋顶 + 门 + 三扇窗 + 烟囱 + 门牌。
## 零新 GLB、零纹理，和 RoadSteles / CrossingMark / FarRidge 用的是同一套工具，
## 所以 PROVENANCE.md 一个字都不用改（`verify_provenance.gd` 只走 res://assets）。
##
## 每个子节点都得起名字——属性名写错（比如在 CSGCylinder3D 上写
## `radial_segments`）会让 GDScript 在运行时中止整个函数，于是后面那些
## 子节点一个都没 add_child，而"房子在不在、落点合不合法"这些断言全绿。
## RoadSteles 那条"Mark 节点必须存在"就是替这个兜底的。
func _build_house(xz: Vector2, road_pt: Vector2, y: float, plate_text: String) -> void:
	var root := Node3D.new()
	root.name = "House"
	root.position = Vector3(xz.x, y, xz.y)
	add_child(root)

	# 石台：踩平了的一块地基。太薄的话下坡那一角会浮起来——四角高差实测
	# 0.2m，台子往下埋 0.58m 就够，同时往上留 0.32m 当室内地坪。
	var plinth := CSGBox3D.new()
	plinth.name = "Plinth"
	plinth.size = Vector3(HALF_W * 2.0 + 0.6, 0.9, HALF_D * 2.0 + 0.6)
	plinth.position = Vector3(0, -0.13, 0)
	plinth.material = _mat(PLINTH)
	root.add_child(plinth)

	var wall := CSGBox3D.new()
	wall.name = "Wall"
	wall.size = Vector3(HALF_W * 2.0 - 1.0, 2.8, HALF_D * 2.0 - 0.5)
	wall.position = Vector3(0, 0.32 + 1.4, 0)
	wall.material = _mat(WALL)
	root.add_child(wall)

	# 两道木腰线。墙是一整块 7×2.8 的白盒子，不加这两道它读成一块广告牌。
	for i in 2:
		var beam := CSGBox3D.new()
		beam.name = "Beam%d" % i
		beam.size = Vector3(HALF_W * 2.0 - 0.9, 0.16, HALF_D * 2.0 - 0.4)
		beam.position = Vector3(0, 0.32 + 0.9 + 1.6 * float(i), 0)
		beam.material = _mat(TIMBER)
		root.add_child(beam)

	# 两片坡屋顶。屋脊沿 X（房子的宽），坡面 30°，出檐 0.4m。
	#
	# 绕 X 轴转 +θ 时 +Z 那端往下沉（(0,0,1) → (0,-sinθ, cosθ)），所以
	# 朝 +Z 的那片取 +θ、朝 −Z 的取 −θ。坡长是斜边 3.64m 而不是投影的
	# 3.15m —— 写成投影值的话两片中间会裂开一条缝，而这种缝在远看时
	# 读成"屋顶中间破了"。
	var eave_y := 0.32 + 2.8
	var ridge_y := eave_y + 3.15 * tan(deg_to_rad(30.0))
	for s in 2:
		var slope := 1.0 if s == 0 else -1.0
		var slab := CSGBox3D.new()
		slab.name = "Roof%d" % s
		slab.size = Vector3(HALF_W * 2.0 - 1.0 + 0.3, 0.2, 3.64)
		slab.rotation_degrees = Vector3(30.0 * slope, 0, 0)
		slab.position = Vector3(0, (eave_y + ridge_y) * 0.5, 1.575 * slope)
		slab.material = _mat(ROOF)
		root.add_child(slab)

	var chimney := CSGBox3D.new()
	chimney.name = "Chimney"
	chimney.size = Vector3(0.7, 1.6, 0.7)
	chimney.position = Vector3(1.9, ridge_y - 0.2, -1.0)
	chimney.material = _mat(PLINTH)
	root.add_child(chimney)

	var door := CSGBox3D.new()
	door.name = "Door"
	door.size = Vector3(1.1, 2.05, 0.12)
	door.position = Vector3(0, 0.32 + 1.025, HALF_D - 0.19)
	door.material = _mat(DOOR)
	root.add_child(door)

	# 三扇窗。正面两扇 + 两侧各一扇，都朝着路——正面那两扇是从路面上
	# 唯一看得见的（房子是侧对路站着的），所以它们必须真的画出来。
	# 一点点自发光：黄昏那一档天暗下来之后，别的房子都是剪影，只有这栋
	# 还亮着——这是"这是我家"在那一档唯一还能读出来的信号。
	for i in 2:
		var w := CSGBox3D.new()
		w.name = "WinF%d" % i
		w.size = Vector3(0.95, 0.85, 0.12)
		w.position = Vector3(-2.2 + 4.4 * float(i), 0.32 + 1.6, HALF_D - 0.19)
		w.material = _win_mat()
		root.add_child(w)
	for i in 2:
		var w := CSGBox3D.new()
		w.name = "WinS%d" % i
		w.size = Vector3(0.12, 0.85, 0.95)
		w.position = Vector3((HALF_W - 0.75) * (1.0 if i == 0 else -1.0),
				0.32 + 1.6, 0.0)
		w.material = _win_mat()
		root.add_child(w)

	# 门牌。不开 billboard —— 它是钉在门楣上的一块木牌，不是飘着的 UI，
	# 而且它跟着房子由 `_face_road()` 一起转向，正面永远朝着路。
	var plate := Label3D.new()
	plate.name = "Plate"
	plate.text = plate_text
	plate.font_size = HOME_LABEL_FONT_PX
	plate.pixel_size = HOME_LABEL_PIXEL_SIZE
	plate.outline_size = 14
	plate.outline_modulate = Color(0.10, 0.09, 0.08, 0.9)
	plate.modulate = TIMBER.linear_to_srgb()
	plate.double_sided = true
	plate.position = Vector3(0, eave_y - 0.42, HALF_D - 0.16)
	root.add_child(plate)

	_face_road(root, xz, road_pt)


## 绕 Y 转整栋房子，让门（局部 +Z）正对着路。
##
## 朝向由**最近的那一段中心线**算，不能由"世界原点"算：8 字环的中心在
## (0, 43) 而不是 (0, 0)，指着原点转会让门歪掉几十度。
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


func _win_mat() -> StandardMaterial3D:
	var m := _mat(WINDOW)
	m.emission_enabled = true
	m.emission = WINDOW.linear_to_srgb()
	m.emission_energy_multiplier = 0.35
	return m
