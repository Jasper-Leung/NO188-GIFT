extends SceneTree
## 路肩软边界的定妆照与**像素判据**。
##
## `verify_road_verge.gd` 量的是剖面（那个纯函数）加两条读源码的判据。
## 它量不到「玩家看不看得见那道线」——**无头回归量不了渲染结果**，
## 这不是它不努力，是 `--headless` 用的是 dummy renderer，连着色器都不编译。
## 所以"看不看得见"这一件只能落在这里，量法只有一条：**正交俯拍逐像素**。
##
## 摆相机的三个坑，前三版各栽一个（详见每处的注释）：
##   ① `make_current()`——World3D 自己那台玩家相机是 `current`，
##      而 `root.get_texture()` 渲的是**当前那台**。不摆 current 就等于
##      摆了机位却从游戏自己的追尾视角上取像素，四张图量到的都是同一张。
##   ② `get_centerline()` 而不是 `road_data.points`——尺子要摆在
##      画出来那条带子的出处上。
##   ③ **正交 + `size`**，不是「透视 + 手算 fov」——`keep_aspect` 默认
##      `KEEP_HEIGHT`，fov 说的是竖直那一档，手算一次就错 16/9 倍。
##      正交把那一整类错误一次消掉：`size` 就是画面竖直方向的总米数。
##
## 用法： godot --path . --script tools/lookdev_verge.gd
##        **不能加 --headless、不能加 --quit-after**（理由同上）
## 出图： user://lookdev_verge/

## 正交相机画面竖直方向的总米数。比例尺 = 图高 / 这个数。
const TOP_SPAN_M := 60.0
## 逐行取样时在一行上左右各摊多少像素——草卡片和地形米斑都是高方差的，
## 单个像素读数没有意义。
const ROW_HALF := 4
## 扫描半径。软边界在 12m，外沿在 14.5m，扫到 26m 足够把地形接缝也量进来。
const SCAN_M := 26.0
## 扫描步长。
const STEP_M := 0.5

var _fails: Array = []
var _oks := 0


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_oks += 1
		print("[OK]   ", label, ("  " + detail) if detail != "" else "")
	else:
		var msg := label + ("（" + detail + "）" if detail != "" else "")
		_fails.append(msg)
		print("[FAIL] ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== 路肩软边界定妆照（正交俯拍逐像素）===")
	var dir := "user://lookdev_verge/"
	DirAccess.make_dir_recursive_absolute(dir)

	var world: Node3D = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	await process_frame

	# World3D 的常量走求值后的那份，别在源码里抠字面量。
	var soft_bound: float = load("res://scripts/World3D.gd") \
			.get_script_constant_map()["SOFT_BOUND"]
	var total_half: float = load("res://scripts/RoadBuilder.gd") \
			.get_script_constant_map()["TOTAL_HALF_WIDTH"]
	print("  （SOFT_BOUND=%.2f  TOTAL_HALF_WIDTH=%.2f）" % [soft_bound, total_half])

	# 取样点躲开 8 字自交点：那个位置路面被 `plaza_mode` 扩成一大块圆盘，
	# 扫过去的整行都是沥青，"带子在不在"根本无从谈起。
	var cl: Array = world._road_builder.get_centerline()
	var bi: int = cl.size() / 4
	var base: Vector3 = cl[bi]
	var nxt: Vector3 = cl[bi + 1]
	var tangent: Vector2 = Vector2(nxt.x - base.x, nxt.z - base.z).normalized()
	var normal := Vector2(-tangent.y, tangent.x)
	print("  base = %s   centerline = %d 点" % [str(base), cl.size()])

	var cam := Camera3D.new()
	cam.far = 400.0
	root.add_child(cam)
	# 坑 ①：必须 make_current()。World3D 自己那台玩家相机是 current，
	# 而 `root.get_texture()` 渲的是**当前那台**——前两版各自摆了机位、
	# 改了 fov、改成正交，然后从**游戏自己的追尾视角**上取像素。
	# 于是量到的那个"扫描线"从来就不是我摆的那条：米数标签、对比度、
	# "带子看不见"这个结论，全都建立在一张不是我拍的图上。
	# 相机摆好了不等于在拍——和「画笔真的调了吗」是同一族：接线没通，
	# 两侧各自都绿。
	cam.make_current()

	# --script 模式下主场景仍会被载进来，标题页那一整块 UI 正好糊在
	# 正中间。量的是地上那条带子，所以把所有 Control / CanvasLayer 收掉。
	_hide_ui(world)
	for c in root.get_children():
		if c is CanvasLayer:
			c.visible = false
		_hide_ui(c)

	var gy: float = world._terrain_builder.get_height_at(base.x, base.z)
	var bp := Vector2(base.x, base.z)

	# ------------------------------------------------------------ 视角三张
	# `ride` 是**真正要判的那一张**：评审 P1-2 说的是「骑进去就找不着路」，
	# 所以判据必须是"车在路上时看不看得见那道线"。另两张分别是站在路心
	# 平拍和斜看——它们偏了：站得高、看得久、还特意朝外看，
	# 那是**给修法照相**的图，不是**给玩家照相**的图。
	for shot in [
		{"name": "ride", "pos": bp - tangent * 6.0, "look": bp + tangent * 22.0},
		{"name": "profile", "pos": bp, "look": bp + normal * 20.0},
		{"name": "oblique", "pos": bp - tangent * 12.0 + normal * 1.0,
			"look": bp + normal * 18.0 + tangent * 4.0},
	]:
		var p: Vector2 = shot["pos"]
		var l: Vector2 = shot["look"]
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 70.0
		cam.position = Vector3(p.x, world._terrain_builder.get_height_at(p.x, p.y) + 1.6, p.y)
		cam.look_at(Vector3(l.x,
				world._terrain_builder.get_height_at(l.x, l.y) + 0.6, l.y),
				Vector3.UP)
		for _i in 4:
			await process_frame
		root.get_texture().get_image().save_png(dir + String(shot["name"]) + ".png")
		print("  wrote ", shot["name"])

	# ---------------------------------------------------------- 俯拍逐像素
	# 坑 ③：**正交相机**，不是「透视 + 手算 fov」。透视下"屏幕距离 = 真实
	# 距离"要过一次三角换算，而换算依赖 `keep_aspect`（引擎默认
	# KEEP_HEIGHT，fov 说的是**竖直**那一档）——第一版把竖直当成水平，
	# 米数整整大了 16/9 倍；第二版改正了换算，却因为手搭的 basis 不正交
	# （y 轴给了水平的切线、z 轴给了竖直），相机压根没朝下看，量到的还是
	# 一张骑行视角的图。正交投影把这一整类错误一次消掉。
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = TOP_SPAN_M
	cam.position = Vector3(base.x, gy + 60.0, base.z)
	cam.look_at(Vector3(base.x, gy, base.z), Vector3(tangent.x, 0.0, tangent.y))
	for _i in 4:
		await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png(dir + "topdown.png")
	print("  wrote topdown")

	var prof: Dictionary = _scan(img, base.x, base.z, tangent, normal)
	print("")

	# ============================================================ 像素判据
	# 下面每一条量的都是**渲出来的那一列像素**，不是剖面里那个反照率数。
	# 这一族的前两版判据量的是后者，而中间隔着法线、太阳角、AGX 与雾，
	# 一层都没量到——所以它们在一片**全白的六米宽水泥地**面前全绿。
	# ① 那条（峰值落在 12m）同时也是"这台相机真的在拍"的正证据：
	# 拍错相机的话那是一张追尾视角，压根不存在"离路心线 12m"这个读数。
	print("=== 像素判据 ===")

	var p: Dictionary = prof["right"]
	print("  右侧剖面（渲出来的真实像素）：")
	_print_prof(p)

	# ① 峰值落在软边界上——**这道线就是推你回来的那道力所在的那条线**。
	# 无头那条钉的是剖面里那一列的距离 == SOFT_BOUND；这条钉的是它
	# 真的被画在了那个位置上。两者必须同时成立，缺一条都可能是错的。
	_ck("**渲出来的亮峰就在 %.1fm**（推力从那儿起）" % soft_bound,
			absf(float(p["peak_m"]) - soft_bound) <= 0.75,
			"峰值在 %.2fm" % p["peak_m"])

	# ② 峰值**不是顶到白的**。第一版的 LINE 那一档在这一档量到 0.99——
	# 六米宽整条白，"一道线"根本不存在。
	# 门槛 0.92 是量出来的：把 `vertex_color_is_srgb` 那行删掉（也就是
	# 顶点色被当线性反照率用）重跑一遍，峰值从 0.780 涨到 **0.944**，
	# 门槛写 0.95 时它**只差 0.006 就被放过**。这一条的全部职责就是
	# 拦"顶到白"，所以留的余量要盖得住真实缺陷。
	var pk: float = p["peak_lum"]
	_ck("亮峰没有顶到白（≤ 0.92）", pk <= 0.92, "峰值亮度 %.3f" % pk)
	_ck("亮峰读得出来（≥ 0.55）", pk >= 0.55, "峰值亮度 %.3f" % pk)

	# ③ 它是一条**线**而不是一段路的末梢：两侧各有一个台阶。
	# 台阶不在，图上就是一圈水泥地而不是一条线。
	_ck("内侧有台阶（峰值内 1m 处 ≤ 峰值的 88%%，实测 %d%%）"
			% int(round(100.0 * float(p["in_lum"]) / maxf(pk, 0.0001))),
			float(p["in_lum"]) <= pk * 0.88,
			"inner=%.3f peak=%.3f" % [p["in_lum"], pk])
	_ck("外侧有台阶（峰值外 1m 处 ≤ 峰值的 92%%，实测 %d%%）"
			% int(round(100.0 * float(p["out_lum"]) / maxf(pk, 0.0001))),
			float(p["out_lum"]) <= pk * 0.92,
			"outer=%.3f peak=%.3f" % [p["out_lum"], pk])

	# ④ 外沿不自己造硬边：土径尽头那三个像素的均值和再往外两米的
	# 地形之差要小。差得多等于「路忽然齐刷刷断了」——把「找不着路」
	# 换成了另一种找不着路。
	var seam: float = prof["seam"]
	_ck("外沿接得住地形（差 ≤ 0.10，实测 %.3f）" % seam, seam <= 0.10)

	# ⑤ 两侧同形。这一条是**正对照**：路是左右对称画的，只量一侧的话，
	# 那一侧压根没画带子时"读得出线"照样绿。
	var pl: Dictionary = prof["left"]
	print("  左侧剖面（正对照）：peak %.1fm lum %.3f" % [pl["peak_m"], pl["peak_lum"]])
	_ck("另一侧也画出了同一条线（正对照）",
			absf(float(pl["peak_m"]) - float(p["peak_m"])) <= 1.0
			and float(pl["peak_lum"]) >= pk - 0.10,
			"左 %.1fm/%.3f   右 %.1fm/%.3f"
			% [pl["peak_m"], pl["peak_lum"], p["peak_m"], pk])

	# ⑥ 内沿那一格是土，要比路外的草地暗，才读得出「这是一条被踩出来的
	# 路」而不是「路又宽了一圈」。
	#
	# 这里换过两次尺子，两次都是**我自己的判据在量不存在的东西**：
	# 第一版取 4.0m 当"沥青"，而那条白漆正落在 4.0m 那一档（读到 0.959），
	# 于是判据变成"土径要比白漆亮"，永远红；改成 1.5m 之后这条又变成
	# "土径要比裸沥青暗"——而一条踩出来的土径**本来就应该比深色的沥青亮**，
	# 它是路外那条最亮的一档。这条从来不是设计目标，是我自己编的。
	# 设计目标写在 `RoadVerge.MIX` 的注释里：**比草暗**，所以只留这一条。
	#
	# **可推广的一条**：判据的取样点自己得先问一句"落在什么东西上"，
	# 而写判据时更得先问一句"这一条到底想证明什么"——不是实现看起来
	# 差得不一样就顺手加一条。
	var in_lum: float = p["in_lum"]
	var line_lum: float = p["line_lum"]
	var far: float = p["far_lum"]
	_ck("内沿的土比路外的草地暗（不是路的一部分）",
			in_lum < far,
			"dirt=%.3f grass=%.3f" % [in_lum, far])
	# 正对照：路面上必须真的有一道**比砾石带亮得多**的标线。缺了它，
	# 上面那条在一张压根没有沥青的世界里也照样绿（"暗"是相对的）。
	# 取 0.5~6m 里**最亮**的那一格，不写死它在几米处——第一版把取样点
	# 定在 3.5m，实测那道白线落在 4.0m，读数 0.398 对 0.959。
	_ck("路面上真的有一道比砾石带亮得多的标线（正对照）",
			line_lum > in_lum * 1.5,
			"line=%.3f dirt=%.3f" % [line_lum, in_lum])

	print("\n=== 结果：OK %d / FAIL %d ===" % [_oks, _fails.size()])
	for f in _fails:
		print("  [FAIL] ", f)
	print("[lookdev_verge] %s  (失败 %d)" % [
			"OK" if _fails.is_empty() else "FAIL", _fails.size()])
	print("  图在 ", dir)
	quit(0 if _fails.is_empty() else 1)


func _hide_ui(n: Node) -> void:
	for c in n.get_children():
		if c is Control or c is CanvasLayer:
			c.visible = false
		else:
			_hide_ui(c)


## 从路心往两侧各扫一遍，把「像素 → 离路心线多少米」的**渲出来的**剖面读出来。
## 比例尺就是 `图高 / TOP_SPAN_M`，一个像素一个定数，不经过任何 fov 约定。
## 每一格在竖直方向上摊开 ROW_HALF 个像素压掉草卡片的高方差。
func _scan(img: Image, wx: float, wz: float, tangent: Vector2, normal: Vector2) -> Dictionary:
	var h: int = img.get_height()
	var w: int = img.get_width()
	var px_per_m: float = float(h) / TOP_SPAN_M
	var y: int = int(h * 0.5)
	print("  --- 俯拍：%.3f px/m，画面横跨 ±%.1fm ---"
			% [px_per_m, (w * 0.5) / px_per_m])

	var out := {"right": _side(img, px_per_m, y, +1),
			"left": _side(img, px_per_m, y, -1)}
	# 接缝：正取 OUTER 那一侧再往外两米（地形自己的取值），左右各一段取平均
	out["seam"] = 0.5 * (_seam(img, px_per_m, y, +1) + _seam(img, px_per_m, y, -1))
	return out


## `sgn` 那一侧的逐米剖面。`step` 从 0.5m 走到 SCAN_M。
func _side(img: Image, px_per_m: float, y: int, sgn: int) -> Dictionary:
	var pts: Array = []
	var n: int = int(SCAN_M / STEP_M)
	for i in range(0, n + 1):
		var m: float = float(i) * STEP_M
		var px: int = int(float(img.get_width()) * 0.5 + sgn * m * px_per_m)
		if px < 0 or px >= img.get_width():
			break
		pts.append([m, _row_lum(img, px, y)])

	# 峰值只在沥青（6.5m）之外找——沥青本来就比土亮，让它参与选峰的话
	# 量到的是路面而不是那道线。
	var peak_m := 0.0
	var peak_lum := -1.0
	for p in pts:
		var m: float = p[0]
		if m < 7.5:
			continue
		if p[1] > peak_lum:
			peak_lum = p[1]
			peak_m = m
	# 峰值左右各 1m 处（半米一格的话是 ±2 格）
	return {
		"pts": pts,
		"peak_m": peak_m,
		"peak_lum": peak_lum,
		"in_lum": _at(pts, peak_m - 1.0),
		"out_lum": _at(pts, peak_m + 1.0),
		# 路面上最亮的一格 = 那道白标线。**不写死它在几米处**——
		# 第一版把取样点钉在 3.5m，实测那道线落在 4.0m 那一档，
		# 于是"最亮"读成 0.398 而正对照永远红。判据的取样点自己
		# 得先问一句落在什么东西上，而**它在哪儿本身就是待测的**。
		"road_lum": _at(pts, 1.5),
		"line_lum": _max_range(pts, 0.5, 6.0),
		# 16m 以外全是地形自己的取值，取平均当"草"
		"far_lum": _mean_from(pts, 16.0),
	}


## 从某米数往外的均值。
func _mean_from(pts: Array, m: float) -> float:
	var acc := 0.0
	var n := 0
	for p in pts:
		if p[0] < m:
			continue
		acc += p[1]
		n += 1
	return acc / float(maxi(n, 1))


## 某一区间的最大值。
func _max_range(pts: Array, lo: float, hi: float) -> float:
	var best := -1.0
	for p in pts:
		if p[0] < lo or p[0] > hi:
			continue
		if p[1] > best:
			best = p[1]
	return maxf(best, 0.0)


## 某一米数上那一格的实际亮度（没有这一格就退回最近的）。
func _at(pts: Array, m: float) -> float:
	for p in pts:
		if absf(float(p[0]) - m) < 0.01:
			return p[1]
	return 0.0


## 14.5m 的外沿和 16.5m 的地形之差——「土径尽头有没有多出一道硬边」。
func _seam(img: Image, px_per_m: float, y: int, sgn: int) -> float:
	var a := _row_lum(img, int(float(img.get_width()) * 0.5 + sgn * 14.5 * px_per_m), y)
	var b := _row_lum(img, int(float(img.get_width()) * 0.5 + sgn * 16.5 * px_per_m), y)
	return absf(a - b)


## 一列像素在竖直方向上摊开之后取均值。
func _row_lum(img: Image, px: int, y: int) -> float:
	var acc := 0.0
	var n := 0
	for dy in range(-ROW_HALF, ROW_HALF + 1):
		var c: Color = img.get_pixel(px, clampi(y + dy, 0, img.get_height() - 1))
		acc += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
		n += 1
	return acc / float(n)


func _print_prof(p: Dictionary) -> void:
	for pt in p["pts"]:
		var m: float = pt[0]
		if m > 8.0 or fmod(m, 1.0) > 0.01:
			continue
		var bar := ""
		var lv: float = pt[1]
		var n: int = int(round(lv * 20.0))
		for _i in n:
			bar += "#"
		print("    %5.1fm  lum=%.3f  %s" % [m, lv, bar])
