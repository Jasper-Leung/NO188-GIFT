extends Control
## FragmentIcon — 单碎片放大图 (F-15)
## 用法：new() 后设 fragment_idx / color / alpha，size 决定绘制基准。
## `_draw` 按 `extent(fragment_idx)`——这一件**实际占的那块矩形**——在两个方向
## 各算一次缩放比取小的那个，所以**框可以开成任何比例**；按控件中心对原点
## 是不行的，五件没有一件是中心对称的（竹偏下、禽偏右）。
## 复用 FragmentBar 的小图标形态，但支持任意大小。

var fragment_idx: int = 0
var color: Color = Color.WHITE
var alpha: float = 1.0


## 五件各自的**实际占位**（设计坐标，已乘 `paint_*` 的那个 sc 与半个线宽）。
##
## 这张表**不是事实来源**——`extent()` 才是，而它是从**画笔真正摆的那些点**
## 上并出来的（`cloud_outline` / `gaiwan_parts` / `guqin_parts` / `bamboo_parts`
## / `bird_parts` 五条都是不碰画笔的纯函数）。这张表只当**对拍**：回归拿它
## 逐值比 `extent()`，改一次形状而忘了改表，那条断言会红——而如果反过来
## （拿表当出处、几何从表里长出来），那张表就会安静地变成第二个事实来源
## （CLAUDE.md 里记过三次的同一条）。
##
## 量它这件事本身有教训：云那条轮廓本身**宽 98**（`sc = 0.40` 才缩回 ±19.6）、
## 禽的喙伸到 x +20、竹的叶梢在 y −15，**五件没有一件是 ±16**。旧版把缩放比
## 写成 `size.x / 32.0` 并按控件中心对原点，于是框开成任何比例都必然有一侧
## 溢出——正方形等于一分余量都没给。实测 56×56 那一版：云 左右各溢出 7.00px、琴 2.79、禽 1.14、茶 顶上 1.05，**竹根本不溢出**——溢出是**横向**的，云那一条最宽（设计坐标 40.0 宽，scale 1.75 → 70px 塞进 56px 的框）。
## `EndCard` 后来拿一个 48×92 的竖长条绕开了，绕的是**摆框**那一处，
## 可"缩放比只由宽决定"这条病还在（180×180 那一档禽的喙到 x≈202）。
const EXTENT := {
	0: Rect2(-20.0, -6.8, 40.0, 13.6),     # 云：轮廓 ×0.40
	1: Rect2(-14.11, -17.84, 28.22, 33.2), # 茶：盖碗 ×0.83（盖钮最高）
	2: Rect2(-17.25, -8.76, 35.19, 22.19),  # 琴：琴身+琴轸 ×0.85
	3: Rect2(-13.7, -13.78, 27.41, 30.01), # 竹：竹身+叶 ×0.82
	4: Rect2(-14.4, -14.4, 33.3, 28.8),    # 禽：剪影 ×0.9（喙伸到右）
}


## 这件东西在设计坐标里**实际占的那块矩形**（不碰画笔的纯函数）。
##
## 回归钉的是它而不是 `EXTENT` 那张表：表是手抄的，而这里是从画笔
## 真正摆出来的点上并出来的——改一次形状而忘了改表，那张表会安静地
## 变成第二个事实来源（CLAUDE.md 里记过三次的同一条）。
static func extent(idx: int) -> Rect2:
	match idx:
		0: return _grow(_rect_of_poly(cloud_outline(96)), 2.0, 0.40)
		1: return _grow(_rect_of_parts(gaiwan_parts()), 2.0, 0.83)
		2: return _grow(_rect_of_parts(guqin_parts()), 2.6, 0.85)
		3: return _grow(_rect_of_parts(bamboo_parts()), 1.6, 0.82)
		4: return _grow(_rect_of_parts(bird_parts()), 2.0, 0.90)
	return Rect2(-16.0, -16.0, 32.0, 32.0)


static func _grow(r: Rect2, stroke_w: float, sc: float) -> Rect2:
	# `r` 是**未乘 sc 的设计坐标**，而画笔在 `c + Vector2(p) * sc` 上落墨，
	# 所以**占位矩形的本体也要乘 sc**——只把线宽乘上去的话量到的是
	# 半个身子（云那条轮廓本身宽 98，漏了这一乘就成 ±49 而不是 ±19.6）。
	# 线宽的一半也要算进去：`draw_line` 的笔画从中心线往两边各铺半个线宽，
	# 而"占位"问的是墨落在哪儿，不是中心线落在哪儿。
	var rs := Rect2(r.position * sc, r.size * sc)
	var g := stroke_w * 0.5 * sc
	return rs.grow_individual(g, g, g, g)


static func _rect_of_poly(p: PackedVector2Array) -> Rect2:
	if p.is_empty():
		return Rect2()
	var r := Rect2(p[0], Vector2.ZERO)
	for i in range(1, p.size()):
		r = r.expand(p[i])
	return r


static func _rect_of_parts(parts: Array) -> Rect2:
	var acc := Rect2()
	var first := true
	for part in parts:
		var k := String(part["k"])
		var got := Rect2()
		if k == "poly":
			got = _rect_of_poly(part["p"])
		elif k == "line":
			got = _rect_of_poly(PackedVector2Array([part["a"], part["b"]]))
		elif k == "circle":
			var c: Vector2 = part["ctr"]
			var rad := float(part["r"])
			got = Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2.0)
		elif k == "ellipse":
			var ec: Vector2 = part["ctr"]
			var er := Vector2(float(part["rx"]), float(part["ry"]))
			got = Rect2(ec - er, er * 2.0)
		else:
			continue
		if first:
			acc = got
			first = false
		else:
			acc = acc.merge(got)
	return acc


## 这一件在 `box` 那个尺寸里**实际会画到的那块矩形**（控件局部坐标）。
##
## 回归调的是这个函数而不是把算式抄一遍——抄一遍就等于给了它一个能自己漂的
## 机会，而"`_draw` 的几何对而画笔没去调它"本来就是这一族量不到的东西
## （回归另有两条读源码文本的钉子，见 `verify_postcard_ending.gd` 第 4 节）。
static func drawn_rect(idx: int, box: Vector2) -> Rect2:
	var ext: Rect2 = extent(idx)
	var s: float = minf(box.x / ext.size.x, box.y / ext.size.y)
	var org: Vector2 = box * 0.5 - (ext.position + ext.size * 0.5) * s
	return Rect2(org + ext.position * s, ext.size * s)


func _draw() -> void:
	if size.x < 1.0 or size.y < 1.0:
		return
	# **两个方向各自算，取小的那个**——不是按宽，也不是按 32 的定数。
	# 按宽算的话高瘦的框会把上下溢出，按 32 算的话五件没有一件装得下
	# （见 `EXTENT` 那段注释）。中心也取**占位矩形的中心**而不是控件中心：
	# 竹偏下、禽偏右 2.25，按控件中心摆它们整体偏一边。
	var ext: Rect2 = extent(fragment_idx)
	var s: float = minf(size.x / ext.size.x, size.y / ext.size.y)
	draw_set_transform(size / 2.0 - (ext.position + ext.size * 0.5) * s,
			0.0, Vector2(s, s))
	var col = Color(color.r, color.g, color.b, alpha)
	match fragment_idx:
		0: paint_cloud(self, Vector2.ZERO, col, alpha, 0.40)
		1: paint_gaiwan(self, Vector2.ZERO, col, alpha, 0.83)
		2: paint_guqin(self, Vector2.ZERO, col, alpha, 0.85)
		3: paint_bamboo(self, Vector2.ZERO, col, alpha, 0.82)
		4: _draw_bird(col)


# ══════════════════════════════════════════════════════════════════════
# 云 / 茶 / 琴：三件从「三份手抄」收成**一个出处**，形状本身也重画过
# ══════════════════════════════════════════════════════════════════════
#
# 收口的理由和禽是同一条，但这一族更糟：**三份不是三份抄写，是三套算法**。
# 禽那三份里两份各画各的（棒棒糖 vs 疙瘩），对拍永远绿——两份各自自洽。
# 云/茶/琴这三件在 `FragmentBar` / `FragmentIcon` / `Postcard` 里各有一份，
# 而这一轮（第四轮 P0-2）逐张放大看下来，**三件读不出自己是什么**：
#   · 云 = 一个几乎处处外凸的土包（相邻鼓包半径和远大于圆心距，凹口全被填平）
#   · 茶 = 上下两个**半径相同、圆心差 6px** 的半圆弧拼出来的透镜，不是杯子
#   · 琴 = 五个点对称分布的透镜 + 底边 = 一座山
# 而 `verify_mini_game.gd` 6g 节的判据全绿，因为它们量的是「不是多边形」
# ——**判「是不是云」和判「是不是多边形」是两个量，那一族只写了后者。**
#
# 所以这一族每件都有两样东西：
#   · `*_parts()` / `cloud_outline()` —— **不碰画笔的纯函数**，回归直接调它，
#     量的是剪影本身（凹口深不深、对不对称、装不装得进 22px 的盘）；
#   · `paint_*()` —— 只是把它重放一遍。**判据钉纯函数，钉不住调用点**，
#     所以另有三条读源码文本的钉子（见 verify_mini_game.gd 6k 节）。
#
# 规范空间：云半宽 43，琴/茶最大半径 ~20，三个文件共用；每处调用方按自己
# 要的显示大小给 `sc`（见各处那一行的注释）。**别在三个文件里各记一个魔数**
# ——记了就会漂，而漂了没有任何几何断言看得见（禽那次的教训）。

# ---------------------------------------------------------------- 云
## 四团鼓包。**这四个数是量出来的**，不是画出来的：相邻两团的圆心距必须
## 接近半径和，凹口才留得下来。原来那组（圆心距 17/19/14，半径和 32/34/24）
## 量出来是 **2 个峰、1 个凹口、深 0.36**——也就是"几乎没有"。
## 现在这组量出来是 **4 个峰、3 个凹口、深 2.9 / 3.3 / 4.3**。
## 改任何一个数都要重跑 `cloud_notch_depths()` 确认凹口还在。
const CLOUD_BUMPS := [
	Vector3(-33.0, 0.0, 10.0),   # x, y, r
	Vector3(-11.0, 0.0, 16.0),   # 主体，最高
	Vector3(11.0, 0.0, 13.0),
	Vector3(33.0, 0.0, 10.0),    # 尾巴
]
## 平底线。云的影子就在脚下，而**平底正是云和烟唯一的区别**——
## 叠圆按定义接不出平底，所以这一行不是装饰。
const CLOUD_BASE := 16.0


## 云的**单位轮廓**。逐列取最上面的鼓包（minf），拼出一条不自交的闭合线。
## 别改成「每团各画一段上半圆再首尾相连」：后一团的起点会落在前一团终点的
## 左边，连出来的是一条自己压自己的线，三角化直接失败——第一版就是这么画成
## 一根线的，而且不报任何错。
static func cloud_outline(samples: int = 96) -> PackedVector2Array:
	var r_max := 0.0
	for b: Vector3 in CLOUD_BUMPS:
		r_max = maxf(r_max, b.z)
	var x0: float = CLOUD_BUMPS[0].x - r_max
	var x1: float = CLOUD_BUMPS[CLOUD_BUMPS.size() - 1].x + r_max
	var poly := PackedVector2Array()
	for i in range(samples + 1):
		var x := lerpf(x0, x1, float(i) / float(samples))
		var top := CLOUD_BASE
		for b: Vector3 in CLOUD_BUMPS:
			var dx: float = x - b.x
			if absf(dx) < b.z:
				top = minf(top, b.y - sqrt(b.z * b.z - dx * dx))
		poly.append(Vector2(x, top))
	poly.append(Vector2(x1, CLOUD_BASE))
	poly.append(Vector2(x0, CLOUD_BASE))
	return poly


## 轮廓的峰 / 谷与凹口深度（纯函数，回归直接调）。
## 返回 {"peaks": int, "notches": int, "depths": […]}
static func cloud_notch_depths(samples: int = 2400) -> Dictionary:
	var poly := cloud_outline(samples)
	var top := PackedVector2Array()
	for p in poly:
		if p.y < CLOUD_BASE - 0.001:
			top.append(p)
	var peaks: Array = []
	var valleys: Array = []
	for i in range(1, top.size() - 1):
		if top[i].y < top[i - 1].y and top[i].y < top[i + 1].y:
			peaks.append(top[i])
		elif top[i].y > top[i - 1].y and top[i].y > top[i + 1].y:
			valleys.append(top[i])
	var depths: Array = []
	for i in range(peaks.size() - 1):
		var a: Vector2 = peaks[i]
		var b: Vector2 = peaks[i + 1]
		var seg: Array = []
		for v in valleys:
			if a.x < v.x and v.x < b.x:
				seg.append(v)
		if seg.is_empty():
			depths.append(0.0)
			continue
		var worst: Vector2 = seg[0]
		for v in seg:
			if v.y > worst.y:
				worst = v
		depths.append(worst.y - maxf(a.y, b.y))
	return {"peaks": peaks.size(), "notches": valleys.size(), "depths": depths}


static func paint_cloud(ci: CanvasItem, c: Vector2, col: Color, a: float, sc: float) -> void:
	ci.draw_colored_polygon(_xform(cloud_outline(96), c, sc),
			Color(col.r, col.g, col.b, a))
	# 主体左上一道留白，跟另外几个线描图标的高光笔触一致
	ci.draw_arc(c + Vector2(-11.0, -6.0) * sc, 11.0 * sc, PI * 1.12, PI * 1.62, 12,
			Color(1, 1, 1, a * 0.55), 2.0 * sc)


# ---------------------------------------------------------------- 茶（盖碗）
## 茶烟小筑端的是盖碗，不是茶壶。**这不是审美选择，是可辨识性的量**：
## 壶的辨识特征是壶嘴和壶把两个小构件，而它们在 22px 的盘上必然消失
## （原来那个把手只占图标宽度的 5%、水位线占面积的 1.5%），剩下的就是
## 「上下两个等半径的半圆弧」——一个透镜。盖碗的剪影是**盖 + 碗 + 圈足**，
## 三样都是大块面，任何尺寸下都不会读错。
const GAIWAN := {
	"lid_cy": -6.5, "lid_rx": 16.0, "lid_ry": 10.0,   # 盖：一个半椭圆
	"gap": 1.5,                                        # 盖与碗之间留一道缝
	"knob": Vector2(0.0, -17.5), "knob_r": 3.0,       # 盖钮
	"bowl_cy": -5.0, "bowl_rx": 15.0, "bowl_ry": 17.0, # 碗
	"bowl_flat": 11.0,                                 # 碗底压平（圈足接在上面）
	"foot_half": 7.0, "foot_y": 17.5,
}


## 盖碗的剪影（不碰画笔的纯函数）：盖 / 碗+圈足两个多边形 + 一个盖钮圆。
## **盖和碗之间那道 1.5 的缝是刻意的**——连成一体就分不出哪是盖，
## 而"分得出盖"正是盖碗区别于碗的地方。缝在 22px 的盘上还剩 1.3px。
static func gaiwan_parts() -> Array:
	var g: Dictionary = GAIWAN
	var parts: Array = []
	# 盖
	var lid := PackedVector2Array()
	const LID_STEPS := 28
	for i in range(LID_STEPS + 1):
		var t := PI + PI * float(i) / float(LID_STEPS)   # PI..TAU = 上半圈
		lid.append(Vector2(cos(t) * float(g["lid_rx"]),
				float(g["lid_cy"]) + sin(t) * float(g["lid_ry"])))
	parts.append({"k": "poly", "p": lid, "c": "ink"})
	# 盖钮
	parts.append({"k": "circle", "ctr": g["knob"], "r": g["knob_r"], "c": "ink"})
	# 碗 + 圈足：碗的弧到 flat 就压平，然后把圈足接在平底上
	var bowl := PackedVector2Array()
	const BOWL_STEPS := 28
	var flat := float(g["bowl_flat"])
	for i in range(BOWL_STEPS + 1):
		var t2 := PI * float(i) / float(BOWL_STEPS)      # PI..TAU = 下半圈
		bowl.append(Vector2(cos(t2) * float(g["bowl_rx"]),
				minf(float(g["bowl_cy"]) + sin(t2) * float(g["bowl_ry"]), flat)))
	# 压平之后底边是一条从右到左的横线，圈足从这里长出去
	var fh := float(g["foot_half"])
	var fy := float(g["foot_y"])
	bowl.append(Vector2(fh, flat))
	bowl.append(Vector2(fh, fy))
	bowl.append(Vector2(-fh, fy))
	bowl.append(Vector2(-fh, flat))
	parts.append({"k": "poly", "p": bowl, "c": "ink"})
	return parts


static func paint_gaiwan(ci: CanvasItem, c: Vector2, col: Color, a: float, sc: float) -> void:
	for part in gaiwan_parts():
		var out := Color(col.r, col.g, col.b, a)
		var pts := PackedVector2Array()
		match String(part["k"]):
			"poly":
				for p in part["p"]:
					pts.append(c + Vector2(p) * sc)
				ci.draw_colored_polygon(pts, out)
			"circle":
				ci.draw_circle(c + Vector2(part["ctr"]) * sc,
						float(part["r"]) * sc, out)
	# 碗里那道水面：一道**亮一截**的横线，跟着碗身的实际半宽走。
	# 旧版把它画成一个半径 3px 的小弧——占图标面积 1.5%，在 22px 上不存在。
	var g: Dictionary = GAIWAN
	var y := float(g["bowl_cy"]) + float(g["bowl_ry"]) * 0.45
	ci.draw_line(c + Vector2(-float(g["bowl_rx"]) * 0.72, y) * sc,
			c + Vector2(float(g["bowl_rx"]) * 0.72, y) * sc,
			Color(1, 1, 1, a * 0.5), 1.6 * sc)


# ---------------------------------------------------------------- 琴
## 古琴的辨识特征是**不对称**：琴额（头）那端方而宽，琴尾那端收细，
## 底下两只雁足。原来的五点 `(−18,3)(−10,−5)(0,−7)(10,−5)(18,3)` 是
## 上下左右全对称的透镜，加一条底边之后读成**一座山**——三样特征一个都没有。
const GUQIN_BODY := [
	Vector2(-19.0, -5.5), Vector2(-12.0, -8.0), Vector2(-1.0, -9.0),
	Vector2(9.0, -7.0), Vector2(17.0, -3.0),          # 上缘（弦面）：头高尾低
	Vector2(17.0, 0.5), Vector2(10.0, 4.5), Vector2(-1.0, 7.5),
	Vector2(-19.0, 3.0),                               # 下缘：也是头高尾低
]
## 雁足。四只坐标**逐个对过 `GUQIN_BODY` 的下缘**——脚必须整个落在木头下面，
## 而"落在下面"是相对的：下缘在 x=-8 处是 y≈5.8、在 x=6 处是 y≈5.6，
## 写死一个 y 的话，改一次琴身形状脚就会重新爬到木头上去（这正是
## `MiniGameZither.foot_polys()` 踩过的坑：注释写着"挂在琴腹以下"，
## 而那个常数 `tail_h * 0.55` 仍在木头里面）。
const GUQIN_FEET := [
	[Vector2(-10.5, 6.6), Vector2(-10.5, 13.5), Vector2(-6.0, 14.5), Vector2(-6.0, 7.6)],
	[Vector2(3.5, 6.6), Vector2(3.5, 13.5), Vector2(8.0, 13.5), Vector2(8.0, 6.0)],
]
const GUQIN_STRINGS := 4
const GUQIN_Y0 := -6.0
const GUQIN_DY := 2.9


static func guqin_parts() -> Array:
	return [
		{"k": "poly", "p": PackedVector2Array(GUQIN_BODY), "c": "ink"},
		{"k": "poly", "p": PackedVector2Array(GUQIN_FEET[0]), "c": "ink"},
		{"k": "poly", "p": PackedVector2Array(GUQIN_FEET[1]), "c": "ink"},
		{"k": "line", "a": Vector2(-17.0, -5.0), "b": Vector2(-17.0, 3.0),
			"w": 2.6, "c": "ink"},                          # 岳山
		{"k": "circle", "ctr": Vector2(18.0, 1.5), "r": 1.8, "c": "ink"},  # 琴轸
		{"k": "circle", "ctr": Vector2(18.0, 5.0), "r": 1.8, "c": "ink"},
	]


## 琴身下缘在某个 x 处的高度（纯函数）。判"脚有没有落在木头下面"要用它，
## 因为下缘是斜的——拿一个 y 去比整条边，量的是"脚在不在某一个高度以下"，
## 不是"脚在不在木头下面"。
static func guqin_bottom_at(x: float) -> float:
	var b := GUQIN_BODY
	for i in range(4, b.size() - 1):
		var p: Vector2 = b[i]
		var q: Vector2 = b[i + 1]
		if minf(p.x, q.x) <= x and x <= maxf(p.x, q.x):
			var t := 0.0 if is_equal_approx(p.x, q.x) else (x - p.x) / (q.x - p.x)
			return lerpf(p.y, q.y, t)
	return b[b.size() - 1].y


## 琴身**上缘**在某个 x 处的高度（纯函数）。判"琴是不是对称的"要用它：
## 上下左右全对称的透镜（原来那五点）加一条底边之后读出来是一座山，
## 而古琴的辨识特征恰恰是**头高尾低**——两头的高度差就是那把尺子。
static func guqin_top_at(x: float) -> float:
	var b := GUQIN_BODY
	for i in range(4):
		var p: Vector2 = b[i]
		var q: Vector2 = b[i + 1]
		if minf(p.x, q.x) <= x and x <= maxf(p.x, q.x):
			var t := 0.0 if is_equal_approx(p.x, q.x) else (x - p.x) / (q.x - p.x)
			return lerpf(p.y, q.y, t)
	return b[0].y if x < b[0].x else b[4].y


## 琴身**上缘**在某个 y 处能伸到多远（纯函数）。弦必须按这个裁：
## 按整块 board 的全宽画的话，弦两头都戳在木头外面，而四个金色键位提示
## 正好落在弦的末端上，看起来像琴上镶了四枚金属钉。
static func guqin_string_half(y: float) -> float:
	var b := GUQIN_BODY
	var lo := 0.0
	for i in range(4):
		var p: Vector2 = b[i]
		var q: Vector2 = b[i + 1]
		if minf(p.y, q.y) <= y and y <= maxf(p.y, q.y):
			var t := 0.0 if is_equal_approx(p.y, q.y) else (y - p.y) / (q.y - p.y)
			var x := lerpf(p.x, q.x, t)
			lo = maxf(lo, absf(x))
	var hi := 0.0
	for i in range(4, b.size() - 1):
		var p: Vector2 = b[i]
		var q: Vector2 = b[i + 1]
		if minf(p.y, q.y) <= y and y <= maxf(p.y, q.y):
			var t := 0.0 if is_equal_approx(p.y, q.y) else (y - p.y) / (q.y - p.y)
			var x2 := lerpf(p.x, q.x, t)
			hi = maxf(hi, absf(x2))
	return minf(lo, hi) if lo > 0.0 and hi > 0.0 else minf(lo if lo > 0.0 else 99.0,
			hi if hi > 0.0 else 99.0)


static func paint_guqin(ci: CanvasItem, c: Vector2, col: Color, a: float, sc: float) -> void:
	for part in guqin_parts():
		var out := Color(col.r, col.g, col.b, a)
		var pts := PackedVector2Array()
		match String(part["k"]):
			"line":
				ci.draw_line(c + Vector2(part["a"]) * sc, c + Vector2(part["b"]) * sc,
						out, float(part["w"]) * sc)
			"poly":
				for p in part["p"]:
					pts.append(c + Vector2(p) * sc)
				ci.draw_colored_polygon(pts, out)
			"circle":
				ci.draw_circle(c + Vector2(part["ctr"]) * sc,
						float(part["r"]) * sc, out)
	# 四根弦，两端按**琴身在这一 y 处的实际半宽**收进去。
	# 亮一截的白弦：琴身是填实的，白弦压在它上面在深色盘和浅纸上都读得出。
	for j in range(GUQIN_STRINGS):
		var y := GUQIN_Y0 + float(j) * GUQIN_DY
		var half := guqin_string_half(y) - 1.2
		ci.draw_line(c + Vector2(-half, y) * sc, c + Vector2(half, y) * sc,
				Color(1, 1, 1, a * 0.55), 1.2 * sc)


static func _xform(pts: PackedVector2Array, c: Vector2, sc: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + p * sc)
	return out


func _draw_bird(col: Color) -> void:
	paint_bird(self, Vector2.ZERO, col, alpha, 0.9)


# ══════════════════════════════════════════════════════════════════════
# 竹：收成**一个出处**，并且按「22px 的盘上认不认得出」重画
# ══════════════════════════════════════════════════════════════════════
#
# 第五轮 P0-3：底栏那个 22px 的盘上，竹读成**一张窗格**。
#
# 原来三份画法里有**两份是逐字相同的同一套算法**（`FragmentBar` 与
# `FragmentIcon`），第三份（`Postcard`）多两片叶。而那套算法是
# **三根等宽竖线，每根再横划四道节**——3 根竖 × 12 道横节在 22px 上
# 就是一张窗格。第四轮判它「✓」看的是**明信片上的大尺寸**，那一版有叶子；
# 而玩家一路盯着的是底栏。同一件东西在两个尺寸上读成两样东西，
# 这一族问题的第四份（前三份是禽、云/茶/琴）。
#
# 更麻烦的是**两份坏的那份还一模一样**——对拍那两份永远绿，
# 它们本来就一样，而「一样」的那一份是坏的。收口之后三处调同一个出处。
#
# 认得出竹要三样同时在，缺一样就退回一根绿色的棍：
#   · **收分**——竹身自下而上收窄（底 2.4 → 梢 1.0）。等宽竖条是柱子不是竹子。
#     这一条是评审点名要量的：「量三根竖条的**收分**，而不是量有几道节」。
#   · **节少而粗**——每根**两道**，不是四道。节是竹子身上最认得出的一处，
#     可三根一排各划四道，它就成了窗棂；两道只够读成"这根是一节一节长的"。
#   · **叶**——长而窄（长约 3.3 倍宽），挂在梢那一段往外斜。
#     这个尺寸上唯一认得出「竹」而不是「栅栏」的东西，缺了它三条竖线就是栅栏。
#
# 规范空间与云/茶/琴/禽共用：全部落在半径 22 之内（`FragmentBar` 那个盘的
# 盘外 23~26.5m 是"这一格是哪一件"的扫视信号，图标伸进去就把那条判据量废了）。
## 三根竹身落在哪。间距 7.5 是被**两道节不许并成一条横线**卡的：
## 节最宽那处（下面那道）的半宽是 `BAMBOO_NODE_W * hw(y)`，两倍之后要
## 小于间距，否则中间那道和右边那道会连成一根横贯的杠——那正是窗棂。
const BAMBOO_X := [-7.5, 0.0, 7.5]
## 竹身：底 y=19 / 半宽 2.2，梢 y=−16 / 半宽 1.0。**收分比 2.2。**
##
## `Y0`/`HW0` 是被**盘沿**卡的，而卡住它的是**竹身底部的外角**而不是叶梢：
## 外角在 `(7.5+2.2, 19)` → 半径 21.4。第一版写的是 `Y0=21` / `HW0=2.4`，
## 而当时只算了叶梢（21.1）就宣布"装得进 22px 的盘"——**外角在 23.2，
## 已经伸进 `FragmentBar` 盘外 23~26.5m 那一圈扫视信号里了**。
## 可推广的一条：**判"这个剪影装不装得进盘"，最远点往往是某根杆子的角，
## 不是你以为的那个叶尖。**
const BAMBOO_Y0 := 19.0
const BAMBOO_Y1 := -16.0
const BAMBOO_HW0 := 2.2
const BAMBOO_HW1 := 1.0
## 竹节两道。只列 y，横向半宽由那一处的竹身宽推出来（`bamboo_half_width`），
## 所以「节比竹身宽多少倍」是一条**算出来的关系**而不是抄出来的数——
## 改竹身的收分，节跟着变，而两处不会各自漂。
const BAMBOO_NODES := [9.0, 1.0]
## 节比那一处竹身宽几倍（半宽的倍数）。1.7 是被上面那道"不许并成一条横线"
## 卡出来的：1.8 就并了。判"节看得见"量的不是这个数，是**节两侧各探出
## 竹身多少**（`(W-1)*hw`），因为缩进竹身里的节等于没画。
const BAMBOO_NODE_W := 1.7
## 竹叶：每根两片。**方向是逐根定的不是算出来的**——外侧那两根朝外，
## 中间那根一左一右；全按 `sign(x)` 的话中间那根的两片都朝右，
## 正好压在右边那根身上，三根就读成两根。
const BAMBOO_LEAVES := [
	# [竹身 x, 叶根 y, 朝向]
	[-7.5, -9.0, -1.0], [-7.5, -4.0, -1.0],
	[0.0, -9.0, -1.0], [0.0, -4.0, 1.0],
	[7.5, -9.0, 1.0], [7.5, -4.0, 1.0],
]
## 一片叶：从叶根往外伸的方向向量（未归一）与半宽。伸 7、垂 5 → 长 8.6，
## 半宽 1.3 → 宽 2.6，**长宽比 3.3**。比再小就读成三根分叉的棍子，
## 比再大在这个尺寸上就是一块补丁。
const BAMBOO_LEAF_REACH := Vector2(7.0, -5.0)
const BAMBOO_LEAF_HW := 1.3


## 竹的设计坐标。**这一份同时是画法和不碰画笔的纯函数**，回归直接调它：
## `paint_bamboo` 只是把它重放一遍，而几何断言量的正是这个剪影本身。
static func bamboo_parts() -> Array:
	var out: Array = []
	for sx in BAMBOO_X:
		var x: float = sx
		out.append({"k": "poly", "c": "stalk", "p": PackedVector2Array([
			Vector2(x - BAMBOO_HW0, BAMBOO_Y0), Vector2(x + BAMBOO_HW0, BAMBOO_Y0),
			Vector2(x + BAMBOO_HW1, BAMBOO_Y1), Vector2(x - BAMBOO_HW1, BAMBOO_Y1)])})
		for ny in BAMBOO_NODES:
			var hw: float = bamboo_half_width(float(ny))
			out.append({"k": "line", "c": "node",
					"a": Vector2(x - hw * BAMBOO_NODE_W, float(ny)),
					"b": Vector2(x + hw * BAMBOO_NODE_W, float(ny)), "w": 1.6})
	for lf in BAMBOO_LEAVES:
		var lx: float = lf[0]
		var ly: float = lf[1]
		var side: float = lf[2]
		var root := Vector2(lx + side * bamboo_half_width(ly), ly)
		var dir: Vector2 = Vector2(BAMBOO_LEAF_REACH.x * side, BAMBOO_LEAF_REACH.y)
		var perp: Vector2 = dir.orthogonal().normalized() * BAMBOO_LEAF_HW
		out.append({"k": "poly", "c": "leaf",
				"p": PackedVector2Array([root + perp, root + dir, root - perp])})
	return out


## 竹身在高度 y 处的半宽。节点那道横杠按它取，所以「节比竹身宽 1.5 倍」
## 是一条真算出来的关系而不是抄出来的数——改竹身的收分，两道节跟着变。
static func bamboo_half_width(y: float) -> float:
	var t: float = clampf((y - BAMBOO_Y1) / (BAMBOO_Y0 - BAMBOO_Y1), 0.0, 1.0)
	return lerpf(BAMBOO_HW1, BAMBOO_HW0, t)


static func paint_bamboo(ci: CanvasItem, c: Vector2, col: Color, a: float,
		sc: float) -> void:
	var out := Color(col.r, col.g, col.b, a)
	for part in bamboo_parts():
		match String(part["k"]):
			"poly":
				ci.draw_colored_polygon(_xform(part["p"], c, sc), out)
			"line":
				ci.draw_line(c + Vector2(part["a"]) * sc, c + Vector2(part["b"]) * sc,
						out, float(part["w"]) * sc)


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
