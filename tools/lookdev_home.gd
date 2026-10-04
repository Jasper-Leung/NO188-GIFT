extends SceneTree
## lookdev_home.gd — 主角的家定妆照
##
## **不能加 --headless，也不能加 --quit-after**。门牌上那两个字是 Label3D，
## 而 headless 用的是 dummy renderer：不创建字形网格，截出来是一片空白——
## 也就是说"门牌上到底有没有字"这件事在无头回归里**永远查不出来**
## （`verify_home_base.gd` 只能量 font_size / pixel_size / 行宽那些**数字**，
## 量不到"那个字号在 12m 上还剩几个像素"）。同 `lookdev_steles.gd` 的理由。
##
## 五张各查一件不同的事：
##   0_riding  — 从路心线上（门正对的那一段）平拍：这是玩家**唯一**看得见
##               它的机位，家在那一点上得读成"一栋房子"而不是一块灰板
##   1_plate   — 门牌近景：字真的画出来了吗
##   2_far     — 沿路 30m：这么远还认不认得出这里有个住处
##   3_aerial  — 俯视：家 / 路 / 广场 / 碑四者的位置关系
##   4_minimap — 骑行视角带小地图：那枚"家"的钉画出来了没有
##
## 用法： godot --path . --script tools/lookdev_home.gd

const SAVE_DIR := "user://lookdev_home"
const SHOT := Vector2i(1280, 720)
const EYE_H := 1.6
## 沿路往远处退多少米再拍一张。30m 那一档问的是"家还立得住吗"，
## 不是"字还读得出来吗"——12px 那条门槛量的是 0_riding 那个机位。
const FAR_DIST := 30.0
## 相机竖直 fov。两个投影换算（`_plate_px_estimate` / `_proj_scale`）都从
## 它推，所以**改这里要连着那两处一起改** —— 各写一个 70.0 早晚会漂。
const FOV := 70.0

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String, detail := "") -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_failures += 1
		print("[FAIL] ", label, ("  — %s" % detail) if detail != "" else "")


func _run() -> void:
	print("=== 主角的家定妆照（带窗口跑）===")
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	root.size = SHOT

	var gm = root.get_node_or_null("GameManager")
	var loc = root.get_node_or_null("Localization")
	if gm == null or loc == null:
		print("[ABORT] 拿不到 autoload")
		quit(1)
		return
	var backup := ""
	if FileAccess.file_exists(str(gm.SAVE_PATH)):
		var rf = FileAccess.open(str(gm.SAVE_PATH), FileAccess.READ)
		if rf != null:
			backup = rf.get_as_text()
			rf.close()
	gm.reset()
	gm.onboarding_shown = true
	gm.prologue_done = true

	var world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(world)
	await create_timer(2.5).timeout
	world._onboarding.visible = false
	world._hud3d.visible = false
	await process_frame

	var home = world._home
	_check(home != null and home.placed, "家建起来了")
	if home == null or not home.placed:
		_restore(gm, backup)
		quit(1)
		return

	# 类型标注不能省：`home` 是 untyped Node3D，`get_node_or_null` 回来是
	# Variant，`var house :=` 在**加载期**就报 "Cannot infer the type"，
	# 整份脚本编译不过（`--check-only --script` 能在跑之前抓到这一族）。
	var house: Node3D = home.get_node_or_null("House")
	var plate := house.get_node_or_null("Plate") as Label3D if house != null else null
	_check(plate != null, "门牌在（Plate）")
	_check(str(plate.text) == str(loc.t("home_name")),
			"门牌上写的是译好的文案",
			"text=%s" % str(plate.text))
	_check(str(plate.text) == "家", "中文那一侧确实是「家」",
			"got=%s" % str(plate.text))

	# 门朝着路。正面 = 局部 +Z，所以"从路那边看"的方向就是它 basis.z 的 XZ 分量。
	var door_fwd := Vector2(house.global_transform.basis.z.x,
			house.global_transform.basis.z.z).normalized()
	var site := Vector2(home.site.x, home.site.z)
	var centre: PackedVector2Array = world._road_builder.get_centerline()
	# **用 `HomeBase.road_pt`，不要拿"离落点最近的那个中心线点"代替**。
	# 8 字的两个瓣靠得很近，而家在瓣外 15m——全局最近点很可能落在**另一瓣**上，
	# 于是"从路那边看"算出来偏了 70°（实测 dot=0.354），门牌的距离也跟着
	# 从 15m 变成几百米，字身从 27px 掉到 4px。**两个红是同一把尺子的毛病，
	# 不是产品的毛病**——`verify_home_base.gd` §3 量的是同一个性质，用的是
	# 同一个 `road_pt`，它一直绿着。
	var road_pt := Vector2(home.road_pt.x, home.road_pt.y)
	var to_road := (road_pt - site).normalized()
	_check(door_fwd.dot(to_road) > 0.9, "门朝着路（正对照，见 §3 定妆照）",
			"dot=%.3f" % door_fwd.dot(to_road))

	var cam := Camera3D.new()
	cam.fov = FOV
	cam.far = 4000.0
	root.add_child(cam)
	# 玩家自带的 Camera3D 必须从树上摘掉：它一进场景就成了 current，而
	# Camera3D.current 只是"最后一个被设为 true 的赢"。摘掉比抢干净。
	var pcam = world.get_node_or_null("Player3D/Camera3D")
	if pcam != null:
		pcam.get_parent().remove_child(pcam)
		pcam.free()
	cam.current = true
	await process_frame

	var tb: Node3D = world._terrain_builder
	var plate_w: Vector3 = plate.global_position

	# ---- 0 骑行视角：站在门正对的那段中心线上 ----
	# 机位**取在 `road_pt` 上**，不是"离门 RIDE_DIST 的地方"——家在中心线外
	# 15m，按门去摆机会把相机摆到路外面的草里去，那不是玩家会待的位置。
	var eye0 := Vector3(road_pt.x, 0.0, road_pt.y)
	eye0.y = tb.get_height_at(eye0.x, eye0.z) + EYE_H
	await _shoot(cam, eye0, Vector3(home.site.x, plate_w.y, home.site.z), "0_riding")
	# 判据量的是**门牌那一块**里的墨，不是全图。全图那份数字在"墙是深色的"
	# 世界里一样很大，而门牌是唯一一块该有笔画的地方。
	var riding_ink := _ink_in_rect(_plate_screen_rect(cam, plate))
	_check(riding_ink > 0, "骑行那一档门牌上还有墨（%d 像素）" % riding_ink)
	# 字高是个**乘积**：字号折成米 × 这个距离上每米多少像素。盯住任一
	# 个因子都量不到玩家读到的那行字有多高（站名牌那次 `pixel_size` 写死
	# 0.002、字号 48，合起来 9.6cm，18m 上 3.3px，而没有一条断言会红）。
	var riding_px := _plate_px_estimate(plate, (plate.global_position - cam.global_position).length())
	# 门槛 12px 取的是**站名牌那一档的实测值**（CLAUDE.md：`verify_stations.gd`
	# 末节钉的 "18m 那一档 ≥12px"）——家和驿站是玩家一路上并排看到的两块牌子，
	# 门槛必须同一把尺子，不许这块松一档。
	_check(riding_px >= 12.0, "骑行那一档字身还有 %.1fpx（12px = 站名牌那一档的实测门槛）"
			% riding_px)

	# ---- 1 门牌近景：字到底画出来了吗 ----
	var eye1 := Vector3(home.site.x, 0.0, home.site.z) + Vector3(door_fwd.x, 0.0, door_fwd.y) * 4.0
	eye1.y = tb.get_height_at(eye1.x, eye1.z) + EYE_H
	await _shoot(cam, eye1, plate_w, "1_plate")
	var close_ink := _ink_in_rect(_plate_screen_rect(cam, plate))
	_check(close_ink > 150, "门牌近景有刻字（暗墨 %d 像素）" % close_ink)
	# 正对照：同一批逻辑对着**旁边的墙**采样，那儿什么都没有。
	# 只测"有墨"的话，把墨换成一块深色贴图也照样绿。
	var wall_ink := _blank_wall_ink(cam)
	_check(close_ink > wall_ink * 3.0,
			"正对照：门牌上的墨明显多于旁边那面空墙（%d vs %d）" % [close_ink, wall_ink])

	# ---- 2 沿路 30m ----
	var far_pt := _offset_along(centre, road_pt, FAR_DIST)
	var eye2 := Vector3(far_pt.x, 0.0, far_pt.y)
	eye2.y = tb.get_height_at(eye2.x, eye2.z) + EYE_H
	await _shoot(cam, eye2, Vector3(home.site.x, plate_w.y, home.site.z), "2_far")

	# ---- 3 俯视：家 / 路 / 广场 / 碑 ----
	await _shoot(cam, Vector3(home.site.x, 120.0, home.site.z + 95.0),
			Vector3(home.site.x, 0.0, home.site.z), "3_aerial")

	# ---- 4 骑行视角带小地图：那枚"家"的钉 ----
	# 藏小地图的那一段是给 3D 定点拍用的；这一张要它，所以放回来。
	if world._minimap != null:
		world._minimap.visible = true
	await process_frame
	var eye4 := Vector3(road_pt.x, 0.0, road_pt.y)
	eye4.y = tb.get_height_at(eye4.x, eye4.z) + EYE_H
	await _shoot(cam, eye4, Vector3(home.site.x, plate_w.y, home.site.z), "4_minimap")
	var pin_with := _cream_pixels(world)
	print("    带着钉的米白像素 %d" % pin_with)
	# 门槛 30 是**量出来的**：钉照现在这个尺寸画出来是 73（2026-10-04 实测），
	# 撤掉之后是 0。取 30 是"不许缩掉一半、不许挪出框"，
	# 而绝对数与差额**成对写**——CLAUDE.md 里"每一路都要配一条承重的正对照"。
	_check(pin_with >= 30, "小地图上那枚'家'的钉画出来了（%d 像素，实测 73）" % pin_with)
	# **正对照：把钉撤掉再数一遍，差值才是这枚钉自己的账。**
	# 小地图上本来就有的米白不止一处——`NEXT_RING`(1,1,1) 套在下一处碎片站
	# 外面那圈白环。第一版扫全图，删掉 `_draw_home()` 之后仍读到 26 个米白
	# 像素，那条"钉画出来了"**照样绿**；框收小之后白环根本不在框里（撤钉 0）。
	# 而这条正对照仍然留着：它证明框里那些像素真的是这枚钉的，而不只是
	# "框里碰巧有东西"。
	world._minimap.has_home = false
	world._minimap.queue_redraw()
	await process_frame
	await process_frame
	var pin_without := _cream_pixels(world)
	print("    撤掉钉之后 %d" % pin_without)
	_check(pin_with - pin_without >= 30,
			"正对照：框里那 %d 个米白像素真是这枚钉的（撤掉钉之后掉到 %d）"
			% [pin_with - pin_without, pin_without])
	world._minimap.has_home = true
	world._minimap.queue_redraw()
	await process_frame

	_restore(gm, backup)
	print("\n截图目录: %s" % ProjectSettings.globalize_path(SAVE_DIR))
	print("[lookdev_home] %s  (失败 %d)" % [
		"PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _restore(gm, backup: String) -> void:
	if backup == "":
		return
	# 三份一起收：存档改成原子写之后，跑一遍会多出 .bak / .tmp，只写回正本会把它们留在盘上
	gm._clear_save()
	var wf = FileAccess.open(str(gm.SAVE_PATH), FileAccess.WRITE)
	if wf != null:
		wf.store_string(backup)
		wf.close()


func _shoot(cam: Camera3D, eye: Vector3, aim: Vector3, name: String) -> void:
	cam.global_position = eye
	cam.look_at(aim, Vector3.UP)
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	var path := "%s/%s.png" % [SAVE_DIR, name]
	img.save_png(path)
	print("    拍了 %s (%dx%d)" % [path, img.get_width(), img.get_height()])


## 沿中心线朝弧长增大的那一侧走出 dist 米。锚点是**中心线上的点**
## （`road_pt` 本身就在上面，距离为 0），所以这里找 index 时不会被
## 8 字另一瓣抢走——第一版拿 `site`（离中心线 15m）当锚，
## 全局最近点落在另一瓣上，整条线都从错的地方开始量。
func _offset_along(line: PackedVector2Array, anchor: Vector2, dist: float) -> Vector2:
	var ai := 0
	var bd := INF
	for i in line.size():
		var d: float = line[i].distance_squared_to(anchor)
		if d < bd:
			bd = d
			ai = i
	var acc := 0.0
	for i in range(ai + 1, line.size()):
		acc += line[i].distance_to(line[i - 1])
		if acc >= dist:
			return line[i]
	return line[line.size() - 1]


## 门牌那行字折成米之后有多高，再乘上"这个距离上每米多少像素"。
##
## 走的是 CLAUDE.md 里量站名牌的那条正路：`Font.get_string_size()` 给宽、
## `Font.get_height()` 给高，都按 `pixel_size` 折成米——**不是** `get_aabb()`
## （它给一个立方体，三条边都等于整行字的总宽）也不是 `global_transform`
## （`billboard` 是在顶点着色器里转的，节点变换根本没跟着转）。
func _plate_px_estimate(plate: Label3D, dist: float) -> float:
	var f: Font = plate.get_font()
	if f == null:
		f = ThemeDB.fallback_font
	if f == null:
		return 0.0
	var h_m: float = f.get_height(plate.font_size) * plate.pixel_size
	var screen_h: int = int(root.size.y)
	# 竖直 fov 70°，屏幕高就是那一条射线的投影长度
	var px_per_m := float(screen_h) / (2.0 * dist * tan(deg_to_rad(FOV) * 0.5))
	return h_m * px_per_m


## 门牌上那行字落在屏幕上的哪一块。只量**墨核**：`outline_size` 从字身
## 向外膨胀，而 `modulate` 那层墨永远画在最上层——所以把描边加粗到 60
## 也不会让墨核多出一根（CLAUDE.md 里量过），**描边不许算进判据**。
##
## billboard 永远正对着相机，所以两根轴取相机的 right / up，绕相机
## 摆出来的框才和屏上那块面对得上。
func _plate_screen_rect(cam: Camera3D, plate: Label3D) -> Rect2:
	var f: Font = plate.get_font()
	if f == null:
		f = ThemeDB.fallback_font
	if f == null:
		return Rect2()
	var t: String = str(plate.text)
	var w_m: float = f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			plate.font_size).x * plate.pixel_size
	var h_m: float = f.get_height(plate.font_size) * plate.pixel_size
	var xf := cam.global_transform
	var right := Vector3(xf.basis.x.x, xf.basis.x.y, xf.basis.x.z)
	var up := Vector3(xf.basis.y.x, xf.basis.y.y, xf.basis.y.z)
	var c := plate.global_position
	var cx := 0.5 * root.size.x + (right.dot(c - cam.global_position) / _depth(c, cam)) * _proj_scale()
	var cy := 0.5 * root.size.y - (up.dot(c - cam.global_position) / _depth(c, cam)) * _proj_scale()
	return Rect2(cx - w_m * 0.5 * _proj_scale(), cy - h_m * 0.5 * _proj_scale(),
			w_m * _proj_scale(), h_m * _proj_scale())


func _depth(c: Vector3, cam: Camera3D) -> float:
	return maxf(0.05, (c - cam.global_position).length())


func _proj_scale() -> float:
	# 竖直 fov 固定 70°（上面建相机时写的），屏幕高换算成"每米多少像素"
	return float(root.size.y) / (2.0 * tan(deg_to_rad(FOV) * 0.5))


## 门牌那块框里的暗像素数 —— 也就是"墨核真的有笔画"。
## **取样框按屏幕分辨率算，不许手算像素**（`lookdev_journey.gd` 里同一个坑：
## 换一次分辨率手算的那版量到的是隔壁那格）。
func _ink_in_rect(r: Rect2) -> int:
	var img: Image = root.get_texture().get_image()
	var n := 0
	var x0 := maxi(0, int(r.position.x))
	var y0 := maxi(0, int(r.position.y))
	var x1 := mini(img.get_width() - 1, int(r.end.x))
	var y1 := mini(img.get_height() - 1, int(r.end.y))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := img.get_pixel(x, y)
			if c.r + c.g + c.b < 0.42:
				n += 1
	return n


func _blank_wall_ink(cam: Camera3D) -> int:
	var img: Image = root.get_texture().get_image()
	var n := 0
	var x0 := int(root.size.x * 0.06)
	var x1 := int(root.size.x * 0.22)
	var y0 := int(root.size.y * 0.40)
	var y1 := int(root.size.y * 0.60)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c := img.get_pixel(x, y)
			if c.r + c.g + c.b < 0.42:
				n += 1
	return n


## 钉**自己那一小块**里"米白"的像素数。
##
## 取样框是围绕 `_w2m(home_site)` 的一小块，不是整个小地图——这一条是被
## 突变逼出来的：第一版扫全图，删掉 `_draw_home()` 之后仍然读到 26 个米白
## 像素（`NEXT_RING` 那圈套在下一处碎片站外面的白环正好落进同一个阈值），
## 于是"钉画出来了"那条**照样绿**。框收小之后那圈白环根本不在框里。
##
## 正对照（撤掉钉再数一遍）仍然留着，但它的作用从"唯一的判据"降成
## "第二道保险"——因为框里的东西已经是这枚钉专属的了。
func _cream_pixels(world: Node3D) -> int:
	var mm: Control = world._minimap
	if mm == null:
		return 0
	# **不要因为 `has_home` 为 false 就早退** —— 正对照那一遍正是把它置成
	# false 之后数的，早退掉的话差值永远是 0，判据又变成恒绿。
	var img: Image = root.get_texture().get_image()
	# 钉在**小地图局部坐标**里的位置，换算到屏幕要加节点自己的全局位置。
	# 不许拿小地图的 `get_global_rect()` 反推：那是控件的框，地图内容画在
	# 里面另外一套 `_w2m` 换算上。
	var c: Vector2 = mm._w2m(mm.home_site) + mm.get_global_rect().position
	var half := 14
	var n := 0
	for y in range(maxi(0, int(c.y) - half), mini(img.get_height(), int(c.y) + half)):
		for x in range(maxi(0, int(c.x) - half), mini(img.get_width(), int(c.x) + half)):
			var px := img.get_pixel(x, y)
			# 钉的色是 `HOME_TINT`(0.93,0.91,0.85)，外加一圈更暗的描边
			# （`HOME_EDGE` 0.12）把米白从近黑的深绿底上托出来。
			if px.r > 0.72 and px.g > 0.70 and px.b > 0.64:
				n += 1
	return n
