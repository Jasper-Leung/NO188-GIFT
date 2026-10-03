extends RefCounted
## 水体定义 —— 名字承诺了水的地方，地上就得真的有水。
##
## 「南溪茶寮」「花房·禽语湖湾」「西湾神苑」三个站名和它们写在 `road_data.text`
## 里的那几句话都在讲水，而世界里原本连一滴水都没有：玩家骑到溪边，拿到的是
## 一片和别处一模一样的草坡。这不是"不够精致"，是**名字在骗人**。
##
## 这一份是 `TerrainBuilder` 和 `Water` 共同的唯一出处：地形按它挖碗，
## 水面按同一组碗找岸线。两边各算一次的话，碗和水面迟早对不上。
##
## ---- 为什么水位是一个全场统一的常数，而不是"碗底 + 一点" ----
## 第一版是"水位 = 碗心实挖高程 + FILL×碗深"，看着天经地义，实测（tools/probe_water.gd）
## 每一处水都有几十度角**在两倍盆沿之外还没露出岸**。原因不是碗挖得不好，
## 是这条路的地形在几十米尺度上就有几米的落差：水位是按碗心定的，
## 顺坡的一侧于是永远追不上岸，水面会在半空中被切断。
##
## 真正把水关住的是这条路地形的一个硬事实：**`_height()` 把高程 clamp 在 [-3, 6]**，
## 也就是说自然地形永远不低于 -3.0（实测 31% 的采样点正好压在这个下限上，
## 是一望无际的平地）。所以只要把水位放到 -3.0 以下，全场低于水位的就只有
## 我们挖出来的那三只碗——碗沿处碗深归零、高度回到自然地形，必然高于水位。
## 于是"水会不会漫出去"这个问题不再取决于地形坡度，而是恒等于否。
## 代价是碗要挖得比"看着差不多"更深一些，而这个深度是算出来的、不是填的：
## `D = 碗心自然高程 - 水位 + WATER_DEPTH`，保证碗心正好有 `WATER_DEPTH` 深的水。

const RoadDataRef = preload("res://scripts/road_data.gd")

## 盆沿离路心线的最小距离。必须大于 `TreeScatter.SIDE_OFFSET`(11) + `OFFSET_JITTER`(1.5)，
## 不然行道树会站在湖里；也要大于 `GrassScatter.ROAD_CLEAR`(8)。
const BASIN_ROAD_CLEAR := 16.0

## 全场统一的水位。**必须低于 `TerrainBuilder` 的高程下限 -3.0**，理由见文件头。
## 离下限留 0.4m 余量：碗沿处的高度是自然地形（≥ -3.0），高出水位越多，
## 岸就越陡、越不会被量化误差啃掉。
const WATER_LEVEL := -3.4

## 碗心的水深。碗深由此反推，所以这个数是唯一要调的旋钮。
const WATER_DEPTH := 1.1

## 找碗心时扫多远的范围、步长，以及"离站太远"的罚分。
##
## 扫这一片不是为了把碗推远，是为了**找低地**：见 `_best_site()`。
## 步长 6m 是拿"够不够平"换来的：水面最终由"自然地形减去碗深 低于水位"
## 那一圈决定，所以候选点要按**整片碗底**的平均高程打分，而不是只看碗心一处
## ——只看碗心的话，选出来的是"最低的那个点"，那片地面往往是陡坡的下缘，
## 于是湖缩成迎水一侧的一弯月牙（实测：花房·禽语湖湾水面半径 7m~29m）。
const SITE_SEARCH_REACH := 150.0
const SITE_SEARCH_STEP := 6.0
## 离站越远，罚分越高。0.006/m = 100m 处多 0.6m 的高程，
## 够压住"跑到远处洼地里去"这种解，而近处一点点的高低仍然由地形说了算。
const SITE_STATION_PENALTY := 0.006
## 三只碗之间要留的空隙，免得两片水在中间连成一条。
const SITE_SEPARATION := 24.0

## 三处碗的形状。`squash` 沿**路的方向**拉长，所以溪是顺着路走的狭长一片，
## 而横向只占 `radius` —— 横向才是决定离路远近的那个维度。
const BASIN_SHAPES := [
	{"station": 2, "radius": 22.0, "squash": 3.2, "depth": 0.7},  # 南溪茶寮
	{"station": 4, "radius": 30.0, "squash": 1.25, "depth": 1.3}, # 花房·禽语湖湾
	{"station": 6, "radius": 26.0, "squash": 1.5, "depth": 1.0},  # 西湾神苑
]

static var _cache: Array = []


## 按真实地形把三只碗定下来。**必须在建地形网格之前调一次**，
## 因为地形网格本身要按碗深来挖，而碗深又取决于自然地形高程。
##
## `natural` 是"未挖碗的"高程查询（`TerrainBuilder.natural_height_at`）。
## 传 Callable 而不是让本文件去依赖 TerrainBuilder，是为了让依赖只朝一个方向走：
## TerrainBuilder → water_data，反过来就成环了。
static func plan(natural: Callable) -> Array:
	_cache.clear()
	var rd = RoadDataRef.new()
	for shape in BASIN_SHAPES:
		var si: int = int(shape["station"])
		var st: Vector3 = rd.get_station_world_pos(si)
		var near := _nearest_centerline(rd, st)
		var away := Vector2(st.x - near.x, st.z - near.z)
		if away.length_squared() < 1e-6:
			away = Vector2.RIGHT
		away = away.normalized()
		# 拉伸轴 = 垂直于 away，即顺着路。溪因此与路平行，而不是戳向路。
		var along := Vector2(-away.y, away.x)
		var radius: float = float(shape["radius"])
		var squash: float = float(shape["squash"])
		var center := _best_site(natural, rd, Vector2(st.x, st.z), away, along,
				radius, squash)
		# 碗深由"碗心要正好有 depth 米水"反推，而不是手填。
		# 手填的话三处碗的水深会随着地形改动而漂，而漂了之后碗底有可能
		# 高于水位——那只碗就成了一个永远露不出水的坑，而回归还在绿。
		var h_c: float = float(natural.call(center.x, center.y))
		var w_depth: float = float(shape["depth"])
		_cache.append({
			"station": si,
			"center": center,
			"radius": radius,
			"depth": h_c - WATER_LEVEL + w_depth,
			"water_depth": w_depth,
			"level": WATER_LEVEL,
			"squash": squash,
			"ax": along.x,
			"az": along.y,
		})
	return _cache


## 碗心站哪儿。这是"玩家看到的是湖还是土坑"的全部决定。
##
## 水面盖住的是"自然地形减去碗深之后低于水位"的那一圈，所以碗好不好看
## 取决于**整片碗底的自然高程平不平**，而不是碗心那一点高不高。
## 只挑最低的点会挑到陡坡的下缘：湖顺着下坡摊开、上坡一侧露成一大片干土，
## 于是水面从 7m 一直拉到 29m（实测的原始值）。
##
## 所以按**碗底足迹的平均高程**打分，踩过的坑就都取最小值。碗心贴着
## 自然地形那片 -3.0 的地板时平均高程最低，自由板最小，水面占到碗的七成。
##
## 硬约束两条：整片碗沿离中心线至少 `radius + BASIN_ROAD_CLEAR`（碗不能压到路），
## 以及和已经定下的碗隔开 `SITE_SEPARATION`（两片水别在中间连成一条）。
## 离站太远则按 `SITE_STATION_PENALTY` 罚分——否则最优解永远是地图角落那片洼地，
## 而玩家骑一圈都不会看见它。
static func _best_site(natural: Callable, rd, st: Vector2, away: Vector2,
		along: Vector2, radius: float, squash: float) -> Vector2:
	var n := int(SITE_SEARCH_REACH / SITE_SEARCH_STEP)
	var need := radius + BASIN_ROAD_CLEAR + 2.0
	var best := st + away * need
	var best_score := INF
	for xi in range(-n, n + 1):
		for zi in range(-n, n + 1):
			var p := st + away * (float(xi) * SITE_SEARCH_STEP) \
					+ along * (float(zi) * SITE_SEARCH_STEP)
			if p.distance_to(st) > SITE_SEARCH_REACH:
				continue
			if _dist_to_centerline(rd, p) < need:
				continue
			var clash := false
			for b in _cache:
				if p.distance_to(b["center"]) < SITE_SEPARATION + float(b["radius"]):
					clash = true
					break
			if clash:
				continue
			var score := _footprint_mean(natural, p, away, along, radius, squash) \
					+ SITE_STATION_PENALTY * p.distance_to(st)
			if score < best_score:
				best_score = score
				best = p
	return best


## 碗底足迹上的自然高程均值。碗是 `k²` 的碗形，实际影响水面的范围大致是
## 内圈到盆沿，所以取 0 / 0.55r / 0.95r 三圈，而中心点权重给三倍——
## 碗心的自由板直接决定"湖底露不露得出来"。
static func _footprint_mean(natural: Callable, c: Vector2, away: Vector2,
		along: Vector2, radius: float, squash: float) -> float:
	var total := 3.0 * float(natural.call(c.x, c.y))
	var n := 0
	for frac in [0.55, 0.95]:
		for k in range(8):
			var a := TAU * float(k) / 8.0
			var dir := along * (cos(a) * squash) + away * sin(a)
			var p := c + dir * (radius * float(frac))
			total += float(natural.call(p.x, p.y))
			n += 1
	return total / float(3 + n)


static func _dist_to_centerline(rd, p: Vector2) -> float:
	var best := INF
	for q in rd.points:
		best = minf(best, Vector2(q.x - p.x, q.z - p.y).length())
	return best


## 碗定好了没有。`depth_at()` 静默返回 0 的话，地形会看起来好好的，
## 只是三只碗从来没被挖过——所以回归里要有一条问它。
static func is_planned() -> bool:
	return not _cache.is_empty()


## 三只碗。`Water.gd` 和回归都从这里读，读的是**同一批对象**——
## 各算一次的话水面和地形迟早对不上，而两边看着都很正常。
static func basins() -> Array:
	return _cache


## 某个世界坐标被碗挖下去多少米。`TerrainBuilder._height()` 调它。
##
## 碗形是 `k²`（k = 1-(d/r)²）：碗底平、碗壁在盆沿处一阶导归零，
## 所以盆沿不会和周围地形之间留一道折痕。两个碗重叠时**相加**而不是取最大——
## 相加的碗和相加的水位仍然自洽，取最大则两处碗的交界会鼓出一块台地。
static func depth_at(x: float, z: float) -> float:
	var total := 0.0
	for b in _cache:
		var dx := x - float(b["center"].x)
		var dz := z - float(b["center"].y)
		var u: float = (dx * float(b["ax"]) + dz * float(b["az"])) / float(b["squash"])
		var v: float = -dx * float(b["az"]) + dz * float(b["ax"])
		var d := sqrt(u * u + v * v)
		var r: float = b["radius"]
		if d >= r:
			continue
		var k := 1.0 - (d / r) * (d / r)
		total += float(b["depth"]) * k * k
	return total


static func _nearest_centerline(rd, p: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var bd := INF
	for q in rd.points:
		var d: float = Vector2(q.x - p.x, q.z - p.z).length_squared()
		if d < bd:
			bd = d
			best = q
	return best
