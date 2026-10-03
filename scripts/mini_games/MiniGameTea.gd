extends Control

## 五个小游戏共用一套景。这里用 preload 而不是 class_name：
## `--script` 模式下 class_name 会拉编译期依赖（见 CLAUDE.md 已知陷阱）。
const MiniGameBackdrop = preload("res://scripts/mini_games/MiniGameBackdrop.gd")
const MiniGameBar = preload("res://scripts/mini_games/MiniGameBar.gd")
const MiniGameChrome = preload("res://scripts/mini_games/MiniGameChrome.gd")
## 茶烟小筑(10) 小游戏：按住3秒把水注满，松手退回零重来
##
## 这一行原来写的是「松开失败」，而代码从来没有实现失败：松手只是把
## `_hold_time` 清零，没有任何一个分支报 CANCELLED。文案（mg_tea_hint_release
## 「松手就退回零」）和 `verify_mini_game.gd` 第 6a 节说的都是后者，所以
## 只有这行注释在讲一个不存在的东西——注释也会骗人。
##
## 茶因此是五个小游戏里唯一必然能过的：它也是五件乐事里的头一件（客至汲泉
## 烹茶，朋友来了），本来就不该是一道关卡，而该是一次"按住三秒"的过场。
## 代价是它比另外四个单薄——要不要给它加一道真的失手，留给打磨轮次。

var _world_ref: Node = null

const SUCCESS := 0
const CANCELLED := 1
const HOLD_DURATION := 3.0

var _hold_time := 0.0
var _holding := false
var _done := false
var _t := 0.0

## 注水进度 0..1。**壶里的水和屏幕下方的进度条读的是同一个值**——
## 两处各算一份的话，松手那一刻条退回零而壶里的水还满着，同一屏上
## 两句话互相拆台（这一族 bug 的通用症状：每处单独看都对）。
func fill_fraction() -> float:
	return clampf(_hold_time / maxf(HOLD_DURATION, 0.001), 0.0, 1.0)

## 水面涨到最高时离壶心多远（壶半高 ry 的几成）。不到 1.0 是因为壶口那一圈
## 留给了盖子。
const WATER_INSET := 0.86

## 壶身几成的位置上有水。**从壶底量起，占壶身全高（2×ry）的几成**，
## 所以和壶画多大无关——回归直接调它，注水 50% 就该落在 0.5 附近。
##
## 抽成纯函数的原因和别处一样：`--headless` 根本不调 `_draw`，而"注水时
## 壶里真的有水在涨"是这一屏除进度条之外**唯一**的读数（壶身原来是近黑的
## 剪影，玩家看不见水位，于是"按住三秒"只剩一条条在爬的槽）。
## 画笔调的就是这个函数，回归量的也是它。
static func water_top_frac(fill: float) -> float:
	return (1.0 - WATER_INSET) * 0.5 + WATER_INSET * clampf(fill, 0.0, 1.0)


## 画面上水面的 y。`pot_c` 是壶心、`ry` 是壶半高。
static func water_line_y(pot_c: Vector2, ry: float, fill: float) -> float:
	return pot_c.y + ry - 2.0 * ry * water_top_frac(fill)


## 壶的几何。原来 rx/ry/壶心三个各写一份在 `_draw()` 里，回归就只能自己
## 再抄一份（抄的那份迟早和画的漂）。抽出来之后，"水位线落在壶身之内"
## 这条判据量的是**壶**和**水**共用的一组常量。
const POT_RX := 78.0
const POT_RY := 60.0
const POT_CY := 0.44

static func pot_scale(view: Vector2) -> float:
	return minf(view.x, view.y) / 400.0

static func pot_center(view: Vector2) -> Vector2:
	return Vector2(view.x * 0.5, view.y * POT_CY)

## 水汽。**三颗随时间上浮、边飘边淡、一轮走完从底下重来**：
## 原来那三颗是画在原地不动的灰圆点，alpha 也一路不变，读起来像壶身上
## 溅了三滴脏水而不是蒸汽。alpha 跟着"飘了多高"走，飘得越高越淡。
const STEAM_COUNT := 3
const STEAM_RISE := 46.0    ## 每秒上浮多少本地像素
const STEAM_SPAN := 96.0    ## 一颗飘完全程的高度（走完就从头再来）
const STEAM_A0 := 0.34      ## 刚冒头时的 alpha
## 一轮里左右摆几个来回。**必须是整数**：原来摆幅那一项写的是 `sin(t * 2.2 + i)`，
## 而 2.2 和"飘一轮要几秒"（STEAM_SPAN/STEAM_RISE = 2.09s）不通约，于是
## `steam_puff(i, t + 一轮, …)` 回到的不是一个位置——那一轮判据当场红，
## 而图上的症状是"每颗水汽飘完一趟回来时横着跳一下"。取整之后摆动也是
## 循环的一部分：u 走到 1 和回到 0 时 `sin(TAU*2·u)` 都落在 0，接得上。
const STEAM_SWAY_CYCLES := 2.0

## 第 i 颗水汽在 t 时刻的位置 / 半径 / 透明度。纯函数（不碰画笔），
## 返回 {"pos": 相对壶心的偏移, "r": 像素, "a": alpha}。
## `u` 是"这一轮走到几成"，三颗各错开 1/3 轮——同相的话那就是同一个点画三遍。
static func steam_puff(i: int, t: float, sc: float) -> Dictionary:
	var period: float = STEAM_SPAN / STEAM_RISE
	var u: float = fmod(t / maxf(period, 0.001) + float(i) / float(STEAM_COUNT), 1.0)
	var rise: float = u * STEAM_SPAN
	var pos := Vector2(
			(float(i) - (float(STEAM_COUNT) - 1.0) * 0.5) * 16.0 * sc
					+ sin(TAU * STEAM_SWAY_CYCLES * u + float(i)) * 9.0 * sc,
			-(rise + 1.30 * POT_RY) * sc)
	return {
		"pos": pos,
		"r": (5.0 + rise * 0.05) * sc,
		"a": STEAM_A0 * (1.0 - u),
	}

## 椭圆多边形。open=true 时只画右半圈，交给 draw_polyline 当壶身轮廓。
func _ellipse(c: Vector2, rx: float, ry: float, open: bool = false) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var segs := 33 if open else 36
	for i in range(segs):
		var a: float = (-PI * 0.5 + PI * float(i) / float(segs - 1)) if open \
				else (TAU * float(i) / float(segs))
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _process(delta: float) -> void:
	_t += delta
	if _done:
		return
	# 每帧都要重画：水汽在飘，不注水的时候壶也在冒气。
	# 旧版只在 _holding 时 queue_redraw()，于是不按的时候画面是死的。
	queue_redraw()
	if _holding:
		_hold_time += delta
		if _hold_time >= HOLD_DURATION:
			_done = true
			_world_ref._on_mini_game_done(SUCCESS)

func _draw() -> void:
	var w := size.x
	var h := size.y

	MiniGameBackdrop.draw_scene(self, w, h, MiniGameBackdrop.TEA)

	# 标题
	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.12),
		Localization.t("mg_tea_title"), HORIZONTAL_ALIGNMENT_CENTER, w, 28, Color.WHITE)

	# 茶壶。原来这里是一个半圆弧 + 一根斜线 + 一个半圆环，落在深色背板上
	# 认不出是茶壶——五个小游戏里只有它没有可读的形象。改成壶身 + 壶盖 +
	# 壶嘴 + 壶把，且壶里的水位跟着注水进度涨，进度条之外再有一处读数。
	var pot_c: Vector2 = pot_center(Vector2(w, h))
	var sc: float = pot_scale(Vector2(w, h))
	var rx: float = POT_RX * sc
	var ry: float = POT_RY * sc
	# 壶身不能是暖褐色。原来 col_pot = (0.40, 0.26, 0.15)，而茶烟小筑那屏的
	# 天光渐变在壶所在的高度上正好是 (0.31, 0.23, 0.16) —— 两者亮度差不到
	# 0.09，图上那只壶是一团和背景同色的糊，连壶嘴壶把都找不着。景做完之后
	# 才暴露出来：这片景比原先那块 0.7 alpha 的黑幕亮，壶就得让开。
	# 改成深色剪影 + 一道亮口沿：亮边在暖底上一眼能认出轮廓，壶里的水也才
	# 亮得起来（深壶身配 0.74 的水，是这屏唯一的高对比处）。
	var col_pot := Color(0.16, 0.10, 0.06)
	var col_edge := Color(0.90, 0.66, 0.36)
	draw_colored_polygon(_ellipse(pot_c, rx, ry), col_pot)
	# 水位。逐行取椭圆的半宽来填，所以水是贴着壶壁涨的，不会溢出一个方块。
	# 水面 y 与下面那条进度条**读同一个** `fill_fraction()`——原来两处各写
	# 一遍 `clampf(_hold_time / HOLD_DURATION, …)`，而那正是"壶里没水"这种
	# 反馈能被悄悄改坏的入口。
	var held: float = fill_fraction()
	var water_y: float = water_line_y(pot_c, ry, held)
	# 64 行：30 行时壶底那圈弧能看出台阶
	var rows := 64
	for r in range(rows):
		var y0: float = pot_c.y - ry + 2.0 * ry * float(r) / float(rows)
		if y0 < water_y:
			continue
		var ny: float = (y0 - pot_c.y) / ry
		if absf(ny) >= 0.999:
			continue
		var hw: float = rx * sqrt(1.0 - ny * ny)
		draw_rect(Rect2(pot_c.x - hw, y0, hw * 2.0, 2.0 * ry / float(rows) + 1.0),
				Color(0.74, 0.46, 0.14, 0.9))
	draw_polyline(_ellipse(pot_c, rx, ry, true), col_edge, 3.0, true)
	# 壶盖 + 钮
	draw_colored_polygon(_ellipse(Vector2(pot_c.x, pot_c.y - ry * 0.94), rx * 0.62, ry * 0.20), col_pot)
	draw_polyline(_ellipse(Vector2(pot_c.x, pot_c.y - ry * 0.94), rx * 0.62, ry * 0.20, true), col_edge, 2.5, true)
	draw_circle(Vector2(pot_c.x, pot_c.y - ry * 1.14), 7.0 * sc, col_edge)
	# 壶嘴
	draw_colored_polygon(PackedVector2Array([
		pot_c + Vector2(rx * 0.72, -ry * 0.55),
		pot_c + Vector2(rx * 1.42, -ry * 1.12),
		pot_c + Vector2(rx * 1.30, -ry * 0.82),
		pot_c + Vector2(rx * 0.80, -ry * 0.20),
	]), col_pot)
	# 壶把
	draw_arc(pot_c + Vector2(-rx * 0.86, -ry * 0.10), ry * 0.52, PI * 0.45, PI * 1.55, 20,
			col_edge, 5.0 * sc)

	# 水汽：三颗从壶口往上飘，越飘越淡，一轮走完从壶口重新冒出来。
	# 位置/半径/透明度都在 `steam_puff()` 里算——画笔只负责把那一颗画出来，
	# 所以"它到底飘没飘"是回归能量的东西（headless 下一笔都不落盘）。
	for i in range(STEAM_COUNT):
		var puff: Dictionary = steam_puff(i, _t, sc)
		draw_circle(pot_c + (puff["pos"] as Vector2), float(puff["r"]),
				Color(1, 1, 1, float(puff["a"])))

	# 进度条。门槛在**条的右端**（按满 HOLD_DURATION 即成），原来这根条
	# 只有一条边框、什么标记都没有，而标题写的是"3秒后完成"——玩家盯着
	# 一个从 0% 爬到 100% 的数，看不出"还差几秒"，而那正是这一屏的全部。
	# 松手时条不倒退是不行的：`_hold_time` 立刻清零，刻痕要跟着往回退，
	# 不然条上留着一道满的刻痕而条是空的，两者在同一屏上互相拆台。
	var bar := MiniGameBar.rect(Vector2(w, h), 0.72, 0.55, 22.0)
	var fill_col := Color(0.6, 0.35, 0.1) if _holding else Color(0.35, 0.2, 0.08)
	MiniGameBar.draw_bar(self, bar, held, 1.0,
			fill_col, Color(0.15, 0.12, 0.08), Color(0.8, 0.6, 0.3),
			Color(1.0, 0.82, 0.45))

	# 进度文字：百分比 + 还差几秒。只报百分比的话，玩家得自己乘一个他
	# 不知道是多少的 HOLD_DURATION 才算得出还差多久。
	draw_string(ThemeDB.fallback_font, Vector2(bar.position.x, bar.position.y - 12),
		"%d%%" % int(held * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(bar.end.x - 130.0, bar.position.y - 12),
		Localization.t("mg_tea_left", [maxf(HOLD_DURATION - _hold_time, 0.0)]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.85, 0.6))

	# 提示
	var hint := Localization.t("mg_tea_hint_release") if _holding \
			else Localization.t("mg_tea_hint_hold") + Localization.t("mg_tea_hint_esc")
	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.88),
		hint, HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color(1, 0.85, 0.6))

	# 取消按钮
	MiniGameChrome.draw_cancel(self, MiniGameChrome.cancel_rect(Vector2(w, h)))

func _gui_input(event: InputEvent) -> void:
	if _done:
		return
	# ESC 取消。取消按钮是 _draw() 画的假按钮，键盘点不到——不接 ESC 的话
	# 键盘玩家既不能放弃、又没法失败（长按 3 秒必然成功），唯一的出路是干等
	# World3D 的 30s 超时。五个小游戏里只有茶原来是这副模样。
	if event is InputEventKey:
		var ekc: int = event.keycode if event.keycode != 0 else event.physical_keycode
		if ekc == KEY_ESCAPE and event.pressed and not event.echo:
			_world_ref._on_mini_game_done(CANCELLED)
			return
	# 热区走画笔那一处。画和点各抄一份 `Rect2(w - 160, ...)` 的话，
	# 挪一次按钮就得改两处，而漏掉的那一处症状是"看得见点不着"。
	var btn_rect: Rect2 = MiniGameChrome.cancel_rect(size)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if btn_rect.has_point(event.position):
				_world_ref._on_mini_game_done(CANCELLED)
				return
			if event.pressed:
				_holding = true
				AudioManager.play_sfx("tea_pour")
			else:
				_holding = false
				_hold_time = 0.0
				queue_redraw()
	elif event is InputEventKey:
		# keycode 和 physical_keycode 都要认：本项目 InputMap 用 physical_keycode
		# 注册 interact，而 Web 导出下 keycode 可能填不上。只判 keycode 的话空格
		# 按了没反应，超时判 CANCELLED，玩家被踢出打卡。
		if event.keycode != KEY_SPACE and event.physical_keycode != KEY_SPACE:
			return
		get_viewport().set_input_as_handled()
		if event.pressed:
			_holding = true
			AudioManager.play_sfx("tea_pour")
		else:
			_holding = false
			_hold_time = 0.0
			queue_redraw()
