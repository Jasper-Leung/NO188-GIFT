extends Control
## 禽语湖湾(4) 小游戏：观察4只鸟的剪影后，从4选项中选出第N只

var _world_ref: Node = null

const SUCCESS := 0
const CANCELLED := 1
const BIRD_COUNT := 4
const SHOW_DURATION := 0.8
const CHOICE_COUNT := 4

enum { STATE_SHOW, STATE_CHOICE }

var _state: int = STATE_SHOW
var _show_timer: float = 0.0
var _bird_index: int = 0
var _seen_bird: int = -1
var _choice_buttons: Array[Rect2] = []
var _correct_choice: int = 0
var _bird_silhouettes: Array = []   # [bird_idx, ...] 打乱顺序
var _choice_options: Array[int] = []  # 选项对应的真实 bird_idx

const BIRD_COLS: Array[Color] = [
	Color(0.55, 0.4, 0.25),
	Color(0.3, 0.35, 0.55),
	Color(0.9, 0.9, 0.85),
	Color(0.2, 0.2, 0.25),
]

## 键盘选第 i 个选项。取消按钮是 _draw() 画的假按钮，键盘够不着，
## 所以键盘玩家原本唯一的出路是干等 World3D 的 30s 超时判 CANCELLED——
## 而禽是 5 块碎片之一，拿不到就永远到不了 5/5，键盘玩家直接卡死在通关前。
const CHOICE_KEYS: Array[int] = [KEY_1, KEY_2, KEY_3, KEY_4]

func _ready() -> void:
	# 随机选一只要记住的鸟
	_seen_bird = randi() % BIRD_COUNT
	_bird_silhouettes = [_seen_bird]
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

	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.7))

	match _state:
		STATE_SHOW:
			_draw_show_phase(w, h)
		STATE_CHOICE:
			_draw_choice_phase(w, h)

func _draw_show_phase(w: float, h: float) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.08),
		Localization.t("mg_bird_title"), HORIZONTAL_ALIGNMENT_CENTER, w, 30, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.14),
		Localization.t("mg_bird_sub"), HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color(0.8, 0.8, 0.8))

	# 鸟的剪影
	var ctr := Vector2(w * 0.5, h * 0.45)
	var sc := minf(w, h) / 280.0
	var col := BIRD_COLS[_seen_bird]
	_draw_bird_silhouette(ctr, col, sc)

	# 倒计时
	draw_string(ThemeDB.fallback_font, Vector2(w * 0.5 - 20, h * 0.78),
		"%d" % max(1, int(_show_timer) + 1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(1, 0.8, 0.4))

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
		draw_rect(r, Color(0.15, 0.15, 0.2), true)
		draw_rect(r, Color(0.7, 0.7, 0.7), false, 2)
		var bird_idx: int = _choice_options[i]
		var col: Color = BIRD_COLS[bird_idx]
		_draw_bird_silhouette(Vector2(bx + btn_w * 0.5, by + btn_h * 0.25), col, sc * 0.7)
		draw_string(ThemeDB.fallback_font, Vector2(bx, by + btn_h * 0.46),
			Localization.t("mg_bird_%d" % bird_idx), HORIZONTAL_ALIGNMENT_CENTER, btn_w, 20, Color(0.9, 0.9, 0.9))
		# 键位角标：键盘玩家看不见鼠标在哪，角标是「哪个键选这只」的唯一线索。
		draw_string(ThemeDB.fallback_font, Vector2(bx + 8.0, by + 24.0),
			str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.75))

func _draw_bird_silhouette(c: Vector2, col: Color, sc: float) -> void:
	# 头
	draw_circle(c + Vector2(20 * sc, -10 * sc), 14 * sc, col)
	# 身体
	draw_circle(c, 22 * sc, col)
	# 翅膀
	var wing_pts := PackedVector2Array([
		c + Vector2(-5 * sc, -5 * sc),
		c + Vector2(-35 * sc, -25 * sc),
		c + Vector2(-20 * sc, 5 * sc),
	])
	draw_colored_polygon(wing_pts, Color(col.r * 0.8, col.g * 0.8, col.b * 0.8))
	# 尾
	var tail_pts := PackedVector2Array([
		c + Vector2(-18 * sc, 5 * sc),
		c + Vector2(-38 * sc, 0),
		c + Vector2(-38 * sc, 15 * sc),
	])
	draw_colored_polygon(tail_pts, Color(col.r * 0.8, col.g * 0.8, col.b * 0.8))

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
	var btn_rect := Rect2(size.x - 160, size.y - 60, 140, 44)
	if btn_rect.has_point(event.position):
		_world_ref._on_mini_game_done(CANCELLED)
		return
	for i in range(_choice_buttons.size()):
		if _choice_buttons[i].has_point(event.position):
			_choose(i)
			return
