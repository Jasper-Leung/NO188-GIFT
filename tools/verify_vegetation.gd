extends SceneTree

var terrain
var road
var veg
var failures := 0


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
	if centerlines.size() != 1:
		_fail("expected one main centerline only (no branch), got %d" % centerlines.size())
	var road_data = road.get_road_data()
	# 节点 8 云影台(idx 7) + 节点 11 茶烟小筑(idx 10) 需要清灌木
	var protected_positions: Array = [
		road_data.get_station_world_pos(7),
		road_data.get_station_world_pos(10),
	]
	veg.setup(road_data.points, terrain, null, centerlines, protected_positions)

	var north := 0
	var south := 0
	var invalid_distance := 0
	var invalid_height := 0
	var outside_terrain := 0
	var protected_station_bushes := 0
	var total := 0
	for pdata in veg._chunks_plants:
		var cfg: Dictionary = pdata.config
		var plant_north := 0
		var plant_south := 0
		for defs in pdata.chunk_defs:
			for item in defs:
				total += 1
				var pos: Vector3 = item.pos
				var distance: float = veg._min_dist_to_road_2d(pos)
				var expected_y: float = terrain.get_height_at(pos.x, pos.z)
				if distance < float(cfg.min_off) - 0.01:
					invalid_distance += 1
				if absf(pos.y - expected_y) > 0.001:
					invalid_height += 1
				if not veg._in_terrain(pos):
					outside_terrain += 1
				if cfg.name == "bush":
					for protected_pos in protected_positions:
						if pos.distance_to(protected_pos) <= veg.STATION_BUSH_CLEAR_RADIUS:
							protected_station_bushes += 1
							break
				if pos.z < 0.0:
					north += 1
					plant_north += 1
				else:
					south += 1
					plant_south += 1
		print("PLANT ", cfg.name, " total=", plant_north + plant_south,
			" north=", plant_north, " south=", plant_south)

	print("VEGETATION total=", total, " north=", north, " south=", south,
		" invalid_distance=", invalid_distance, " invalid_height=", invalid_height,
		" outside_terrain=", outside_terrain, " protected_station_bushes=", protected_station_bushes)
	if invalid_distance > 0:
		failures += invalid_distance
	if invalid_height > 0:
		failures += invalid_height
	if outside_terrain > 0:
		failures += outside_terrain
	if protected_station_bushes > 0:
		failures += protected_station_bushes
	if north != south:
		failures += 1

	road.queue_free()
	terrain.queue_free()
	veg.queue_free()
	await process_frame
	print("VEGETATION_REGRESSION: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)


func _fail(message: String) -> void:
	failures += 1
	print("FAIL: ", message)
