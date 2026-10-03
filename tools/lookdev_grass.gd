extends SceneTree
## lookdev_grass.gd — 草皮的四张定妆照
##
## **不能加 --headless，也不能加 --quit-after。**
## --headless 用的是 dummy renderer，**根本不编译着色器**：grass.gdshader 里
## 写错一个标识符（比如把内建的 NORMAL 写成 normal）在无头下只报一行红字，
## 不会中断，回归照样"PASS"。必须带真窗口跑，语法错才会变成一片纯色。
## --quit-after 是按帧数计的，这台机器窗口模式能跑 280+ FPS，给小了会在
## 中途把进程掐掉、只剩一串 warning 看着像通过——所以脚本自己 quit()。
##
## 计时一律用 Time.get_ticks_msec() 比墙钟，不用"帧数 ÷ 60"当秒数。
##
## 五张各查一件不同的事：
##   4m   —— MODEL_MATRIX 是否真的含逐实例变换。引擎哪天不把实例变换乘进
##           MODEL_MATRIX，全部十万丛会塌成一个点，这张一眼可见。
##   15m  —— 草叶有没有轮廓、能不能看出一丛一丛（band 0/1，真实尺寸）
##   45m  —— band 2 起点：卡片放大到 1.8 倍后不该看出接缝或"变稀"
##   100m —— band 3：3.2 倍的大卡片在 165m 外该糊成一层草色的绒，
##           不该是一地看得出来的独立绿块
##   185m —— 淡出带末端（fade 130→200m）：不能有卡片边界炸出来
##
## 用法： godot --path . --script tools/lookdev_grass.gd

const SHOTS := [4.0, 15.0, 45.0, 100.0, 190.0]
const SAVE_DIR := "user://lookdev_grass"
## 相机高度。自行车视角差不多这个高度，别拍成俯视。
const EYE_H := 1.6

## 覆盖率判据的界。**两个数都是量出来的**，不是拍脑袋的：
##   DENSITY = 2.2（本轮定的值）：脚下那段 = 0.069，稠密带/开阔带 = 2.74
##   DENSITY = 5.0（旧的、把地盖死的值）：脚下那段 = 0.135，比值掉到 1.74
## 界取 0.10，落在两者中间：退回 5.0 必红，而 2.2 有一倍余量。
const NEAR_OPEN_MAX := 0.10

var _failures := 0
var _shots := {}          # int(距离) -> Image

## 近景那一带「竖直梯度占比」——草占掉了多少地面。
##
## 这条指标量的是**覆盖率**，不是高度。原来 ring 0 是 5.0 丛/m²、每丛 10 片叶，
## 从 EYE_H=1.6 看下去脚边到 30m 环沿一寸土都不露，整片糊成一块均匀的绿，
## 地形的起伏和远处的山脊线全被吃掉。**而 card_height 只有 0.085m**，
## ring 0/1 最坏 0.085×1.35×1.25≈0.14m，够不上"齐腰"——所以量高度永远量不到
## 那个病灶，量"地面还露不露"才量得到。
##
## 为什么用竖直梯度而不是数草：草是**竖的结构**（叶片的侧边在竖直方向上产生
## 强边缘），地面是平滑的米斑。`|d(亮度)/dy|` 大于一个固定阈值的像素占比，
## 于是就是"这一块被草的结构占住了多少"。它与分辨率无关（比的是相邻行的差），
## 也不需要知道草长在哪——量的是整幅图的统计。
static func vgrad_fraction(img: Image, y0: int, y1: int, thr: float) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var hit := 0
	var total := 0
	for y in range(maxi(y0, 1), mini(y1, h - 1)):
		for x in range(w):
			var a := img.get_pixel(x, y).get_luminance()
			var b := img.get_pixel(x, y - 1).get_luminance()
			var c := img.get_pixel(x, y + 1).get_luminance()
			total += 1
			# absf 不是 absi：亮度差是 0~1 的浮点，absi 会把它截成 0，
			# 于是这一条判据恒为 0.000、恒绿——量��用的尺子自己坏了。
			if maxf(absf(a - b), absf(a - c)) > thr:
				hit += 1
	return float(hit) / maxf(float(total), 1.0)


## 近景地面还露不露得出来（覆盖率判据，带阈值）
func _grass_coverage_section() -> void:
	print("\n---- 近景地面还露不露得出来 ----")
	# 取样带取画面下半：那里是"玩家脚边到中景"，也就是被草吃掉最狠的那一段。
	# 上半是天空和远山，量到的是山不是草。
	const THR := 0.02
	var near_img: Image = _shots.get(4, null)
	var far_img: Image = _shots.get(190, null)
	if near_img == null or far_img == null:
		_check(false, "拍到了 4m 与 190m 两张（%s / %s）" % [
			str(near_img != null), str(far_img != null)])
		return
	var h := near_img.get_height()
	var y0 := int(h * 0.55)
	var y1 := h
	# 两条取样带，都在 4m 那张**同一张图**里：
	#   稠密带 = 地平线正下方那一段（中景，草最密的地方）
	#   开阔带 = 画面最下缘那一段（脚下，5.0 时是被盖死的那一段）
	var dense_y0 := int(h * 0.56)
	var dense_y1 := int(h * 0.66)
	var open_y0 := int(h * 0.93)
	var open_y1 := h
	var f_near := vgrad_fraction(near_img, y0, y1, THR)
	var f_dense := vgrad_fraction(near_img, dense_y0, dense_y1, THR)
	var f_open := vgrad_fraction(near_img, open_y0, open_y1, THR)
	var f_far := vgrad_fraction(far_img, y0, y1, THR)
	print("    近景(4m) 下半合计 = %.3f  稠密带 = %.3f  开阔带 = %.3f  远景(190m) = %.3f"
		% [f_near, f_dense, f_open, f_far])
	# 主判据量的是**脚下那一段**（画面最下缘），不是整幅下半。
	# 试过用"下半合计"，分离度不够：2.2 时 0.125、5.0 时 0.184，只有 1.47 倍，
	 # 界放在中间很容易被一次抖动穿过去。脚下那一段分离度好得多——
	# 2.2 时 0.069、5.0 时 0.135，近乎两倍——因为它整段都是"该露土的地面"，
	 # 没有远处草皮的稀释。
	_check(f_open <= NEAR_OPEN_MAX,
		"脚下那段地面还露得出来：4m 图最下缘的竖直梯度占比 <= %.2f（实测 %.3f）"
		% [NEAR_OPEN_MAX, f_open])
	# 正对照（尺子自己得先被验）：**同一张图**里，稠密带必须明显高于开阔带。
	# 这一条守的是"判据本身还灵不灵"——不写它，占比恒为 0.000（absi 截断那次）
	# 或者恒为 1.0（阈值定成 0）时，`<= 0.10` 两条都能绿。
	_check(f_dense >= f_open * 1.5 + 0.01,
		"正对照：同一张图里稠密带明显高于开阔带（%.3f vs %.3f，比值 %.2f）"
		% [f_dense, f_open, f_dense / maxf(f_open, 0.0001)])


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_failures += 1
		print("[FAIL] ", label)


func _run() -> void:
	print("=== 草皮定妆照（带窗口跑）===")
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

	# 太阳：和 World3D 的 DirectionalLight3D 同一组角度，草影才和游戏里一致
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -126.0, 0.0)
	sun.light_energy = 1.1
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
	env.environment = e
	root.add_child(env)

	var grass = load("res://scripts/GrassScatter.gd").new()
	grass.name = "GrassScatter"
	root.add_child(grass)
	var centerlines: Array = rb.get_all_centerlines()
	grass.setup(terrain, centerlines, [])
	await process_frame

	# uniform 改名后会静默失效（set_shader_parameter 对不存在的名字不报错），
	# 所以每次跑都点一次名，别等到看图才发现草是一片纯色才发现 uniform 没了
	var mat: ShaderMaterial = grass.grass_material()
	var names: Array = []
	for u in mat.shader.get_shader_uniform_list(true):
		names.append(u.get("name", ""))
	for want in ["ground_color", "fade_start", "fade_end", "blade_count",
			"blade_base", "blade_tip", "wind_amp", "mottle_scale"]:
		_check(names.has(want), "shader 暴露了 uniform %s" % want)

	var cam := Camera3D.new()
	cam.fov = 65.0
	cam.far = 800.0
	root.add_child(cam)
	cam.current = true

	# 站到路边的草地上（离路 >= 8m 才能有草）。中心广场附近是铺装。
	var base := Vector3(40.0, 0.0, 0.0)
	var gh: float = terrain.get_height_at(base.x, base.z)
	grass.set_focus(Vector3(base.x, gh, base.z))
	# 铺满整个驻留环（开局是分 tick 灌的，200m 半径下是 ~148 格）。
	# 队列是 tick() 里跑 _retarget 才入队的，所以第一下必须无条件打出去。
	var drain := 1
	grass.tick(0.2)
	await process_frame
	while grass.get("_pending").size() > 0 and drain < 400:
		grass.tick(0.2)
		drain += 1
		await process_frame
	print("    半径 %.0fm，铺满用了 %d 个 tick" % [float(grass.get("_radius")), drain])
	print("    驻留 %d 格 / %d 丛 / %d draw call" % [
		grass.live_cell_keys().size(), grass.live_tuft_count(),
		grass.live_draw_call_count()])
	_check(grass.live_tuft_count() > 40000,
		"草真的铺出来了（%d 丛）" % grass.live_tuft_count())

	# 先量一帧的墙钟，别用帧数折算
	var t0 := Time.get_ticks_msec()
	for _i in range(30):
		await process_frame
	print("    静态 %d 帧共 %dms，单帧 %.2fms"
		% [30, Time.get_ticks_msec() - t0,
			float(Time.get_ticks_msec() - t0) / 30.0])

	for d in SHOTS:
		# 相机**站在焦点上**往 -Z 看，d 是视线的落点到相机的水平距离。
		# 必须站在焦点上：shader 的淡出带量的是"到相机的距离"，把相机搬到
		# 190m 外去拍，等于站进了 band 3 的草里，量到的是"草贴脸"，
		# 不是玩家看见的"远处一层草"。玩家永远在环心，相机就得在环心。
		cam.global_position = Vector3(base.x, gh + EYE_H, base.z)
		var aim := Vector3(base.x,
			terrain.get_height_at(base.x, base.z - d) + 0.15, base.z - d)
		cam.look_at(aim, Vector3.UP)
		await process_frame
		await process_frame

		var img: Image = root.get_texture().get_image()
		var path := "%s/%02dm.png" % [SAVE_DIR, int(d)]
		img.save_png(path)
		_shots[int(d)] = img
		print("    拍了 %s  (%dx%d)  草 %d 丛 / %d draw call" % [
			path, img.get_width(), img.get_height(),
			grass.live_tuft_count(), grass.live_draw_call_count()])

	_grass_coverage_section()

	# 淡出带末端的硬边是给人眼看的，脚本能查的只有"草环跟着焦点走"：
	var before_far: int = grass.live_tuft_count()
	grass.set_focus(Vector3(base.x, gh, base.z - 200.0))
	var d2 := 1
	grass.tick(0.2)
	await process_frame
	while grass.get("_pending").size() > 0 and d2 < 400:
		grass.tick(0.2)
		d2 += 1
		await process_frame
	var after_far: int = grass.live_tuft_count()
	_check(before_far > 0 and after_far > 0,
		"焦点移动后草环跟着重建（旧 %d 丛 / 新 %d 丛）" % [before_far, after_far])
	_check(absi(after_far - before_far) < int(before_far * 0.15),
		"移动 200m 后草总量没有失控（%d -> %d）" % [before_far, after_far])

	print("\n截图目录: %s" % ProjectSettings.globalize_path(SAVE_DIR))
	print("[lookdev_grass] %s  (失败 %d)" % [
		"PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
