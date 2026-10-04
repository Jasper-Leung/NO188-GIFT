extends Node3D
## RoadVerge — 路肩之外那一道**看得见**的软边界。
##
## 评审 P1-2：车骑出路肩 15~20m 之后「找不着路」。这一族在 CLAUDE.md 的陷阱
## 清单里早就记着机制——`SOFT_BOUND`(12m) 之外 `_apply_boundary_force()` 开始
## 往回推，而推力在 21m 处就压过 `Player3D.ACCEL = 8.0`，所以一辆满速 15m/s 的
## 车在 27m 处正好被钉住。当年的结论是「回归验证：无」，因为当时只有一把
## 「这辆车怎么不动」的尺子，量不出「玩家看不见该往哪骑」。
##
## 修法是**画出来**，不是削弱推力（削弱推力会让人真的骑进 25m 那道硬墙，
## 而墙只是更硬，方向仍然是错的）。评审给的两条路是「草色变浅 / 一道土径」，
## 这里取后者做成一条**压实的碎石路肩**：从沥青外沿一直铺到 14.5m，
## 颜色从砾石 → 车辙压实的那一档 → 在**恰好 `World3D.SOFT_BOUND` 那个距离上**
## 刷亮成一道粉线 → 再淡回地形本来的草色。
##
## **原来是土径，而土径就是这一轮清掉的那个东西**：沿整条环路两侧读成两条
## 泥带。所以中间三档全是低饱和的灰砾石（通道差 ≤ 0.027），
## 亮带也跟着去掉了那点土黄——留着它会在灰砾石底上重新读成一道泥印。
## 而"边界画在哪"这件事一个字没变：亮带仍然钉在 `SOFT_BOUND` 上。
##
## **这道带子必须落在 SOFT_BOUND 上，一米都不许偏。** 推力是按到中心线的
## 距离算的，玩家能看见的提示是按眼睛看的东西算的；这两条线一旦错开，
## 玩家会在「已经开始被推」的时候还什么也没看见，于是那道墙读起来仍然是
## 「没有理由的墙」。所以 `MARK` 就是 `World3D.SOFT_BOUND` 的值本身，
## `World3D` 建这个节点时是**从自己那个常量传进来的**，不是两边各抄一个 12.0。
##
## 零纹理（和 asphalt / terrain_grass / grass 同一族约束），纯顶点色。
## 只铺**主环路**——`World3D._apply_boundary_force()` 的 `_road_points_2d`
## 同样只喂了 `road_data.points`，支线不参与那道推力，所以支线上画一条
## 边界反而是**另一处**「屏幕在说代码没说的话」。

## 内沿：沥青外沿（RoadBuilder.TOTAL_HALF_WIDTH = 6.5m）。
const INNER := 6.5
## 外沿。再远就该由地形自己接管了，铺过去只会多出一圈自己造的硬边。
const OUTER := 14.5
## 抬离地形这么多，免得和地形网格共面打架。
const LIFT := 0.05
## 内沿：压实的碎石路肩。**这一带原来是一条土径**（`DIRT` 0.300/0.250/0.170），
## 而那正是这一轮要清掉的东西——沿整条环路两侧读成两条泥带，而评审要的判据是
## "骑过这带子的人不会觉得自己骑到乡下去了"。改成**低饱和的灰砾石**：
## 满带最大通道差 0.027，肉眼里读成石头而不是土，铺法也和沥青到碎石路肩
## 的做法一致。亮度守住了"比草地暗"（相对亮度 0.124 对草地 0.215），
## 所以"从沥青上走下来了"那一读数没丢。
##
## **下面这四个数是按"渲出来什么样"定的，不是按反照率定的。**
## 量法：正交俯拍（`size = 60m`，比例尺 12 px/m）从路心往外每 0.5m 读一行
## 像素，读到 8.5~14.5m 那六米的真实颜色。第一版照着 WCAG 反照率对比度
## 定的 0.84/0.82/0.70，渲出来是 sRGB(0.99,0.99,1.00) —— **整条 6m 宽的
## 带子全顶到白**，"一道线"根本不存在，读出来是一圈水泥地。
## 而回归那两条「对比度 ≥ 2.2:1」当时**全绿**：它们量的是我填进去的那个
## 0.84，中间隔着法线、太阳、AGX 与雾，一层都没量到。
const GRAVEL := Color(0.395, 0.386, 0.368)
## 中段：车辙压得更实一点的同一种砾石，比 GRAVEL 再暗一档（相对亮度 0.097
## 对 0.124），但仍远暗于那道漂白带（0.290，34%）——**两级台阶都要在**，
## 少一级那条带子就退成一整片水泥地，"线"根本读不出来。
const PACKED := Color(0.352, 0.344, 0.328)
## 边界那道漂白带。全场最要紧的一个数。
## 0.58 那一档渲出来约 sRGB 0.77 —— 比两侧的砾石（0.42）和草（0.50）
## 都亮出一截，又没有顶到白。第一版 0.84 那一档在 sRGB 口径下渲成
## 0.99，**整条 6m 宽的带子一起顶到白**，"一道线"根本不存在。
## 通道差从原来的 0.11（暖白）收到 0.022：它是**刷在砾石上的一道粉线**，
## 带着原来那点土黄会在灰砾石底上重新读成一道泥印。
const LINE := Color(0.580, 0.575, 0.558)
## 外沿必须渲成和地形一样，否则土径尽头会多出一道**自己造出来的**硬边
## ——那就等于把「找不着路」换成了「路忽然齐刷刷断了」。
## **注意它不等于 terrain_grass.gdshader 的 ground_color。** 那条带子走
## StandardMaterial3D、地形走自己的 shader，同一个反照率（0.36,0.55,0.24）
## 实测渲出来是 0.90 对 0.48 —— 差 1.8 倍，所以照抄 ground_color 会在
## 14.5m 处多出一圈比周围亮的环。这一档是把外沿**反算**回地形那个值的。
const GRASS := Color(0.292, 0.422, 0.180)

var _terrain_builder: Node3D = null
var _mesh: MeshInstance3D = null


## 剖面：[距离, 颜色]。**`mark` 那一列的距离由 `build()` 从 World3D
## 传进来的 `soft_bound` 算**，所以「画出来的边界」和「推你回来的那道力」
## 引的是同一个数，改一边另一边一定跟着动。
static func verge_profile(soft_bound: float) -> Array:
	return [
		[INNER, GRAVEL],
		[9.0, PACKED],
		[soft_bound - 0.9, PACKED],
		[soft_bound, LINE],
		[soft_bound + 1.1, LINE.lerp(GRASS, 0.62)],
		[OUTER, GRASS],
	]


func set_terrain_builder(tb: Node3D) -> void:
	_terrain_builder = tb


func _terrain_h(wx: float, wz: float) -> float:
	if _terrain_builder != null and _terrain_builder.has_method("get_height_at"):
		return _terrain_builder.get_height_at(wx, wz)
	return 0.0


## 主环路一条。`centerline` 是 RoadBuilder 那份已经平滑+重采样过的，
## `soft_bound` 是 World3D.SOFT_BOUND。
func build(centerline: Array, soft_bound: float) -> void:
	if centerline.size() < 3:
		return
	var prof: Array = verge_profile(soft_bound)
	var cols: int = prof.size()
	var sides: Array[Vector3] = _side_vectors(centerline)
	var n: int = centerline.size()

	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	# 每个中心线点：路左 cols 个（由内到外）+ 路右 cols 个
	for i in n:
		var p: Vector3 = centerline[i]
		var s: Vector3 = sides[i]
		for sgn in [1.0, -1.0]:
			for c in cols:
				var d: float = prof[c][0]
				var x: float = p.x + s.x * d * sgn
				var z: float = p.z + s.z * d * sgn
				var th: float = _terrain_h(x, z)
				# 内沿与沥青路肩齐平（路肩沉下去 SHOULDER_SINK=0.15），
				# 往外 2.5m 平滑抬到地形之上——否则车轮下会多出一道 0.2m 的台阶
				var k: float = clampf((d - INNER) / 2.5, 0.0, 1.0)
				var y: float = lerpf(th - 0.15, th + LIFT, k * k * (3.0 - 2.0 * k))
				verts.append(Vector3(x, y, z))
				colors.append(prof[c][1])

	# 带子在环上首尾相接，所以最后一段绕回 0——不接的话出发点与终点
	# 之间会裂一道口子，而那恰好是玩家每一趟都经过的地方。
	var per: int = cols * 2
	for i in n:
		var a: int = i * per
		var b: int = ((i + 1) % n) * per
		for c in per:
			# 跳过「路左最外」跨到「路右最内」那一跳：连上会把整条路
			# 盖成一张横跨的板子
			if c == per - 1 or c % cols == cols - 1:
				continue
			indices.append(a + c)
			indices.append(b + c)
			indices.append(a + c + 1)
			indices.append(a + c + 1)
			indices.append(b + c)
			indices.append(b + c + 1)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = _face_normals(verts, indices)
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	# 顶点色按 **sRGB** 解释。`vertex_color_is_srgb` 默认是 false，也就是
	# 引擎把数组里那个 0.21 当成**线性**反照率用——换成 sRGB 口径它其实是
	# 0.50，整条带子凭空亮了一档半，14.5m 的外沿渲成 0.71 而旁边的地形是
	# 0.40，于是土径尽头多出一圈比周围亮的环。
	# 全工程其余的颜色（GLB 的 `linear_to_srgb()`、`DayCycle` 那些常量、
	# 地形着色器的 `ground_color`）一律按 sRGB 写，这一个也不例外。
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# 缠绕方向不判：这是一条铺在地上的带子，背面朝下永远看不见，
	# 而逐面推正确的朝向要在起伏地形上多算一遍 cross product。
	# 关掉剔除换来的是「缠绕写反了也不会整条消失」这一条保险。
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)

	_mesh = MeshInstance3D.new()
	_mesh.name = "VergeMesh"
	_mesh.mesh = mesh
	add_child(_mesh)


## 逐面累加再归一化，和 `RoadBuilder._build_road()` 同一套算法。
##
## **这个数组不许省。** 第一版没写 `ARRAY_NORMAL`，于是着色器拿到的是零法线：
## 方向光的 `N·L` 恒为 0，这条带子只吃到天光环境光，于是那一圈本该是
## **苍白**的标记带渲出来是 sRGB(0.16,0.29,0.54) 的**深蓝**——比两边的
## 草地还暗两档，俯拍量到的是一条"暗沟"，骑行视角量到的是"路外有一道
## 阴影"。而且它不会消失：颜色、顶点色、剔除开关、LIFT 埋深全都正常，
## **只有看图才发现**——回归里量的是剖面里的 `LINE` 那个颜色，
## 而那个颜色确实就是 0.84/0.82/0.70，一格不差。
## 教训是同一条的两头：**顶点色不是屏幕上的颜色**，
## 中间隔着法线、太阳角度、AGX 与雾；量到"我填进去的那个数"，
## 量不到"玩家看见的那个数"。
func _face_normals(verts: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in normals.size():
		normals[i] = Vector3.ZERO
	for t in range(0, indices.size(), 3):
		var pa: Vector3 = verts[indices[t]]
		var n: Vector3 = (verts[indices[t + 2]] - pa).cross(verts[indices[t + 1]] - pa).normalized()
		normals[indices[t]] += n
		normals[indices[t + 1]] += n
		normals[indices[t + 2]] += n
	for i in normals.size():
		# 累加不抵消的那些（本环内外沿交界处缠绕方向相反）退回竖直向上，
		# 宁可法线粗糙一点，也不要让一片地面收不到太阳
		if normals[i].length_squared() > 1e-8:
			normals[i] = normals[i].normalized()
		else:
			normals[i] = Vector3.UP
	return normals


func _side_vectors(centerline: Array) -> Array[Vector3]:
	var n: int = centerline.size()
	var out: Array[Vector3] = []
	out.resize(n)
	for i in n:
		var t: Vector3
		if i == 0:
			t = centerline[1] - centerline[0]
		elif i == n - 1:
			t = centerline[n - 1] - centerline[n - 2]
		else:
			t = centerline[i + 1] - centerline[i - 1]
		if t.length_squared() < 1e-6:
			t = Vector3(1.0, 0.0, 0.0)
		t = t.normalized()
		out[i] = Vector3(-t.z, 0.0, t.x)
	return out


## 建出来的网格，供回归对账。
func get_mesh() -> MeshInstance3D:
	return _mesh
