extends SceneTree

var terrain
var road
var veg
var station_scene
var station_model
var _fails := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	terrain = load("res://scripts/TerrainBuilder.gd").new()
	root.add_child(terrain)
	road = load("res://scripts/RoadBuilder.gd").new()
	road.set_terrain_builder(terrain)
	root.add_child(road)
	veg = load("res://scripts/VegBuilder.gd").new()
	root.add_child(veg)
	await process_frame

	var centerlines: Array = road.get_all_centerlines()
	var road_data = road.get_road_data()
	# 节点 8 云影台(idx 7) + 节点 11 茶烟小筑(idx 10)
	var protected_positions: Array = [
		road_data.get_station_world_pos(7),
		road_data.get_station_world_pos(10),
	]
	veg.setup(road_data.points, terrain, null, centerlines, protected_positions)

	var station_pos: Vector3 = road_data.get_station_world_pos(7)
	station_pos.y = terrain.get_height_at(station_pos.x, station_pos.z)
	station_scene = load("res://assets/models/station_0.glb")
	station_model = station_scene.instantiate()
	station_model.scale = Vector3(10, 10, 10)
	var station_aabb: AABB
	for child in station_model.get_children():
		if child is MeshInstance3D:
			station_aabb = station_aabb.merge(child.get_aabb())
	print("STATION0 pos=", station_pos, " local_aabb=", station_aabb)

	var bush = veg._chunks_plants[0]
	var near_count := 0
	var protected_count := 0
	var worst_gap := -INF
	var worst: Dictionary = {}
	for defs in bush.chunk_defs:
		for item in defs:
			var pos: Vector3 = item.pos
			var d := INF
			for protected_pos in protected_positions:
				d = minf(d, pos.distance_to(protected_pos))
			if d > 50.0:
				continue
			near_count += 1
			if d <= veg.STATION_BUSH_CLEAR_RADIUS:
				protected_count += 1
			var terrain_y: float = terrain.get_height_at(pos.x, pos.z)
			var road_y: float = road.get_road_ribbon_height(pos.x, pos.z)
			var gap: float = pos.y - terrain_y
			if absf(gap) > worst_gap:
				worst_gap = absf(gap)
				worst = {"pos": pos, "station_d": d, "terrain_y": terrain_y, "road_y": road_y, "gap": gap}
			print("BUSH_NEAR pos=", pos, " station_d=%.2f" % d,
				" terrain_y=%.6f" % terrain_y, " road_y=", road_y, " gap=%.6f" % gap)
	print("BUSH_NEAR count=", near_count, " protected_count=", protected_count, " worst=", worst)

	# 统一契约：每条回归都打 `[OK]` / `[FAIL]` 行。`tools/check_all.sh` 靠它统计，
	# 而它判"这条没跑成"的方式是**一条断言都没打出来**——这条脚本原来只
	# `quit(1 if ...)`，一个断言都不打，于是它在自检表里既不算通过也不算失败，
	# 只是安静地跑完了。
	_ck("驿站净空内的灌木被清干净了", protected_count == 0,
			"还剩 %d 丛（净空半径 %.1fm）" % [protected_count, veg.STATION_BUSH_CLEAR_RADIUS])
	_ck("净空附近确实有灌木被检查过（不是附近一丛都没有，判据空转）",
			near_count > 0, "附近 %d 丛" % near_count)
	_ck("每株灌木都贴在地形上（gap≈0）", worst_gap < 0.05,
			"最大偏差 %.4fm" % worst_gap)

	station_model.free()
	road.queue_free()
	terrain.queue_free()
	veg.queue_free()
	await process_frame
	quit(0 if _fails == 0 else 1)


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_fails += 1
		print("[FAIL] ", label + ("（" + detail + "）" if detail != "" else ""))
