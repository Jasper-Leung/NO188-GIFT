extends SceneTree


func _initialize() -> void:
	var road = load("res://scripts/RoadBuilder.gd").new()
	var cell := 8.0
	road._tri_data.append([Vector3(0, 1, 0), Vector3(6, 1, 0), Vector3(0, 1, 6)])
	road._tri_data.append([Vector3(0, 3, 0), Vector3(6, 3, 0), Vector3(0, 3, 6)])
	var key := Vector2i(int(floorf(3.0 / cell)), int(floorf(3.0 / cell)))
	road._tri_grid[key] = [0, 1]
	var failures := 0
	for p in [Vector2(1, 1), Vector2(2, 2), Vector2(3, 3)]:
		var h: float = road.get_road_ribbon_height(p.x, p.y)
		if not is_finite(h) or absf(h - 3.0) > 1e-6:
			failures += 1
			print("FAIL upper_surface p=", p, " h=", h)
	var outside: float = road.get_road_ribbon_height(6, 6)
	if is_finite(outside):
		failures += 1
		print("FAIL outside should be -INF, got=", outside)
	road.free()
	print("SYNTHETIC_ROAD_HEIGHT: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
