extends Control

## 五个小游戏共用一套景。这里用 preload 而不是 class_name：
## `--script` 模式下 class_name 会拉编译期依赖（见 CLAUDE.md 已知陷阱）。
const MiniGameBackdrop = preload("res://scripts/mini_games/MiniGameBackdrop.gd")
const MiniGameBar = preload("res://scripts/mini_games/MiniGameBar.gd")
const MiniGameChrome = preload("res://scripts/mini_games/MiniGameChrome.gd")
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

## 五根竹子的摆法。
##
## 原来每根是一条 `draw_rect(..., 12, ...)` 画的**等宽竖条**，竹节那四条线
## 也是 12px 宽的——画在一条 12px 的条上等于没有。所以这一屏上根本没有竹子，
## 只有五根绿色的柱子和五个数字，而标题写的是"竹子一冒头就按空格"。
const SPACING := 152.0
const STALK_W_BASE := 30.0
const STALK_W_TIP := 15.0
const NODE_COUNT := 4
## 还没冒头那根笋的高度占比。太小的话剩四座就成四个点，
## 这一屏读成"一根竹子 + 四粒灰"。
const SPROUT_FRAC := 0.20
## 砍倒之后画成什么样。
##
## 不把整根放平：五根按 `SPACING` 并排，一根 `h*0.52` 高的竹子倒下去要横跨
## 好几列，五个全倒就是一片绿线团，谁也数不清自己砍了几根。留一截桩、上半截
## 斜靠在桩上，是砍竹子本来就会有的样子，也老老实实待在自己那一列里。
const STUMP_FRAC := 0.16
const FALL_DEG := 72.0
## 斜靠那截的横向伸出占列距的几成。这个数是**从"不许伸进邻居那一列"反解**出来的，
## 不是窗口高度的百分比 —— 按高度取的话，720p 上量着刚好不压到邻居，1080p 上
## 就压上去了（这一节的判据在 1280 高的视口上量到 177px > 152px 就是这么翻的）。
const FALL_REACH_FRAC := 0.78

## 砍倒那截该有多长。横向伸出 = 长度 × sin(FALL_DEG)，所以长度由列距反解。
static func fall_len(spacing: float) -> float:
	return spacing * FALL_REACH_FRAC / sin(deg_to_rad(FALL_DEG))


## 一根竹子的四边形：底宽 `w_base`、顶窄 `w_tip`，绕**底端**朝 `lean_deg`
## 倒过去。倒下的上半截和立着的那半截走的是同一个函数——它们本来就是
## 同一根竹子，只是躺下了。
## 纯函数，不碰画笔（headless 不调 `_draw`，见 CLAUDE.md 已知陷阱）。
static func stalk_poly(base: Vector2, height: float, w_base: float, w_tip: float,
		lean_deg: float) -> PackedVector2Array:
	var a := deg_to_rad(lean_deg)
	var dir := Vector2(sin(a), -cos(a))          # lean=0 时指向正上方
	var side := Vector2(cos(a), sin(a))          # 与竹身垂直
	var tip := base + dir * height
	return PackedVector2Array([
		base - side * (w_base * 0.5), tip - side * (w_tip * 0.5),
		tip + side * (w_tip * 0.5), base + side * (w_base * 0.5),
	])

## 第 n 个竹节距底端的高度占比。竹节比竹身宽一点，是竹子身上最认得出来的一处。
static func node_fracs(count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for n in count:
		# 底端那个节贴着地不算数，从 1/count 开始往上排
		out.append((float(n) + 1.0) / float(count + 1))
	return out

## 第 i 根竹子该往哪边倒。左右交替：都往同一边倒的话，斜靠的那截会压在
## 右边那根还立着的竹子上。交替之后每截只伸进自己那一列。
static func fall_dir(i: int) -> float:
	return 1.0 if i % 2 == 0 else -1.0

## 顶上那片叶。`reach`/`drop`/`width` 三个都直接以像素计。
##
## 叶是**窄条**。原来一片叶的三个顶点是根、朝外上方、斜下方各一个，
## 于是一片叶横向伸到 `bh * 0.31`（116px）却只垂 `bh * 0.14`（52px）——
## 比 30px 宽的竹身还大好几倍，两片一左一右读成一对翅膀或者龙舌兰。
## 竹叶身上最认得出的是"长而窄"：叶宽大致是叶长的十五分之一。
##
## 叶宽是**参数**，不是从别的量推出来的：把中点沿弦的垂直方向推开
## 半个 `width`，量出来的最大宽度就正好是 `width`（等腰三角形），
## 回归可以拿返回的多边形自己复核，不用信这里的注释。
static func leaf_poly(root: Vector2, side: float, reach: float, drop: float,
		width: float) -> PackedVector2Array:
	var tip := root + Vector2(side * reach, drop)
	var chord := tip - root
	if chord.length() <= 0.0:
		return PackedVector2Array([root, root, tip])
	var mid := root + chord * 0.5 + chord.orthogonal().normalized() * (width * 0.5)
	return PackedVector2Array([root, mid, tip])

## 顶上那几片叶。每一项是 [根距竹梢的高度占比（负数）, 横向伸出, 垂下, 叶宽]，
## 四个量都按 `bh` 计。左右各一片。
##
## **画笔和回归读的是同一张表**（和 `CLOUD_CIRCLES` 同一个道理）：测试里另抄
## 一份数字的话，改画不动测、测会一直绿，而"叶宽只有竹身的四分之一"这件事
## 正是这一版的正事。
const LEAVES := [
	[-0.82, 0.24, 0.16, 0.035],   # 长的那片甩出去
	[-0.70, 0.14, 0.30, 0.030],   # 矮的那片垂下来
]


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

	MiniGameBackdrop.draw_scene(self, w, h, MiniGameBackdrop.BAMBOO)

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
	var start_x := w * 0.5 - (BAMBOO_COUNT * SPACING) * 0.5
	var base_y := h * 0.82
	var bh := h * 0.52

	for i in range(BAMBOO_COUNT):
		var bx := start_x + i * SPACING
		var state: int = _bamboo_states[i]
		var alpha := 1.0

		if state == 0:
			# 可砍（当前）：闪烁
			alpha = 0.7 + sin(_t * 12) * 0.3
			# 显示倒计时
			var urgency := 1.0 - _window_timer / WINDOW_SEC
			var timer_col := Color(1.0, urgency, 0.0, 1.0)
			draw_string(ThemeDB.fallback_font, Vector2(bx - 5, base_y - bh - 10),
				"%.1f" % maxf(_window_timer, 0.0),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, timer_col)

		_draw_stalk(i, Vector2(bx, base_y), bh, state, alpha)

		# 序号
		draw_string(ThemeDB.fallback_font, Vector2(bx - 2, base_y + 26),
			"%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.9, 0.7, alpha))

	# 进度：五格。**原来只有一行"进度 0/5"的字，条都没有**——门槛写在了
	# 字里，画在屏上的却是一整屏竹子，玩家读不出还差几根。而竹子的进度是
	# **五件互相独立的事**，所以分格而不是一根连续条：一根填到 60% 的条
	# 读成"有一根被砍掉了 60%"，实际是三根倒了、两根还立着。
	var pbar := MiniGameBar.rect(Vector2(w, h), 0.88, 0.42, 14.0)
	MiniGameBar.draw_pips(self, pbar, BAMBOO_COUNT, _current_bamboo, _current_bamboo,
			Color(0.30, 0.62, 0.32, 0.95), Color(0.14, 0.20, 0.16, 0.75),
			Color(1.0, 0.9, 0.5))

	# 取消按钮。**这一屏原来一个按钮都没画**——理由写在这里是对的：
	# 左键在竹子是"砍"，画个按钮上去还得判点击落在哪、怕误砍。
	# 可那个理由只解释了难做，没解释不做：ESC 能按，可鼠标玩家看见的是
	# 一个点哪都能砍的屏，他没有任何"退出"的地方（ESC 在这一屏是隐藏的）。
	# 误砍的代价是零——1.2 秒窗口自己会过，驿站还能再来一次。
	# 和云那一屏一样，热区判在"当成砍"之前，顺序反了就变成点了取消反而挨一刀。
	MiniGameChrome.draw_cancel(self, MiniGameChrome.cancel_rect(Vector2(w, h)))


## 一根竹子。`state`: -1=还没冒头, 0=可砍, 1=已砍。
## 三种状态走的是同一套几何 —— 立着的时候是上下收分的竹身 + 竹节 + 顶上两片叶，
## 砍倒之后底下一截桩、上半截斜靠着（`stalk_poly` 的 `lean_deg` 就是那个斜度）。
func _draw_stalk(i: int, base: Vector2, bh: float, state: int, alpha: float) -> void:
	var skin := Color(0.30, 0.62, 0.32, alpha)
	var skin_lo := Color(0.20, 0.45, 0.22, alpha)
	var node_col := Color(0.46, 0.74, 0.40, alpha)

	if state == 1:
		var sdir := fall_dir(i)
		# 留在地上的那截桩
		draw_colored_polygon(
			stalk_poly(base, bh * STUMP_FRAC, STALK_W_BASE, STALK_W_BASE * 0.86, 0.0), skin)
		# 斜靠在上半截：同一个四边形按 FALL_DEG 摆过去，所以上下两截
		# 必然接得上、宽窄也必然连续
		var top := base + Vector2(0, -bh * STUMP_FRAC)
		draw_colored_polygon(
			stalk_poly(top, fall_len(SPACING), STALK_W_BASE * 0.86, STALK_W_TIP,
					FALL_DEG * sdir),
			skin)
		# 断口
		draw_line(top + Vector2(-STALK_W_BASE * 0.43, 0.0),
				top + Vector2(STALK_W_BASE * 0.43, 0.0), skin_lo, 3.0)
		return

	if state == -1:
		# 还没冒头：地上一个笋尖。原来只画到 `bh * 0.10` 高，于是这一屏是
		# 一根立着的竹加四个几乎看不见的点，剩四座亭子空着——笋子要读得出
		# "这里还有一根"，高度得够它自己被认成一株。
		draw_colored_polygon(
			stalk_poly(base, bh * SPROUT_FRAC, STALK_W_BASE * 0.62, STALK_W_TIP * 0.7, 0.0),
			Color(0.30, 0.62, 0.32, 0.45))
		return

	draw_colored_polygon(stalk_poly(base, bh, STALK_W_BASE, STALK_W_TIP, 0.0), skin)
	# 竹节：比竹身宽一点的一道亮环
	for f in node_fracs(NODE_COUNT):
		var ny := base.y - bh * f
		var hw := lerpf(STALK_W_BASE, STALK_W_TIP, f) * 0.5 + 3.0
		draw_line(Vector2(base.x - hw, ny), Vector2(base.x + hw, ny), node_col, 4.0)
	# 顶上两片叶。竹子身上最认得出的一处，缺了它这条就是绿色的棍子。
	# 长的那片甩出去，矮的那片垂下来，两片错开一层。
	for s in [-1.0, 1.0]:
		for L in LEAVES:
			draw_colored_polygon(
					leaf_poly(base + Vector2(0.0, bh * L[0]), s,
							bh * L[1], bh * L[2], bh * L[3]), node_col)


## 砍完 5 根后的收尾画面：5 根全倒 + 一句成功文案 + 结算前的停留倒计时。
## 玩家需要这一屏来确认"是我砍赢的"，而不是小游戏被一脚踢掉。
func _draw_success(w: float, h: float) -> void:
	# 收尾时把底色压暗一点，让文案跳出来
	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.45))

	# 5 根全部倒伏，位置/尺寸跟主画面保持一致
	var start_x := w * 0.5 - (BAMBOO_COUNT * SPACING) * 0.5
	var base_y := h * 0.82
	var bh := h * 0.52
	for i in range(BAMBOO_COUNT):
		_draw_stalk(i, Vector2(start_x + i * SPACING, base_y), bh, 1, 0.75)

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
	# ESC 取消。成功画面期间不给 ESC：那 1.6s 是给玩家确认"是我砍赢的"，
	# 跳过它就回到"小游戏凭空消失"那个老毛病。
	if _is_esc_event(event):
		_world_ref._on_mini_game_done(CANCELLED)
		queue_free()
		return
	# 取消按钮。**必须判在"当成砍"之前**：左键在这一屏是砍，
	# 判在后面就成了"点了取消反而挨一刀"。热区走画笔那一处，
	# 见 MiniGameChrome 那条注释。
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and MiniGameChrome.cancel_rect(size).has_point(event.position):
		get_viewport().set_input_as_handled()
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
