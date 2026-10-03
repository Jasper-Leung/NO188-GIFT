extends SceneTree
## lookdev_steles.gd — 路碑定妆照
##
## **不能加 --headless，也不能加 --quit-after**。碑面那个「188」是 Label3D，
## 而 headless 用的是 dummy renderer：不创建字形网格，截出来是一片空白——
## 也就是说"碑面上有没有字"这件事在无头回归里**永远查不出来**，只能看图。
##
## 六张各查一件不同的事：
##   0..2_close — 骑到三块完好碑前，从玩家眼高（1.6m）看：字得**正着读得出**
##   3_worn     — 被凿平的那块近景：崩口要真的啃掉半个 188
##   4_distant  — 隔着路面看：远一点还认不认得出"这里立着个东西"
##   5_all      — 俯视四块碑：碑和碑的间距、碑和路的关系
##
## 用法： godot --path . --script tools/lookdev_steles.gd

const SAVE_DIR := "user://lookdev_steles"
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
	print("=== 路碑定妆照（带窗口跑）===")
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
	if world._minimap != null:
		world._minimap.visible = false
	await process_frame

	var steles = world._steles
	_check(steles != null and steles.get_child_count() == 4,
		"四块碑都建出来了")

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 4000.0
	root.add_child(cam)
	# 玩家自带的 Camera3D 必须从树上摘掉：它一进场景就成了 current，而
	# Camera3D.current 只是"最后一个被设为 true 的赢"，脚本里再设一次
	# 未必每一帧都压得住。摘掉比抢干净。
	var pcam = world.get_node_or_null("Player3D/Camera3D")
	if pcam != null:
		pcam.get_parent().remove_child(pcam)
		pcam.free()
	cam.current = true
	await process_frame

	for i in range(steles.get_child_count()):
		var p: Vector3 = steles.stele_positions[i]
		var mark = steles.get_child(i).get_node_or_null("Mark") as Label3D
		if mark == null:
			continue
		# 站在"路这边、正对着碑"的位置。Label3D 的正面是它自己 basis.z 指向的
		# 那一侧，所以相机要站在 **+fwd** 这边——第一版写成 -fwd，站在碑背面
		# 透过 slab 拍 double_sided 的字，出来是镜像的"88"，看着像刻漏了首位。
		var fwd := Vector2(mark.global_transform.basis.z.x, mark.global_transform.basis.z.z).normalized()
		var eye := Vector3(p.x, 0.0, p.z) + Vector3(fwd.x, 0.0, fwd.y) * 7.0
		eye.y = world._terrain_builder.get_height_at(eye.x, eye.z) + EYE_H
		var aim := Vector3(p.x, mark.global_position.y, p.z)
		var name := "3_worn" if i == 3 else "%d_close" % i
		await _shoot(cam, eye, aim, name)
		_check(_has_dark_pixels_on_bright_stone(cam), "%s 碑面上有刻痕" % name)

	# 隔着路面看：距离拉远，碑还立不立得住
	var p0: Vector3 = steles.stele_positions[0]
	var m0 = steles.get_child(0).get_node_or_null("Mark") as Label3D
	var far_eye := Vector3(p0.x, 0.0, p0.z) + Vector3(m0.global_transform.basis.z.x, 0.0,
		m0.global_transform.basis.z.z).normalized() * 26.0
	far_eye.y = world._terrain_builder.get_height_at(far_eye.x, far_eye.z) + EYE_H
	await _shoot(cam, far_eye, Vector3(p0.x, m0.global_position.y, p0.z), "4_distant")

	# 俯视：四块碑各自的间距、碑与路的关系
	await _shoot(cam, Vector3(0.0, 260.0, 43.0), Vector3(0.0, 0.0, 43.0), "5_all")

	if backup != "":
		var wf = FileAccess.open(str(gm.SAVE_PATH), FileAccess.WRITE)
		if wf != null:
			wf.store_string(backup)
			wf.close()

	print("\n截图目录: %s" % ProjectSettings.globalize_path(SAVE_DIR))
	print("[lookdev_steles] %s  (失败 %d)" % [
		"PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _shoot(cam: Camera3D, eye: Vector3, aim: Vector3, name: String) -> void:
	cam.global_position = eye
	cam.look_at(aim, Vector3.UP)
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	var path := "%s/%s.png" % [SAVE_DIR, name]
	img.save_png(path)
	print("    拍了 %s (%dx%d)" % [path, img.get_width(), img.get_height()])


## 碑面是浅石色（0.60, 0.585, 0.545），刻的字是 0.20 的深褐。取全图
## 最暗的一批像素——它们只可能来自刻痕或描边。字画不出来时这块会读到 0，
## 因为 headless 下 Label3D 根本不生成字形。
func _has_dark_pixels_on_bright_stone(cam: Camera3D) -> bool:
	var img: Image = root.get_texture().get_image()
	var dark := 0
	var w := img.get_width()
	var h := img.get_height()
	for y in range(0, h, 3):
		for x in range(0, w, 3):
			var c := img.get_pixel(x, y)
			if c.r + c.g + c.b < 0.55:
				dark += 1
	print("    暗像素 %d / %d" % [dark, (w / 3) * (h / 3)])
	return dark > 200
