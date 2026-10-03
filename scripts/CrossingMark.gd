extends Node3D
## CrossingMark — 8 字交叉点那块「路自此复」的碑。
##
## 为什么要在交叉点放东西：这个地方是**全世界唯一能一眼看完整条路**的位置
## （`lookdev_crossing.gd` 的 `0_aerial` 就是站在这儿拍的），而它原来是一块
## 空的沥青。`verify_crossing.gd` 量的是路面在自交处的**高度连续**——玩家会不会
## 感觉到台阶——它对"这个位置长什么样"一个字都没说。几何回归量不出"空"，
## 空是要人看的。
##
## 碑面上刻的不是字，是**这条路自己的形状**。刻线由 `RoadData.points` 生成，
## 和 `RoadBuilder` 建沥青用的是同一份数据——所以这张图不可能说谎，
## 改环路它自己跟着改。这比再刻一句「这里是交叉点」强：那句话只是在复述
## 坐标，而这张图是**证据**。
##
## 全部 CSG 图元 + 一个自己拼的 ArrayMesh 带子，零新 GLB、零纹理，
## 和 RoadSteles / FarRidge 用的是同一套工具。

## 碑面离交叉点多远。
##
## 上界是沥青：两条支路在这里中心线只差 2m，沥青半宽 6.5，所以那一块横向
## 糊出十几米，碑必须站到这片沥青外面去。
##
## 下界是**人**。`World3D._apply_boundary_force()` 从 12m（`SOFT_BOUND`）起往回推，
## 而推力是 `12 × (d-12)/13` m/s：13m 处 0.9、16m 处 3.7、21m 处 8.3——
## 21m 之外它就压过 `Player3D.ACCEL`(8)，车被钉在原地、速度 15m/s 而距离不变。
## 16m 落在推力远小于油门的那一档：人停得住、站定了抬头就看见它，
## 而实测它在那个方向上离沥青还有 12.7m。
const CROSS_OFFSET := 16.0
## 碑身半宽（局部 X）。刻线按它缩放。
##
## 环路近方形（329.2×361.0m，宽高比 0.91），所以碑面也取近方形：2.6 宽配
## 2.4 高的话刻线只占面宽的 52%，两侧各空出一条谁也说不清是装饰还是失误的
## 灰板；收成 1.9 宽之后刻线占到 63%，一眼就看出"图是主角"。
const FACE_W := 1.9
## 碑面高度（局部 Y）。刻线按它缩放。
##
## **这块高度是倒推出来的**，不是挑出来的：目标是碑顶落在 2.45m 左右
## （再高就得仰头，而碑面后仰之后仰头那一刻正好看到石板的一条窄边），
## 而碑顶 = `PLINTH_H + PLINTH_CLEAR + FACE_H·cos(倾角)`。定下 0.42/0.10/14°
## 三项，反解出来 1.94m。
##
## 顺带记一条**当时推错了的**：3.0 那版量出来是块 2.85m 的石头，理由写的是
## "站着低头就正对着脸"——可低头读得清的那一档恰恰是最躺的一档，两条要求
## 在一块石头上是打架的，见 FACE_TILT_DEG。
const FACE_H := 1.94
## 石板厚度（局部 Z）。
const SLAB_D := 0.22
## 石台多高。
##
## 石台不是装饰，它是**碑面下沿的地面**——题字和刻线下半段量的是"离地多高"，
## 而离地的起点是石台顶。原来石台 0.95m 而石板下沿落在 0.16m，于是 0.79m
## 的石板和整行题字**埋在石头里面**：图上是一个闭环加一条尾巴（下瓣被石台
## 切掉了），题字一个字没有，而包围盒、刻线对拍、面朝向**全部照绿**——
## 4.1 那条断言只问"离地 y=0 有多远"，从来没问过"离石台顶有多远"。
## 0.42 是压到草梢（草皮 0.085~0.15m）之上、又不至于把碑面顶高的那一档。
const PLINTH_H := 0.42
const PLINTH_D := 1.4
## 石板下沿要高过石台顶多少。留一道缝，看得出碑面是**架在**石台上的。
const PLINTH_CLEAR := 0.10
## 碑面后仰多少度。
##
## 这里是这个文件改得最彻底的一个数：原来是 40°，理由是"站着低头就正对着脸"。
## 量过之后发现那条理由本身是反的——**低头才看得清的那一档恰恰是最躺的一档**。
## 一个 1.94m 的面后仰 40° 的话竖直跨度是 `1.94·cos40° = 1.49m`，为了不把
## 下沿埋进石台就得整体抬高 1.2m，碑顶于是顶到 2.9m；反过来把面降到
## 站着平视的高度（心 1.49m、眼 1.6m），它就是一块**正对着人的牌子**，
## 视差为零、读出来最省力。40° 那版真正买到的是"俯视读图"这个仪式感，
## 代价是碑顶仰头 + 下瓣被石台切 + 题字埋掉，而这三样在图上一眼看得出、
## 在几何断言里一条都不红。
##
## 14° 留的是"这是块立着的碑、雨水顺得下去"——不是仪式感。**量可读性的
## 那一半永远是玩家眼睛到碑面中心的连线，不是倾角。**
const FACE_TILT_DEG := 14.0
## 刻线在碑面局部坐标里能占的框（米，x 向左为负、y 向上为正）。
##
## 写死成米而不用比例，是因为**题字那一格是从这块地里省出来的**：两个框
## 必须一起动，只动一个就会有一边被石板边沿或石台切掉（而断言量的是
## 包围盒，包围盒永远"在碑面之内"——它量不到"被石台挡住"）。
const TRACE_BOX := Rect2(-0.74, -0.44, 1.48, 1.32)
## 题字基线区在碑面局部 y 上的位置。与 TRACE_BOX.y 的下沿之间留着
## 0.13m 的空档，玩家一眼能分出"图"和"字"。
const TEXT_Y := -0.70
## 题字一个像素多少米。4 个汉字 × `96 × pixel_size` = 面宽的 75%。
const TEXT_PIXEL := 0.0037
## 刻线多宽（米，碑面局部坐标）。0.055 在 1.2m 宽的图上是 4.6%，
## 两个瓣在腰上叠成两个鼓包；收到 0.042 之后交叉处才读得出是"线压线"。
const TRACE_W := 0.042
## 从环路采样多少个点去刻。961 个点全刻是浪费——刻线宽 4.2cm，
## 而整张图才 1.2m 宽，采样密过 1cm 就只是把同一段描粗。
const TRACE_SAMPLES := 160
## 找落点时绕交叉点扫多少个方向。72 = 每 5°。
## 原来取的是"中心线在该点的法线 ± 两侧"——那是**错的**，实测两侧都只离
## 沥青 3.5m，全落在另一个环的臂上：8 字的交叉点是两个环的**极端点**
## （这里 z=43 同时是上一个环的最小 z 和下一个环的最大 z），
## 垂直于行进方向的那一侧直接扎进隔壁那条臂里。
## 真有地的那块是 45°~75° 那个缺口，所以改成整圈扫、按余量最大挑。
const SITE_SWEEP := 72
## 和任何一座驿站的最小间距。
const CLEAR_OF_STATION := 16.0
## 碑与沥青的最小间距（沥青半宽 6.5 + 一点余量）。
const CLEAR_OF_ASPHALT := 9.0

## 和 RoadSteles 同一套色，**sRGB 口径**：`StandardMaterial3D.albedo_color`
## 在着色器里当线性值用，填 0.50 渲出来是 sRGB 0.80，一块近白的新水泥。
## `_mat()` 里过一道 linear_to_srgb，方向反了整块碑暗成黑的。
const STONE := Color(0.50, 0.485, 0.445)
const STONE_DARK := Color(0.34, 0.33, 0.305)
const CARVED := Color(0.20, 0.18, 0.16)

## 碑在世界里的落点（y 取地形高度）。定妆照与回归都靠它点名。
var mark_position: Vector3 = Vector3.ZERO
## 碑面正面朝向的那个单位向量（XZ 平面）。朝**路**，不朝世界原点。
var mark_facing := Vector2(0, 1)
## 刻线在碑面局部坐标里的包围盒，供回归直接量（不碰画笔的纯数据）。
var trace_bounds := Rect2()
## 交叉点的世界坐标——「两支路心线在这里最近」的那一对点之中点。
var crossing_point := Vector3.ZERO
## 碑到整条中心线的最近距离。落点判据的唯一出处，回归直接读它。
var road_clearance := 0.0


## 碑面原点离地多高（**算出来的**）。
##
## 写死 `PLINTH_H + 0.20` 是这个文件埋得最深的一个雷：石板下沿离地
## `lift - (FACE_H/2)·cosθ - (SLAB_D/2)·sinθ`，而这后头两项加起来
## 接近 1m——**碑面高矮一动，这个数就悄悄埋进石台里**，而题字和刻线下半段
## 量的是同一个量。写成函数之后"下沿高过石台顶 PLINTH_CLEAR"这句话
## 永远成立，改 FACE_H / FACE_TILT_DEG / PLINTH_H 都不必记得回来重算。
##
## 它必须是 **static**：回归在 `--script` 模式下拿不到节点，而"碑面该
## 抬多高"正好是一条纯算术，用不着世界。
static func face_lift() -> float:
	var t := deg_to_rad(FACE_TILT_DEG)
	return PLINTH_H + PLINTH_CLEAR + (FACE_H * 0.5) * cos(t) + (SLAB_D * 0.5) * sin(t)


## 碑面局部坐标里的一点，换成离地多高。
## 回归靠它判"有没有被石台吃掉"——那是一条任何包围盒都量不到的遮挡。
static func local_height(face_lift: float, y: float) -> float:
	return face_lift + y * cos(deg_to_rad(FACE_TILT_DEG))


## rd              —— RoadData，刻线和落点都从它出
## terrain_builder —— 贴地的唯一出处
func setup(rd, terrain_builder: Node3D) -> void:
	if rd == null or rd.points.size() < 3:
		return
	var hit := _find_crossing(rd)
	if hit.is_empty():
		return
	crossing_point = hit["p"]
	var xz: Vector2 = _pick_site(rd, hit)
	if xz == Vector2.INF:
		return
	mark_position = Vector3(xz.x, 0.0, xz.y)
	# 正面朝交叉点。这里**不能**图省事改成朝世界原点：8 字的交叉点恰好就是
	# 环的中心 (0, 43)，两种写法算出来是同一条向量——已变异验证过，把这行
	# 换成 (0, 43) 之后回归全绿，一个数都不掉。RoadSteles 那条"朝向不是按
	# 世界原点算的"断言在这块碑上是个恒真的空跑，别把它抄过来。
	mark_facing = (Vector2(hit["p"].x, hit["p"].z) - xz).normalized()
	road_clearance = _road_clearance(xz, rd.points)
	_build(xz, rd, terrain_builder)


## 找「两支路心线最近」的那一对点。
##
## 找的不是解析式的自交点，是**采样出来**的那一对：8 字是自闭合的，
## 交叉处两条支路隔着半圈，所以判据是「相隔约半圈、距离最小」。
## 解析交点在这份数据里恰好就是 `points[0]`，而那依赖"起点正好落在交点"
## 这个巧合——换个采样起点就失效，而失效的 symptom 是碑凭空消失。
func _find_crossing(rd) -> Dictionary:
	var pts: Array[Vector3] = rd.points
	var n: int = pts.size()
	var half: float = float(n) * 0.5
	var best := INF
	var bi := -1
	var bj := -1
	for i in range(n):
		for j in range(i + 1, n):
			if absf(float(j - i) - half) > 3.0:
				continue
			var a: Vector2 = Vector2(pts[i].x, pts[i].z)
			var b: Vector2 = Vector2(pts[j].x, pts[j].z)
			var d: float = a.distance_to(b)
			if d < best:
				best = d
				bi = i
				bj = j
	if bi < 0:
		return {}
	return {"i": bi, "j": bj, "p": Vector3(
			(pts[bi].x + pts[bj].x) * 0.5, pts[bi].y,
			(pts[bi].z + pts[bj].z) * 0.5), "gap": best}


## 绕交叉点扫一圈，挑余量最大的那个方向。
##
## 不再取"中心线的法线"：交叉点是两个环的极端点，垂直于行进方向的两侧
## 全扎在隔壁那条臂上（实测只离沥青 3.5m），而 8 字腰上那块缺口
## （实测 45°~75°）离沥青有 12.7m。两处都不是"对称"能推出来的，
## 扫一圈让数据说话。
func _pick_site(rd, hit: Dictionary) -> Vector2:
	var pts: Array[Vector3] = rd.points
	var c: Vector2 = Vector2(hit["p"].x, hit["p"].z)
	var station_pts: Array[Vector2] = []
	for s in range(rd.stations.size()):
		var sp: Vector3 = rd.get_station_world_pos(s)
		station_pts.append(Vector2(sp.x, sp.z))
	var best := Vector2.INF
	var best_clear := 0.0
	for k in range(SITE_SWEEP):
		var a: float = TAU * float(k) / float(SITE_SWEEP)
		var p: Vector2 = c + Vector2(cos(a), sin(a)) * CROSS_OFFSET
		var clear := _road_clearance(p, pts)
		if clear < CLEAR_OF_ASPHALT or not _clear_of_stations(p, station_pts):
			continue
		if clear > best_clear:
			best_clear = clear
			best = p
	return best


func _clear_of_stations(p: Vector2, station_pts: Array[Vector2]) -> bool:
	for sp in station_pts:
		if p.distance_to(sp) < CLEAR_OF_STATION:
			return false
	return true


## 离**整条**中心线都要够远——只量交叉那一处是不够的：
## 路在 8 字腰上还有别的分支贴着，一个落点完全可能压在另一段沥青上。
## 返回的是到最近那段中心线的距离，落点判据和回归都直接用这个值。
func _road_clearance(p: Vector2, pts: Array[Vector3]) -> float:
	var best := INF
	for q in pts:
		var d := Vector2(q.x, q.z).distance_to(p)
		if d < best:
			best = d
	return best


func _build(xz: Vector2, rd, terrain_builder: Node3D) -> void:
	var y := 0.0
	if terrain_builder != null and terrain_builder.has_method("get_height_at"):
		y = terrain_builder.get_height_at(xz.x, xz.y)
	# 落点写回 y：mark_position 的注释承诺「y 取地形高度」，而它原来只拿到
	# xz（y 恒为 0）。碑身节点在下面按地形高度摆对了，于是**画面上**是对的，
	# 而任何按 mark_position 算落点的代码（回归、定妆照机位、将来的自动导览）
	# 量到的是一个悬在 y=0 的点。
	mark_position = Vector3(xz.x, y, xz.y)
	var node := Node3D.new()
	node.name = "CrossingStele"
	node.position = mark_position
	# 绕 Y 转到 mark_facing。绕 Y 转 θ 时局部 +Z 映到 (sinθ, 0, cosθ)，
	# 所以要它等于 mark_facing 就得 θ = atan2(fx, fz) —— 写反了会得到
	# 正好差 180° 的背面，而**所有"朝向"断言照样绿**：它们量的是 dot > 阈值，
	# 而 −1 一样是个漂亮的数。回归盯的就是这个符号。
	node.rotation.y = atan2(mark_facing.x, mark_facing.y)
	add_child(node)

	# 底座：踩平的一块石台，压住"是从地里长出来的"而不是浮在上面
	var base := CSGBox3D.new()
	base.name = "Base"
	base.size = Vector3(FACE_W + 0.5, PLINTH_H, PLINTH_D)
	base.position = Vector3(0, PLINTH_H * 0.5, 0)
	base.material = _mat(STONE_DARK)
	node.add_child(base)

	# 碑面：立在石台上，略微后仰（见 FACE_TILT_DEG），心在站着的人眼睛上
	var face := Node3D.new()
	face.name = "Face"
	face.position = Vector3(0, face_lift(), 0.15)
	face.rotation.x = deg_to_rad(FACE_TILT_DEG)
	node.add_child(face)

	var slab := CSGBox3D.new()
	slab.name = "Slab"
	slab.size = Vector3(FACE_W, FACE_H, SLAB_D)
	slab.material = _mat(STONE)
	face.add_child(slab)

	# 刻线：这条路自己的形状
	trace_bounds = _build_trace(rd, face)

	# 题字。放在刻线下方那一截——刻线占了面上部，别让字压在图上。
	var mark := Label3D.new()
	mark.name = "Mark"
	mark.text = _inscription()
	mark.font_size = 96
	mark.pixel_size = TEXT_PIXEL
	mark.modulate = CARVED
	mark.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	mark.no_depth_test = false
	mark.position = Vector3(0, TEXT_Y, SLAB_D * 0.5 + 0.005)
	face.add_child(mark)


## 把 `RoadData.points` 缩到碑面上刻一条带子。返回刻线在碑面局部坐标里的包围盒。
##
## 走的是**同一份** `rd.points`——`RoadBuilder` 建沥青用的也是它。
## 刻线和路不可能对不上，而"这张图和这个世界一致"本来就是这块碑的全部意义。
func _build_trace(rd, face: Node3D) -> Rect2:
	var pts: Array[Vector3] = rd.points
	var n: int = pts.size()
	var step: int = maxi(1, int(float(n) / float(TRACE_SAMPLES)))

	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for i in range(0, n, step):
		var p: Vector3 = pts[i]
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	var span: Vector2 = Vector2(max_x - min_x, max_z - min_z)
	if span.x <= 0.0 or span.y <= 0.0:
		return Rect2()
	# 按 TRACE_BOX 缩放。写死那个框而不是按面高取比例，是因为题字那格
	# 是从这块地里省出来的（见 TRACE_BOX 的注释）。
	var s: float = minf(TRACE_BOX.size.x / span.x, TRACE_BOX.size.y / span.y)
	var mid := Vector2((min_x + max_x) * 0.5, (min_z + max_z) * 0.5)
	var off := Vector2(TRACE_BOX.position.x + TRACE_BOX.size.x * 0.5,
			TRACE_BOX.position.y + TRACE_BOX.size.y * 0.5)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bmin := Vector2(INF, INF)
	var bmax := Vector2(-INF, -INF)
	for i in range(0, n, step):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + step) % n]
		var pa := _to_face(a, mid, s, off)
		var pb := _to_face(b, mid, s, off)
		# 用横跨笔画的宽度向量加粗。用 (b-a) 的垂线而不是固定方向，
		# 这样整条带子的粗细一致，拐弯处也不会翻面。
		var dir: Vector2 = (pb - pa).normalized()
		if dir == Vector2.ZERO:
			continue
		var nrm := Vector2(-dir.y, dir.x) * (TRACE_W * 0.5)
		var q0 := pa + nrm
		var q1 := pa - nrm
		var q2 := pb + nrm
		var q3 := pb - nrm
		_quad(st, q0, q1, q3, q2)
		for q in [q0, q1, q2, q3]:
			bmin = bmin.min(q)
			bmax = bmax.max(q)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Trace"
	mi.mesh = mesh
	mi.material_override = _mat(CARVED)
	mi.position = Vector3(0, 0, SLAB_D * 0.5 + 0.008)
	face.add_child(mi)
	return Rect2(bmin, bmax - bmin)


## 世界坐标 → 碑面局部坐标（面在局部 XY 平面上，正面朝 +Z）。
func _to_face(p: Vector3, mid: Vector2, s: float, off: Vector2) -> Vector2:
	return Vector2((p.x - mid.x) * s, -(p.z - mid.y) * s) + off


## 一个 quad 六个顶点。
##
## 顺序是 **(a,c,b) / (a,d,c)** 而不是看上去更顺的 (a,b,c) / (a,c,d)：
## Godot 的正面是**顺时针**，而带上那对法线偏移之后 (a,b,c) 恰好数出逆时针，
## 整条刻线于是全是背面——从正面看过去**什么都没有**，而带子本身、
## 顶点朝向、包围盒、段数、逐点对拍全都正常，headless 下无一处会红。
## 判据只有图能判：绕 Y 满偏 180° 那一版的定妆照上碑面是一块空白石板。
func _quad(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> void:
	for v in [a, c, b, a, d, c]:
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(Vector3(v.x, v.y, 0.0))


func _inscription() -> String:
	var loc := get_node_or_null("/root/Localization")
	if loc != null and loc.has_method("t"):
		return str(loc.call("t", "crossing_mark_line"))
	return "路自此复"


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.linear_to_srgb()
	m.roughness = 0.92
	m.metallic = 0.0
	return m
