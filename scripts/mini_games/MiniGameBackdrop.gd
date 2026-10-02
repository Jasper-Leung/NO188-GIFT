extends RefCounted
## MiniGameBackdrop — 五个小游戏各自的"地方"。
##
## 原来五个小游戏都在一块 0.7 alpha 的黑幕上作画，于是「雨后台阶看云」「朋友来了
## 先煮茶」「把风声听成琴音」全都长一个样：黑底 + 一个图形 + 一行字。玩家刚在
## 云影台看过台阶上的云，进了茶烟小筑却还是那片黑，五个乐事之间没有任何距离感。
##
## 这里给每件乐事一个**不透明**的景：天光渐变 + 一道远景剪影 + 几样本地的东西。
## 必须不透明 —— `World3D._make_mini_game_backdrop()` 那层是 0.93 alpha，
## 底下 7% 的 3D 世界会透上来（截图里能看见车和草丛），那看着像没画完。
##
## 只画远景和底色，不画玩法元素：玩法元素还得压在最上面。

const SKY := 4      ## 渐变分几段
const BANDS := 3    ## 远景剪影分几层

## 主题下标。**只在这一份**里定义，别在五个小游戏里各写一个数字 ——
## 顺序和 THEMES 一一对应，改一处漏一处的话那一屏会静默画成另一件乐事的景。
const CLOUD := 0    ## 云影台
const TEA := 1      ## 茶烟小筑
const ZITHER := 2   ## 琴音林
const BAMBOO := 3   ## 竹雨庭
const BIRD := 4     ## 花房·禽语湖湾

## 五件乐事各一套配色。顺序 0..4 与碎片顺序 云/茶/琴/竹/禽 一致。
const THEMES := [
	# 0 云 · 云影台：雨后初霁，高台上一片被洗过的淡蓝
	{"top": Color("9FC3DC"), "bot": Color("E4EEF2"), "far": Color("7E9DAF"), "mid": Color("5E7D8C")},
	# 1 茶 · 茶烟小筑：灶上的暖黄，屋里比屋外亮
	{"top": Color("3B2C20"), "bot": Color("6B4E33"), "far": Color("8A6540"), "mid": Color("4A3626")},
	# 2 琴 · 琴音林：林子里的暮色，风把叶子翻过来是亮的
	{"top": Color("2A3A33"), "bot": Color("546B52"), "far": Color("3E5647"), "mid": Color("26362C")},
	# 3 竹 · 竹雨庭：夜雨，湿的、发亮的
	{"top": Color("141C1E"), "bot": Color("2E3A38"), "far": Color("222D2C"), "mid": Color("161E1F")},
	# 4 禽 · 花房·禽语湖湾：天刚亮，湖面比天暗
	{"top": Color("5C7A93"), "bot": Color("D9C9AE"), "far": Color("7E94A3"), "mid": Color("4E6069")},
]


static func draw_scene(ci: CanvasItem, w: float, h: float, theme_idx: int) -> void:
	var t: Dictionary = THEMES[clampi(theme_idx, 0, THEMES.size() - 1)]
	# 天光渐变
	for i in SKY:
		var k0 := float(i) / float(SKY)
		var k1 := float(i + 1) / float(SKY)
		var col: Color = t["top"].lerp(t["bot"], k0)
		ci.draw_rect(Rect2(0.0, h * k0, w, h * (k1 - k0) + 1.0), col, true)
	# 两层远景：远的一层更淡（空气透视），近的一层更沉
	_horizon(ci, w, h, h * 0.62, t["far"])
	_horizon(ci, w, h, h * 0.74, t["mid"])
	match theme_idx:
		0: _clouds(ci, w, h)
		1: _steam(ci, w, h, t)
		2: _grove(ci, w, h, t)
		3: _rain(ci, w, h, t)
		4: _water(ci, w, h, t)


## 一层起伏的地面/山脊剪影。振幅和波长都随宽度走，换分辨率不会变形。
static func _horizon(ci: CanvasItem, w: float, h: float, base_y: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 48
	for i in steps + 1:
		var t := float(i) / float(steps)
		var y := base_y + sin(t * 7.0 + base_y * 0.01) * h * 0.022 \
				+ sin(t * 19.0) * h * 0.010
		pts.append(Vector2(w * t, y))
	pts.append(Vector2(w, h))
	pts.append(Vector2(0.0, h))
	ci.draw_colored_polygon(pts, col)


static func _clouds(ci: CanvasItem, w: float, h: float) -> void:
	for i in 5:
		var cx := w * (0.08 + 0.21 * float(i)) + sin(float(i) * 2.1) * w * 0.04
		var cy := h * (0.12 + 0.07 * float(i % 3))
		var r := h * (0.045 + 0.02 * float(i % 2))
		ci.draw_circle(Vector2(cx, cy), r, Color(1, 1, 1, 0.42))
		ci.draw_circle(Vector2(cx + r * 0.9, cy + r * 0.18), r * 0.74, Color(1, 1, 1, 0.30))
		ci.draw_circle(Vector2(cx - r * 0.85, cy + r * 0.26), r * 0.62, Color(1, 1, 1, 0.26))


static func _steam(ci: CanvasItem, w: float, h: float, t: Dictionary) -> void:
	# 屋里另外两处灶烟。**避开正中**：茶壶在 w*0.5，而这三道原来正好排在
	# 0.30/0.50/0.70，中间那道从壶后面笔直穿上去，图上读成三道划痕而不是烟。
	# 排到两侧 + 压低不透明度之后才是背景，主角是那只壶。
	for i in 2:
		var bx := w * (0.17 if i == 0 else 0.83)
		var pts := PackedVector2Array()
		for s in range(13):
			var k := float(s) / 12.0
			pts.append(Vector2(bx + sin(k * 4.0 + float(i) * 2.0) * w * 0.028 * k,
					h * 0.58 - k * h * 0.26))
		ci.draw_polyline(pts, Color(1, 0.94, 0.84, 0.10 - 0.03 * float(i)), 3.0)
	# 桌面：一条暖色的横带，把下半截压住
	ci.draw_rect(Rect2(0.0, h * 0.80, w, h * 0.20), t["mid"].darkened(0.10), true)


static func _grove(ci: CanvasItem, w: float, h: float, t: Dictionary) -> void:
	# 几竿竹叶的剪影，从下往上斜着插进画面
	for i in 4:
		var bx := w * (0.06 + 0.26 * float(i))
		var lean := w * (0.05 if i % 2 == 0 else -0.04)
		ci.draw_line(Vector2(bx, h), Vector2(bx + lean, h * 0.52),
				t["mid"].darkened(0.18), 5.0)
		for n in range(3):
			var ky := h * (0.86 - 0.10 * float(n))
			var kx := lerpf(bx, bx + lean, 1.0 - ky / h)
			ci.draw_line(Vector2(kx, ky), Vector2(kx + lean * 0.7 * (1 if n % 2 == 0 else -1), ky - h * 0.03),
					t["mid"].darkened(0.10), 3.0)


static func _rain(ci: CanvasItem, w: float, h: float, t: Dictionary) -> void:
	# 雨：一批斜线，按 y 错开，看起来是下着的而不是贴上去的
	for i in 46:
		var rx := fmod(float(i) * 97.3, w)
		var ry := fmod(float(i) * 61.7, h)
		var len_px := h * 0.035
		ci.draw_line(Vector2(rx, ry), Vector2(rx - len_px * 0.22, ry + len_px),
				Color(0.72, 0.80, 0.82, 0.16), 1.0)
	# 湿地面上一道反光
	ci.draw_rect(Rect2(0.0, h * 0.86, w, h * 0.14),
			Color(t["mid"].r, t["mid"].g, t["mid"].b, 1.0), true)


static func _water(ci: CanvasItem, w: float, h: float, t: Dictionary) -> void:
	# 湖面：比天暗一档，几道横向的反光条
	ci.draw_rect(Rect2(0.0, h * 0.70, w, h * 0.30), t["mid"].lightened(0.06), true)
	for i in 7:
		var ry := h * (0.73 + 0.035 * float(i))
		var rw := w * (0.10 + 0.09 * float(i % 3))
		ci.draw_rect(Rect2(w * (0.12 + 0.10 * float(i % 4)), ry, rw, 2.0),
				Color(1, 0.98, 0.92, 0.14), true)
