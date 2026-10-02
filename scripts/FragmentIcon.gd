extends Control
## FragmentIcon — 单碎片放大图 (F-15)
## 用法：new() 后设 fragment_idx / color / alpha，size 决定绘制基准，
## _draw 内部用 draw_set_transform 把 32px 设计坐标缩放到实际尺寸。
## 复用 FragmentBar 的小图标形态，但支持任意大小。

var fragment_idx: int = 0
var color: Color = Color.WHITE
var alpha: float = 1.0


func _draw() -> void:
	if size.x < 1.0:
		return
	var s = size.x / 32.0
	draw_set_transform(size / 2.0, 0.0, Vector2(s, s))
	var col = Color(color.r, color.g, color.b, alpha)
	match fragment_idx:
		0: _draw_cloud(col)
		1: _draw_teacup(col)
		2: _draw_guqin(col)
		3: _draw_bamboo(col)
		4: _draw_bird(col)


## 云：和 `Postcard._draw_cloud` 同一套鼓包、同一段轮廓算法，只是缩到 32px 基准。
## 这五件碎片在顶栏和明信片上各画一遍，两边**必须**是同一个形状 —— 玩家一路
## 收集的是云、最后带走的那张纸上却不是同一朵云，是在最贵的那一屏上拆台。
## 轮廓逐列取最上面的鼓包（详见 Postcard 那边的注释：别改成「每团各画半圆」，
## 相邻两团半径和大于圆心距，那样连出来是自交的线，三角化出 0 面积）。
func _draw_cloud(col: Color) -> void:
	var bumps := [
		[Vector2(-26.0, 5.0), 13.0],
		[Vector2(-9.0, -6.0), 19.0],
		[Vector2(10.0, -2.0), 15.0],
		[Vector2(24.0, 6.0), 9.0],
	]
	var sc := 0.44
	var base_y := 13.0 * sc
	var x0 := -38.0 * sc
	var x1 := 32.0 * sc
	var poly := PackedVector2Array()
	const STEPS := 48
	for i in range(STEPS + 1):
		var x := lerpf(x0, x1, float(i) / float(STEPS))
		var top := base_y
		for b in bumps:
			var r := float(b[1]) * sc
			var dx := x - float(b[0].x) * sc
			if absf(dx) < r:
				top = minf(top, float(b[0].y) * sc - sqrt(r * r - dx * dx))
		poly.append(Vector2(x, top))
	poly.append(Vector2(x1, base_y))
	poly.append(Vector2(x0, base_y))
	draw_colored_polygon(poly, col)
	draw_arc(Vector2(-9.0 * sc, -6.0 * sc), 12.0 * sc, PI * 1.12, PI * 1.62, 10,
			Color(1, 1, 1, alpha * 0.7), 2.0)


func _draw_teacup(col: Color) -> void:
	draw_arc(Vector2(0, 2), 10.0, 0, PI, 16, col, 2.0)
	draw_line(Vector2(-10, 2), Vector2(-10, -4), col, 2.0)
	draw_line(Vector2(10, 2), Vector2(10, -4), col, 2.0)
	draw_arc(Vector2(0, -4), 10.0, PI, TAU, 16, col, 2.0)
	draw_arc(Vector2(-14, -2), 4.0, -PI * 0.3, PI * 0.3, 8, col, 1.5)
	draw_arc(Vector2(-3, -10), 3.0, PI, TAU, 8, Color(1, 1, 1, alpha * 0.5), 1.0)


func _draw_guqin(col: Color) -> void:
	var pts = [
		Vector2(-18, 3), Vector2(-10, -5), Vector2(0, -7),
		Vector2(10, -5), Vector2(18, 3)
	]
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], col, 2.0)
	draw_line(pts[0], pts[4], col, 2.0)
	for j in range(4):
		var y = -4.0 + j * 2.5
		draw_line(Vector2(-14, y), Vector2(14, y), Color(1, 1, 1, alpha * 0.4), 1.0)


func _draw_bamboo(col: Color) -> void:
	for sx in range(-1, 2):
		var bx = sx * 9.0
		for n in range(4):
			var by = -14.0 + n * 10.0
			draw_line(Vector2(bx, by - 10.0), Vector2(bx, by + 4.0), col, 2.5)
			draw_line(Vector2(bx - 4.0, by), Vector2(bx + 4.0, by), col, 1.5)


func _draw_bird(col: Color) -> void:
	draw_arc(Vector2(0, 2), 9.0, 0, TAU, 16, col, 2.0)
	draw_line(Vector2(9, 2), Vector2(18, -2), col, 2.0)
	draw_line(Vector2(12, -4), Vector2(17, -9), col, 1.5)
	draw_line(Vector2(12, -4), Vector2(14, -8), col, 1.5)
	draw_arc(Vector2(18, -2), 3.0, -PI * 0.2, PI * 0.8, 8, col, 1.5)
