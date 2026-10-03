extends Control

## 五个小游戏共用一套景。这里用 preload 而不是 class_name：
## `--script` 模式下 class_name 会拉编译期依赖（见 CLAUDE.md 已知陷阱）。
const MiniGameBackdrop = preload("res://scripts/mini_games/MiniGameBackdrop.gd")
const MiniGameBar = preload("res://scripts/mini_games/MiniGameBar.gd")
const MiniGameChrome = preload("res://scripts/mini_games/MiniGameChrome.gd")
## 云影台(7) 小游戏：拖拽沿轨迹绘制云的形状
## 成功条件：完成80%以上路径

var _world_ref: Node = null

const SUCCESS := 0
const CANCELLED := 1

## 云的形状：**三团叠在一起的圆**，和 `MiniGameBackdrop._clouds()` 画背景那五片
## 云用的是同一套画法。每一项是 [圆心, 半径]（相对轮廓中心的 2D 坐标）。
##
## 原来这里是一串手抄的八边形顶点——玩家描的是"一个多边形"，而同一屏上背景
## 里的云是三个圆叠出来的圆鼓鼓的一团。**同一件事两套画法**，于是"云"这个字
## 在这一屏上没有任何东西指认。轮廓由这五团圆算出来，所以两处必然一致。
const CLOUD_CIRCLES := [
	[Vector2(0.0, -10.0), 30.0],     # 主峰
	[Vector2(-26.0, 2.0), 24.0],     # 左肩
	[Vector2(27.0, 3.0), 22.0],      # 右肩
	[Vector2(-48.0, 15.0), 17.0],    # 左尾
	[Vector2(49.0, 16.0), 16.0],     # 右尾
]
## 轮廓采样数。相邻两点之间的间距必须显著大于 `KEY_STEP`(12px)，否则键盘
## 光标整步走会在目标两侧横跳、`_next_seg` 卡死在没描到的那一段上。
const OUTLINE_SAMPLES := 40
## 云底压平的那条线。团状轮廓的底是圆的，而画上的云一律坐在一条平边上——
## 没有平底的那团东西读成"一团棉花"而不是"一片云"。
const FLAT_Y := 27.0
const PATH_TOLERANCE := 45.0
const SUCCESS_THRESHOLD := 0.75

## 游戏区（描边板）占屏的比例。轨迹的缩放和板子的位置都从它推出来，
## 两处各写一份 `0.15 / 0.7` 必然漂。
const AREA_POS_FRAC := 0.15
const AREA_SIZE_FRAC := 0.70
## 轮廓外接盒占板子的几成。留两成余量，免得描边线宽和落笔容差贴到板边。
const FIT_FRAC := 0.88

static func area_rect(w: float, h: float) -> Rect2:
	return Rect2(w * AREA_POS_FRAC, h * AREA_POS_FRAC,
			w * AREA_SIZE_FRAC, h * AREA_SIZE_FRAC)


## 进度条的几何。**抽成常量**的原因不是整洁：操作提示行的落位要从**量出来的**
## 图形下缘和条上沿之间那段空白里取，而那个 y 分数要是只写在画笔里，
## 提示和条迟早各按各的走。
const BAR_Y_FRAC := 0.88
const BAR_W_FRAC := 0.5
const BAR_H := 16.0

## 操作提示行（"方向键 / WASD 挪光标 · 按住空格落笔 · ESC 取消"）。
const HINT_FONT := 20
## 行盒高。比字号高一点，容得下字形的上下伸部——`draw_string` 的 position.y
## 是**基线**不是行盒顶，量行盒量不出字形有没有探出去。
const HINT_LINE_H := 26.0
## 离前后两样东西各留多少空。
const HINT_GAP := 12.0


## 某个视口下要描的那条轨迹（屏幕坐标）。纯函数：`_build_path_world()` 和
## 回归量的是同一个，抄一份算式的话改画不动测、测会一直绿。
static func path_for(view: Vector2) -> PackedVector2Array:
	var outline := cloud_outline(CLOUD_CIRCLES, OUTLINE_SAMPLES, FLAT_Y)
	var board := area_rect(view.x, view.y)
	var sc := fit_scale(outline, board.size)
	# 按外接盒中心对位，不按原点。轮廓本身不对称（底被压平了），
	# 绕原点缩放再摆到板心，云会整体偏上，板子下沿空出一条。
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in outline:
		mn = mn.min(p)
		mx = mx.max(p)
	var ctr := board.get_center() - (mn + mx) * (sc * 0.5)
	var out := PackedVector2Array()
	for p in outline:
		out.append(ctr + p * sc)
	return out


## 轨迹的外接盒（屏幕坐标）。纯函数。
static func path_bounds(path: PackedVector2Array) -> Rect2:
	if path.size() < 2:
		return Rect2()
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in path:
		mn = mn.min(p)
		mx = mx.max(p)
	return Rect2(mn, mx - mn)


## 操作提示行的行盒（`text_w` 是这串字量出来的宽度，由调用方给）。
##
## 原来这行字落在 `h * 0.8`，而 720p 上要描的云下缘在 563px、那行字的基线
## 在 576px——**玩家的字就横穿在要描的那条轮廓上**，描线时一直压着图形。
## 所以判据是"两个 y 区间不相交"，不是"落在某个绝对位置"。
##
## 落位按顺序试，取第一个**整行都在屏内**的：
##   ① 图形下缘与条上沿之间那段空白（题面要的那一段）
##   ② 条与刻痕标签的下面
##   ③ 板子上沿（title 之下）
## ① 是常态。②③ 只在板子占满整屏高度的窄高视口上才轮得到——那时图形下缘
## 离条太近，硬塞进去就压到条上，而压在条上和压在图形上是同一种毛病。
static func hint_rect(w: float, h: float, path: PackedVector2Array, text_w: float) -> Rect2:
	var tw: float = maxf(text_w, 1.0) + 4.0
	var bar := MiniGameBar.rect(Vector2(w, h), BAR_Y_FRAC, BAR_W_FRAC, BAR_H)
	var lab := MiniGameBar.tick_label_rect(bar, SUCCESS_THRESHOLD)
	var cands: Array[float] = [
		path_bounds(path).end.y + HINT_GAP,
		lab.end.y + HINT_GAP,
		area_rect(w, h).position.y - HINT_LINE_H - HINT_GAP,
	]
	for top in cands:
		if top >= HINT_GAP and top + HINT_LINE_H <= h - HINT_GAP:
			return Rect2((w - tw) * 0.5, top, tw, HINT_LINE_H)
	# 三处都塞不下（视口比这一屏该有的样子还矮）：贴中间，别掉出屏外。
	return Rect2((w - tw) * 0.5, maxf(HINT_GAP, (h - HINT_LINE_H) * 0.5), tw, HINT_LINE_H)


## 把轮廓铺进 `avail` 的缩放。**从外接盒量，不从某一个圆量**——
## 原来写死 `minf(size.x, size.y) / 300.0`，而这个 300 是按 720p 窗口
## 手调的：实测轮廓外接盒 130×67，1280×720 上缩放 2.4 得到 312px 宽，
## 压在 896px 宽的板子正中间——板子四周空出一大片，描边区小到点不准。
static func fit_scale(outline: PackedVector2Array, avail: Vector2) -> float:
	if outline.size() < 2 or avail.x <= 0.0 or avail.y <= 0.0:
		return 1.0
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in outline:
		mn = mn.min(p)
		mx = mx.max(p)
	var span: Vector2 = mx - mn
	if span.x <= 0.0 or span.y <= 0.0:
		return 1.0
	return minf(avail.x * FIT_FRAC / span.x, avail.y * FIT_FRAC / span.y)

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
	# 走 `path_for()`：轨迹的算式只有一份，画笔和回归读同一个函数。
	# 仍然是 Array 而不是 PackedVector2Array——`verify_mini_game.gd` 第 7 节
	# 按 `var cpts: Array = cloud._path_world` 读它。
	_path_world.clear()
	for p in path_for(size):
		_path_world.append(p)
	if _key_cursor == Vector2.ZERO:
		_key_cursor = _path_world[0] if _path_world.size() > 0 else size * 0.5


## 团状轮廓：绕中心每条射线上取**最远**的一处圆周。
##
## 纯函数，不碰画笔——headless 根本不调 `_draw`（见 CLAUDE.md 已知陷阱），
## 所以"描的东西到底是不是一朵云"必须在函数层面量得到。
##
## 取最远而不是去求这几圆真正的并集边界：这团东西对中心是星形的
## （没有哪条射线先进后出两趟），于是射线最大值给出来的就是外圈那一串鼓包。
static func cloud_outline(circles: Array, samples: int, flat_y: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in samples:
		var th := TAU * float(i) / float(samples)
		var dir := Vector2(cos(th), sin(th))
		var far := 0.0
		for c in circles:
			var cd: Array = c
			var p: Vector2 = cd[0]
			var r: float = cd[1]
			# 射线 t·dir 与圆 (p, r) 相交：t² − 2t(dir·p) + (p·p − r²) = 0
			var b := dir.dot(p)
			var disc := b * b - (p.dot(p) - r * r)
			if disc <= 0.0:
				continue
			far = maxf(far, b + sqrt(disc))
		# 底沿压平：落在平边以下的点抬上来，相邻两点之间自然连成一条直线
		out.append(Vector2(dir.x * far, minf(dir.y * far, flat_y)))
	return out

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
	var area := area_rect(w, h)
	draw_rect(area, Color(0.16, 0.22, 0.28, 0.34), true)
	draw_rect(area, Color(1, 1, 1, 0.55), false, 2)

	# 标题
	draw_string(ThemeDB.fallback_font, Vector2(0.0, h * 0.1),
		Localization.t("mg_cloud_title"), HORIZONTAL_ALIGNMENT_CENTER, w, 28, Color.WHITE)

	# 云本身：一层压淡的实心剪影。原来只有一圈点和虚线，中间是透出天光的
	# 空板子——玩家描的是"一个圈"，而"云"是这块圈围出来的**面**。
	var fill := PackedVector2Array(_path_world)
	if fill.size() > 2:
		draw_colored_polygon(fill, Color(0.94, 0.97, 1.0, 0.22))

	# 描过的笔迹。一个"描边"游戏原本**一笔都不画**——进度只由那个百分比
	# 承担，而百分比是抽象的：玩家看不见自己画到哪儿了，只知道它在涨。
	# 笔迹就是 `_next_seg` 本身：段是顺序认领的，所以"已经描过的"恰好等于
	# 0.._next_seg 这一段前缀，不用另记一份数据。
	if _next_seg >= 2 and _next_seg <= _path_world.size() - 1:
		draw_polyline(PackedVector2Array(_path_world.slice(0, _next_seg + 1)),
				Color(0.55, 0.86, 1.0, 0.95), 5.0, true)

	# 目标轨迹（虚线）。板子现在是半透明的，底下是随高度变化的天光，
	# 纯白的点在天亮的那一段会淡掉 —— 每个点先压一道深色晕再点白心。
	for i in range(_path_world.size()):
		var p: Vector2 = _path_world[i]
		if i < _path_world.size() - 1:
			var np: Vector2 = _path_world[i + 1]
			# 已经描过的那一段不再压虚线，免得笔迹被盖回去
			if i < _next_seg:
				continue
			draw_line(p, np, Color(0.10, 0.14, 0.18, 0.35), 4, true)
			draw_line(p, np, Color(1, 1, 1, 0.72), 2, true)
		if i > _next_seg:
			draw_circle(p, 7, Color(0.10, 0.14, 0.18, 0.40))
			draw_circle(p, 5, Color(1, 1, 1, 0.92))

	# 进度条。**门槛要画在条上**：原来只把 75% 写在字里（"到 75% 算过"），
	# 而条是一条填到头就赢的槽——玩家看着 40% 不知道那是还有一半的路，
	# 还是差得远。刻痕跨在条外，门槛之后那一截底色也更亮。
	var bar := MiniGameBar.rect(Vector2(w, h), BAR_Y_FRAC, BAR_W_FRAC, BAR_H)
	MiniGameBar.draw_bar(self, bar, _drawn_ratio, SUCCESS_THRESHOLD,
			Color(0.4, 0.8, 1.0), Color(0.2, 0.2, 0.2), Color(1, 1, 1, 0.55),
			Color(1.0, 0.85, 0.35))
	draw_string(ThemeDB.fallback_font, Vector2(bar.position.x, bar.position.y - 8),
		# 把及格线一起报出来。原来只写"完成度 62%"，玩家不知道 62% 到底算不算赢，
		# 于是描到边缘也不知道是差一口还是早就能松手了 —— 一个没有任何参照的百分比。
		Localization.t("mg_complete", [int(_drawn_ratio * 100), int(SUCCESS_THRESHOLD * 100)]),
		HORIZONTAL_ALIGNMENT_LEFT, bar.size.x, 18, Color.WHITE)
	# 刻痕上的那个数。字里报了一次、条上报一次，两处是同一个常量——差一步
	# 就是"刻痕在 75%、字里写 70%"，而那正是玩家会拿去做决定的那个数。
	# 落位走 `tick_label_rect()`：宽度那个参数是**裁切宽度**，给窄了百分号
	# 被切掉，图上只剩「75」——这只有定妆照看得见。
	var tl: Rect2 = MiniGameBar.tick_label_rect(bar, SUCCESS_THRESHOLD)
	draw_string(ThemeDB.fallback_font, tl.position,
			"%d%%" % int(SUCCESS_THRESHOLD * 100), HORIZONTAL_ALIGNMENT_CENTER,
			tl.size.x, MiniGameBar.TICK_LABEL_FONT, Color(1.0, 0.85, 0.35))

	# 取消按钮
	MiniGameChrome.draw_cancel(self, MiniGameChrome.cancel_rect(Vector2(w, h)))

	# 键盘光标：没有它键盘玩家看不见自己在哪儿，只能盲按方向键
	draw_line(_key_cursor + Vector2(-9, 0), _key_cursor + Vector2(9, 0), Color(1, 0.85, 0.4), 2.0, true)
	draw_line(_key_cursor + Vector2(0, -9), _key_cursor + Vector2(0, 9), Color(1, 0.85, 0.4), 2.0, true)
	# 操作提示行。落位走 `hint_rect()`：原来它写死 `h * 0.8`，而 720p 上要描的
	# 云下缘在 563px、这行字的基线在 576px——**字横穿在要描的那条轮廓上**。
	# 宽度用 `get_string_size()` 量（`draw_string` 的宽度参数是**裁切宽度**，
	# 写死一个 `w` 当居中宽度虽然碰巧不裁，但也量不出"这行字有多宽"）。
	var hint_text: String = Localization.t("mg_cloud_hint")
	var hint: Rect2 = hint_rect(w, h, PackedVector2Array(_path_world),
			ThemeDB.fallback_font.get_string_size(hint_text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT).x)
	# 基线，不是行盒顶：字形要从行盒顶往下长
	draw_string(ThemeDB.fallback_font,
			Vector2(hint.position.x, hint.position.y + ThemeDB.fallback_font.get_ascent(HINT_FONT)),
			hint_text, HORIZONTAL_ALIGNMENT_LEFT, hint.size.x, HINT_FONT,
			Color(0.75, 0.75, 0.8))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_gui_input_key(event)
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 热区走画笔那一处，见 MiniGameChrome 那条注释
				var btn_rect: Rect2 = MiniGameChrome.cancel_rect(size)
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
