extends SceneTree
## verify_water.gd — 三处水的回归
##
## 世界里原本连一滴水都没有，而三个站名（南溪茶寮 / 花房·禽语湖湾 / 西湾神苑）
## 和它们写在 `road_data.text` 里的话都在讲水。这条回归守的是"名字承诺的水
## 真的在地上"，具体是四件各自会红的事：
##
##   1  **该有水的三座站真的有水**，且这三座是**按站名挑出来的**——
##      下标抄一份在这里的话，产品改了站名这条照样绿。
##   2  **水面压在土里**：碗心地形低于水位。不是一张悬在空中的蓝片。
##   3  **水不漫到岸外**：水面边缘（±几个角度）地形必须高于水位。
##      这一条是"蓝纸铺在干地上"的唯一拦得住的地方，而它只有在
##      岸线是**沿真实地形求交**算出来的时候才成立——用圆盘就会红。
##   4  **水不压到路**：水面任何一个顶点离路心线都要够远，
##      而且中心线没有一段落进任何一只碗里（碗挖进了地形，
##      而路面高度是从地形采样的）。
##
## 另外顺手钉住"行道树不许站在湖里"：树在 SIDE_OFFSET 11m，
## 碗沿在 BASIN_ROAD_CLEAR(16)，这条本来是余量，但余量只有 5m，
## 改任一个常数都可能吃掉它，而吃掉的症状是玩家看见一棵树从水面长出来。

## 运行时 `load()` 而不是 `preload`：preload 会把 road_data.gd 拉进**编译期**，
## 而它引用了 `Localization` autoload —— `--script` 模式下 analyzer 解析不了
## autoload，于是报 "Identifier not found: Localization"，接着脚本整份加载失败。
## 判据仍然是产品自己的那份定义，不是这里抄一份。
var _road_data_script: Script = null
var _water_data_script: Script = null

var _fails := 0
var _ck_count := 0


func _ck(label: String, cond: bool, detail: String = "") -> void:
	_ck_count += 1
	if cond:
		print("[OK]   ", label)
	else:
		_fails += 1
		print("[FAIL] ", label + ("（" + detail + "）" if detail != "" else ""))


func _initialize() -> void:
	Engine.max_fps = 60
	for n in {"GameManager": "res://scripts/GameManager.gd",
			"AudioManager": "res://scripts/AudioManager.gd",
			"Localization": "res://scripts/Localization.gd"}:
		if root.get_node_or_null(n) == null:
			var node: Node = load(n).new()
			node.name = n
			root.add_child(node)
	var gm = root.get_node("GameManager")
	gm._clear_save()
	gm.headless_mode = true
	gm.onboarding_shown = true
	gm.prologue_done = true
	root.size = Vector2i(1280, 720)
	root.add_child(load("res://scenes/World3D.tscn").instantiate())
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	var w = root.get_child(root.get_child_count() - 1)
	_road_data_script = load("res://scripts/road_data.gd")
	_water_data_script = load("res://scripts/water_data.gd")
	var rd = _road_data_script.new()
	var tb = w._terrain_builder
	var water = w.get_node_or_null("Water")
	_ck("World3D 里挂了 Water 节点", water != null)
	if water == null:
		_finish()
		return
	var bodies = water.bodies()

	# ---- 1 该有水的三座站 ----
	# 按名字挑，不按下标。中文名里带水字的那三座就是承诺了水的三座。
	var want: Array = []
	for i in rd.stations.size():
		var nm: String = rd.stations[i]["name"]
		if "溪" in nm or "湖" in nm or "湾" in nm or "泉" in nm:
			want.append(i)
	_ck("站名里承诺了水的有三座", want.size() == 3,
			"找到 %s" % str(want))
	var got: Array = []
	for b in bodies:
		got.append(int(b.get_meta("station")))
	got.sort()
	var want_sorted := want.duplicate()
	want_sorted.sort()
	_ck("水体正好挂在那三座站上（按下标对拍，不是抄一份表）",
			got == want_sorted, "水体在 %s，站名挑出来的是 %s" % [str(got), str(want_sorted)])

	# ---- 2/3 水面压在土里 / 不漫到岸外 ----
	# 先钉住整套设计的那个前提：水位压在自然地形的高程下限**之下**。
	# 三只碗之所以关得住水，全靠这一条——自然地形恒不低于下限，
	# 于是全场低于水位的只有挖出来的碗（推导见 water_data.gd 文件头）。
	# 有人把水位调回上限之上，这条立刻红，而且解释得了红的原因。
	var lowest_natural := INF
	for xi in range(-30, 31, 3):
		for zi in range(-30, 31, 3):
			lowest_natural = minf(lowest_natural,
					tb.natural_height_at(float(xi) * 20.0, float(zi) * 20.0))
	var levels := {}
	for b in bodies:
		levels[float(b.get_meta("level"))] = true
	_ck("水位压在自然地形下限之下（关得住水的那个前提）",
			levels.size() == 1 and lowest_natural > float(bodies[0].get_meta("level")),
			"最低自然高程 %.2f 水位 %s" % [lowest_natural, str(levels.keys())])
	_ck("三处水共用同一个水位（不是一个按碗心各算各的）", levels.size() == 1,
			"量到 %s" % str(levels.keys()))

	for b in bodies:
		var si := int(b.get_meta("station"))
		var level: float = b.get_meta("level")
		var rad: float = b.get_meta("radius")
		var nm: String = rd.stations[si]["name"]
		var verts: PackedVector3Array = b.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var c := _centre(verts)
		_ck("%s：碗心地形低于水位（水压在土里，不是悬着的蓝片）" % nm,
				tb.get_height_at(c.x, c.y) < level,
				"碗心 %.2f 水位 %.2f" % [tb.get_height_at(c.x, c.y), level])
		# 边缘高程：沿 8 个角度各取最外圈顶点，往外再走 1.5m 看地形。
		# 用"边缘顶点 + 1.5m"而不是边缘顶点本身，因为交点上两者相等，
		# 差值落在 MESH_DROP(0.04) 的量级里，量不出东西。
		#
		# 取的是**最小**值：漫出去只要有一个方向漏出去就算漏，
		# 而 maxf 量的是"最高的那处"——那个方向永远是最干的一处，于是这条
		# 无论岸线画成什么样都绿。第一版就是这么写的。
		var lowest := INF
		for k in range(8):
			var a := TAU * float(k) / 8.0
			var p := c + Vector2(cos(a), sin(a)) * (rad + 1.5)
			lowest = minf(lowest, tb.get_height_at(p.x, p.y) - level)
		_ck("%s：岸外地形高于水位（水没漫出去）" % nm, lowest > 0.0,
				"最低的那处还差 %.2fm" % -lowest)

		# 上面那条量的是"外圈之外 1.5m"，中间那一圈仍然没人管：岸线画大了
		# （比如退化成"以碗心为圆心的圆盘"）的话，越界的顶点全都落在外圈上，
		# 而外圈**之外**1.5m 仍然是干的——于是上一条照样绿。
		# 这一条把判据压到水面自己身上：**每一个顶点都得站在水位以下的土里**，
		# 任何一个顶点下面是干的，就是水铺到了岸外。
		var on_dry := 0
		for v in verts:
			if tb.get_height_at(v.x, v.z) - level > 0.0:
				on_dry += 1
		_ck("%s：水面每个顶点都落在水位以下（水没铺到干地上）" % nm, on_dry == 0,
				"%d / %d 个顶点下面是干的" % [on_dry, verts.size()])

	# ---- 4 水不压到路 ----
	var lines = w._road_builder.get_all_centerlines()
	var closest := 1e9
	for b in bodies:
		var verts: PackedVector3Array = b.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for v in verts:
			closest = minf(closest, _dist_to_road(lines, Vector2(v.x, v.z)))
	_ck("水面离路心线始终够远（路肩 6.5m + 行道树 11m）",
			closest >= 14.0, "最近 %.1fm" % closest)

	# 碗挖进了地形，而路面高度是从地形采样的：中心线只要有一段落进碗里，
	# 那一段的路就会跟着往下陷。所以碗必须整个待在路外面。
	var inside := 0
	for line in lines:
		for p in line:
			if _water_data_script.depth_at(p.x, p.z) > 0.01:
				inside += 1
	_ck("中心线没有任何一段落进碗里", inside == 0, "有 %d 个采样点在碗内" % inside)

	# ---- 5 行道树不许站在湖里 ----
	var in_water := 0
	var tree_list: Array = []
	if w._tree_scatter != null:
		tree_list = w._tree_scatter._trees
	for t in tree_list:
		var tp: Vector3 = t["pos"]
		for b in bodies:
			var verts: PackedVector3Array = b.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var c := _centre(verts)
			var level: float = b.get_meta("level")
			if Vector2(tp.x - c.x, tp.z - c.y).length() < float(b.get_meta("radius")) \
					and tp.y < level:
				in_water += 1
	_ck("没有行道树站在水里", in_water == 0, "%d 棵" % in_water)

	# ---- 6 水得真的装在碗里，而不是碗底的一小滩 ----
	#
	# 这条守的是**碗选址**而不是碗的形状。自由板（碗心的自然高程 − 水位）
	# 决定水面能盖住碗的多少：自由板 3m 的碗，60m 宽而只露着半径 12m 的水，
	# 玩家看到的是一圈干土围着的一小滩蓝——而上面那几条**全部照过**。
	# 碗心落在低地时自由板只有 0.4m，水面能占到碗的两成到七成。
	# 门槛取 55%：实测 61%/70%/71%。第一版门槛是 45%，而把碗心退回"沿 away 推固定
	# 距离"之后量到 42%/46%/50% —— 45% 只拦得住最差的那一处，三处里两处照绿，
	# 等于门槛定在了噪声里。55% 让三个数一起离开阈值。
	var basins_fill = tb.water_basins()
	for bi in basins_fill.size():
		var bb: Dictionary = basins_fill[bi]
		var bc: Vector2 = bb["center"]
		var br: float = float(bb["radius"])
		var balong := Vector2(float(bb["ax"]), float(bb["az"]))
		var baway := Vector2(balong.y, -balong.x)
		var bsq: float = float(bb["squash"])
		# 只量**这只碗自己的**水面。拿全部水体一起扫的话，别处的顶点只要
		# 偶然落在这条射线上就会被算进来，而量到的"碗盖住多少"会平白多出一截。
		var mine: Array = []
		for body in bodies:
			if int(body.get_meta("station")) == int(bb["station"]):
				mine.append(body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
		var bfill := 0.0
		for k in range(32):
			var a := TAU * float(k) / 32.0
			var dir := Vector2(cos(a), sin(a))
			var u: float = (dir.x * balong.x + dir.y * balong.y) / bsq
			var v: float = dir.x * baway.x + dir.y * baway.y
			var span: float = br / maxf(sqrt(u * u + v * v), 1e-6)
			# 只看**建出来的水面**到底伸到哪儿（不重走一遍 Water 的求交，
			# 那样量的是 Water 自己的算法，不是它的结果）
			var reach := 0.0
			for bv in mine:
				for p in bv:
					var rel := Vector2(p.x - bc.x, p.z - bc.y)
					if absf(rel.dot(Vector2(-dir.y, dir.x))) > 2.0:
						continue
					if rel.dot(dir) > 0.0:
						reach = maxf(reach, rel.length())
			bfill += minf(reach, span) / span
		var pc := int(100.0 * bfill / 32.0)
		var bnm: String = rd.stations[int(bb["station"])]["name"]
		_ck("%s：水面盖住了碗的一半以上（是湖不是土坑）" % bnm, pc >= 55, "只盖住 %d%%" % pc)
		# 顺带钉住自由板：它是上面那个百分比的成因，量出来是为了报的时候
		# 能一眼看出是"碗挖浅了"还是"碗挖歪了"。
		var freeboard: float = float(bb["depth"]) - float(bb["water_depth"])
		print("       （%s 自由板 %.2fm，水面盖住碗的 %d%%）" % [bnm, freeboard, pc])

	# ---- 7 碗真的挖了，且没有铺满半个世界 ----
	# 碗从地形那边读（`water_basins()` 返回的就是 `water_data` 那一批对象），
	# 而不是在这里重新算一遍——两处各算一次的话，两边可以各自看着都对，
	# 而水面对着的是一只压根没挖出来的碗。
	var basins = tb.water_basins()
	_ck("碗定下来了（water_data.plan() 在建地形前跑过）",
			basins.size() == 3, "%d 只" % basins.size())
	var dug := 0
	for b in basins:
		var c: Vector2 = b["center"]
		if _water_data_script.depth_at(c.x, c.y) > float(b["depth"]) * 0.9:
			dug += 1
	_ck("三只碗都真的挖下去了", dug == basins.size(), "%d / %d" % [dug, basins.size()])
	# 这一条守的是"把 FILL 调过 1"或者把碗半径调成几百米那类改坏：
	# 那时水会淹掉整片低地，而路上、驿站、别的回归全绿。
	var wet := 0
	var total := 0
	for xi in range(-40, 41):
		for zi in range(-40, 41):
			var x := float(xi) * 10.0
			var z := float(zi) * 10.0
			total += 1
			if _water_data_script.depth_at(x, z) > 0.01:
				wet += 1
	_ck("被挖的地面占全场不到 6%（水不是一片海）",
			float(wet) / float(total) < 0.06,
			"%.2f%%" % (100.0 * float(wet) / float(total)))

	_finish()


func _centre(verts: PackedVector3Array) -> Vector2:
	var c := Vector2.ZERO
	for v in verts:
		c += Vector2(v.x, v.z)
	return c / float(verts.size())


func _dist_to_road(lines: Array, p: Vector2) -> float:
	var best := INF
	for line in lines:
		for q in line:
			best = minf(best, Vector2(q.x - p.x, q.z - p.y).length())
	return best


func _finish() -> void:
	print("=== 结果：OK %d / FAIL %d ===" % [_ck_count, _fails])
	print("[verify_water] " + ("PASS" if _fails == 0 else "FAIL") + "  (失败 %d)" % _fails)
	quit(0 if _fails == 0 else 1)
