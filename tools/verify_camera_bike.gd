extends SceneTree
## verify_camera_bike.gd — 钉住"跟随机位下自行车还认得出是一辆车"
##
## 为什么需要这条：改动前的跟随机位是**正后方** 6m / 高 4m / 横向 0。在那个
## 角度上一辆 1.37m 高、2.38m 长的自行车正投影成一根竖条——车架三角和两个
## 轮子全部侧对镜头，屏幕上 61×187px，认不出是辆车。整个 demo 的主角物件
## 认不出来，而 `lookdev_journey.gd` 原有的两条断言（"整辆车在画面内"、
## "车 ≥100px 高"）在那个坏机位上**全绿**——它们量的是"看得见"，不是"认得出"。
##
## 量的必须是**轮廓**而不是 AABB：AABB 的 8 个角里带着 1.19m 的车长，
## 透视会让它在 x 上散开，所以"正后方"也能量出一个虚高的宽度。真正决定
## 认不认得出的是网格顶点投影后的横向铺开——正后方时车最宽的东西只有
## 0.55m 的车把。
##
## 同时跑一遍旧机位当**反向对照**：同一条判据在旧机位上必须不通过。
## 一条只会全绿的断言等于没有断言。
##
## 注意：**不能加 --headless**。dummy display server 给的是 1280×1280 的方视口，
## 而真机是 1280×720，竖直方向多出来的 560px 会把车上量出一截看不见的部分，
## 宽高比直接被压低（实测 0.86 → 0.50）。`root.size` 在 headless 下改不动。
##
## 用法： godot --path . --script tools/verify_camera_bike.gd

const MIN_ASPECT := 0.65          ## 车在屏幕上的投影宽 / 高（实测 0.86，旧机位 0.30）
const MIN_EDGE_OFFSET := 60.0     ## 车心离屏幕中线至少这么远（证明不是正后方）
const MIN_HEIGHT_PX := 100.0

var _pass := 0
var _fail := 0
var _world: Node = null


func _ck(ok: bool, label: String, detail := "") -> void:
	if ok:
		_pass += 1
		print("[OK]   %s%s" % [label, ("　" + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("[FAIL] %s%s" % [label, ("　" + detail) if detail != "" else ""])


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
	# headless 的 dummy display server 给的是方视口（实测 1280×1280），
	# 而真机是 1280×720。竖直方向多出来的 560px 会让所有投影数失真：
	# 车上多出一大截看不见的部分，宽高比直接被压低。不改视口量出来的数
	# 一条都作废，所以先把窗口拉回真机尺寸，并且把它当一条断言守着。
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	_ensure_autoloads()
	var gm = root.get_node("GameManager")
	gm.onboarding_shown = true
	gm.headless_mode = true
	gm.prologue_done = true
	_run.call_deferred()


func _run() -> void:
	print("=== 跟随机位下的自行车可读性 ===")
	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	await create_timer(2.5).timeout

	var player: Node = _world.get_node_or_null("Player3D")
	_ck(player != null, "真实 World3D 里有 Player3D")
	if player == null:
		_report()
		return
	var cam: Camera3D = player.get_node_or_null("Camera3D")
	_ck(cam != null, "Player3D 上挂着 Camera3D")
	if cam == null:
		_report()
		return

	var pts := _bike_screen_points(player, cam)
	_ck(not pts.is_empty(), "车在玩家节点下且有可投影的网格", "%d 个顶点" % pts.size())
	if pts.is_empty():
		_report()
		return

	var vs: Vector2 = cam.get_viewport().get_visible_rect().size
	_ck(vs == Vector2(1280, 720), "量的是真机 16:9 视口，不是 headless 的方视口", str(vs))
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for p in pts:
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	var bw := mx.x - mn.x
	var bh := mx.y - mn.y
	var aspect := bw / maxf(bh, 0.001)
	var cx := (mn.x + mx.x) * 0.5
	var edge := absf(cx - vs.x * 0.5)

	print("  —— 现役机位 ——")
	print("  屏幕 %s，车轮廓 %.0f×%.0fpx，宽高比 %.2f，车心 x=%.0f（离中线 %.0fpx）" %
			[str(vs), bw, bh, aspect, cx, edge])

	_ck(aspect >= MIN_ASPECT, "车在屏幕上横向铺开（宽高比 ≥ %.2f，量的是顶点轮廓不是 AABB）" % MIN_ASPECT,
			"实测 %.2f" % aspect)
	_ck(bh >= MIN_HEIGHT_PX, "车够大（≥ %.0fpx 高）" % MIN_HEIGHT_PX, "实测 %.0fpx" % bh)
	_ck(edge >= MIN_EDGE_OFFSET, "车不在画面正中间（离中线 ≥ %.0fpx = 侧向机位）" % MIN_EDGE_OFFSET,
			"实测 %.0fpx" % edge)
	_ck(mn.x >= 0.0 and mn.y >= 0.0 and mx.x <= vs.x and mx.y <= vs.y,
			"整辆车在画面内", "(%.0f,%.0f)-(%.0f,%.0f)" % [mn.x, mn.y, mx.x, mx.y])

	# 相机真的横移开了没有——直接量偏移向量，别靠推断
	var right: Vector3 = player.global_transform.basis.x
	var lateral: float = (cam.global_position - player.global_position).dot(right)
	_ck(absf(lateral) >= 1.0, "相机相对车横向让开 ≥ 1.0m",
			"实测 %.2fm" % lateral)

	# 纵向还要看得到路：注视点前方 12m 处不能被相机甩出画面
	var fwd: Vector3 = -player.global_transform.basis.z
	var ahead: Vector2 = cam.unproject_position(
			player.global_position + fwd * 12.0 + Vector3(0, 0.5, 0))
	_ck(ahead.x >= 0.0 and ahead.x <= vs.x and ahead.y >= 0.0 and ahead.y <= vs.y,
			"车头前方 12m 仍在画面内（别为了看车把路丢了）",
			"(%.0f,%.0f)" % [ahead.x, ahead.y])

	# 反向对照：把旧的正后方机位摆回去，同一条判据必须不通过
	print("  —— 反向对照：旧机位（正后方 6m / 高 4m / 横向 0）——")
	var old: Dictionary = _measure_old_camera(player, cam, vs)
	_ck(float(old["aspect"]) < MIN_ASPECT,
			"旧机位在同一判据下确实不通过（否则这条断言没在量东西）",
			"旧机位宽高比 %.2f" % float(old["aspect"]))

	_report()


func _measure_old_camera(player: Node, cam: Camera3D, vs: Vector2) -> Dictionary:
	# 复原改动前的那一组数：global_position - forward*6.0 + Vector3(0,4,0)，
	# 注视 global_position + forward*3.0 + Vector3(0,1,0)，横向 0。
	var keep_pos: Vector3 = cam.global_position
	var keep_rot := cam.global_transform.basis
	var fwd: Vector3 = -player.global_transform.basis.z
	cam.global_position = player.global_position - fwd * 6.0 + Vector3(0, 4.0, 0)
	cam.look_at(player.global_position + fwd * 3.0 + Vector3(0, 1.0, 0), Vector3.UP)
	var pts := _bike_screen_points(player, cam)
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for p in pts:
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	var bw := mx.x - mn.x
	var bh := mx.y - mn.y
	cam.global_position = keep_pos
	cam.global_transform.basis = keep_rot
	return {"aspect": bw / maxf(bh, 0.001), "w": bw, "h": bh}


func _bike_screen_points(player: Node, cam: Camera3D) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for m in _player_meshes(player):
		var mi: MeshInstance3D = m
		if mi.mesh == null:
			continue
		out.append_array(_surface_points(mi, mi.global_transform, cam))
	return out


func _surface_points(mi: MeshInstance3D, xf: Transform3D, cam: Camera3D) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var mesh: Mesh = mi.mesh
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for v in verts:
			var p: Vector2 = cam.unproject_position(xf * v)
			if not is_finite(p.x) or not is_finite(p.y):
				continue
			if p.x < -4000.0 or p.x > 8000.0 or p.y < -4000.0 or p.y > 8000.0:
				continue   # 在相机背后，投影值没意义
			out.append(p)
	return out


func _player_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_player_meshes(c))
	return out


func _report() -> void:
	print("")
	if _fail == 0:
		print("RESULT PASS  (%d 条通过)" % _pass)
	else:
		print("RESULT FAIL  (通过 %d / 失败 %d)" % [_pass, _fail])
	quit()
