extends Control

## 五个小游戏共用一套景。这里用 preload 而不是 class_name：
## `--script` 模式下 class_name 会拉编译期依赖（见 CLAUDE.md 已知陷阱）。
const MiniGameBackdrop = preload("res://scripts/mini_games/MiniGameBackdrop.gd")
const MiniGameChrome = preload("res://scripts/mini_games/MiniGameChrome.gd")
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

## 古琴身上那 13 个"徽"。它们是嵌在琴面里的螺钿小圆点，从琴额那头的岳山
## 一路排向琴尾的雁足，标的是泛音的位置——**古琴最有辨识度的一处**。
##
## 原来这具琴身只有一块收分的木色多边形加四根弦，屏上又没有一处字提到"琴"
## （标题是「记住音符顺序并重复」），于是这一屏读出来的是"一块有四根线的板子"。
## 徽位、岳山、雁足三样一起摆上，那块板子才真的是一张琴。
const HUI_COUNT := 13
const HUI_R := 6.0
## 徽只排在岳山与雁足之间，不铺满全长
const HUI_FROM := 0.16
const HUI_TO := 0.88


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

## 琴身所占的矩形。四块几何都从它推出来，所以它自己也是一份单一出处。
func _board_rect() -> Rect2:
	return Rect2(size.x * 0.10, size.y * 0.24, size.x * 0.80, size.y * 0.40)


## 四根弦的命中区。**只算几何，不碰画笔**。
##
## 原来这段只写在 `_draw()` 里，于是"弦到底顺不顺着琴身长边"这件事在
## `--headless` 下量不到：回归读 `_note_rects` 只会读到空数组，量的是
## "headless 不调 _draw"这条已知事实，不是这段几何对不对（同族：禽的
## 剪影抽 `_poly` / `_oval`）。抽出来之后 `_draw()` 照旧填 `_note_rects`，
## 回归直接调它。
func _string_rects() -> Array[Rect2]:
	var board := _board_rect()
	var row_h := board.size.y / float(NOTE_COUNT)
	var out: Array[Rect2] = []
	for i in range(NOTE_COUNT):
		var sy := board.position.y + row_h * (float(i) + 0.5)
		out.append(Rect2(board.position.x, sy - row_h * 0.5, board.size.x, row_h))
	return out


## 13 个徽在琴面上的位置。**纯函数，不碰画笔**（headless 不调 `_draw`）。
## 判据钉的是"徽有 13 个、且不铺满全长"，而不是某一组坐标。
static func hui_positions(from_frac: float, to_frac: float, count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in count:
		out.append(from_frac + (to_frac - from_frac) * float(i) / float(count - 1))
	return out


## 琴身的收分多边形。**抽成静态纯函数**的原因不是整洁：`head_h` / `tail_h`
## / 收分的起点是琴身、弦、雁足三样共用的尺寸，原先只写在 `_draw()` 里，
## 于是"弦有没有超出木头""雁足有没有被琴身盖住"这两条在 `--headless` 下
## 根本无从量起（headless 根本不调 `_draw`，见 CLAUDE.md 已知陷阱）。
static func body_poly(board: Rect2) -> PackedVector2Array:
	var cy := board.position.y + board.size.y * 0.5
	var head_h := board.size.y * 0.5
	var tail_h := board.size.y * 0.34
	return PackedVector2Array([
		Vector2(board.position.x, cy - head_h),
		Vector2(board.end.x - board.size.x * 0.10, cy - tail_h),
		Vector2(board.end.x, cy - tail_h * 0.72),
		Vector2(board.end.x, cy + tail_h * 0.72),
		Vector2(board.end.x - board.size.x * 0.10, cy + tail_h),
		Vector2(board.position.x, cy + head_h),
	])


## 琴身在某一行的左右沿。**纯函数，不碰画笔**。
##
## 四根弦原来是按 `board` 的**全宽**画的（`_draw_string_h` 里那个 `x1 =
## board.end.x - 18`），而琴身是内收的多边形——于是在靠外的那两根弦上，
## 弦从 `x ≈ 0.70·W` 之后就在木头外面了，那一段连同它两端的琴码和雁柱一起
## 悬在半空，屏上读出来是"四条线加四个悬空的小方块"。
##
## 判据钉的是这个函数量出来的**那一行的实际左右沿**，不是弦画在哪儿：
## 弦的左右端必须落在这一行的沿**内侧**，而两端点到沿的距离得由弦自己的
## 内缩量决定（`STRING_INSET`），写死一个 `board.end.x` 就是把 bug 抄回来。
static func body_span_at(body: PackedVector2Array, y: float) -> Vector2:
	var lo := INF
	var hi := -INF
	var n := body.size()
	for i in n:
		var a := body[i]
		var b := body[(i + 1) % n]
		if is_equal_approx(a.y, b.y):
			# 水平边：这一行若正落在它上面，两端都算进沿
			if absf(y - a.y) <= 0.5:
				lo = minf(lo, minf(a.x, b.x))
				hi = maxf(hi, maxf(a.x, b.x))
			continue
		if y >= minf(a.y, b.y) and y <= maxf(a.y, b.y):
			var t := (y - a.y) / (b.y - a.y)
			var x := lerpf(a.x, b.x, t)
			lo = minf(lo, x)
			hi = maxf(hi, x)
	if hi < lo:
		return Vector2.ZERO
	return Vector2(lo, hi)


## 弦的两端（木面里侧收进来的那一点）。**纯函数**：`y` 是弦所在的那一行，
## 返回的是这根弦真正画的左右端——回归量的是它和 `body_span_at()` 的关系。
static func string_span(board: Rect2, body: PackedVector2Array, y: float) -> Vector2:
	var span := body_span_at(body, y)
	return Vector2(span.x + STRING_INSET, span.y - STRING_INSET)


## 弦两端往木头里收多少。琴码和雁柱是钉在木面上的，弦得压在木头里一点。
const STRING_INSET := 14.0


## 岳山与雁足的落点。**和 `_draw` 同源**——判据量的是画笔真的摆的那一处。
## 在测试里把这几个算式抄一遍的话，改画不动测、测会一直绿。
static func head_anchor(board: Rect2) -> Vector2:
	return Vector2(board.position.x + board.size.y * 0.12, board.get_center().y)


## 琴身在某一列的上下沿。`body_span_at` 的横向版本——
## 雁足要挂在"某个 x 处的肚子底下"，而那个下沿只能横着求。
##
## 缺了它就会写出拿横向跨度当竖直落差的那种代码：第一版
## `foot_anchor` 返回 `Vector2(span.y - 44.0, center.y)`，拿**右沿的 x**
## 减 44 当锚点、再用同一行的右沿减锚点 y 当"脚该垂多低"，
## 于是 drop 算出来 590px——琴腹底下挂了两只各半米长的脚。
static func body_vspan_at(body: PackedVector2Array, x: float) -> Vector2:
	var lo := INF
	var hi := -INF
	var n := body.size()
	for i in n:
		var a := body[i]
		var b := body[(i + 1) % n]
		if is_equal_approx(a.x, b.x):
			if absf(x - a.x) <= 0.5:
				lo = minf(lo, minf(a.y, b.y))
				hi = maxf(hi, maxf(a.y, b.y))
			continue
		if x >= minf(a.x, b.x) and x <= maxf(a.x, b.x):
			var t := (x - a.x) / (b.x - a.x)
			var y := lerpf(a.y, b.y, t)
			lo = minf(lo, y)
			hi = maxf(hi, y)
	if hi < lo:
		return Vector2.ZERO
	return Vector2(lo, hi)


## 雁足挂在**琴腹下沿之下**，而那个下沿是琴身在该 x 处的真实边界。
## 原来写的是 `tail_h * 0.55`，而琴尾那处的琴腹下沿在 `tail_h * 0.82`
## 上下——两只脚于是整只都埋在木头里，画是画了，一根墨都没露出来，
## 而"没有雁足的琴"和"有雁足的琴"在无头下是同一张图。
static func foot_anchor(board: Rect2, body: PackedVector2Array) -> Vector2:
	var x := board.position.x + board.size.x * FOOT_X_FRAC
	return Vector2(x, body_vspan_at(body, x).y)


## 琴长上几成处挂雁足。古琴的雁足在琴尾那一段，挂在琴腹底下。
const FOOT_X_FRAC := 0.86


## 雁足从琴腹下沿**开始**，往下、朝外分叉成两支。`drop` 是脚的高度。
static func foot_polys(anchor: Vector2, drop: float) -> Array:
	var out: Array = []
	for s in [-1.0, 1.0]:
		out.append(PackedVector2Array([
			anchor + Vector2(0.0, 2.0),
			anchor + Vector2(s * drop * 0.55, drop),
			anchor + Vector2(s * drop * 1.05, drop * 0.82),
		]))
	return out


## 琴额那头的岳山与琴轸。岳山是弦在琴头那端压住的那一道，琴轸是穿过它调弦的两枚栓。
##
## 岳山要**压在琴面里**：原来的高取到 `head_h * 0.86`，而琴额那半高就是
## `head_h`，于是一道比琴身还高的黑板戳在琴头左侧、上下各露出一截——
## 读起来是"琴旁边竖了块牌子"，不是琴上压弦的那道棱。
static func headgear_poly(anchor: Vector2, head_h: float) -> PackedVector2Array:
	return PackedVector2Array([
		anchor + Vector2(-head_h * 0.22, -head_h * 0.58),
		anchor + Vector2(0.0, -head_h * 0.44),
		anchor + Vector2(0.0, head_h * 0.44),
		anchor + Vector2(-head_h * 0.22, head_h * 0.58),
	])



func _draw() -> void:
	var w := size.x
	var h := size.y

	MiniGameBackdrop.draw_scene(self, w, h, MiniGameBackdrop.ZITHER)

	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.1),
		Localization.t("mg_zither_title"), HORIZONTAL_ALIGNMENT_CENTER, w, 28, Color.WHITE)

	# 琴面。原版是四块并排的纯色方块 + 数字，玩家读到的是"按 2"，
	# 不是"拨第二根弦"。这里给一块木色琴面 + 四根并排的弦。
	#
	# 弦必须**顺着琴身的长边**走。古琴的弦平行于长轴，玩家是横着拨的；
	# 旧版把四根弦竖着插在一条又宽又短的琴身上，等于让玩家去拨一块
	# 2.4m 宽的板子的短边——那不是琴，而且木面的宽高比和"琴"正好相反。
	# 琴身也照古琴的样子收分：琴额（左）宽，琴尾（右）窄。
	var board := _board_rect()
	var cy := board.position.y + board.size.y * 0.5
	var head_h := board.size.y * 0.5
	var body := body_poly(board)
	draw_colored_polygon(body, Color("4A3524"))
	draw_polyline(body, Color("2A1C12"), 3.0)

	# 琴身的三样附件：岳山+琴轸在琴额那头，雁足在琴尾，13 个徽排在当中。
	# 徽要压在弦**下面**一层（它们嵌在木面里），所以画在弦之前。
	var hx0 := board.position.x
	var hx1 := board.end.x
	# 锚点给琴额**内侧**：headgear 的背面从锚点往左退 0.22·head_h，
	# 锚点摆在 hx0 + 16 的话那道棱就有 15px 戳在琴身之外（原来那块黑板就是这么
	# 冒出来的）。弦从 hx0 + 14 起，正好压在岳山上面——古琴本来就是这样。
	draw_colored_polygon(headgear_poly(head_anchor(board), head_h), Color("3A2818"))
	# 琴轸：岳山两侧各一枚
	draw_rect(Rect2(hx0 + 0.06 * head_h, cy - head_h * 0.40, 22.0, 5.0), Color("9A7A52"), true)
	draw_rect(Rect2(hx0 + 0.06 * head_h, cy + head_h * 0.40 - 5.0, 22.0, 5.0), Color("9A7A52"), true)
	# 雁足挂在**量出来的**琴腹下沿之下。原来写死 `tail_h * 0.55`，那是木头里面，
	# 两只脚整只被琴身盖住——画了，等于没画。
	var fa := foot_anchor(board, body)
	for fp in foot_polys(fa, board.size.y * 0.16):
		draw_colored_polygon(fp, Color("3A2818"))
	# 徽：排在正中线上——四根弦的两根中间正好空出一条，而徽本就该在这条线上
	for f in hui_positions(HUI_FROM, HUI_TO, HUI_COUNT):
		var hp := Vector2(lerpf(hx0, hx1, f), cy)
		draw_circle(hp, HUI_R, Color("D8CDA8", 0.95))
		draw_circle(hp, HUI_R * 0.42, Color("6B5535", 0.9))

	var row_h := board.size.y / float(NOTE_COUNT)
	var amp := row_h * 0.26
	# 命中区是整根弦所在的一条横带，比弦本身粗，玩家不必瞄准细线。
	# 几何全在 _string_rects() 里，这里只把它搬到鼠标要用的那一份。
	_note_rects = _string_rects()
	for i in range(NOTE_COUNT):
		var sy := _note_rects[i].get_center().y
		_draw_string_h(i, sy, body, amp)
		# 键位提示压在琴尾之外，数字不再抢在弦前面
		draw_string(ThemeDB.fallback_font,
			Vector2(board.end.x + 12.0, sy + 9.0), "%d" % (i + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.85, 0.78, 0.62))

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
	MiniGameChrome.draw_cancel(self, MiniGameChrome.cancel_rect(Vector2(w, h)))

## 一根弦。**横向**的：沿着琴身长边从琴额拉到琴尾，振动方向是上下。
## 振幅 = _ring[i] 随时间衰减，位移是两端固定的驻波：
## sin(pi·t) 保证两端钉死不动（琴码和雁柱），sin(_ring_t·f) 给出振动。
## 不振时退化成一条直线，但仍然画——四根弦必须在静止时也看得出来是四根。
func _draw_string_h(i: int, sy: float, body: PackedVector2Array, amp: float) -> void:
	var col: Color = _note_cols[i]
	var e: float = _ring[i]
	var lit := _active_note == i
	# 两端按**琴身在这一行的实际左右沿**裁，不要按 `board` 全宽。
	# 靠外那两根弦原本一直画到 `board.end.x`，而那一段木头已经收走了——
	# 弦连同两端的琴码、雁柱一起悬在半空。
	var span := string_span(_board_rect(), body, sy)
	var x0 := span.x
	var x1 := span.y
	var pts := PackedVector2Array()
	for s in range(RING_SEGMENTS + 1):
		var t := float(s) / float(RING_SEGMENTS)
		pts.append(Vector2(
			lerpf(x0, x1, t),
			sy + e * amp * sin(_ring_t * RING_FREQ + t * 3.0) * sin(PI * t)))
	draw_polyline(pts, col.lightened(0.15 if lit else 0.0), 3.0 if lit else 1.8)
	# 两端的弦轴：左端琴码、右端雁柱，把这条线钉在木面上，
	# 也顺便交代"这是弦不是划痕"
	draw_rect(Rect2(x0 - 12.0, sy - 7.0, 8.0, 14.0), Color("8A6A4A"), true)
	draw_rect(Rect2(x1 + 4.0, sy - 6.0, 7.0, 12.0), Color("8A6A4A"), true)
	# 拨响时弦心亮一下，驻波的包络比整条弦提亮更容易被余光捕捉
	if e > 0.02:
		draw_circle(Vector2(lerpf(x0, x1, 0.5), sy), 4.0 + 6.0 * e,
				Color(col.r, col.g, col.b, 0.55 * e))


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

	# 取消按钮。热区走画笔那一处，见 MiniGameChrome 那条注释
	var btn_rect: Rect2 = MiniGameChrome.cancel_rect(size)
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
