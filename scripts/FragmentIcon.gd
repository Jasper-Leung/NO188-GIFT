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
	paint_bird(self, Vector2.ZERO, col, alpha, 0.9)


## 禽那只鸟画过三遍：顶栏底栏（`FragmentBar._draw_bird`）、单碎片放大图
## （`FragmentIcon._draw_bird`）、明信片五格（`Postcard._draw_bird`）。
## 原来是**三份**画法，其中两份还是**两套不同的**——底栏与放大图是同一个
## 「一颗圆 + 一根棍」，明信片那份是「一颗填实的圆 + 一片同色的翅」。
## 两份都读不出是鸟：圆加棍读成棒棒糖，而明信片那份的翅膀是**同一个墨色**
## 画在身子上的，两块并成一颗疙瘩。云那一族是三份抄开的同算法，禽更糟：
## 玩家一路看着它长大，最后带走的那张纸上根本不是同一只东西。
##
## 所以形状收成**这一处** static，三处都调它。
static func paint_bird(ci: CanvasItem, c: Vector2, col: Color, a: float, sc: float) -> void:
	for part in bird_parts():
		var out := Color(col.r, col.g, col.b, a)
		match String(part["c"]):
			"wing": out = Color(1, 1, 1, a * 0.30)
			"eye": out = Color(1, 1, 1, a * 0.9)
		var pts := PackedVector2Array()
		match String(part["k"]):
			"line":
				ci.draw_line(c + Vector2(part["a"]) * sc, c + Vector2(part["b"]) * sc,
						out, float(part["w"]) * sc)
			"poly":
				for p in part["p"]:
					pts.append(c + Vector2(p) * sc)
				ci.draw_colored_polygon(pts, out)
			"ellipse":
				for i in range(28):
					var t := TAU * float(i) / 28.0
					pts.append(c + (Vector2(part["ctr"])
							+ Vector2(cos(t) * float(part["rx"]), sin(t) * float(part["ry"]))) * sc)
				ci.draw_colored_polygon(pts, out)
			"circle":
				ci.draw_circle(c + Vector2(part["ctr"]) * sc, float(part["r"]) * sc, out)


## 禽的单位设计坐标。**这一份同时是画法和不碰画笔的纯函数**，回归直接调它：
## `paint_bird` 只是把它重放一遍，而几何断言要量的正是这只剪影本身
## （有尾、有尖喙、有栖枝、翅是留白、整体落在 FragmentBar 那个 22px 盘里）。
##
## 认得出鸟要三样同时在，缺一样就退回一块墨：
##   · **尾**——楔子，往左下甩出去，和身子拉开角；没有它剪影上下左右对称，
##     读成一颗圆。
##   · **喙**——尖角，不是那根棍；棍状的东西接在圆上读成棒棒糖。
##   · **栖枝**——脚下那条横线。它给了这只鸟一个"站着"的地面，缺了它
##     剪影再对也读成一块漂浮的墨。
## 另有两条量得到的：身子是**椭圆**（rx > ry，正圆读成球），
## 翅是**留白**——墨色的翅压在墨色的身上等于没画，那正是明信片那份读不出来的
## 原因，也是这一族回归要单独钉住的一条。
static func bird_parts() -> Array:
	return [
		{"k": "line", "a": Vector2(-14, 14), "b": Vector2(14, 14), "w": 2.0, "c": "ink"},
		{"k": "line", "a": Vector2(-2, 5), "b": Vector2(-2, 13.5), "w": 1.2, "c": "ink"},
		{"k": "line", "a": Vector2(3, 5), "b": Vector2(3, 13.5), "w": 1.2, "c": "ink"},
		{"k": "poly", "p": PackedVector2Array([
			Vector2(3, 0), Vector2(-15, 12), Vector2(-14, 15), Vector2(5, 6)]), "c": "ink"},
		{"k": "ellipse", "ctr": Vector2(-1, -2), "rx": 11.0, "ry": 8.5, "c": "ink"},
		{"k": "circle", "ctr": Vector2(8, -9), "r": 6.0, "c": "ink"},
		{"k": "poly", "p": PackedVector2Array([
			Vector2(12, -11), Vector2(20, -8.5), Vector2(12, -6)]), "c": "ink"},
		{"k": "poly", "p": PackedVector2Array([
			Vector2(-7, -5), Vector2(-1, -8), Vector2(1, -1), Vector2(-6, 1)]), "c": "wing"},
		{"k": "circle", "ctr": Vector2(9.5, -10), "r": 1.4, "c": "eye"},
	]
