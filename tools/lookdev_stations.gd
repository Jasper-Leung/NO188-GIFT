extends SceneTree
## lookdev_stations.gd — 驿站布局定妆照
##
## **不能加 --headless，也不能加 --quit-after。** --headless 用 dummy renderer，
## 截出来的 PNG 是一片纯色，看着像"路和亭子都在"其实什么都没画；--quit-after
## 按墙钟折算，这台机器窗口模式能跑 280+ FPS，给小了会在中途把进程掐掉。
## 脚本自己 quit()。
##
## 数据层的硬断言（每个驿站脚底离中心线的净空）在 verify_stations.gd 里，
## 这里只补人眼要看的那件事：**亭子确实没架在沥青上**。用的是真 World3D，
## 驿站是 _setup_stations() 摆的真 GLB，不是模拟。
##
##   01..05  俯拍几个代表驿站（含广场那个交叉点驿站）：路从亭子旁边过
##   06      全路线高空俯视：16 个亭子都落在 8 字外侧
##   07      骑行视角：贴在路面上朝前看，亭子在路肩外
##
## 用法： godot --path . --script tools/lookdev_stations.gd

const SAVE_DIR := "user://lookdev_stations"
const SHOT := Vector2i(1280, 720)
## 俯拍高度。够高才看得见"路从旁边过"，够低才分得清亭子和路肩。
const TOP_H := 55.0
## 骑行视角的相机高度，和 Player3D 的自行车视角一致。
const EYE_H := 1.6
## 代表驿站：0 起程驿楼、4 禽语湖湾、8 灯影亭（广场交叉点）、12 西谷岭台、15 榕树下。
## 12 是净空最紧的那座，8 是唯一落在广场盘上的。
const TOP_IDX := [0, 4, 8, 12, 15]

var _fails := 0
var _shots := 0
var _gm: Node = null
var _world: Node = null


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_fails += 1
		print("[FAIL] ", label + ("（" + detail + "）" if detail != "" else ""))


func _ensure_autoloads() -> void:
	var paths := {
		"GameManager": "res://scripts/GameManager.gd",
		"AudioManager": "res://scripts/AudioManager.gd",
		"Localization": "res://scripts/Localization.gd",
	}
	for n in paths:
		if root.get_node_or_null(n) == null:
			var node: Node = load(paths[n]).new()
			node.name = n
			root.add_child(node)


func _initialize() -> void:
	Engine.max_fps = 60
	_ensure_autoloads()
	_gm = root.get_node("GameManager")
	_gm._clear_save()
	_gm.headless_mode = true
	# World3D 自带 OnboardingGuide（操作说明那整块），不置掉的话它盖满全屏，
	# 顶拍/骑拍都只能拍到它。
	_gm.onboarding_shown = true
	_gm.prologue_done = true
	root.size = SHOT
	_run.call_deferred()


func _run() -> void:
	print("=== 驿站布局定妆照（带窗口跑）===")
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	# --script 模式仍会把 project.godot 里的 main_scene 挂上来，先摘干净。
	for c in root.get_children():
		if c == _gm or c == root.get_node("AudioManager") \
				or c == root.get_node("Localization"):
			continue
		c.queue_free()
	await process_frame
	await process_frame

	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	# 等 _setup_stations() 把 16 座亭子摆完（还有地形/路面/植被的构建）。
	await create_timer(2.5).timeout
	_ck("World3D 已建", _world != null and _world._stations.size() == 16,
			"stations=%d" % (0 if _world == null else _world._stations.size()))
	# HUD（碎片栏/小地图/遮罩）会盖住俯拍画面，定妆照里一律关掉。
	for layer in ["HUDLayer", "FragmentBarLayer", "JoystickLayer", "MiniGameLayer"]:
		if _world.has_node(layer):
			_world.get_node(layer).visible = false
	await process_frame

	var cam := Camera3D.new()
	cam.name = "LookDevCam"
	cam.fov = 60.0
	cam.near = 0.1
	cam.far = 2000.0
	root.add_child(cam)

	# ---- 俯拍每个代表驿站 ----
	var rd = load("res://scripts/road_data.gd").new()
	for idx in TOP_IDX:
		var p: Vector3 = _world._stations[idx].position
		cam.global_position = p + Vector3(0.0, TOP_H, 24.0)
		cam.look_at(p, Vector3.UP)
		cam.make_current()
		var nm := "%02d_top_%d_%s" % [_shots + 1, idx,
				str(rd.get("stations")[idx].get("name_en", "")).replace(" ", "")]
		await _snap(cam, nm)

	# ---- 全路线高空俯视 ----
	cam.fov = 45.0
	cam.global_position = Vector3(0.0, 420.0, 260.0)
	cam.look_at(Vector3(0.0, 0.0, 40.0), Vector3.UP)
	cam.make_current()
	await _snap(cam, "06_overview_全路线")

	# ---- 骑行视角：贴着路面朝灯影亭（广场那个）看 ----
	cam.fov = 65.0
	var st8: Vector3 = _world._stations[8].position
	# 站在驿站正对的那条路上，沿路往回退 22m，再抬到车把高度。
	var to_road := Vector3(0.0, 0.0, 43.0) - Vector3(st8.x, 0.0, st8.z)
	var back := to_road.normalized() * 22.0
	cam.global_position = Vector3(st8.x + back.x, EYE_H, st8.z + back.z)
	cam.look_at(Vector3(st8.x, EYE_H + 1.0, st8.z), Vector3.UP)
	cam.make_current()
	await _snap(cam, "07_rider_朝灯影亭")

	_world.queue_free()
	await process_frame
	_gm._clear_save()

	print("\n截图目录: %s" % ProjectSettings.globalize_path(SAVE_DIR))
	print("[lookdev_stations] %s  (失败项 %d, 共 %d 张)" % [
			"PASS" if _fails == 0 else "FAIL", _fails, _shots])
	quit(0 if _fails == 0 else 1)


## 渲染两帧再导 PNG：queue_redraw / 材质编译都到下一帧才落地。
func _snap(cam: Camera3D, name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	var path := "%s/%s.png" % [SAVE_DIR, name]
	var err: int = img.save_png(path)
	_ck("%s 导出成功（%dx%d）" % [name, img.get_width(), img.get_height()],
			err == OK and img.get_width() == SHOT.x,
			"err=%d size=%dx%d" % [err, img.get_width(), img.get_height()])
	# dummy renderer 下导出的图整张是 0；带窗口的正常有内容。
	var c := img.get_pixel(SHOT.x / 2, SHOT.y / 2)
	_ck("%s 画面非空（中心像素 %s）" % [name, str(c)], c.a > 0.0)
	_shots += 1
