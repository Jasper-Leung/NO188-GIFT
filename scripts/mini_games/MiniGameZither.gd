extends Control
## 琴音林(13) 小游戏：Simon Says 记忆音符序列

var _world_ref: Node = null

const SUCCESS := 0
const CANCELLED := 1
const SEQUENCE_LEN := 4
const NOTE_COUNT := 4
const SHOW_DELAY := 0.7
## 示范阶段两声之间的空档。原来这个 0.2 是散在协程末尾的一个字面量。
const SHOW_GAP := 0.2
const INPUT_TIMEOUT := 2.5

enum { STATE_SHOW, STATE_INPUT, STATE_DONE }

var _state: int = STATE_SHOW
var _sequence: Array[int] = []
var _player_input: Array[int] = []
var _seq_index: int = 0
var _note_show_timer: float = 0.0
var _input_timer: float = 0.0
var _active_note: int = -1
var _note_rects: Array[Rect2] = []
var _note_keys: Array[int] = [KEY_1, KEY_2, KEY_3, KEY_4]
var _note_cols: Array[Color] = [
	Color("C9A26B"), Color("8FB35A"), Color("6E9C6B"), Color("B0C4DE")
]

## 弦的振动。原来四个音符是四块纯色方块加数字——玩家看到的是"按 2"，
## 不是"拨第二根弦"。这里给每根弦一份能量：拨下去瞬间置 1，每帧衰减，
## _draw 把弦画成一条两端固定的驻波。示范阶段和玩家输入都会亮，同一根弦
## 因此同时承担"现在该按谁"和"这是一件乐器"两件事。
const RING_DECAY := 2.6
const RING_FREQ := 34.0
const RING_SEGMENTS := 18
var _ring: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _ring_t: float = 0.0

func _ready() -> void:
	_build_sequence()
	_note_show_timer = 0.5  # 首次显示延迟
	queue_redraw()

func _build_sequence() -> void:
	for i in range(SEQUENCE_LEN):
		_sequence.append(randi() % NOTE_COUNT)

func _process(delta: float) -> void:
	_ring_t += delta
	var ringing := false
	for i in range(NOTE_COUNT):
		_ring[i] = maxf(0.0, _ring[i] - delta * RING_DECAY)
		if _ring[i] > 0.001:
			ringing = true
	# 弦在振的时候必须继续重画：光靠 _active_note 的开关做不出"拨下去→余音收住"
	# 这条衰减曲线，只会在两个离散状态之间硬切。
	if ringing:
		queue_redraw()
	match _state:
		STATE_SHOW:
			_note_show_timer -= delta
			if _note_show_timer <= 0.0:
				_advance_show()
			else:
				queue_redraw()
		STATE_INPUT:
			_input_timer -= delta
			if _input_timer <= 0.0:
				# 超时未输入 → 失败
				_world_ref._on_mini_game_done(CANCELLED)
				queue_free()
			queue_redraw()

## 示范阶段只有这一个时钟。
##
## 原来这里是两套：`_show_next_note()` 既设了 `_note_show_timer = SHOW_DELAY`，
## 又 `await get_tree().create_timer(SHOW_DELAY).timeout` 然后自己把灯灭掉、
## `_seq_index += 1`——而 `_process` 那边还在每帧把同一个计时器往下减，减到 0
## 就再调一次 `_show_next_note()`。两套时钟抢同一个 `_seq_index`。
##
## 本机 280+ FPS 下协程稳定抢先，量出来是干净的 0.7s 节拍（见
## .review/probe_zither.gd 的 0.68/0.21），所以**看不出问题**；帧率一低
## （Web 导出正是这个场景）就可能两边同时到，于是同一个音播两遍、
## `_seq_index` 一次跳两格——玩家听到的序列和屏上写的「第 n/4 个」对不上，
## 照着弹必然错。这类"只在本机不复现"的竞态，改法是消灭竞态而不是加延时。
func _advance_show() -> void:
	if _active_note >= 0:
		# 刚才那声弹完了：灭灯、记进度，再留一小段空档
		_active_note = -1
		_seq_index += 1
		_note_show_timer = SHOW_GAP
		queue_redraw()
		return
	if _seq_index >= _sequence.size():
		_state = STATE_INPUT
		_input_timer = INPUT_TIMEOUT
		queue_redraw()
		return
	_active_note = _sequence[_seq_index]
	_ring[_active_note] = 1.0
	# 示范阶段这声比玩家敲的那几声更关键：整个小游戏就是"先听一段、再照着弹"，
	# 静音的时候玩家只能死盯高亮的那一格记住顺序。
	AudioManager.play_sfx("zither_%d" % (_active_note + 1))
	_note_show_timer = SHOW_DELAY
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y

	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.7))

	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.1),
		Localization.t("mg_zither_title"), HORIZONTAL_ALIGNMENT_CENTER, w, 28, Color.WHITE)

	# 琴面。原版是四块并排的纯色方块 + 数字，玩家读到的是"按 2"，
	# 不是"拨第二根弦"。这里给一块木色琴面 + 四根并排的弦。
	var board := Rect2(w * 0.10, h * 0.24, w * 0.80, h * 0.40)
	draw_rect(board, Color("4A3524"), true)
	draw_rect(board, Color("2A1C12"), false, 3.0)

	var col_w := board.size.x / NOTE_COUNT
	var amp := board.size.x * 0.028
	_note_rects.clear()
	for i in range(NOTE_COUNT):
		var cx := board.position.x + col_w * (float(i) + 0.5)
		# 命中区是整根弦所在的一列，比弦本身宽，玩家不必瞄准细线
		_note_rects.append(Rect2(cx - col_w * 0.5, board.position.y - 24.0, col_w, board.size.y + 48.0))
		_draw_string_v(i, cx, board, amp)
		# 键位提示压在木面下沿，数字不再抢在弦前面
		draw_string(ThemeDB.fallback_font,
			Vector2(cx - col_w * 0.5, board.end.y + 34.0), "%d" % (i + 1),
			HORIZONTAL_ALIGNMENT_CENTER, col_w, 26, Color(0.85, 0.78, 0.62))

	# 状态文字
	var status := ""
	match _state:
		STATE_SHOW:
			status = Localization.t("mg_zither_watch", [_seq_index + 1, SEQUENCE_LEN])
		STATE_INPUT:
			status = Localization.t("mg_zither_turn", [
				_player_input.size() + 1, SEQUENCE_LEN, maxf(_input_timer, 0.0)])

	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.88),
		status, HORIZONTAL_ALIGNMENT_CENTER, w, 24, Color(0.9, 0.9, 0.9))

	# 取消
	var btn_rect := Rect2(w - 160, h - 60, 140, 44)
	draw_rect(btn_rect, Color(0.4, 0.3, 0.3), true)
	draw_rect(btn_rect, Color(0.8, 0.3, 0.3), false, 2)
	draw_string(ThemeDB.fallback_font, Vector2(btn_rect.position.x, btn_rect.position.y + 30),
		Localization.t("mg_cancel"), HORIZONTAL_ALIGNMENT_CENTER, btn_rect.size.x, 22, Color.WHITE)

## 一根弦。振幅 = _ring[i] 随时间衰减，横向位移是两端固定的驻波：
## sin(pi·t) 保证两端钉死不动（琴码和雁柱），sin(_ring_t·f) 给出振动。
## 不振时退化成一条直线，但仍然画——四根弦必须在静止时也看得出来是四根。
func _draw_string_v(i: int, cx: float, board: Rect2, amp: float) -> void:
	var col: Color = _note_cols[i]
	var e: float = _ring[i]
	var lit := _active_note == i
	var pts := PackedVector2Array()
	for s in range(RING_SEGMENTS + 1):
		var t := float(s) / float(RING_SEGMENTS)
		var x := cx + e * amp * sin(_ring_t * RING_FREQ + t * 3.0) * sin(PI * t)
		pts.append(Vector2(x, board.position.y + board.size.y * t))
	draw_polyline(pts, col.lightened(0.15 if lit else 0.0), 3.0 if lit else 1.8)
	# 弦轴：上端一颗小圆点，把这根线钉在木面上，也顺便交代"这是弦不是划痕"
	draw_circle(Vector2(cx, board.position.y), 5.0, Color("8A6A4A"))
	draw_circle(Vector2(cx, board.end.y), 5.0, Color("8A6A4A"))
	# 拨响时弦心亮一下，驻波的包络比整条弦提亮更容易被余光捕捉
	if e > 0.02:
		draw_circle(Vector2(cx, board.position.y + board.size.y * 0.5),
			4.0 + 6.0 * e, Color(col.r, col.g, col.b, 0.55 * e))


func _gui_input(event: InputEvent) -> void:
	# ESC 取消。取消按钮是 _draw() 画的假按钮，键盘点不到——不接 ESC 的话
	# 键盘玩家在示范阶段完全出不去，只能看着它自己走完；示范完了也只有
	# 2.5s 的 INPUT_TIMEOUT 能把他带走，剩下那两个小游戏都有 ESC。
	if event is InputEventKey:
		var ekc: int = event.keycode if event.keycode != 0 else event.physical_keycode
		if ekc == KEY_ESCAPE and event.pressed and not event.echo:
			_world_ref._on_mini_game_done(CANCELLED)
			queue_free()
			return
	if _state != STATE_INPUT:
		return
	if _note_rects.is_empty():
		return

	# 取消按钮
	var w := size.x
	var h := size.y
	var btn_rect := Rect2(w - 160, h - 60, 140, 44)
	if event is InputEventMouseButton and event.pressed and btn_rect.has_point(event.position):
		_world_ref._on_mini_game_done(CANCELLED)
		return

	# 键盘输入。keycode 和 physical_keycode 都要认：本项目 InputMap 用
	# physical_keycode 注册 interact，而 Web 导出下 keycode 可能填不上，
	# 只判 keycode 的话琴键按了没反应，INPUT_TIMEOUT 到点判 CANCELLED。
	var key_idx := -1
	if event is InputEventKey and event.pressed:
		for i in range(NOTE_COUNT):
			if event.keycode == _note_keys[i] or event.physical_keycode == _note_keys[i]:
				key_idx = i
				break

	# 鼠标点击
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(NOTE_COUNT):
			if _note_rects[i].has_point(event.position):
				key_idx = i
				break

	if key_idx < 0:
		return

	_player_input.append(key_idx)
	_input_timer = INPUT_TIMEOUT
	_ring[key_idx] = 1.0
	# 音在"敲下去"这一刻就出，不等对错判定——弹错音的反馈本来就该和
	# 手指落弦同时发生，等判完再响会慢半拍。
	AudioManager.play_sfx("zither_%d" % (key_idx + 1))

	# 检查正确性
	if _player_input[_player_input.size() - 1] != _sequence[_player_input.size() - 1]:
		_world_ref._on_mini_game_done(CANCELLED)
		queue_free()
		return

	if _player_input.size() >= _sequence.size():
		_world_ref._on_mini_game_done(SUCCESS)
		queue_free()
