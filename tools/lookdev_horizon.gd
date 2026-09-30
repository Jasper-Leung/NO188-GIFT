extends SceneTree
## lookdev_horizon.gd — 远景山线定妆照
##
## **不能加 --headless，也不能加 --quit-after**（理由同 lookdev_grass.gd：
## dummy renderer 不编译着色器、帧数不等于秒数）。
##
## 山线是纯几何 + StandardMaterial3D，本来无头也能渲，但**这个脚本要看的正是
## "山和天怎么接"**——接缝、山脚浮空、雾把山吃干净，这三样在无头截图里看不出来，
## 必须在真渲染器下看。
##
## 四张各查一件不同的事：
##   road_eye — 骑在路面上（相机 1.6m，和玩家一样）：山线该压在草绿地平线之上
##   hilltop  — 站到地形高点：远山该从下面退到地平线附近，不该突然压过来
##   toward_sun — 朝太阳方向：山该逆光偏暗，不该亮成一片白
##   aerial   — 站到地形一角：三层山该递淡，最近那层最绿、最远那层最接近雾色
##
## 用法： godot --path . --script tools/lookdev_horizon.gd

const SAVE_DIR := "user://lookdev_horizon"
const SHOT := Vector2i(1280, 720)
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
	print("=== 远景山线定妆照（带窗口跑）===")
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	root.size = SHOT

	var TB = load("res://scripts/TerrainBuilder.gd")
	var terrain = TB.new()
	terrain.name = "TerrainBuilder"
	root.add_child(terrain)
	await process_frame

	# 和 World3D.tscn 的 Env_sky / ProceduralSky_sun 抄同一组参数，
	# 不然山接天的那条缝在定妆照里是准的、进了游戏又对不上
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.27, 0.53, 0.95, 1.0)
	sm.sky_horizon_color = Color(0.72, 0.85, 0.97, 1.0)
	sm.sky_curve = 0.15
	sm.ground_horizon_color = Color(0.62, 0.70, 0.60, 1.0)
	sm.ground_bottom_color = Color(0.42, 0.48, 0.40, 1.0)
	sm.ground_curve = 0.02
	# World3D.tscn 里那份 ProceduralSky 还留着 sun_energy / sun_latitude 等键，
	# 但 4.6 的 ProceduralSkyMaterial 上只剩 sun_angle_max 和 sun_curve——照抄
	# 那几行会直接抛 "Invalid assignment"，然后 SceneTree 永不 quit，定妆照
	# 脚本会挂到超时。太阳位置和强度由 DirectionalLight3D 决定，天空这边不用设。
	sm.sun_angle_max = 90.0
	sm.sun_curve = 0.04
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.0
	e.fog_enabled = true
	e.fog_light_color = Color(0.88, 0.92, 0.98, 1.0)
	e.fog_density = 0.0003
	e.fog_aerial_perspective = 0.0
	e.fog_sky_affect = 0.3
	env.environment = e
	root.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -126.0, 0.0)
	sun.light_energy = 1.1
	root.add_child(sun)

	var ridge = load("res://scripts/FarRidge.gd").new()
	ridge.name = "FarRidge"
	root.add_child(ridge)
	await process_frame
	_check(ridge.get_child_count() == 3,
		"三层山脊都建出来了（%d 层）" % ridge.get_child_count())

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.current = true

	var base := Vector3(60.0, 0.0, 40.0)
	var gh: float = terrain.get_height_at(base.x, base.z)
	# 全场最高点：远山该"退下去"而不是"压过来"
	var hi_p := Vector3.ZERO
	var hi_h := -INF
	for x in range(-360, 361, 40):
		for z in range(-360, 361, 40):
			var h: float = terrain.get_height_at(float(x), float(z))
			if h > hi_h:
				hi_h = h
				hi_p = Vector3(float(x), h, float(z))
	print("    地形最高点 %.1fm @ %s" % [hi_h, hi_p])

	var shots := [
		["road_eye", base + Vector3(0, EYE_H, 0), Vector3(0, 0, -1)],
		["hilltop", hi_p + Vector3(0, EYE_H, 0), Vector3(0, 0, -1)],
		# 太阳 rotation_degrees = (-48, -126, 0)，-Z 轴转到世界向量的方位
		["toward_sun", base + Vector3(0, EYE_H, 0), Vector3(-0.70, 0.16, 0.70)],
		["aerial", Vector3(-330.0, 60.0, -330.0), Vector3(0.8, -0.12, 0.6)],
	]
	for s in shots:
		cam.global_position = s[1]
		cam.look_at(cam.global_position + Vector3(s[2]).normalized() * 100.0, Vector3.UP)
		await process_frame
		await process_frame
		var img: Image = root.get_texture().get_image()
		var path := "%s/%s.png" % [SAVE_DIR, s[0]]
		img.save_png(path)
		print("    拍了 %s (%dx%d)" % [path, img.get_width(), img.get_height()])
		_check(_horizon_has_band(img), "%s 的地平线上方有山带（不是一条直边）" % s[0])

	print("\n截图目录: %s" % ProjectSettings.globalize_path(SAVE_DIR))
	print("[lookdev_horizon] %s  (失败 %d)" % [
		"PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


## 地平线在 720p、fov 70（垂直）下大约落在 H/2 附近。取地平线上下各一条窄带，
## 量的是"有没有出现和天空明显不同的像素带"——山是暗的，天是亮的。
## 不能只量一条水平线：那正好落在草和天的接缝上。
func _horizon_has_band(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var cy := int(h * 0.5)
	var sky_ref := img.get_pixel(w - 8, int(h * 0.12))
	var hit := 0
	for y in range(maxi(0, cy - int(h * 0.18)), cy):
		for x in range(0, w, 4):
			var c := img.get_pixel(x, y)
			if absf(c.r - sky_ref.r) + absf(c.g - sky_ref.g) + absf(c.b - sky_ref.b) > 0.09:
				hit += 1
	return hit > 40
