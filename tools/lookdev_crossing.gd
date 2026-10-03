extends SceneTree
## lookdev_crossing.gd — 8 字交叉点定妆照
##
## **不能加 --headless，不能加 --quit-after**。这一族量的全是观感：路面在交叉
## 处叠成什么样、玩家骑到那儿看见的是什么，而"两支路心线最近只差 1.97m"这句话
## 本身推不出画面。`verify_crossing.gd` 量的是**高度连续**（玩家会不会感觉到台阶），
## 它对"两条沥青粘成一摊"这件事一个字都没说。
##
## 五张各查一件不同的事：
##   0_aerial   — 200m 俯视：整个 8 字能不能一眼看出是 8
##   1_merge    — 50m 斜看交叉处：两支路面是叠成一片还是分得开
##   2_ride_in  — 玩家眼高顺着路骑进去：拐弯那一下有没有东西可看
##   3_ride_out — 从交叉处往外看：出去那一段是什么样
##   4_ground   — 正上方垂直俯拍：两条沥青的边界到底在哪儿
## 再加那块「路自此复」的碑四张（5~8），见下面。
##
## 用法： godot --path . --script tools/lookdev_crossing.gd

const SAVE_DIR := "user://lookdev_crossing"
const SHOT := Vector2i(1280, 720)
const EYE_H := 1.6
## 8 字的自交点。`road_data` 解析式采样出来的两条支路在这里重合。
const CROSSING := Vector3(0.0, 0.0, 43.0)

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
	print("=== 8 字交叉点定妆照（带窗口跑）===")
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

	# --- 先把"两支离得多近"量出来，再拍照 ---
	# 拍照只是记录，而这一节真正要回答的问题是"路面在那里叠成什么样"，
	# 所以数字先摆在这儿，看图的人可以对着它判断 2m 到底算不算分得开。
	var line: Array = world._road_builder.get_centerline()
	var n: int = line.size()
	var best := INF
	var bi := -1
	var bj := -1
	for i in range(n):
		for j in range(i + 1, n):
			if absf(float(j - i) - float(n) * 0.5) > 30.0:
				continue
			var d: float = Vector2(line[i].x - line[j].x, line[i].z - line[j].z).length()
			if d < best:
				best = d
				bi = i
				bj = j
	print("    两支最近处 %.2fm（i=%d j=%d），沥青半宽 6.5m → 边沿重叠 %.2fm" % [
			best, bi, bj, maxf(0.0, 13.0 - best)])
	_check(best > 0.5, "两支中心线没有真的相交（相交了就是一座立交，不是 8 字）")

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 4000.0
	root.add_child(cam)
	var pcam = world.get_node_or_null("Player3D/Camera3D")
	if pcam != null:
		pcam.get_parent().remove_child(pcam)
		pcam.free()
	cam.current = true
	await process_frame

	# 交叉处路面那一圈的高程（相机站位要用，不能拍到地底下）
	var ground: float = world._terrain_builder.get_height_at(CROSSING.x, CROSSING.z)

	await _shoot(cam, Vector3(CROSSING.x, 200.0, CROSSING.z),
			Vector3(CROSSING.x, 0.0, CROSSING.z), "0_aerial")
	await _shoot(cam, Vector3(CROSSING.x + 34.0, ground + 26.0, CROSSING.z + 34.0),
			Vector3(CROSSING.x, ground, CROSSING.z), "1_merge")

	# 顺着路骑进去：站在交叉点前 60m 的路面上，眼睛离地 1.6m
	var entry := _point_at_arclength(world, 0.0, -60.0)
	await _shoot(cam, Vector3(entry.x, ground + EYE_H, entry.z),
			Vector3(CROSSING.x, ground + 1.0, CROSSING.z), "2_ride_in")
	# 从交叉处往外看
	var exit_p := _point_at_arclength(world, 0.0, 60.0)
	await _shoot(cam, Vector3(CROSSING.x, ground + EYE_H, CROSSING.z),
			Vector3(exit_p.x, ground + 1.0, exit_p.z), "3_ride_out")
	# 正上方垂直俯拍：两条沥青的边界到底画在哪儿
	await _shoot(cam, Vector3(CROSSING.x, 90.0, CROSSING.z + 0.01),
			Vector3(CROSSING.x, 0.0, CROSSING.z), "4_ground")

	# ---- 交叉点那块「路自此复」的碑 ----
	# 四张各查一件不同的事，而**没有一张能量"字刻没刻出来"**：
	#   5_mark      — 站在碑前两米低头：刻线读不读得出是个 8、题字在不在下沿
	#   6_ride      — 从骑行眼高顺着路看过去：那块碑在不在视野里、是不是一块石头
	#   7_face      — 正对碑面：刻线和石板的比例
	#   8_from_air  — 从 200m 高空：碑和交叉点、路的关系
	# 刻线是 SurfaceTool 拼的 ArrayMesh、题字是 Label3D——**headless 下两者
	# 一笔都不落盘**，所以这一族只有带窗口才拍得出来。
	var mark = world.get_node_or_null("CrossingMark")
	if mark == null or mark.get_child_count() == 0:
		print("[ABORT] 交叉点那块碑没建出来")
		_failures += 1
		quit(1)
		return
	var mp: Vector3 = mark.mark_position
	print("    碑在 (%.1f, %.1f, %.1f)，离沥青 %.1fm，正面朝 (%.2f, %.2f)" % [
			mp.x, mp.y, mp.z, float(mark.road_clearance),
			float(mark.mark_facing.x), float(mark.mark_facing.y)])
	# 骑上来的人：站在碑前 2m、眼睛 1.6m、低头看碑面中心
	var fwd: Vector2 = mark.mark_facing
	var side := Vector2(-fwd.y, fwd.x)
	var stand := Vector2(mp.x, mp.z) + fwd * 2.4
	var my_ground: float = world._terrain_builder.get_height_at(stand.x, stand.y)
	var face_mid := Vector3(mp.x, mp.y + 1.5, mp.z)
	await _shoot(cam, Vector3(stand.x, my_ground + EYE_H, stand.y),
			face_mid, "5_mark")
	# 正对碑面，看刻线占碑面的比例。
	# 站位是**正前方**而不是侧方——第一版写成 `side * 4.2`，那正好是碑的
	# 法线的垂线，于是相机把碑面看成了��条边：拍出来是一块斜着的白板，
	# 刻线和题字一样都读不到，而判据"拍到了碑"照样过。
	# 侧偏只留 0.5m（人不会正对着碑中心站），够看出碑有多厚。
	var front := Vector2(mp.x, mp.z) + fwd * 3.4 + side * 0.5
	await _shoot(cam, Vector3(front.x, mp.y + 1.9, front.y),
			face_mid, "6_face")
	# 从骑行眼高、在路上看过去：碑是不是一件看得见的布景
	var approach := _point_at_arclength(world, 0.0, -70.0)
	await _shoot(cam, Vector3(approach.x, ground + EYE_H, approach.z),
			face_mid, "7_ride")
	# 高空：碑和交叉点、路的关系
	await _shoot(cam, Vector3(mp.x + 30.0, 60.0, mp.z + 30.0),
			Vector3(mp.x, mp.y, mp.z), "8_from_air")

	if backup != "":
		var wf = FileAccess.open(str(gm.SAVE_PATH), FileAccess.WRITE)
		if wf != null:
			wf.store_string(backup)
			wf.close()

	print("\n截图目录: %s" % ProjectSettings.globalize_path(SAVE_DIR))
	print("[lookdev_crossing] %s  (失败 %d)" % [
		"PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


## 中心线上离交叉点约 `offset` 米的一点（正数往后、负数往前）。
## 用来把相机摆在"路面上"而不是"路的旁边"——摆在旁边拍出来的合并
## 和玩家真正看见的不是同一件事。
func _point_at_arclength(world: Node, from_idx: float, offset: float) -> Vector3:
	var line: Array = world._road_builder.get_centerline()
	var total: float = world._road_builder.get_road_data().total_arclength()
	var i: int = clampi(int(from_idx), 0, line.size() - 1)
	var want: float = offset / maxf(total, 1.0) * float(line.size())
	var j: int = posmod(i + int(round(want)), line.size())
	return line[j]


func _shoot(cam: Camera3D, eye: Vector3, aim: Vector3, name: String) -> void:
	cam.global_position = eye
	cam.look_at(aim, Vector3.UP)
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	var path := "%s/%s.png" % [SAVE_DIR, name]
	img.save_png(path)
	print("    拍了 %s (%dx%d)" % [path, img.get_width(), img.get_height()])
