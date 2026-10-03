extends Control

## 五个小游戏共用一套景。这里用 preload 而不是 class_name：
## `--script` 模式下 class_name 会拉编译期依赖（见 CLAUDE.md 已知陷阱）。
const MiniGameBackdrop = preload("res://scripts/mini_games/MiniGameBackdrop.gd")
const MiniGameChrome = preload("res://scripts/mini_games/MiniGameChrome.gd")
## 禽语湖湾(4) 小游戏：看清一只鸟的剪影，再从4只里把它认出来

var _world_ref: Node = null

const SUCCESS := 0
const CANCELLED := 1
const BIRD_COUNT := 4
## 展示一只鸟要多久。原来是 0.8 秒——那是"看清 → 记住 → 再回头扫四个选项"
## 这一串动作根本做不完的长度：阶段切换没有任何提示（没有响声、没有位移，
## 只有画面整个换掉），于是玩家往往还盯着那只鸟，屏幕已经变成四个按钮，
## 于是重新去看一眼被换掉的画面 —— 于是忘了。
##
## 也不加"点一下继续"：那就把记忆测试变成了走过场。四只鸟的剪影现在是四份
## 真的不同（见 _draw_bird_silhouette），1.6 秒认一个形状够用，而下面那条
## 收缩的横带是玩家唯一的时间参照，说多少就是多少。
const SHOW_DURATION := 1.6
const CHOICE_COUNT := 4

enum { STATE_SHOW, STATE_CHOICE }

var _state: int = STATE_SHOW
var _show_timer: float = 0.0
var _bird_index: int = 0
var _seen_bird: int = -1
var _choice_buttons: Array[Rect2] = []
var _correct_choice: int = 0
var _choice_options: Array[int] = []  # 选项对应的真实 bird_idx

## 四张选项格的底色。它是"这只鸟认不认得出来"那把尺子，所以是常量而不是
## 画笔里的一个字面量：回归量的必须是**画笔真的填的那一个颜色**。
const CARD_BG := Color(0.22, 0.22, 0.27)

const BIRD_COLS: Array[Color] = [
	Color(0.55, 0.4, 0.25),
	Color(0.3, 0.35, 0.55),
	Color(0.9, 0.9, 0.85),
	# 乌鸦是四只里唯一的深色，**而且必须继续是深色**——把它提亮它就不再是乌鸦，
	# 玩家读出来的是"一只灰色的鸟"，题面就换了个问题。
	# 原来它是 (0.11, 0.11, 0.14)，压在 CARD_BG 上 WCAG 只有 1.47:1，
	# 也就是"黑底上的黑"：四只里认不出哪只是鸦，而这一局问的正是
	# "刚才那只是哪一只"。现在抬到 0.17 档的**深炭灰**（比卡底暗、比另三只暗得多，
	# 深色那一头读得出来），真正把它从卡底上分出来的是 `BIRD_RIM_COLS` 那圈浅描边。
	Color(0.17, 0.17, 0.20),
]

## 每只鸟的描边色（外圈那一道亮线）。**四只都有**，不是只给乌鸦：
## 一屏四个选项、四个底色，描边是唯一一条"对四张卡一视同仁"的分界线，
## 而"某一只身上有、另外三只身上没有"本身也是一条形状/颜色上的差别，
## 记忆测试不该考这个。
const BIRD_RIM_COLS: Array[Color] = [
	Color(0.80, 0.70, 0.52),   # 麻雀：暖浅褐，和本体同一个色系但提上去一档
	Color(0.66, 0.76, 0.95),   # 燕子：浅蓝
	Color(0.99, 0.98, 0.92),   # 白鹭：比本体还亮的米白
	Color(0.88, 0.89, 0.92),   # 乌鸦：**浅冷灰**——本体不能再亮，这是唯一能把
								# 深炭灰从深藏青卡底上勾出来的办法
]
## 描边宽度（sc=1 的本地像素）。放大画在本体底下，所以画出来的那一圈是它的两倍。
const RIM_W := 2.2

## 键盘选第 i 个选项。取消按钮是 _draw() 画的假按钮，键盘够不着，
## 所以键盘玩家原本唯一的出路是干等 World3D 的 30s 超时判 CANCELLED——
## 而禽是 5 块碎片之一，拿不到就永远到不了 5/5，键盘玩家直接卡死在通关前。
const CHOICE_KEYS: Array[int] = [KEY_1, KEY_2, KEY_3, KEY_4]

func _ready() -> void:
	# 随机选一只要记住的鸟
	_seen_bird = randi() % BIRD_COUNT
	_build_options()
	_show_timer = SHOW_DURATION
	_state = STATE_SHOW
	AudioManager.play_sfx("bird_call")
	queue_redraw()

func _build_options() -> void:
	# 生成4个选项，其中1个正确
	_choice_options.clear()
	var opts: Array[int] = [_seen_bird]
	while opts.size() < CHOICE_COUNT:
		var r := randi() % BIRD_COUNT
		if r not in opts:
			opts.append(r)
	# 打乱
	opts.shuffle()
	_correct_choice = opts.find(_seen_bird)
	_choice_options = opts

func _process(delta: float) -> void:
	if _state == STATE_SHOW:
		_show_timer -= delta
		if _show_timer <= 0.0:
			_state = STATE_CHOICE
			queue_redraw()
		else:
			queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y

	MiniGameBackdrop.draw_scene(self, w, h, MiniGameBackdrop.BIRD)

	match _state:
		STATE_SHOW:
			_draw_show_phase(w, h)
		STATE_CHOICE:
			_draw_choice_phase(w, h)

## 展示期还剩多少，0..1。**画出来的那条横带用的就是这个值**，
## 单独抽出来是为了让 verify_mini_game.gd 能在无头下量它：原来那个倒计时是
## `max(1, int(_show_timer) + 1)`，在 0.8 秒的窗口里恒等于 1，而 draw_* 在
## headless 下一笔都不落盘——所以只要读数是画出来的，任何断言都抓不到它钉死。
## 抽成函数之后，"读数随时间真的在变"就成了可以断言的东西。
func countdown_fraction() -> float:
	return clampf(_show_timer / maxf(SHOW_DURATION, 0.001), 0.0, 1.0)


func _draw_show_phase(w: float, h: float) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.08),
		Localization.t("mg_bird_title"), HORIZONTAL_ALIGNMENT_CENTER, w, 30, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.14),
		Localization.t("mg_bird_sub"), HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color(0.8, 0.8, 0.8))

	# 鸟的剪影
	var ctr := Vector2(w * 0.5, h * 0.45)
	var sc := minf(w, h) / 280.0
	_draw_bird_silhouette(_seen_bird, ctr, sc)

	# 这条横带就是全部的"还剩多久"。原来这里画的是一个整数倒计时
	# `max(1, int(_show_timer) + 1)`，而 SHOW_DURATION 只有 0.8 秒 ——
	# int(0.8) 到 int(0.0) 一直是 0，+1 之后恒为 1。那个"1"从头到尾没动过，
	# 于是它不是倒计时，是**一个宣称自己在倒、其实钉死的数字**：玩家会一直
	# 等那个 1 变成 0，而它永远不会。0.8 秒也撑不起秒级的整数倒计时，
	# 所以改成一条按真实剩余时间收缩的横带——说多少就是多少。
	var bar_w := w * 0.4
	var bar_h := 10.0
	var bar_x := w * 0.5 - bar_w * 0.5
	var bar_y := h * 0.78
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(1, 1, 1, 0.16), true)
	draw_rect(Rect2(bar_x, bar_y, bar_w * countdown_fraction(), bar_h),
			Color(1, 0.8, 0.4, 0.9), true)

func _draw_choice_phase(w: float, h: float) -> void:
	var sc := minf(w, h) / 280.0
	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.08),
		Localization.t("mg_bird_question"), HORIZONTAL_ALIGNMENT_CENTER, w, 28, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.13),
		Localization.t("mg_key_hint"), HORIZONTAL_ALIGNMENT_CENTER, w, 20, Color(0.75, 0.75, 0.8))

	# 4个选项按钮
	var btn_w := w * 0.2
	var btn_h := h * 0.4
	var gap := w * 0.06
	var start_x := w * 0.5 - (btn_w * 2 + gap) * 0.5
	var start_y := h * 0.15

	_choice_buttons.clear()
	for i in range(CHOICE_COUNT):
		var bx := start_x + (i % 2) * (btn_w + gap)
		var by := start_y + (i / 2) * (btn_h * 0.6)
		var r := Rect2(bx, by, btn_w, btn_h * 0.5)
		_choice_buttons.append(r)
		draw_rect(r, CARD_BG, true)
		draw_rect(r, Color(0.7, 0.7, 0.7), false, 2)
		var bird_idx: int = _choice_options[i]
		# 0.38 不是随手挑的：选项格是 btn_h*0.5 高，白鹭那一只是竖着长出来
		# 最高的，再大一点就顶出格子压到下面的名字上；燕子是最宽的，再大
		# 一点就压到旁边的格子。中心抬到 0.22 是给下面那行名字让出位置。
		_draw_bird_silhouette(bird_idx, Vector2(bx + btn_w * 0.5, by + btn_h * 0.22), sc * 0.38)
		draw_string(ThemeDB.fallback_font, Vector2(bx, by + btn_h * 0.46),
			Localization.t("mg_bird_%d" % bird_idx), HORIZONTAL_ALIGNMENT_CENTER, btn_w, 20, Color(0.9, 0.9, 0.9))
		# 键位角标：键盘玩家看不见鼠标在哪，角标是「哪个键选这只」的唯一线索。
		draw_string(ThemeDB.fallback_font, Vector2(bx + 8.0, by + 24.0),
			str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.75))

	# 取消。这一屏原来**留了热区却没画**：那块矩形只写在 `_pick_by_mouse()`
	# 里，右下角于是变成一块点得着、读不出是什么的地方——玩家在那一带点空了，
	# 小游戏就没了，而界面上没有任何东西告诉他那里能点。
	# 画出来，这块角落才是它自己声称的那样。
	MiniGameChrome.draw_cancel(self, MiniGameChrome.cancel_rect(Vector2(w, h)))


## 四只鸟必须是**四个形状**，不能是同一个形状刷四种颜色。
##
## 原来四只鸟的头/身/翼/尾是同一套坐标，唯一的区别是填充色——于是这个
## "记住哪一只"的游戏考的是"记住一个色号"，而且那个色号只闪 SHOW_DURATION 秒。
##
## 所以形状搬进这张表：**颜色不在表里**，表里只有几何。画的时候按表遍历，
## 回归的时候也按表遍历，于是"四只鸟真的长得不一样"这件事从"看图才知道"
## 变成能断言的。坐标是"sc=1 时"的本地像素，由 _poly/_oval 统一乘一次。
##   ["o", cx, cy, rx, ry]           椭圆（主色）
##   ["c", cx, cy, r]                圆（主色）
##   ["p", x1,y1, x2,y2, …]          多边形（主色）
##   ["q", x1,y1, x2,y2, …]          多边形（暗一档）
##   ["l", x1,y1, x2,y2, w]          线（暗一档）
##   ["L", x1,y1, x2,y2, …, w]       折线（主色）
const BIRD_SHAPES: Array = [
	[  # 麻雀：矮、圆、尾短 —— 一团紧凑的球
		["o", 0, 0, 22.0, 18.0],
		["c", 15, -12, 12.0],
		["q", 26, -13, 39, -9, 26, -7],
		["q", -19, 6, -37, 1, -37, 15],
		["l", -4, 22, -9, 33, 2.0],
		["l", 10, 22, 8, 33, 2.0],
	],
	[  # 燕子：后掠长翼 + 深叉尾 —— 横着的一个叉
		["o", 0, 2, 21.0, 10.0],
		["c", 14, -7, 9.0],
		["q", 5, -2, -17, -27, -31, -20, -13, 2],
		["q", 26, -8, 41, -4, 26, -3],
		["q", -16, 4, -54, 17, -30, 12],
		["q", -16, 2, -54, -9, -30, 0],
	],
	[  # 白鹭：长颈 + 长腿 —— 竖着的一条。
		# 尺寸是压过的：第一版按"真比例"画，84px 高的身子在 144px 的选项格
		# 里顶出上沿、压到下面的名字上，而另外三只只有 45px 高，一眼看过去
		# 就是"一只巨大的加三只小的"——那是尺寸在认人，不是形状在认人。
		["o", 0, 8, 15.0, 18.0],
		["L", 2, -4, 12, -20, 8, -32, 15, -42, 6.0],
		["c", 15, -44, 6.0],
		["q", 21, -46, 38, -42, 21, -40],
		["q", -13, 2, -31, -4, -13, 13],
		["l", -4, 24, -6, 38, 2.5],
		["l", 7, 24, 9, 38, 2.5],
	],
	[  # 乌鸦：厚重、低头、钝喙 —— 一坨
		["o", -2, 8, 27.0, 21.0],
		["c", 19, -6, 14.0],
		["q", 31, -10, 51, -3, 31, 2],
		["q", -26, 8, -45, 1, -45, 23],
		["l", -9, 29, -11, 37, 2.0],
		["l", 10, 29, 10, 37, 2.0],
	],
]

func _draw_bird_silhouette(bird_idx: int, c: Vector2, sc: float) -> void:
	var col: Color = BIRD_COLS[bird_idx]
	# 辅色往**亮**里去还是往**暗**里去，看这只鸟本身有多深。原先一律乘 0.74，
	# 于是乌鸦身上的辅色（喙、脚、翅根）比身子还暗 0.11×0.74 = 0.08——
	# 压在 CARD_BG 上彻底没了，那只鸦就只剩一团看不出形状的墨。
	# 这不是配色偏好，是"辅色必须比本体更靠近底色以外的那一侧"。
	var lum := col.r * 0.3 + col.g * 0.59 + col.b * 0.11
	var shade: Color = col.lightened(0.34) if lum < 0.30 else col.darkened(0.26)
	# **两遍**：先把每一笔放大 `RIM_W` 用描边色画一遍，再把本体压上去。
	# 外露的那半圈就是描边。之所以用"放大"而不是"加线宽"：
	# `draw_colored_polygon` 不收线宽参数，而"这只鸦在深卡上看不见"
	# 恰恰是这一族里唯一不能靠线宽救的形状（本体比卡底还暗）。
	# 两遍都必须走 `_poly` / `_oval`：`--headless` 根本不调 `_draw`，
	# 这一族构造写错时无头回归全绿（见 `_poly` 那条注释里的 Vector2 坑）。
	_paint_silhouette(bird_idx, c, sc, BIRD_RIM_COLS[bird_idx],
			BIRD_RIM_COLS[bird_idx], RIM_W * sc)
	_paint_silhouette(bird_idx, c, sc, col, shade, 0.0)


## 按表走一遍剪影。`grow` 是**外扩的屏幕像素**（描边那遍传 `RIM_W * sc`，
## 本体那遍传 0）；`accent` 是辅色（喙/翅根/脚）那一档颜色。
## 拆成独立函数是因为两遍要遍历同一张表各画一次——把两遍写在一个循环里
## 的话，第二遍会被第一遍的顺序问题带着走，而顺序正是辅色压在本体上那一层。
func _paint_silhouette(bird_idx: int, c: Vector2, sc: float, col: Color,
		accent: Color, grow: float) -> void:
	for prim in BIRD_SHAPES[bird_idx]:
		var a: Array = prim
		var cc: Color = accent if (a[0] == "q" or a[0] == "l") else col
		# 线宽本来是本地像素，而 grow 是屏幕像素，换算要除以 sc
		var wg: float = grow * 2.0 / maxf(sc, 0.001)
		match a[0]:
			"o": draw_colored_polygon(
					_oval(c + Vector2(a[1], a[2]) * sc, sc, float(a[3]) + grow, float(a[4]) + grow), cc)
			"c": draw_circle(c + Vector2(a[1], a[2]) * sc, (float(a[3]) + grow) * sc, cc)
			"p", "q": draw_colored_polygon(
					_grow_poly(_poly(c, sc, a.slice(1)), c, grow), cc)
			"l": draw_line(c + Vector2(a[1], a[2]) * sc, c + Vector2(a[3], a[4]) * sc,
					cc, (float(a[5]) + wg) * sc)
			"L": draw_polyline(_grow_poly(_poly(c, sc, a.slice(1, a.size() - 1)), c, grow),
					cc, (float(a[a.size() - 1]) + wg) * sc, true)


## 沿"离这只鸟中心的方向"把多边形每个顶点往外推 `grow` 像素。
## 按中心缩放（`v * (1 + k)`）不行：喙在 x=+51、尾在 x=-45，离中心的距离差一倍，
## 缩放出来的描边一头厚一头薄，而鸦那一头正好是它贴在卡底上认不出的那一头。
func _grow_poly(pts: PackedVector2Array, c: Vector2, grow: float) -> PackedVector2Array:
	if grow <= 0.0:
		return pts
	var out := PackedVector2Array()
	for p in pts:
		var v: Vector2 = p
		var d: Vector2 = v - c
		var l: float = d.length()
		out.append(v if l <= 0.001 else v + d / l * grow)
	return out

## 表本身的文字签名。只包含几何、不包含颜色，所以"四份签名两两不同"就等于
## "四只鸟真的长得不一样"——而这正是 draw_* 画出来之后无头下量不到的那件事。
func silhouette_signature(bird_idx: int) -> String:
	return str(BIRD_SHAPES[bird_idx])


## 一只鸟的**外接盒**（sc=1 的本地坐标）。纯函数，不碰画笔。
##
## `silhouette_signature()` 只能证明"四串字两两不同"——可四串不同的字
## 完全可以画出**几乎一样**的两只鸟（把雀的尾尖从 -37 挪到 -40 就是一对
## 长度不同的签名，而两个色块在 44px 的选项格里读起来一模一样）。
## 记忆游戏认的是形状，所以判据得落在**剪影自己的几何**上。
## 线宽的一半也算进去：一条 `l` 画出的是有宽度的笔画，不算就少了一截。
static func silhouette_bbox(bird_idx: int) -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in _silhouette_points(bird_idx):
		var v: Vector2 = p
		mn = mn.min(v)
		mx = mx.max(v)
	return Rect2(mn, mx - mn)


## 剪影面积（sc=1 的本地平方像素）。纯函数。
##
## 面积是"这只鸟有多重"的量：外接盒可以一样大而一只塞满、另一只空一大半
## （一个胖团 vs 一个细十字），而认鸟靠的正是这个差别。**部件面积相加**
## 而不是去求并集：并集要用屏幕像素去重，量的是"重叠了几处"这种画法细节，
## 而各部件的面积和与表是一一对应的，表错一处这里立刻动。
static func silhouette_area(bird_idx: int) -> float:
	var total := 0.0
	for prim in BIRD_SHAPES[bird_idx]:
		var a: Array = prim
		match str(a[0]):
			"o": total += PI * float(a[3]) * float(a[4])
			"c": total += PI * float(a[3]) * float(a[3])
			"p", "q": total += absf(_shoelace(a, 1, a.size()))
			"l": total += float(a[5]) \
					* Vector2(a[1], a[2]).distance_to(Vector2(a[3], a[4]))
			"L": total += float(a[a.size() - 1]) * _flat_path_len(a, 1, a.size() - 1)
	return total


## 外接盒的长宽比（宽 ÷ 高）。竖着的白鹭和横着的燕子靠这个分开，
## 而它们的外接盒面积可以一样大。
static func silhouette_aspect(bird_idx: int) -> float:
	var r: Rect2 = silhouette_bbox(bird_idx)
	return r.size.x / maxf(r.size.y, 0.001)


## 一只鸟剪影上的全部角点（含线宽的一半），按部件展开。
## `L` 的最后一项是线宽不是坐标，所以点只到 `size - 1`。
static func _silhouette_points(bird_idx: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for prim in BIRD_SHAPES[bird_idx]:
		var a: Array = prim
		var hw := Vector2.ZERO
		# 坐标对数**按种类算**，不能拿 `a.size()` 推：椭圆后面跟的是两个半径、
		# 线后面跟的是一个线宽，它们不是坐标对。第一版一律当成坐标，
		# 于是 `["c", 15, -12, 12.0]` 会去读 a[4]（越界），而这只鸦的
		# 外接盒量出来是 nan——判据于是报"nan% 差"，红得莫名其妙。
		var npairs := 0
		match str(a[0]):
			"o":
				hw = Vector2(a[3], a[4])
				npairs = 1
			"c":
				hw = Vector2(a[3], a[3])
				npairs = 1
			"l":
				hw = Vector2(a[5], a[5]) * 0.5
				npairs = 2
			"L":
				hw = Vector2.ONE * float(a[a.size() - 1]) * 0.5
				npairs = (a.size() - 2) / 2
			_:
				npairs = (a.size() - 1) / 2
		for i in npairs:
			var v := Vector2(a[1 + i * 2], a[2 + i * 2])
			out.append(v - hw)
			out.append(v + hw)
	return out


## 鞋带公式算多边形面积（绝对值）。表里给的是成对的标量，不是 Vector2 数组。
static func _shoelace(a: Array, from: int, to: int) -> float:
	var acc := 0.0
	var n: int = (to - from) / 2
	for i in n:
		var p := Vector2(a[from + i * 2], a[from + i * 2 + 1])
		var q := Vector2(a[from + ((i + 1) % n) * 2], a[from + ((i + 1) % n) * 2 + 1])
		acc += p.x * q.y - q.x * p.y
	return acc * 0.5


## 折线各段长度之和（`L` 的面积就是它 × 线宽）。
static func _flat_path_len(a: Array, from: int, to: int) -> float:
	var total := 0.0
	var n: int = (to - from) / 2
	for i in range(1, n):
		total += Vector2(a[from + (i - 1) * 2], a[from + (i - 1) * 2 + 1]) \
				.distance_to(Vector2(a[from + i * 2], a[from + i * 2 + 1]))
	return total

## 本地坐标 → 屏幕。表里那些字面量全是"sc=1 时"的像素，统一在这里乘一次，
## 免得每处都得记得写 * sc（漏一处就是一只大一倍的鸟）。
## flat 是**成对的标量**（26, -13, 39, …），不是 Vector2 数组——
## GDScript 的 Vector2 **没有**单参数构造，写成 `Vector2(p)` 会抛
## "Nonexistent 'Vector2' constructor"，而这一行只在真的画到多边形时才跑到，
## headless 根本不调 _draw，于是无头回归全绿、实机一进选项页就满屏红字。
func _poly(c: Vector2, sc: float, flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		out.append(c + Vector2(flat[i], flat[i + 1]) * sc)
	return out

func _oval(c: Vector2, sc: float, rx: float, ry: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(28):
		var a: float = TAU * float(i) / 28.0
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry) * sc)
	return out

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		_pick_by_mouse(event)
		return
	if not event.pressed or event.echo:
		return
	# keycode 和 physical_keycode 都要认：本项目 InputMap 用 physical_keycode
	# 注册动作，而 Web 导出下 keycode 可能填不上（见 CLAUDE.md 已知陷阱）。
	var kc: int = event.keycode if event.keycode != 0 else event.physical_keycode
	if kc == KEY_ESCAPE:
		_world_ref._on_mini_game_done(CANCELLED)
		queue_free()
		return
	# 观察阶段没有可答的题，数字键先不接，等进入 STATE_CHOICE 再按。
	if _state != STATE_CHOICE:
		return
	for i in range(CHOICE_KEYS.size()):
		if kc == CHOICE_KEYS[i]:
			_choose(i)
			return


func _choose(i: int) -> void:
	_world_ref._on_mini_game_done(SUCCESS if i == _correct_choice else CANCELLED)
	queue_free()


func _pick_by_mouse(event: InputEvent) -> void:
	if _state != STATE_CHOICE or _choice_buttons.is_empty():
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	# 热区走画笔那一处，见 MiniGameChrome 那条注释
	var btn_rect: Rect2 = MiniGameChrome.cancel_rect(size)
	if btn_rect.has_point(event.position):
		_world_ref._on_mini_game_done(CANCELLED)
		return
	for i in range(_choice_buttons.size()):
		if _choice_buttons[i].has_point(event.position):
			_choose(i)
			return
