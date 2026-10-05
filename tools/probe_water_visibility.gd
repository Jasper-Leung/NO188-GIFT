extends SceneTree
## probe_water_visibility.gd — 三处水**从路上看不看得见**
##
## 问的是"玩家骑在路上能不能看见水面"，不是"碗挖得对不对"。后者是
## `probe_water.gd` / `verify_water.gd` 的活（盖住碗的百分之几、水面半径、
## 每个顶点底下是不是湿的），而那一族的判据**全绿而玩家一整圈没看见过
## 一片水**——因为它们量的是**碗和水**的关系，一条都没问过**路和水**的关系。
##
## 距离不是原因：`BASIN_ROAD_CLEAR` 已经保证**盆沿**离路心线 ≥16m，
## 而 16m 远的一片水本身是看得见的。看不见的原因是**水在路的下方**——
## 水位 −3.4，而路多半压在那片被 clamp 的 −3.0 地板之上，于是碗是一个
## 骑到边上才看得见的坑。
##
## 所以判据是一道**视线**：从路面眼高出发，往碗心打一条射线，沿途查地形
## 有没有高过这条视线。查的是**挖碗之后的高程**（`natural - depth_at`），
## 不是自然高程——第一版图省事只查自然高程，而**碗的footprint 之内挖碗
## 是把地形往下压的**，于是射线快到碗心时读到的是 −3.00 的地板、判成
## "被挡住了"，报出来 0/3 处看不见。那是**尺子量错了对象**：
## 自然高程只在碗外是"挡视线的东西"的上界，碗内它比真实地面高好几米。
##
## **headless 可跑**：量的是几何，不出图。但**改碗的参数之后必须看图**
## （`lookdev_water.gd`），因为"看得见"和"看着像水"是两件事。
##
## 用法： godot --headless --path . --script tools/probe_water_visibility.gd

## 骑行眼高。见 `Player3D.CAM_UP` 那一族。
const EYE_H := 1.6
## 视线全程高出地形这么多才算看得见。取的是**地形网格的分辨率**
## （`TerrainBuilder` 的步进），比它小的高程差渲染不出来，
## 而拿 0 当门槛会把浮点噪声报成遮挡。
const BLOCK_EPS := 0.15


func _initialize() -> void:
	Engine.max_fps = 60
	_run.call_deferred()


func _run() -> void:
	print("=== 水面从路面看不看得见 ===")
	# `load()` 一个 .gd 拿回来的是 GDScript，**必须 .new()**——
	# 忘了这一步会在第一次 `natural.call(...)` 上抛 "Nonexistent function"，
	# 而这个协程一抛异常 `quit()` 就永远走不到，于是进程**挂着不退**，
	# 报错只有一行、看上去像"卡住了"。
	var rd = load("res://scripts/road_data.gd").new()
	var tb = load("res://scripts/TerrainBuilder.gd").new()
	var wd = load("res://scripts/water_data.gd")
	var road: Array = rd.points
	print("中心线 %d 个采样点，总长 %.1fm" % [road.size(), rd.total_arclength()])

	var natural := func(x: float, z: float) -> float:
		return tb.natural_height_at(x, z)
	var basins: Array = wd.plan(natural)
	# 碗挖完之后那一片的真实地面。`depth_at` 就是给 `TerrainBuilder._height()`
	# 用的同一个函数，所以量到的和渲染出来的是同一块地。
	var ground := func(x: float, z: float) -> float:
		return tb.natural_height_at(x, z) - wd.depth_at(x, z)

	var n_seen := 0
	for b in basins:
		if _report(int(b["station"]), rd, b, road, ground):
			n_seen += 1
	print("\n看得见的 %d / %d 处" % [n_seen, basins.size()])
	quit(0)


func _report(si: int, rd, b: Dictionary, road: Array, ground: Callable) -> bool:
	var c := Vector2(float(b["center"].x), float(b["center"].y))
	var level: float = float(b["level"])
	var near := _nearest(c, road)
	var dist: float = Vector2(near.x - c.x, near.z - c.y).length()
	var nm: String = rd.stations[si]["name"]
	print("\n[%d] %s" % [si, nm])
	print("    碗心离路心线 %.1fm   路高 %.2fm   水位 %.2fm   路高出水 %.2fm"
			% [dist, near.y, level, near.y - level])

	var from := Vector2(near.x, near.z)
	var eye_y: float = near.y + EYE_H
	var steps := maxi(int(dist), 8)
	var hit := -1.0
	# 视线的**余量**：全程最紧的那一格还差多少米才被地形咬住。
	# "看得见"是个布尔，而布尔不说"差 0.2m"和"差 4m"是一回事——
	# 前者意味着任何一棵树、任何一次量化误差都能让它在实机上消失。
	var margin := INF
	for s in range(1, steps + 1):
		var t: float = float(s) / float(steps)
		var p: Vector2 = from.lerp(c, t)
		var ray_y: float = eye_y + (level - eye_y) * t
		var g: float = float(ground.call(p.x, p.y))
		if ray_y - g < margin:
			margin = ray_y - g
		if g > ray_y + BLOCK_EPS:
			hit = p.distance_to(from)
			print("    **看不见**：离路 %.1fm 处地形就挡住了视线（地形 %.2fm，视线上 %.2fm）"
					% [hit, g, ray_y])
			break
	if hit < 0.0:
		print("    看得见：视线全程最紧的一格离地形还有 %.2fm" % margin)
		return true
	return false


func _nearest(p: Vector2, road: Array) -> Vector3:
	var best := INF
	var at: Vector3 = road[0]
	for q in road:
		var d: float = Vector2(q.x - p.x, q.z - p.y).length_squared()
		if d < best:
			best = d
			at = q
	return at