extends Control
## 竹雨庭(14) 小游戏：QTE 砍竹 — 5根竹子依次倒下，需在窗口内按键

var _world_ref: Node = null

const SUCCESS := 0
const CANCELLED := 1
const BAMBOO_COUNT := 5
const WINDOW_SEC := 1.2
const INTRO_SEC := 0.8
## 砍完最后一根后停留在成功画面的时长。必须给一段停留：早先在
## _next_bamboo 里直接 _on_mini_game_done(SUCCESS) + queue_free()，遮罩在同一帧
## 就没了，玩家看到的是"按空格小游戏凭空消失"，既分不清是砍赢了还是被踢出去。
const SUCCESS_HOLD_SEC := 1.6

var _bamboo_states: Array = []   # -1=未出现, 0=可砍, 1=已砍
var _current_bamboo: int = 0
var _window_timer: float = 0.0
var _window_active: bool = false
var _succeeded := false
var _success_timer := 0.0
var _t := 0.0
var _intro_active := false
var _intro_timer := 0.0

func _ready() -> void:
	for i in range(BAMBOO_COUNT):
		_bamboo_states.append(-1)
	_intro_active = true
	_intro_timer = INTRO_SEC
	queue_redraw()

func _next_bamboo() -> void:
	if _current_bamboo >= BAMBOO_COUNT:
		_enter_success()
		return
	_bamboo_states[_current_bamboo] = 0
	_window_active = true
	_window_timer = WINDOW_SEC
	queue_redraw()

## 进入成功画面并停留 SUCCESS_HOLD_SEC，期间不接受任何输入，然后才结算。
func _enter_success() -> void:
	if _succeeded:
		return
	_succeeded = true
	_success_timer = SUCCESS_HOLD_SEC
	queue_redraw()
	get_tree().create_timer(SUCCESS_HOLD_SEC).timeout.connect(_on_success_done, CONNECT_ONE_SHOT)


func _on_success_done() -> void:
	if not is_inside_tree():
		return
	_world_ref._on_mini_game_done(SUCCESS)
	queue_free()

func _process(delta: float) -> void:
	_t += delta
	if _succeeded:
		# 成功画面：倒计时走完就结算。窗口/倒计时都不再动，避免玩家以为还能砍。
		_success_timer = maxf(_success_timer - delta, 0.0)
		queue_redraw()
		return
	if _intro_active:
		_intro_timer -= delta
		if _intro_timer <= 0.0:
			_intro_active = false
			_next_bamboo()
		else:
			queue_redraw()
		return
	if _window_active:
		_window_timer -= delta
		if _window_timer <= 0.0:
			_window_active = false
			_world_ref._on_mini_game_done(CANCELLED)
			queue_free()
		else:
			queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y

	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.65))

	if _succeeded:
		_draw_success(w, h)
		return

	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.1),
		Localization.t("mg_bamboo_title"), HORIZONTAL_ALIGNMENT_CENTER, w, 28, Color.WHITE)

	if _intro_active:
		# 引导期：告诉玩家提前按也可以，不用等倒计时
		draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.17),
			Localization.t("mg_bamboo_intro"), HORIZONTAL_ALIGNMENT_CENTER, w, 20,
			Color(0.9, 0.9, 0.9, 0.9))

	# 5根竹子
	var start_x := w * 0.5 - (BAMBOO_COUNT * 70) * 0.5
	var base_y := h * 0.82
	var bh := h * 0.55

	for i in range(BAMBOO_COUNT):
		var bx := start_x + i * 70.0
		var state: int = _bamboo_states[i]
		var offset := 0.0
		var alpha := 1.0

		if state == -1:
			# 未出现
			alpha = 0.2
			offset = -bh
		elif state == 0:
			# 可砍（当前）
			offset = 0.0
			var urgency := 1.0 - _window_timer / WINDOW_SEC
			# 闪烁
			alpha = 0.7 + sin(_t * 12) * 0.3
			# 显示倒计时
			var timer_col := Color(1.0, urgency, 0.0, 1.0)
			draw_string(ThemeDB.fallback_font, Vector2(bx - 5, base_y - bh - 10),
				"%.1f" % maxf(_window_timer, 0.0),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, timer_col)
		elif state == 1:
			# 已砍（倒下）
			offset = bh * 0.9
			alpha = 0.6

		var bamboo_top := base_y - bh + offset
		# 竹身
		var col := Color(0.3, 0.65, 0.3, alpha)
		draw_rect(Rect2(bx, bamboo_top, 12, bh - offset), col, true)
		# 竹节
		for n in range(4):
			var ny := bamboo_top + n * (bh / 4.0)
			draw_line(Vector2(bx, ny), Vector2(bx + 12, ny),
				Color(0.2, 0.45, 0.2, alpha), 2.0)

		# 序号
		draw_string(ThemeDB.fallback_font, Vector2(bx - 2, base_y + 20),
			"%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.9, 0.7, alpha))

	# 进度
	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.92),
		Localization.t("mg_progress", [_current_bamboo, BAMBOO_COUNT]),
		HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color(0.8, 1.0, 0.8))


## 砍完 5 根后的收尾画面：5 根全倒 + 一句成功文案 + 结算前的停留倒计时。
## 玩家需要这一屏来确认"是我砍赢的"，而不是小游戏被一脚踢掉。
func _draw_success(w: float, h: float) -> void:
	# 收尾时把底色压暗一点，让文案跳出来
	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.45))

	# 5 根全部倒伏，位置/尺寸跟主画面保持一致
	var start_x := w * 0.5 - (BAMBOO_COUNT * 70) * 0.5
	var base_y := h * 0.82
	var bh := h * 0.55
	for i in range(BAMBOO_COUNT):
		var bx := start_x + i * 70.0
		var bamboo_top := base_y - bh + bh * 0.9
		draw_rect(Rect2(bx, bamboo_top, 12, bh * 0.1), Color(0.3, 0.65, 0.3, 0.6), true)

	# 成功文案，入场时轻微淡入
	var fade: float = clampf(1.0 - _success_timer / SUCCESS_HOLD_SEC, 0.0, 1.0)
	var alpha: float = clampf(0.35 + fade * 2.5, 0.0, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.38),
		Localization.t("mg_bamboo_done"), HORIZONTAL_ALIGNMENT_CENTER, w, 40,
		Color(0.85, 1.0, 0.75, alpha))
	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.47),
		Localization.t("mg_progress", [BAMBOO_COUNT, BAMBOO_COUNT]),
		HORIZONTAL_ALIGNMENT_CENTER, w, 24, Color(0.8, 1.0, 0.8, alpha))

	# 即将结算的进度条
	var bar_w := w * 0.3
	var bar_x := w * 0.5 - bar_w * 0.5
	var bar_y := h * 0.56
	var left: float = maxf(_success_timer, 0.0)
	draw_rect(Rect2(bar_x, bar_y, bar_w, 8), Color(1, 1, 1, 0.18), true)
	draw_rect(Rect2(bar_x, bar_y, bar_w * (left / SUCCESS_HOLD_SEC), 8),
		Color(0.6, 0.9, 0.5, 0.8), true)

## 砍掉当前这根：标记倒下，0.4s 后进入下一根。
## 0.4s 延迟用一次连接，不要 await 写在 _gui_input 里——
## 那个回调是逐事件驱动的，带 await 会变成协程，回调返回时状态已改。
func _cut_current_bamboo() -> void:
	if not _window_active:
		return
	_window_active = false
	_bamboo_states[_current_bamboo] = 1
	_current_bamboo += 1
	AudioManager.play_sfx("bamboo_cut")
	queue_redraw()
	get_tree().create_timer(0.4).timeout.connect(_on_cut_delay_done, CONNECT_ONE_SHOT)


func _on_cut_delay_done() -> void:
	if is_inside_tree():
		_next_bamboo()


func _gui_input(event: InputEvent) -> void:
	# 成功画面期间什么都不做，但按键照样要吃掉：这段时间玩家多半还在惯性乱按，
	# 漏给全局 interact 就可能在结算的同一帧重新打卡。
	if _succeeded:
		if _is_space_event(event):
			get_viewport().set_input_as_handled()
		return
	# ESC 取消。这一屏连取消按钮都没画（鼠标点击在这里是"砍"，画个按钮上去
	# 还要判点击落在哪、怕误砍），所以键盘玩家原本只能等 1.2s 窗口自己过掉。
	# 成功画面期间不给 ESC：那 1.6s 是给玩家确认"是我砍赢的"，跳过它就回到
	# "小游戏凭空消失"那个老毛病。
	if _is_esc_event(event):
		_world_ref._on_mini_game_done(CANCELLED)
		queue_free()
		return
	# 引导期提前按也算数：玩家看到遮罩第一反应就是按空格，
	# 那一下不能被静默吃掉，否则每次开局都要干等 0.8 秒
	if _intro_active:
		if _is_cut_event(event):
			get_viewport().set_input_as_handled()
			_intro_active = false
			_next_bamboo()
		return
	# 两根竹子之间的 0.4s 空档里窗口没开，按键砍不到东西。但事件照样要吃掉：
	# 空格同时是全局 "interact" 动作，放行的话这一次按键会漏到 World3D 那侧。
	if not _window_active:
		if _is_space_event(event):
			get_viewport().set_input_as_handled()
		return
	if _is_cut_event(event):
		# 吃掉事件，别让这次按键继续走全局 "interact" 动作或其他控件
		get_viewport().set_input_as_handled()
		_cut_current_bamboo()


## 是否是一次"砍竹"输入。按键只认真正的按下，长按连发(echo)不算，
## 否则一直按住空格就能秒过全部 5 根。
func _is_cut_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo and _is_space_event(event)
	if event is InputEventMouseButton:
		return event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	return false


## 空格判定必须 keycode 和 physical_keycode 都认。本项目的 InputMap 用
## physical_keycode 注册 interact（GameManager._add_action），而 Web 导出下
## keycode 可能填不上——只判 keycode 的话空格既砍不到竹子、又不被吃掉，
## 1.2s 窗口一过就判 CANCELLED，玩家被踢出打卡，看起来就是"按空格退出游戏"。
##
## 必须先判类型：窗口没开的那条分支对任意事件都调本函数，鼠标移动事件没有
## keycode，直接访问会报 Invalid access to property 'keycode' on
## 'InputEventMouseMotion'。守卫放在函数里而不是各调用点，少一个漏网的调用方。
func _is_space_event(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	return event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE


func _is_esc_event(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	if not event.pressed or event.echo:
		return false
	return event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE
