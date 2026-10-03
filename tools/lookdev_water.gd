extends SceneTree
## lookdev_water.gd — 三处水的定妆照
##
## **不能加 --headless，也不能加 --quit-after**（理由同 lookdev_grass.gd：
## dummy renderer 不编译着色器、帧数不等于秒数）。
##
## 水面是着色器 + 逐角度求出来的岸线，无头渲出来的要么是白片要么什么都没有。
##
## ---- 为什么要渲两遍 ----
## 这一族的断言全是**像素**的，而"哪些像素是水"第一版是**靠颜色猜**的
## （偏蓝且不亮）。那个判据当场就废了两次：
##   · 只判"偏蓝"时**整片天都算成水**——天本身就是亮的青蓝，于是
##     "水跑到天上去了"那条永远红，而真正该量的"水面在半空中被切断"反而量不到；
##   · 补上"不亮"之后，天顶那片深蓝的亮度又掉进阈值里，还是被当成水。
## 靠颜色猜"这是水"，量到的是**天空长什么样**，不是水长什么样。
##
## 所以每张拍两遍：第一遍把三片水换成一片**不受光的洋红**，量它遮住哪些
## 像素（纯几何，谁也不用猜颜色）；第二遍换回真材质，量观感。
## 断言写在第一遍上，于是"水没跑到天上""岸线有起伏"这类判断终于量的是水。

const SAVE_DIR := "user://lookdev_water"
const SHOT := Vector2i(1280, 720)
const EYE_H := 1.6
## 掩膜色。洋红既不是草也不是天，判据是"红通道压过绿和蓝"（见 `_is_mask`）。
const MASK_COL := Color(1.0, 0.0, 0.9)
## 水面与它周围陆地的平均色至少要差这么多，否则"看着像水"这条就不成立。
## 0.02 是下限：只差一点点的话玩家分不出那是水还是影子。
const MIN_WATER_LAND_DELTA := 0.02
## 岸线的"逐行宽度有起伏"门槛。看圆盘的投影在各行之间几乎等宽，
## 而跟着地形走的岸线会有几成起伏。
const MIN_SHORE_SWING := 0.08

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
	print("=== 三处水定妆照（带窗口跑）===")
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	root.size = SHOT

	var terrain = load("res://scripts/TerrainBuilder.gd").new()
	terrain.name = "TerrainBuilder"
	root.add_child(terrain)
	await process_frame
	_check(terrain.water_basins().size() == 3, "三只碗都定下来了")

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	# 与 World3D.tscn / lookdev_horizon.gd / DayCycle 的 DAY_SKY_* 同一组数。
	# 抄一份的话，"天压暗之后水还亮着"这件事就量不出来了。
	sm.sky_top_color = Color(0.27, 0.53, 0.95, 1.0)
	sm.sky_horizon_color = Color(0.72, 0.85, 0.97, 1.0)
	sm.sky_curve = 0.15
	sm.ground_horizon_color = Color(0.62, 0.70, 0.60, 1.0)
	sm.ground_bottom_color = Color(0.42, 0.48, 0.40, 1.0)
	sm.ground_curve = 0.02
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
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 54.0, 0.0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.75, 0.82, 0.95, 1.0)
	root.add_child(fill)

	var ridge = load("res://scripts/FarRidge.gd").new()
	ridge.name = "FarRidge"
	root.add_child(ridge)

	var water = load("res://scripts/Water.gd").new()
	water.name = "Water"
	root.add_child(water)
	water.setup(terrain, sun)
	await process_frame
	var bodies: Array = water.bodies()
	_check(bodies.size() == 3, "三片水面都建出来了")

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.current = true

	# 机位站在**水边**而不是碗外十几米。站远了湖就被压成地平线上的一条
	# 细带（相机只高出水面 2.4m，60m 宽的湖从 46m 外看过去只剩画面高度的 7%），
	# 岸线什么样根本看不清——量出来的每一条都是"有个东西在那儿"。
	var views := []
	for b in terrain.water_basins():
		var c: Vector2 = b["center"]
		var along := Vector2(float(b["ax"]), float(b["az"]))
		var side := Vector2(along.y, -along.x).normalized()
		views.append({
			"station": int(b["station"]), "center": c, "side": side,
			"level": float(b["level"]),
			"eye": _bank_eye(terrain, c, side, float(b["level"])),
		})

	var cove = views[1]    # 花房·禽语湖湾，最大的一只
	var creek = views[0]   # 南溪茶寮，最狭长
	var west = views[2]    # 西湾神苑

	var shots := [
		["cove_shore_湖湾岸线", cove],
		["creek_南溪", creek],
		["westbay_西湾", west],
		# 站近一点。第一版在 85m 外拍，40m 宽的湖只占画面高度的 1/4，
		# 读成"绿地上一个水坑"——而这条断言恰恰是量"它不是一片海"的，
		# 机位太远时它量的是相机离得多远。
		["aerial_湖湾俯瞰", {
			"eye": Vector3(cove["center"].x, 0.0, cove["center"].y) + Vector3(-30, 38, -30),
			"look": Vector3(cove["center"].x, 0.0, cove["center"].y),
		}],
	]
	var shot_img := {}
	for s in shots:
		var pair := await _shoot(cam, String(s[0]), s[1], bodies)
		shot_img[String(s[0])] = pair
		var nm := String(s[0])
		var mx := _mask_pixels(pair["mask"])
		_check(mx > 400, "%s：看得见水（掩膜 %d 个采样像素）" % [nm, mx])
		_check(_no_water_above_horizon(pair["mask"]),
				"%s：水没有跑到天上（不是半空中被切断的蓝片）" % nm)
		var d := _water_reads_as_water(pair["mask"], pair["shot"])
		_check(d > MIN_WATER_LAND_DELTA,
				"%s：水看着跟旁边的地不一样（色差 %.3f）" % [nm, d])
		if nm == "cove_shore_湖湾岸线":
			_check(_shore_is_irregular(pair["mask"]),
					"%s：岸线逐行宽度有起伏（跟着地形，不是圆盘）" % nm)
		if nm == "aerial_湖湾俯瞰":
			# 俯瞰量的是"整片水被岸围住了，没漫成一片海"。水面不到画面一半
			# 才算过——连成一片的话世界读起来就不是那条环形骑行路线了。
			var total := float(pair["mask"].get_width() * pair["mask"].get_height() / 4)
			_check(float(mx) < 0.5 * total, "%s：水面不到画面一半（不是一片海，%d%%）"
					% [nm, int(100.0 * float(mx) / total)])

	# ---- 黄昏：与湖湾岸线**同机位**的第二张 ----
	# 少了配对的那张就判不出"天到底变了没有"，两帧之间混进了机位差的话，
	# 看的人分不清哪些变化是天色给的（CLAUDE.md 昼夜那条的同款理由）。
	var day_cycle = load("res://scripts/DayCycle.gd").new()
	day_cycle.name = "DayCycle"
	root.add_child(day_cycle)
	day_cycle.setup(sun, fill, env, ridge, water)
	day_cycle.set_laps(3.0, 10.0)   # delta 远大于 FADE_SEC，一帧就到 t=1
	await process_frame
	await process_frame
	_check(day_cycle.get_t() >= 1.0, "黄昏转场走到了 t=1")
	var dusk := await _shoot(cam, "cove_dusk_湖湾黄昏", cove, bodies)
	_check(_no_water_above_horizon(dusk["mask"]), "黄昏那张的水也没有跑到天上")

	var day: Dictionary = shot_img["cove_shore_湖湾岸线"]
	_check(_mean(dusk["shot"]) < _mean(day["shot"]) * 0.75,
			"黄昏那张明显比正午暗（%.3f vs %.3f）" % [_mean(dusk["shot"]), _mean(day["shot"])])

	print("\n截图目录: %s" % ProjectSettings.globalize_path(SAVE_DIR))
	print("[lookdev_water] %s  (失败 %d)" % [
		"PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


## 站在水边。沿 `side` 从碗心往外走，找出"还泡在水里"的最远处，
## 那是这一侧的岸线；再往外退 3m 就是脚下的干地。
##
## 直接站在盆沿（半径那一圈）不行：碗沿是自然地形，有高有低，
## 站低了水面糊在脚下、站高了湖缩成一条带。而岸线是**逐角度求出来的**，
## 所以这里也照它的办法走一遍——量的是同一个事实，不是另一个近似。
func _bank_eye(tb: Node, c: Vector2, side: Vector2, level: float) -> Vector3:
	var r := 2.0
	var wet := 2.0
	while r <= 160.0:
		if tb.get_height_at(c.x + side.x * r, c.y + side.y * r) >= level:
			break
		wet = r
		r += 0.5
	var p := c + side * (wet + 3.0)
	return Vector3(p.x, tb.get_height_at(p.x, p.y) + EYE_H, p.y)


## 拍两张：一张水被换成掩膜色（量几何），一张真材质（量观感）。
## 落盘的是后者——掩膜那张只是量用的中间结果。
func _shoot(cam: Camera3D, name: String, v: Dictionary, bodies: Array) -> Dictionary:
	_cam_to(cam, v)
	var saved := []
	for b in bodies:
		saved.append(b.material_override)
		b.material_override = _mask_material()
	await _frames()
	var mask: Image = root.get_texture().get_image()
	mask.save_png("%s/%s_mask.png" % [SAVE_DIR, name])
	for i in range(bodies.size()):
		bodies[i].material_override = saved[i]
	await _frames()
	var shot: Image = root.get_texture().get_image()
	shot.save_png("%s/%s.png" % [SAVE_DIR, name])
	print("    拍了 %s/%s.png（掩膜 %s/%s_mask.png）"
			% [SAVE_DIR, name, SAVE_DIR, name])
	return {"mask": mask, "shot": shot}


func _cam_to(cam: Camera3D, v: Dictionary) -> void:
	var eye: Vector3 = v["eye"]
	cam.global_position = eye
	if v.has("look"):
		cam.look_at(v["look"], Vector3.UP)
	else:
		var c: Vector2 = v["center"]
		cam.look_at(Vector3(c.x, eye.y, c.y), Vector3.UP)


func _frames() -> void:
	await process_frame
	await process_frame
	await process_frame


## 掩膜材质：不受光的纯洋红。颜色只用来"认出来"，深度测试照常开着，
## 所以站在水底下的土不会把它误算成水。
##
## `disable_fog` 是必需的：场景那层雾的 `fog_light_color` 几乎是白的，
## 开着雾时洋红会被洗成一份淡粉，绿通道抬到阈值边上——第一版的掩膜
## 一片都没量到，量到的却是天空长什么样。
func _mask_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = MASK_COL
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	return m


## 判据比的是**通道之间的差距**，不是绝对值。
##
## 绝对阈值（"红蓝都高、绿低"）量的是掩膜那个色号在 AGX + 雾之后落到哪一档，
## 而那正是被 tonemap 挪动的那几档——掩膜被调淡一点，整族断言就集体变成
## "量到了 0 个像素"。红通道**同时**压过绿和蓝则是这个场景里唯一站得住的
## 事实：草是绿的（红低于绿），天是蓝的（红也低于绿），只有洋红反过来。
func _is_mask(c: Color) -> bool:
	return c.r > c.g + 0.18 and c.b > c.g + 0.12


func _mask_pixels(img: Image) -> int:
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			if _is_mask(img.get_pixel(x, y)):
				n += 1
	return n


## 水不许出现在天的位置。
##
## 这是**第一版设计的病**，而它只有看图才看得出来：水位按碗心定，顺坡的一侧
## 追不上岸，水面在半空中被切断——于是天上飘着一片蓝。
## 判据取画面上 35%：相机是站在水边平视的，地平线落在这条线附近。
func _no_water_above_horizon(mask: Image) -> bool:
	for y in range(0, int(mask.get_height() * 0.35), 2):
		for x in range(0, mask.get_width(), 2):
			if _is_mask(mask.get_pixel(x, y)):
				return false
	return true


## 岸线跟着地形走，而不是一个正圆。逐行量水面的左右边界，
## 若整片水的宽度在各行之间几乎不变，读出来就是"一块圆盘"。
func _shore_is_irregular(mask: Image) -> bool:
	var widths: Array = []
	for y in range(int(mask.get_height() * 0.4), int(mask.get_height() * 0.95), 6):
		var lo := -1
		var hi := -1
		for x in range(mask.get_width()):
			if _is_mask(mask.get_pixel(x, y)):
				if lo < 0:
					lo = x
				hi = x
		if lo >= 0 and hi - lo > mask.get_width() * 0.05:
			widths.append(float(hi - lo))
	if widths.size() < 6:
		return false
	var mn: float = widths[0]
	var mx: float = widths[0]
	for v in widths:
		mn = minf(mn, v)
		mx = maxf(mx, v)
	return (mx - mn) / mx > MIN_SHORE_SWING


## 水看着得跟旁边的地不一样。
##
## 不比"更蓝"而比"差多少"：水的颜色一半来自菲涅耳的天空色，掠射角一大
## 就接近天色，那时候"偏蓝"根本不是判据；而"水里那些像素的平均色"和
## "紧挨着岸的陆地的平均色"差多少，与相机怎么摆无关，是真的在看观感。
func _water_reads_as_water(mask: Image, shot: Image) -> float:
	var in_sum := Vector3.ZERO
	var in_n := 0
	# 紧挨着掩膜外圈的一圈陆地，作为"这片地本来什么颜色"的基准
	var land_sum := Vector3.ZERO
	var land_n := 0
	for y in range(3, mask.get_height() - 3, 3):
		for x in range(3, mask.get_width() - 3, 3):
			var m := _is_mask(mask.get_pixel(x, y))
			var s := shot.get_pixel(x, y)
			if m:
				in_sum += Vector3(s.r, s.g, s.b)
				in_n += 1
			elif not _is_mask(mask.get_pixel(x - 3, y)) \
					and not _is_mask(mask.get_pixel(x + 3, y)):
				land_sum += Vector3(s.r, s.g, s.b)
				land_n += 1
	if in_n == 0 or land_n == 0:
		return 0.0
	var a := in_sum / float(in_n)
	var b := land_sum / float(land_n)
	return absf(a.x - b.x) + absf(a.y - b.y) + absf(a.z - b.z)


func _mean(img: Image) -> float:
	var s := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			s += (c.r + c.g + c.b) / 3.0
			n += 1
	return s / float(maxi(n, 1))