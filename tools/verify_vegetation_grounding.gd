extends SceneTree
## verify_vegetation_grounding.gd — 每一株植物都必须站在地上
##
## VegBuilder 原来用 Transform3D(basis, pos).scaled(Vector3(s,s,s)) 组装实例变换，
## 而 Godot 的 Transform3D.scaled() 会把 origin 一起缩放（origin.y * s），
## 于是每株植物实际落在「地面高度 × 缩放」而不是地面高度上。
## 实测灌木平均浮空 0.74m、最多 4.35m；树平均浮空 7.79m、最多 24.64m。
##
## 断言的是语义属性（origin.y == 地面高度）而不是公式本身，
## 所以任何写错缩放作用对象的改法都会在这里炸掉。
##
## 只能直接调 VegBuilder.instance_transform()（static），不能回读
## MultiMesh.get_instance_transform()：--headless 用的是 dummy renderer，
## 那个调用一律返回单位矩阵，量出来的永远是"完美贴地"的假象。
##
## 用法： godot --headless --path . --script tools/verify_vegetation_grounding.gd

const GROUND_EPS := 0.0001

var _failures := 0
var _worst := 0.0
var _worst_where := ""


func _check(cond: bool, label: String) -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_failures += 1
		print("[FAIL] ", label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== 植被贴地回归 ===")
	_unit_check()

	var terrain = load("res://scripts/TerrainBuilder.gd").new()
	root.add_child(terrain)
	var road = load("res://scripts/RoadBuilder.gd").new()
	road.set_terrain_builder(terrain)
	root.add_child(road)
	await process_frame

	var road_data = road.get_road_data()
	var centerlines: Array = road.get_all_centerlines()

	# 两条放置路径都要查：程序化生成，和游戏实际加载的 layout.json 覆盖项
	await _check_placement(terrain, road_data, centerlines, {}, "程序化放置")
	var layout = load("res://scripts/LayoutData.gd")
	if layout.exists():
		var ov = load("res://scripts/LayoutData.gd").get_plant_overrides_by_type(
			load("res://scripts/LayoutData.gd").load())
		await _check_placement(terrain, road_data, centerlines, ov, "layout.json 覆盖放置")
	else:
		print("[SKIP] 没有 layout.json，跳过覆盖路径")

	print("\n---------------- 汇总 ----------------")
	print("最大离地误差 = %.4fm（%s）" % [_worst, _worst_where])
	print("[verify_vegetation_grounding] %s  (失败 %d)" % [
		"PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


## 直接单元检查：无论缩放多大、位置在哪，origin 都必须原封不动
func _unit_check() -> void:
	var b := Basis().rotated(Vector3.UP, 0.7)
	var cases := [
		{"pos": Vector3(10, 3, -4), "s": 2.5, "y_off": 0.0},
		{"pos": Vector3(0, 0, 0), "s": 7.0, "y_off": 0.0},
		{"pos": Vector3(-120, -2.8, 90), "s": 0.6, "y_off": 0.0},
		{"pos": Vector3(5, 4, 5), "s": 1.0, "y_off": 0.0},
		# y_offset 仍按缩放后的高度偏移，语义不变
		{"pos": Vector3(1, 2, 3), "s": 2.0, "y_off": 0.5},
	]
	var all_ok := true
	for cs in cases:
		var tf: Transform3D = load("res://scripts/VegBuilder.gd").instance_transform(
			b, cs.pos, cs.y_off, cs.s)
		var want: Vector3 = cs.pos + Vector3(0.0, cs.y_off * cs.s, 0.0)
		var ok: bool = tf.origin.distance_to(want) < 1e-5
		# 缩放必须真的落在 basis 上
		var s_ok: bool = absf(tf.basis.get_scale().x - cs.s) < 1e-5
		if not ok or not s_ok:
			all_ok = false
			print("    pos=%s s=%.2f y_off=%.2f -> origin=%s basis_scale=%.4f"
				% [str(cs.pos), cs.s, cs.y_off, str(tf.origin), tf.basis.get_scale().x])
	_check(all_ok, "instance_transform() 对 5 组 (位置/缩放/y_offset) 保持 origin 不变、缩放只进 basis")


func _check_placement(terrain, road_data, centerlines: Array,
		overrides: Dictionary, tag: String) -> void:
	var veg = load("res://scripts/VegBuilder.gd").new()
	root.add_child(veg)
	await process_frame
	veg.setup(road_data.points, terrain, null, centerlines, [], overrides)
	await process_frame

	var items: Array = veg.get_all_items()
	if items.is_empty():
		_check(false, "%s：没有生成任何植物" % tag)
		veg.queue_free()
		await process_frame
		return

	var by_type := {}
	var bad := 0
	for it in items:
		var type_name: String = it.type
		by_type[type_name] = int(by_type.get(type_name, 0)) + 1
		# 复刻 _build_chunk 的调用：parts[0] 就是全部 part（当前两种植物都只有 1 个）
		var cfg_parts: Array = _parts_for(veg, type_name)
		for part in cfg_parts:
			var tf: Transform3D = load("res://scripts/VegBuilder.gd").instance_transform(
				it["_item"]["basis"], it["_item"]["pos"],
				part.get("y_offset", 0.0), it["_item"]["scale"])
			# 关键：origin 必须正好落在该 XZ 的地面高度上
			var ground: float = terrain.get_height_at(tf.origin.x, tf.origin.z)
			var err: float = absf(tf.origin.y - ground)
			if err > _worst:
				_worst = err
				_worst_where = "%s %s @ %s" % [tag, type_name, str(tf.origin.snapped(Vector3(0.01, 0.01, 0.01)))]
			if err > GROUND_EPS:
				bad += 1

	print("   %s：%d 株 %s" % [tag, items.size(), str(by_type)])
	_check(bad == 0, "%s：全部 %d 株的实例变换贴在地面上（越界 %d 株）" % [tag, items.size(), bad])

	veg.queue_free()
	await process_frame


func _parts_for(veg, type_name: String) -> Array:
	for pdata in veg._chunks_plants:
		if pdata.name == type_name:
			return pdata.config.parts
	return []
