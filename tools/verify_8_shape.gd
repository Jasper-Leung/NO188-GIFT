extends SceneTree
## verify_8_shape.gd — 路线真的是那条 8 字，而不是"我记得是"
##
## ---- 第一版这条回归什么都没验 ----
## 它把 `road_data.gd` 的 `LEMNISCATE_LOCAL` **整张表手抄了一份**，
## 然后拿自己抄的这份去插值出"当前"曲线，再拿同一张表的原始 48 点当"参考"，
## 比两者的质心和包围盒。**产品一次都没被加载过。**
## 于是 `road_data.gd` 被整个改写成一条直线，这个回归照样全绿——
## 而它的名字、它在 CLAUDE.md 里那一行"改 stations 之前先跑这个"都在说相反的话。
## 这正是 `CLAUDE.md` 里那条"手抄一份表蒙是不行的"的 purest 形态：抄的那份
## 和被测的那份没有任何关系，于是它测的是**自己和自己自洽**。
##
## 现在它读**真实的 `road_data.gd`**（运行时 `load()`，不用类型注解——
## `--script` 模式下注解会拉起编译期依赖，见 CLAUDE.md），断的是产品自己的几何：
## 点数、闭环、两个环心关于中点对称、包围盒近似方形、总弧长 1228.8m。
## SVG 也改成画产品的那份曲线，目视核对时看到的才是游戏里真正骑的那条。
##
## 输出仍写一份 `user://current_road.svg` 供人工目视核对。

## 环路总长。全工程到处都写着 1228.8m（README / CLAUDE.md / 明信片背面），
## 改采样密度或 LEMNISCATE_SCALE 时这条会红——那正是它该做的事。
const EXPECT_ARCLEN := 1228.8
const ARCLEN_TOL := 2.0
## 包围盒的 x/y 跨度之比。8 字是旋转 60° 之后摆进世界坐标的，
## 实测 658.33 / 722.00 = 0.912，所以判据是"接近"而不是"相等"。
const BBOX_RATIO_LO := 0.80
const BBOX_RATIO_HI := 1.00
## 两个环心分居包围盒中点两侧，且左右对称。允许 2% 的跨度作为容差。
const LOOP_SYMMETRY_TOL := 0.02

var _fails := 0


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_fails += 1
		print("[FAIL] ", label + ("（" + detail + "）" if detail != "" else ""))


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# 运行时 load：不加类型注解，否则 --script 模式会在编译期拉起 road_data.gd
	# 的依赖，而它引用了 `Localization` autoload。
	var rd = load("res://scripts/road_data.gd").new()
	var pts: Array[Vector3] = rd.points

	print("CURRENT_POINTS=%d" % pts.size())
	_ck("中心线点数在预期量级（插值没被掐断）", pts.size() > 400,
			"实测 %d 点" % pts.size())

	# ---- 闭环：首尾必须接得上 ----
	# 自闭合是"跑三圈"和"8 字环"成立的前提。断开的话环变成一条断头路，
	# 而顶栏的驿数、小地图、回访导航全部照旧画得很好。
	var gap := Vector2(pts[0].x - pts[pts.size() - 1].x, pts[0].z - pts[pts.size() - 1].z).length()
	var span := _bbox_span(pts)
	_ck("环路自闭合（首尾接得上）", gap < span.x * 0.01,
			"首尾差 %.2fm，跨度 %.1fm" % [gap, span.x])

	# ---- 8 字：两个环 + 对称 ----
	var mn_x := INF; var mn_z := INF
	var mx_x := -INF; var mx_z := -INF
	for p in pts:
		mn_x = minf(mn_x, p.x); mx_x = maxf(mx_x, p.x)
		mn_z = minf(mn_z, p.z); mx_z = maxf(mx_z, p.z)
	var mid_x := (mn_x + mx_x) * 0.5
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for p in pts:
		if p.x < mid_x:
			left.append(Vector2(p.x, p.z))
		else:
			right.append(Vector2(p.x, p.z))
	# "左右两半各有点数"是条**量不到东西**的判据：任何一条穿过中线的曲线都满足，
	# 截断成一段之后它照样绿（实测：把中心线砍到 120 点时它仍然 OK）。
	# 8 字真正说的是两件事，都得量：
	#   · 中线被穿过 4 次——图案旋转了 60°，世界 X 轴切的是**每个环的进出各一次**，
	#     两个环就是 4 次（一个环才是 2 次）。
	#   · 两半**相接**——这是 8 字与"两个分开的圈"的唯一区别，也是最要紧的一条。
	var crossings := 0
	var prev_sign := 0
	for p in pts:
		var s := 0 if absf(p.x - mid_x) < 1e-6 else (1 if p.x > mid_x else -1)
		if s != 0:
			if prev_sign != 0 and s != prev_sign:
				crossings += 1
			prev_sign = s
	_ck("中线被中心线穿过 4 次（两个环各进出一次）", crossings == 4,
			"实测 %d 次；左右点数 %d / %d" % [crossings, left.size(), right.size()])

	var touch := _closest_gap(left, right)
	_ck("两半在中心相接（是 8 字，不是两个分开的圈）", touch <= 2.0,
			"两半最近相距 %.2fm" % touch)

	var lc := _centroid(left)
	var rc := _centroid(right)
	var x_span := mx_x - mn_x
	# 断的是**镜像对称**：两个环心分居包围盒中点两侧且等距。
	# 写成"环心落在 ±半跨度处"是断不出东西的——8 字的两个环质心远在包围盒
	# 内部（实测 ±74.5 对半跨度 164.6），那条判据量的是质心离边多远，
	# 而质心在哪本来就不该被要求。第一版就是这么写错的。
	var mirror := absf(lc.x + rc.x - 2.0 * mid_x) / x_span
	_ck("两环关于包围盒中点镜像对称", mirror <= LOOP_SYMMETRY_TOL,
			"环心 x = %.1f / %.1f，中点 %.1f，跨度 %.1f，偏 %.2f%%"
			% [lc.x, rc.x, mid_x, x_span, mirror * 100.0])

	# ---- 包围盒近似方形 ----
	# 8 字图案两轴同量级。塌成一条长带（某次采样只剩一段）时这条会红。
	var ratio := x_span / maxf(mx_z - mn_z, 1e-6)
	_ck("包围盒两轴同量级（不是塌成一条带）",
			ratio >= BBOX_RATIO_LO and ratio <= BBOX_RATIO_HI,
			"x/y = %.3f（x %.1fm / y %.1fm）" % [ratio, x_span, mx_z - mn_z])

	# ---- 总弧长 ----
	var al: float = rd.total_arclength()
	_ck("环路总长 = %.1fm" % EXPECT_ARCLEN, absf(al - EXPECT_ARCLEN) <= ARCLEN_TOL,
			"实测 %.1fm（改了采样密度或 LEMNISCATE_SCALE 就会漂）" % al)

	print("CURRENT_X_RANGE=%.1f..%.1f Y_RANGE=%.1f..%.1f" % [mn_x, mx_x, mn_z, mx_z])

	_write_svg("user://current_road.svg", pts, rd)
	print("WROTE user://current_road.svg")

	print("\n[verify_8_shape] " + ("PASS" if _fails == 0 else "FAIL") + "  (失败 %d)" % _fails)
	quit(0 if _fails == 0 else 1)


func _bbox_span(pts: Array[Vector3]) -> Vector2:
	var mn_x := INF; var mn_z := INF
	var mx_x := -INF; var mx_z := -INF
	for p in pts:
		mn_x = minf(mn_x, p.x); mx_x = maxf(mx_x, p.x)
		mn_z = minf(mn_z, p.z); mx_z = maxf(mx_z, p.z)
	return Vector2(mx_x - mn_x, mx_z - mn_z)


func _centroid(pts: PackedVector2Array) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var s := Vector2.ZERO
	for p in pts:
		s += p
	return s / float(pts.size())


## 两组点之间的最近距离。8 字的两个环在中心掐在一起，这个值接近 0；
## 换成两个分开的圈，它就是两环直径加上中间的空隙。
func _closest_gap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var best := INF
	for p in a:
		for q in b:
			best = minf(best, p.distance_squared_to(q))
	return sqrt(best)


func _write_svg(path: String, pts: Array[Vector3], rd) -> void:
	# 画的是**产品**的中心线（世界坐标投回画布），不是本地那张表。
	var s: Array[String] = []
	s.append('<svg xmlns="http://www.w3.org/2000/svg" viewBox="-46 -34 892 1800" width="400" height="800">')
	s.append('<rect x="-46" y="-34" width="892" height="1800" fill="#fafafa"/>')
	s.append('<g stroke="#dc2626" stroke-width="3" fill="none" opacity="0.85">')
	s.append('<polyline points="')
	for i in range(pts.size()):
		var p := pts[i]
		# 世界 (x, z) → 画布。LEMNISCATE_CX/CY 是 road_data 的画布原点。
		var cx := 400.0 + p.x * 350.0
		var cy := 800.0 + p.z * 350.0
		s.append("%.1f,%.1f%s" % [cx, cy, " " if i < pts.size() - 1 else ""])
	s.append('"/>')
	s.append('</g>')
	for i in range(rd.stations.size()):
		var sp: Vector3 = rd.get_station_world_pos(i)
		var cx := 400.0 + sp.x * 350.0
		var cy := 800.0 + sp.z * 350.0
		s.append('<circle cx="%.1f" cy="%.1f" r="6" fill="#3b82f6"/>')
		s.append('<text x="%.1f" y="%.1f" font-size="12" fill="#C8443A">%d</text>' % [cx + 10.0, cy - 6.0, i + 1])
	s.append('</svg>')
	var f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("".join(s))
	f.close()