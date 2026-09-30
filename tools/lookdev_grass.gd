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

var _failures := 0


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
		print("    拍了 %s  (%dx%d)  草 %d 丛 / %d draw call" % [
			path, img.get_width(), img.get_height(),
			grass.live_tuft_count(), grass.live_draw_call_count()])

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
