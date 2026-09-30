extends SceneTree
## lookdev_trees.gd — 行道树定妆照
##
## **不能加 --headless，也不能加 --quit-after**——和 lookdev_grass.gd 同一个理由：
## --headless 用 dummy renderer，visibility_range 的抖动淡出只有真渲染器才会实际
## 生效，无头跑完照样"PASS"，等于没看。--quit-after 按墙钟折算，这台机器窗口
## 模式能跑 280+ FPS，给小了会在中途把进程掐掉、只剩一串 warning 看着像通过。
## 所以脚本自己 quit()，计时一律用 Time.get_ticks_msec()。
##
## 相机**站在驻留环的圆心**往外看：visibility_range 量的是"到相机的距离"，把相机
## 搬到 150m 外去拍远景，等于站进了淡出带里，量到的是"树贴脸"而不是玩家看见的
## "远处一排树"。玩家永远在环心，相机就得在环心。
##
## 每张都直接对准**一棵真实的树**，距离用它的真实值命名（树只长在路肩 11m 那
## 一圈，从立足点看出去的距离是离散的，凑整的"10m/30m"那里可能压根没树）：
##   ~14/55/100/135m —— 按"相机到树"距离挑，宽视角 65°：近景一路到加载半径
##                      150m 之内，树应始终是完整实体、没有噪点
##   fade_*.png      —— 按"相机到**格心**"距离挑（引擎量的是这个，不是到树），
##                      窄视角 16°，淡出系数 0.5 和 0.15 各一张。专看
##                      visibility_range 的抖动淡出没在生效、有没有硬边。
##                      脚本还会量画面中心区的像素亮度当硬指标：曾经跑出来
##                      "图里什么都没有"，人眼和 print 都对不上，最后靠
##                      像素值定位到是格心距离越界、那棵早就淡完了。
##   row.png         —— 顺着整条树排看过去：25m 间距、左右各一排、右侧错开半格
##   overhead100m.png —— 编辑模式的相机离地 100m。set_fade_for_camera 必须把
##                       可见边界外扩，否则整圈树全判在 range 之外直接消失。
##
## 用法： godot --path . --script tools/lookdev_trees.gd

const BANDS := [14.0, 55.0, 100.0, 135.0]
## 淡出带特写要拍的淡出系数（按格心距离算）。0.5 是带中间，0.15 是快淡完了。
const FADE_AT := [0.5, 0.15]
## 和 TreeScatter.CELL 一致，用来自己算格心。
const CELL := 32.0
const SAVE_DIR := "user://lookdev_trees"
## 相机高度。自行车视角差不多这个高度，别拍成俯视。
const EYE_H := 1.6
const OVERHEAD_H := 100.0
## 立足点取在环路的这个弧长处附近，往它的反方向退 STAND_BACK。
const STAND_ARC := 150.0
## 沿路退这么远，最近那棵正好在十几米外（横向还有 11m）。
const STAND_BACK := 8.0
## 常规视角。
const WIDE_FOV := 65.0
## 淡出带特写的窄视角：160m 的树在 65° 下只有 28px 高，看不出抖动淡出没生效。
const CLOSE_FOV := 16.0
## 和 TreeScatter.FADE_BAND 一致，只用来打印这张照的淡出系数。
const FADE_BAND := 40.0

var _failures := 0
var _pts := PackedVector3Array()
var _cum := PackedFloat32Array()


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_failures += 1
		print("[FAIL] ", label)


## 和 TreeScatter 一样的闭合折线 + 累计弧长表。这里只用来挑一个立足点、
## 算一个朝向，不参与断言，所以直接抄一份简单的。
func _build_loop(line: Array) -> void:
	_pts = PackedVector3Array()
	for q in line:
		_pts.append(q if q is Vector3 else Vector3(q.x, 0.0, q.y))
	_pts.append(_pts[0])
	_cum.resize(_pts.size())
	_cum[0] = 0.0
	for i in range(1, _pts.size()):
		_cum[i] = _cum[i - 1] + _pts[i - 1].distance_to(_pts[i])


func _arc_total() -> float:
	return _cum[_cum.size() - 1]


func _at(arc: float) -> Vector3:
	var total := _arc_total()
	var a := fposmod(arc, total)
	var lo := 0
	var hi := _cum.size() - 1
	while lo < hi - 1:
		var mid := (lo + hi) / 2
		if _cum[mid] <= a:
			lo = mid
		else:
			hi = mid
	var seg: float = _cum[lo + 1] - _cum[lo]
	var t := 0.0 if seg < 1e-6 else (a - _cum[lo]) / seg
	return _pts[lo].lerp(_pts[lo + 1], t)


func _tan(arc: float) -> Vector3:
	var t := _at(arc + 2.0) - _at(arc - 2.0)
	t.y = 0.0
	if t.length_squared() < 1e-9:
		return Vector3(1.0, 0.0, 0.0)
	return t.normalized()


## 在 entries 里挑 key 那个字段最接近 goal 的一条。
func _nearest_by(entries: Array, key: String, goal: float) -> Dictionary:
	var best: Dictionary = {}
	var bd := 1e9
	for e in entries:
		var d := absf(float(e[key]) - goal)
		if d < bd:
			bd = d
			best = e
	return best


func _run() -> void:
	print("=== 行道树定妆照（带窗口跑）===")
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var TB = load("res://scripts/TerrainBuilder.gd")
	var RB = load("res://scripts/RoadBuilder.gd")
	var terrain = TB.new()
	terrain.name = "TerrainBuilder"
	root.add_child(terrain)
	await process_frame
	var rb = RB.new()
	rb.name = "RoadBuilder"
	root.add_child(rb)
	rb.set_terrain_builder(terrain)
	await process_frame
	var centerlines: Array = rb.get_all_centerlines()
	_build_loop(centerlines[0])

	# 太阳：和 World3D 的 DirectionalLight3D 同一组角度，树影才和游戏里一致
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -126.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300.0
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 40.0, 0.0)
	fill.light_energy = 0.25
	fill.light_color = Color(0.72, 0.82, 1.0)
	root.add_child(fill)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.27, 0.53, 0.95, 1.0)
	sky_mat.sky_horizon_color = Color(0.72, 0.85, 0.97, 1.0)
	sky_mat.ground_horizon_color = Color(0.62, 0.70, 0.60, 1.0)
	sky_mat.ground_bottom_color = Color(0.42, 0.48, 0.40, 1.0)
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	e.fog_enabled = true
	e.fog_light_color = Color(0.88, 0.92, 0.98, 1.0)
	e.fog_density = 0.0003
	env.environment = e
	root.add_child(env)

	var scatter = load("res://scripts/TreeScatter.gd").new()
	scatter.name = "TreeScatter"
	root.add_child(scatter)
	scatter.setup(terrain, centerlines, [])
	await process_frame

	# ---- 立足点：站到一段树排的正后方，正对着那条树排 ----
	# 光把相机摆在驻留环的圆心还不够——"近景"那张得真有一棵十几米外的树，
	# 否则相机只对着空路。树字典里带 arc，取最靠近 STAND_ARC 的那棵，
	# 沿它的反方向退 STAND_BACK，相机就正好对着它。
	var trees: Array = scatter.trees()
	var ka := 0
	var da_best := 1e9
	for i in range(trees.size()):
		var ti: Dictionary = trees[i]
		var darc := absf(float(ti["arc"]) - STAND_ARC)
		if darc < da_best:
			da_best = darc
			ka = i
	var kt: Dictionary = trees[ka]
	var stand_arc := float(kt["arc"]) - STAND_BACK
	var base := _at(stand_arc)
	var tg := _tan(stand_arc)
	base.y = terrain.get_height_at(base.x, base.z)
	var eye := Vector3(base.x, base.y + EYE_H, base.z)
	scatter.set_focus(base)
	scatter.set_fade_for_camera(eye)
	scatter.tick(0.2)
	await process_frame

	var radius: float = scatter.radius()
	var rend: float = scatter.range_end()
	print("    环路 %.1fm，相机在弧长 %.1fm、正对弧长 %.1fm 那棵"
		% [_arc_total(), stand_arc, stand_arc + STAND_BACK])
	print("    半径 %.0fm / 可见边界 %.1fm / 驻留半径 %.1fm / %d 格 / %d 棵"
		% [radius, rend, scatter.reside_reach(), scatter.cell_count(),
			scatter.tree_count()])
	_check(scatter.tree_count() > 40, "真的种出了树（%d 棵）" % scatter.tree_count())
	_check(scatter.live_tree_count() > 0,
		"驻留环里确实有树（%d 棵在场）" % scatter.live_tree_count())

	# ---- 挑真实存在的目标距离 ----
	# 树只长在路面两侧 11m 那一圈，从立足点看出去的距离是被离散化的。照表拍
	# "10m/30m" 这种凑整的数，那里很可能压根没树——所以反过来：把全部树的距离
	# 排个序，按目标距离去捞最近的那棵，文件名用它的**真实**距离。
	#
	# 每条记**两把尺子**：dist 是相机到树，cd 是相机到**格心**。
	# visibility_range 量的是 cd 不是 dist——MultiMesh 节点坐在格心上，整格共用
	# 一个淡出系数，两把尺子差最多半格对角线 22.6m。按 dist 去挑"淡出带中间"
	# 的树，很可能捞到一棵早就淡完了的（第一次跑就踩了这个坑：160m 那棵的
	# 格心已经越界，图里什么都没有）。
	var entries: Array = []
	for i in range(trees.size()):
		var tr: Dictionary = trees[i]
		var pp: Vector3 = tr["pos"]
		var cc := Vector2((floor(pp.x / CELL) + 0.5) * CELL,
			(floor(pp.z / CELL) + 0.5) * CELL)
		entries.append({"pos": pp, "dist": eye.distance_to(pp),
			"cd": Vector2(eye.x, eye.z).distance_to(cc),
			"scale": float(tr["scale"]),
			"top": pp.y + 0.45 * float(tr["scale"])})
	entries.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]))
	var picked: Array = []
	for D in BANDS:
		picked.append(_nearest_by(entries, "dist", float(D)))
	picked.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]))

	print("    引擎淡出带按格心距离算 = [%.1f, %.1f]m" % [rend - FADE_BAND, rend])
	for p in picked:
		print("      树距 %.1fm / 格心距 %.1fm"
			% [float(p["dist"]), float(p["cd"])])
	_check(picked.size() == BANDS.size(),
		"挑出了 %d 个真实存在的目标距离" % picked.size())
	var cam := Camera3D.new()
	cam.fov = WIDE_FOV
	cam.far = 1000.0
	root.add_child(cam)
	cam.current = true

	# 先量一帧的墙钟，别用帧数折算
	var t0 := Time.get_ticks_msec()
	for _i in range(30):
		await process_frame
	print("    静态 %d 帧共 %dms，单帧 %.2fms"
		% [30, Time.get_ticks_msec() - t0,
			float(Time.get_ticks_msec() - t0) / 30.0])

	for pe in picked:
		var pp: Vector3 = pe["pos"]
		var dd: float = float(pe["dist"])
		cam.global_position = eye
		# 瞄准树冠中部，把整棵树框进画面
		var aim := Vector3(pp.x, float(pe["top"]), pp.z)
		cam.look_at(aim, Vector3.UP)
		var off := rad_to_deg((-cam.global_transform.basis.z)
			.angle_to((aim - cam.global_position).normalized()))
		var hpx := 720.0 * float(pe["scale"]) / (2.0 * dd * tan(cam.fov * PI / 360.0))
		print("    目标 %.1fm（高 %.1fm）→ 视线偏差 %.3f°，应占 %.0fpx 高"
			% [dd, float(pe["scale"]), off, hpx])
		await process_frame
		await process_frame
		var img: Image = root.get_texture().get_image()
		var path := "%s/%04dm.png" % [SAVE_DIR, int(round(dd))]
		img.save_png(path)
		print("    拍了 %s  (%dx%d)  驻留 %d 格 / %d 棵（上界）"
			% [path, img.get_width(), img.get_height(),
				scatter.live_cell_count(), scatter.live_tree_count()])

	# ---- 淡出带特写 ----
	# 160m 的树在 65° FOV 下只占 20px，看不出抖动淡出没在生效。收窄 FOV 拉近。
	# 目标按**格心**距离挑（引擎量的是这个）；按树距挑会捞到已经淡完的树。
	cam.fov = CLOSE_FOV
	var mid_lum := 1.0
	for f in FADE_AT:
		var ft := _nearest_by(entries, "cd", rend - FADE_BAND * float(f))
		var fd: float = float(ft["dist"])
		var fcd: float = float(ft["cd"])
		var fpp: Vector3 = ft["pos"]
		var faim := Vector3(fpp.x, float(ft["top"]), fpp.z)
		cam.global_position = eye
		cam.look_at(faim, Vector3.UP)
		# 自检：视线必须正对目标（偏差 0），树在画面里得真的够大
		var foff := rad_to_deg((-cam.global_transform.basis.z)
			.angle_to((faim - cam.global_position).normalized()))
		var fhpx := 720.0 * float(ft["scale"]) / (2.0 * fd * tan(cam.fov * PI / 360.0))
		var ffact := clampf((rend - fcd) / FADE_BAND, 0.0, 1.0)
		print("    [特写] 树距 %.1fm / 格心距 %.1fm → 引擎淡出系数 %.2f，"
			% [fd, fcd, ffact])
		print("          视线偏差 %.3f°，树高约 %.0fpx" % [foff, fhpx])
		await process_frame
		await process_frame
		var fimg: Image = root.get_texture().get_image()
		var fp4 := "%s/fade_%04dm.png" % [SAVE_DIR, int(round(fd))]
		fimg.save_png(fp4)
		# 硬指标：中心 201x181 里最暗的像素亮度。半透明的深绿树必须比草地
		# （约 0.45）暗；同时不能暗到接近实心树——否则说明淡出根本没生效。
		# 用像素值判，不靠人眼：前面那张 160m 的图已经证明人眼会看错。
		var flum := 1.0
		var fcy := fimg.get_height() / 2
		var fcx := fimg.get_width() / 2
		for yy in range(fcy - 90, fcy + 91):
			for xx in range(fcx - 100, fcx + 101):
				var px := fimg.get_pixel(xx, yy)
				flum = minf(flum, 0.299 * px.r + 0.587 * px.g + 0.114 * px.b)
		print("    拍了 %s  中心区最暗亮度 %.3f（草地约 0.45、天空约 0.91）" % [fp4, flum])
		if absf(float(f) - 0.5) < 0.01:
			mid_lum = flum
	cam.fov = WIDE_FOV
	_check(mid_lum < 0.42,
		"淡出系数 0.5 的树在画面中心留下了暗于草地的像素（最暗 %.3f）" % mid_lum)
	_check(mid_lum > 0.22,
		"淡出系数 0.5 的树是半透明而不是实心（最暗 %.3f）" % mid_lum)

	# 一张顺着整条树排看过去的：判断"这是一排树"这个整体读法成不成立
	cam.global_position = eye
	var row_aim := base + tg * 120.0
	row_aim.y = terrain.get_height_at(row_aim.x, row_aim.z) + 3.0
	cam.look_at(row_aim, Vector3.UP)
	await process_frame
	await process_frame
	var img3: Image = root.get_texture().get_image()
	img3.save_png("%s/row.png" % SAVE_DIR)
	print("    拍了 %s/row.png  (%dx%d)"
		% [SAVE_DIR, img3.get_width(), img3.get_height()])

	# ---- 高空俯视：编辑模式的相机离地 100m ----
	# visibility_range 量的是到相机的距离，100m 起步就顶到淡出带里去了。
	# set_fade_for_camera 补这一截，否则整圈树全判在 range 之外、直接消失。
	var high := Vector3(base.x, base.y + OVERHEAD_H, base.z)
	scatter.set_fade_for_camera(high)
	# set_fade_for_camera 会把 _focus_cell 复位逼一次 _refresh，这里补上 tick
	scatter.set_focus(base)
	scatter.tick(0.2)
	await process_frame
	var rend_hi: float = scatter.range_end()
	print("    相机升空 %.0fm：可见边界 %.1fm -> %.1fm，%d 棵在场"
		% [OVERHEAD_H, rend, rend_hi, scatter.live_tree_count()])
	# rend 是在相机高 EYE_H 时量的，所以增量应该正好是 OVERHEAD_H - EYE_H
	_check(rend_hi - rend >= OVERHEAD_H - EYE_H - 2.0,
		"相机升空后可见边界跟着外扩了 %.1fm（%.1f -> %.1f）"
		% [rend_hi - rend, rend, rend_hi])
	_check(scatter.live_tree_count() > 0,
		"相机升空 %.0fm 后树没有整圈消失（%d 棵在场）" % [OVERHEAD_H, scatter.live_tree_count()])
	cam.global_position = high
	cam.look_at(base + tg * 45.0, Vector3.UP)
	await process_frame
	await process_frame
	var img2: Image = root.get_texture().get_image()
	img2.save_png("%s/overhead%02dm.png" % [SAVE_DIR, int(OVERHEAD_H)])
	print("    拍了 %s/overhead%02dm.png  (%dx%d)"
		% [SAVE_DIR, int(OVERHEAD_H), img2.get_width(), img2.get_height()])

	# ---- 骑开 200m：驻留集合要跟着换 ----
	scatter.set_fade_for_camera(eye)
	scatter.set_focus(base)
	scatter.tick(0.2)
	await process_frame
	var before: int = scatter.live_tree_count()
	# 沿路再走 200m——注意不是沿切线，切线会在几米后就甩出这条 8 字环路
	var base2 := _at(STAND_ARC + 200.0)
	base2.y = terrain.get_height_at(base2.x, base2.z)
	scatter.set_focus(base2)
	scatter.set_fade_for_camera(Vector3(base2.x, base2.y + EYE_H, base2.z))
	scatter.tick(0.2)
	await process_frame
	var after: int = scatter.live_tree_count()
	_check(before > 0 and after > 0,
		"焦点移动后驻留集合跟着重建（旧 %d / 新 %d 棵）" % [before, after])
	_check(after <= scatter.tree_count(),
		"移动 200m 后在场棵数仍不超过总数（%d -> %d / 共 %d）"
		% [before, after, scatter.tree_count()])

	print("\n截图目录: %s" % ProjectSettings.globalize_path(SAVE_DIR))
	print("[lookdev_trees] %s  (失败 %d)" % [
		"PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
