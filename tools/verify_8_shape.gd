extends SceneTree

## 验证当前 road_data.gd 的 8 字形是否为期望的 lemniscate 图案
## 输出 user://current_road.svg 供人工目视核对（几何自检,不依赖任何外部参考文件）

const ROT_DEG := 60.0
const SCALE := 0.5
const CX := 400.0
const CY := 714.0

# 与 scripts/road_data.gd 中的 LEMNISCATE_LOCAL 保持一致
const LEMNISCATE_LOCAL: Array[Vector2] = [
	Vector2(0.0, 0.0),         Vector2(0.1305, 0.1682),   Vector2(0.2588, 0.325),
	Vector2(0.3827, 0.4596),   Vector2(0.5, 0.5629),      Vector2(0.6088, 0.6279),
	Vector2(0.7071, 0.65),     Vector2(0.7934, 0.6279),   Vector2(0.866, 0.5629),
	Vector2(0.9239, 0.4596),   Vector2(0.9659, 0.325),    Vector2(0.9914, 0.1682),
	Vector2(1.0, 0.0),         Vector2(0.9914, -0.1682),  Vector2(0.9659, -0.325),
	Vector2(0.9239, -0.4596),  Vector2(0.866, -0.5629),   Vector2(0.7934, -0.6279),
	Vector2(0.7071, -0.65),    Vector2(0.6088, -0.6279),  Vector2(0.5, -0.5629),
	Vector2(0.3827, -0.4596),  Vector2(0.2588, -0.325),   Vector2(0.1305, -0.1682),
	Vector2(0.0, 0.0),         Vector2(-0.1305, 0.1682),  Vector2(-0.2588, 0.325),
	Vector2(-0.3827, 0.4596),  Vector2(-0.5, 0.5629),     Vector2(-0.6088, 0.6279),
	Vector2(-0.7071, 0.65),    Vector2(-0.7934, 0.6279),  Vector2(-0.866, 0.5629),
	Vector2(-0.9239, 0.4596),  Vector2(-0.9659, 0.325),   Vector2(-0.9914, 0.1682),
	Vector2(-1.0, 0.0),        Vector2(-0.9914, -0.1682), Vector2(-0.9659, -0.325),
	Vector2(-0.9239, -0.4596), Vector2(-0.866, -0.5629),  Vector2(-0.7934, -0.6279),
	Vector2(-0.7071, -0.65),   Vector2(-0.6088, -0.6279), Vector2(-0.5, -0.5629),
	Vector2(-0.3827, -0.4596), Vector2(-0.2588, -0.325),  Vector2(-0.1305, -0.1682),
	Vector2(0.0, 0.0),
]
const LEMNISCATE_SCALE := 350.0
const LEMNISCATE_CX := 400.0
const LEMNISCATE_CY := 800.0
const STATION_IDX := [1, 4, 6, 9, 11, 12, 15, 18, 24, 27, 36, 39, 30, 42, 45, 47]
const INTERP := 20


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var current_pts := _build_current()
	var ref_pts := _build_reference()
	print("CURRENT_POINTS=%d" % current_pts.size())
	print("REFERENCE_POINTS=%d" % ref_pts.size())

	var min_x := INF; var min_y := INF
	var max_x := -INF; var max_y := -INF
	for p in current_pts + ref_pts:
		min_x = minf(min_x, p.x); max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y); max_y = maxf(max_y, p.y)
	print("CURRENT_X_RANGE=%.1f..%.1f Y_RANGE=%.1f..%.1f" % [min_x, max_x, min_y, max_y])

	var current_metrics := _compute_metrics(current_pts)
	var ref_metrics := _compute_metrics(ref_pts)
	print("===CURRENT=== ", current_metrics)
	print("===REFERENCE=== ", ref_metrics)

	_write_svg("user://current_road.svg", current_pts, ref_pts, STATION_IDX)
	print("WROTE user://current_road.svg")
	quit(0)


func _local_to_svg(p: Vector2) -> Vector2:
	var rot := deg_to_rad(ROT_DEG)
	var xr := p.x * cos(rot) - p.y * sin(rot)
	var yr := p.x * sin(rot) + p.y * cos(rot)
	return Vector2(LEMNISCATE_CX + xr * LEMNISCATE_SCALE,
		LEMNISCATE_CY + yr * LEMNISCATE_SCALE)


func _build_current() -> Array:
	# 沿 lemniscate 插值,与 road_data.gd._build_points 一致
	var out: Array = []
	var n = LEMNISCATE_LOCAL.size()
	for i in range(n - 1):
		var a: Vector2 = _local_to_svg(LEMNISCATE_LOCAL[i])
		var b: Vector2 = _local_to_svg(LEMNISCATE_LOCAL[i + 1])
		for k in range(INTERP):
			var t := float(k) / float(INTERP)
			out.append(Vector2(lerpf(a.x, b.x, t), lerpf(a.y, b.y, t)))
	var a2: Vector2 = _local_to_svg(LEMNISCATE_LOCAL[n - 2])
	var b2: Vector2 = _local_to_svg(LEMNISCATE_LOCAL[n - 1])
	out.append(Vector2(b2.x, b2.y))
	return out


func _build_reference() -> Array:
	# 参考基准 = LEMNISCATE_LOCAL 自身采样的 48 个线段点（自洽校验）
	var local: Array = []
	for i in range(1, LEMNISCATE_LOCAL.size()):
		local.append(LEMNISCATE_LOCAL[i])
	var out: Array = []
	for p in local:
		out.append(_local_to_svg(p))
	return out


func _compute_metrics(pts: Array) -> Dictionary:
	var min_x := INF; var max_x := -INF
	var min_y := INF; var max_y := -INF
	for p in pts:
		min_x = minf(min_x, p.x); max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y); max_y = maxf(max_y, p.y)
	var mid_x := (min_x + max_x) * 0.5
	var left_pts := []
	var right_pts := []
	for p in pts:
		if p.x < mid_x:
			left_pts.append(p)
		else:
			right_pts.append(p)
	return {
		"left_loop_center": _centroid(left_pts),
		"right_loop_center": _centroid(right_pts),
		"bbox": Vector4(min_x, min_y, max_x, max_y),
		"x_span": max_x - min_x,
		"y_span": max_y - min_y,
	}


func _centroid(pts: Array) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var sx := 0.0; var sy := 0.0
	for p in pts:
		sx += p.x; sy += p.y
	return Vector2(sx / pts.size(), sy / pts.size())


func _write_svg(path: String, current_pts: Array, ref_pts: Array, station_idx: Array) -> void:
	var s: Array[String] = []
	s.append('<svg xmlns="http://www.w3.org/2000/svg" viewBox="-46 -34 892 1800" width="400" height="800">')
	s.append('<rect x="-46" y="-34" width="892" height="1800" fill="#fafafa"/>')
	# 当前（lemniscate 沿曲线）
	s.append('<g stroke="#dc2626" stroke-width="3" fill="none" opacity="0.85">')
	s.append('<polyline points="')
	for i in range(current_pts.size()):
		s.append("%.1f,%.1f%s" % [current_pts[i].x, current_pts[i].y, " " if i < current_pts.size() - 1 else ""])
	s.append('"/>')
	s.append('</g>')
	# 参考（dashed）
	s.append('<g stroke="#1f2937" stroke-width="3" fill="none" opacity="0.85" stroke-dasharray="8 4">')
	s.append('<polyline points="')
	for i in range(ref_pts.size()):
		s.append("%.1f,%.1f%s" % [ref_pts[i].x, ref_pts[i].y, " " if i < ref_pts.size() - 1 else ""])
	s.append('"/>')
	s.append('</g>')
	# 16 驿站
	var frag_colors := ["#9e9e9e", "#9e9e9e", "#9e9e9e", "#9e9e9e", "#3b82f6", "#9e9e9e", "#9e9e9e", "#06b6d4", "#9e9e9e", "#9e9e9e", "#22c55e", "#9e9e9e", "#9e9e9e", "#16a34a", "#84cc16", "#15803d"]
	for i in range(station_idx.size()):
		var idx: int = station_idx[i]
		var pos: Vector2 = _local_to_svg(LEMNISCATE_LOCAL[idx])
		s.append('<circle cx="%.1f" cy="%.1f" r="6" fill="%s"/>' % [pos.x, pos.y, frag_colors[i]])
		s.append('<text x="%.1f" y="%.1f" font-size="12" fill="#C8443A">%d</text>' % [pos.x + 10, pos.y - 6, i + 1])
	s.append('</svg>')
	var f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("".join(s))
	f.close()