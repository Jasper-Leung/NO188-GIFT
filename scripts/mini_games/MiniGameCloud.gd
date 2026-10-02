extends Control

## 五个小游戏共用一套景。这里用 preload 而不是 class_name：
## `--script` 模式下 class_name 会拉编译期依赖（见 CLAUDE.md 已知陷阱）。
const MiniGameBackdrop = preload("res://scripts/mini_games/MiniGameBackdrop.gd")
## 云影台(7) 小游戏：拖拽沿轨迹绘制云的形状
## 成功条件：完成80%以上路径

var _world_ref: Node = null

const SUCCESS := 0
const CANCELLED := 1

# 云朵轨迹点（相对于中心的2D坐标）
const PATH_POINTS := [
	Vector2(0, -40), Vector2(30, -30), Vector2(50, 0),
	Vector2(40, 25), Vector2(0, 40), Vector2(-40, 25),
	Vector2(-50, 0), Vector2(-30, -30),
]
const PATH_TOLERANCE := 45.0
const SUCCESS_THRESHOLD := 0.75

## 键盘光标每按一次方向键挪多远（像素）。按住会走 OS 的按键重复，
## 一次长按能把光标从一头拉到另一头。
const KEY_STEP := 12.0

var _path_world: Array = []
var _drawn_ratio := 0.0
var _started := false
var _start_pos := Vector2.ZERO
var _dragging := false
var _total_path_length := 0.0
var _followed_length := 0.0
## 键盘光标。空格按住 = 落笔，方向键/WASD = 挪光标。
## 走的还是 _update_draw() 那一条路，判成功/失败的判据与鼠标完全共用——
## 两套输入只负责「把一个点送到轨迹附近」，不各算各的进度。
var _key_cursor := Vector2.ZERO
var _key_down := false
var _brush_last_ms := -9999
## 下一个**还没记过分**的段序号。
##
## 原来 _update_draw 每调一次就记 `段长 * 0.1`，而它不记得哪几段已经记过。
## 于是"按住空格在原地左右晃"就能对同一段反复计分——实测在第 0 段中点
## 来回晃 60 次，完成度就冲到 78.1%，越过 75% 的及格线：这是一个"描边"
## 游戏，却不描边也能赢。（更早一版修的是"光标停着不动也涨"，那个是
## 挂在 _process 上按帧累加的锅，晃一晃就绕过去了。）
##
## 只认"下一段"就够了，不必再开一个 claimed 数组：顺序推进天然保证每段
## 至多记一次，而且描边本来就是一个顺序动作。
var _next_seg := 0

func _ready() -> void:
	_build_path_world()
	_total_path_length = _calc_path_length()
	# 窗口尺寸变化时按新 size 重建轨迹，避免轨迹错位
	resized.connect(_on_resized)
	queue_redraw()

func _on_resized() -> void:
	_build_path_world()
	_total_path_length = _calc_path_length()
	queue_redraw()

func _build_path_world() -> void:
	_path_world.clear()
	var ctr := size * 0.5
	var sc := minf(size.x, size.y) / 400.0
	for p in PATH_POINTS:
		_path_world.append(ctr + p * sc)
	if _key_cursor == Vector2.ZERO:
		_key_cursor = _path_world[0] if _path_world.size() > 0 else ctr

func _calc_path_length() -> float:
	var l := 0.0
	for i in range(_path_world.size() - 1):
		l += _path_world[i].distance_to(_path_world[i + 1])
	return l

func _draw() -> void:
	var w := size.x
	var h := size.y

	MiniGameBackdrop.draw_scene(self, w, h, MiniGameBackdrop.CLOUD)

	# 游戏区域。这块板子原来是近乎全黑的不透明矩形，压在一片雨后初霁的
	# 淡蓝天上像一块贴上去的补丁；改成半透明，让背景的天光透上来，
	# 描边提亮，轨迹的对比度靠板子的暗而不是靠"不透明"。
	var area_rect := Rect2(w * 0.15, h * 0.15, w * 0.7, h * 0.7)
	draw_rect(area_rect, Color(0.16, 0.22, 0.28, 0.34), true)
	draw_rect(area_rect, Color(1, 1, 1, 0.55), false, 2)

	# 标题
	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.1),
		Localization.t("mg_cloud_title"), HORIZONTAL_ALIGNMENT_CENTER, w, 28, Color.WHITE)

	# 目标轨迹（虚线）。板子现在是半透明的，底下是随高度变化的天光，
	# 纯白的点在天亮的那一段会淡掉 —— 每个点先压一道深色晕再点白心。
	for i in range(_path_world.size()):
		var p: Vector2 = _path_world[i]
		if i < _path_world.size() - 1:
			var np: Vector2 = _path_world[i + 1]
			draw_line(p, np, Color(0.10, 0.14, 0.18, 0.35), 4, true)
			draw_line(p, np, Color(1, 1, 1, 0.72), 2, true)
		draw_circle(p, 7, Color(0.10, 0.14, 0.18, 0.40))
		draw_circle(p, 5, Color(1, 1, 1, 0.92))

	# 进度条
	var bar_w := w * 0.5
	var bar_h := 16.0
	var bar_x := w * 0.5 - bar_w * 0.5
	var bar_y := h * 0.88
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.2, 0.2, 0.2), true)
	draw_rect(Rect2(bar_x, bar_y, bar_w * _drawn_ratio, bar_h), Color(0.4, 0.8, 1.0), true)
	draw_string(ThemeDB.fallback_font, Vector2(bar_x, bar_y - 8),
		# 把及格线一起报出来。原来只写"完成度 62%"，玩家不知道 62% 到底算不算赢，
		# 于是描到边缘也不知道是差一口还是早就能松手了 —— 一个没有任何参照的百分比。
		Localization.t("mg_complete", [int(_drawn_ratio * 100), int(SUCCESS_THRESHOLD * 100)]),
		HORIZONTAL_ALIGNMENT_LEFT, bar_w, 18, Color.WHITE)

	# 取消按钮
	var btn_rect := Rect2(w - 160, h - 60, 140, 44)
	draw_rect(btn_rect, Color(0.4, 0.3, 0.3), true)
	draw_rect(btn_rect, Color(0.8, 0.3, 0.3), false, 2)
	draw_string(ThemeDB.fallback_font, Vector2(btn_rect.position.x, btn_rect.position.y + 30),
		Localization.t("mg_cancel"), HORIZONTAL_ALIGNMENT_CENTER, btn_rect.size.x, 22, Color.WHITE)

	# 键盘光标：没有它键盘玩家看不见自己在哪儿，只能盲按方向键
	draw_line(_key_cursor + Vector2(-9, 0), _key_cursor + Vector2(9, 0), Color(1, 0.85, 0.4), 2.0, true)
	draw_line(_key_cursor + Vector2(0, -9), _key_cursor + Vector2(0, 9), Color(1, 0.85, 0.4), 2.0, true)
	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.8),
		Localization.t("mg_cloud_hint"), HORIZONTAL_ALIGNMENT_CENTER, w, 20, Color(0.75, 0.75, 0.8))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_gui_input_key(event)
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var w := size.x
				var h := size.y
				var btn_rect := Rect2(w - 160, h - 60, 140, 44)
				if btn_rect.has_point(event.position):
					_world_ref._on_mini_game_done(CANCELLED)
					return
				_dragging = true
				_start_pos = event.position
				if _path_world.size() > 0 and event.position.distance_to(_path_world[0]) < PATH_TOLERANCE:
					_started = true
			else:
				_dragging = false
				if _started and _drawn_ratio >= SUCCESS_THRESHOLD:
					_world_ref._on_mini_game_done(SUCCESS)
				_started = false
	elif event is InputEventMouseMotion and _dragging and _started:
		_update_draw(event.position)


## 键盘通路：方向键 / WASD 挪光标，空格落笔，ESC 取消。
## 取消按钮是 _draw() 画的假按钮，键盘点不到——不接 ESC 的话键盘玩家唯一的
## 出路是干等 World3D 的 30s 超时，而云是 5 块碎片之一，拿不到就到不了 5/5。
func _gui_input_key(event: InputEvent) -> void:
	# keycode 和 physical_keycode 都要认：本项目 InputMap 用 physical_keycode
	# 注册动作，而 Web 导出下 keycode 可能填不上（见 CLAUDE.md 已知陷阱）。
	var kc: int = event.keycode if event.keycode != 0 else event.physical_keycode
	if kc == KEY_ESCAPE and event.pressed and not event.echo:
		_world_ref._on_mini_game_done(CANCELLED)
		return
	if kc == KEY_SPACE:
		if event.pressed:
			_key_down = true
			# 落笔的起点要求和鼠标版一样贴着第一个点，否则一按空格进度就从中间起算
			if _path_world.size() > 0 \
					and _key_cursor.distance_to(_path_world[0]) < PATH_TOLERANCE:
				_started = true
		else:
			_key_down = false
			if _started and _drawn_ratio >= SUCCESS_THRESHOLD:
				_world_ref._on_mini_game_done(SUCCESS)
			_started = false
		return
	if not event.pressed:
		return
	var step := Vector2.ZERO
	match kc:
		KEY_LEFT, KEY_A: step = Vector2.LEFT
		KEY_RIGHT, KEY_D: step = Vector2.RIGHT
		KEY_UP, KEY_W: step = Vector2.UP
		KEY_DOWN, KEY_S: step = Vector2.DOWN
	if step == Vector2.ZERO:
		return
	# echo 不拦：按住方向键要能连着走，不然挪一格就得松一次
	_key_cursor = (_key_cursor + step * KEY_STEP).clamp(Vector2.ZERO, size)
	# 进度只跟「光标真的挪了」挂钩。不能挂 _process 上按帧累加：
	# _update_draw 每调一次就记一段路的长度，光标停着不动也会照样涨——
	# 键盘长按空格就能原地刷满，跟描边的本意完全相反。
	if _key_down and _started:
		_update_draw(_key_cursor)
	queue_redraw()

func _update_draw(pos: Vector2) -> void:
	if _path_world.size() < 2:
		return
	# 找到当前离 pos 最近的路径段
	var min_dist := INF
	var seg_idx := 0
	for i in range(_path_world.size() - 1):
		var d := _dist_to_segment(pos, _path_world[i], _path_world[i + 1])
		if d < min_dist:
			min_dist = d
			seg_idx = i

	if min_dist >= PATH_TOLERANCE:
		return
	# 只认"还没记过分"的段，顺序推进。同一段晃一百次也只记一次，所以那个
	# * 0.1 的按帧分摊（鼠标拖动按帧记、键盘每按一次方向键记一次，两种频率
	# 都不对）一并去掉了。
	#
	# 允许**跳过**中间几段并把它们一起记上：鼠标甩得够快时 _gui_input 只送来
	# 终点那一帧，nearest 会直接落到后面两段，只认"下一段"的话 _next_seg 就
	# 卡死在没描到的那一段上，后面整条云再也描不完。往后跳不往前退，所以
	# 跳过也不给刷分的机会——想往前补就得真的把光标挪回去。
	if seg_idx < _next_seg:
		return  # POSITIVE_CONTROL
	for i in range(_next_seg, seg_idx + 1):
		_followed_length += _path_world[i].distance_to(_path_world[i + 1])
	_next_seg = seg_idx + 1
	_drawn_ratio = clampf(_followed_length / _total_path_length, 0.0, 1.0)
	# 笔触音挂在这里：鼠标拖和键盘挪都只在这一条路上汇合，别在两处各放一个。
	# 鼠标拖是每帧调一次，不节流就是一叠糊在一起的噪声。
	var now := Time.get_ticks_msec()
	if now - _brush_last_ms >= 300:
		_brush_last_ms = now
		AudioManager.play_sfx("cloud_brush")
	queue_redraw()

func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ap := p - a
	var ab := b - a
	var t := clampf(ap.dot(ab) / ab.dot(ab), 0.0, 1.0)
	return p.distance_to(a.lerp(b, t))
