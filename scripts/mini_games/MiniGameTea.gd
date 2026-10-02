extends Control

## 五个小游戏共用一套景。这里用 preload 而不是 class_name：
## `--script` 模式下 class_name 会拉编译期依赖（见 CLAUDE.md 已知陷阱）。
const MiniGameBackdrop = preload("res://scripts/mini_games/MiniGameBackdrop.gd")
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
	var pot_c := Vector2(w * 0.5, h * 0.44)
	var sc := minf(w, h) / 400.0
	var rx := 78.0 * sc
	var ry := 60.0 * sc
	# 壶身不能是暖褐色。原来 col_pot = (0.40, 0.26, 0.15)，而茶烟小筑那屏的
	# 天光渐变在壶所在的高度上正好是 (0.31, 0.23, 0.16) —— 两者亮度差不到
	# 0.09，图上那只壶是一团和背景同色的糊，连壶嘴壶把都找不着。景做完之后
	# 才暴露出来：这片景比原先那块 0.7 alpha 的黑幕亮，壶就得让开。
	# 改成深色剪影 + 一道亮口沿：亮边在暖底上一眼能认出轮廓，壶里的水也才
	# 亮得起来（0.11 的壶身配 0.74 的水，是这屏唯一的高对比处）。
	var col_pot := Color(0.16, 0.10, 0.06)
	var col_edge := Color(0.90, 0.66, 0.36)
	draw_colored_polygon(_ellipse(pot_c, rx, ry), col_pot)
	# 水位。逐行取椭圆的半宽来填，所以水是贴着壶壁涨的，不会溢出一个方块。
	var fill: float = clampf(_hold_time / HOLD_DURATION, 0.0, 1.0)
	var water_y: float = pot_c.y + ry * 0.86 - 2.0 * ry * 0.86 * fill
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

	# 水汽：从壶盖往上飘，不再是壶周围一圈随机白点
	for i in range(3):
		var rise: float = fmod(_t * 46.0 + i * 34.0, 96.0)
		var sx: float = pot_c.x + (float(i) - 1.0) * 16.0 * sc + sin(_t * 2.2 + i) * 9.0 * sc
		var sy: float = pot_c.y - ry * 1.30 - rise * sc
		draw_circle(Vector2(sx, sy), (5.0 + rise * 0.05) * sc,
				Color(1, 1, 1, 0.30 * (1.0 - rise / 96.0)))

	# 进度条背景
	var bar_w := w * 0.55
	var bar_h := 22.0
	var bar_x := w * 0.5 - bar_w * 0.5
	var bar_y := h * 0.72
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.15, 0.12, 0.08), true)
	# 进度条填充
	var fill_w := bar_w * clampf(_hold_time / HOLD_DURATION, 0.0, 1.0)
	var fill_col := Color(0.6, 0.35, 0.1) if _holding else Color(0.35, 0.2, 0.08)
	draw_rect(Rect2(bar_x, bar_y, fill_w, bar_h), fill_col, true)
	# 进度条边框
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.8, 0.6, 0.3), false, 2)

	# 进度文字
	draw_string(ThemeDB.fallback_font, Vector2(w * 0.5 - 60, bar_y - 12),
		"%d%%" % int(clampf(_hold_time / HOLD_DURATION, 0.0, 1.0) * 100),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)

	# 提示
	var hint := Localization.t("mg_tea_hint_release") if _holding \
			else Localization.t("mg_tea_hint_hold") + Localization.t("mg_tea_hint_esc")
	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.88),
		hint, HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color(1, 0.85, 0.6))

	# 取消按钮
	var btn_rect := Rect2(w - 160, h - 60, 140, 44)
	draw_rect(btn_rect, Color(0.4, 0.3, 0.3), true)
	draw_rect(btn_rect, Color(0.8, 0.3, 0.3), false, 2)
	draw_string(ThemeDB.fallback_font, Vector2(btn_rect.position.x, btn_rect.position.y + 30),
		Localization.t("mg_cancel"), HORIZONTAL_ALIGNMENT_CENTER, btn_rect.size.x, 22, Color.WHITE)

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
	var w := size.x
	var h := size.y
	var btn_rect := Rect2(w - 160, h - 60, 140, 44)

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
