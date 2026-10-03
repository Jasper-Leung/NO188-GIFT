extends SceneTree
## verify_road_height.gd — `get_road_ribbon_height()` 取的是**上层路面**，
## 路外返回 -INF。
##
## 打的是 `[OK]` / `[FAIL]` 行而不是自定义的 `SYNTHETIC_ROAD_HEIGHT:` 那一行：
## `tools/check_all.sh` 靠统一契约统计，而它判"没跑成"的方式是**一条断言都没打出来**
## ——退出码在这种脚本上是 0，只看退出码会把空跑判成通过。

var failures := 0


func _initialize() -> void:
	var road = load("res://scripts/RoadBuilder.gd").new()
	var cell := 8.0
	road._tri_data.append([Vector3(0, 1, 0), Vector3(6, 1, 0), Vector3(0, 1, 6)])
	road._tri_data.append([Vector3(0, 3, 0), Vector3(6, 3, 0), Vector3(0, 3, 6)])
	var key := Vector2i(int(floorf(3.0 / cell)), int(floorf(3.0 / cell)))
	road._tri_grid[key] = [0, 1]
	for p in [Vector2(1, 1), Vector2(2, 2), Vector2(3, 3)]:
		var h: float = road.get_road_ribbon_height(p.x, p.y)
		_ck("路面上层取到 3.0（不是下层的 1.0） p=%s" % str(p),
				is_finite(h) and absf(h - 3.0) <= 1e-6, "实测 %s" % str(h))
	var outside: float = road.get_road_ribbon_height(6, 6)
	_ck("路外返回 -INF（不是 0，否则玩家会掉到路面高度）",
			not is_finite(outside), "实测 %s" % str(outside))
	road.free()
	print("SYNTHETIC_ROAD_HEIGHT: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("[OK]   ", label)
	else:
		failures += 1
		print("[FAIL] ", label + ("（" + detail + "）" if detail != "" else ""))
