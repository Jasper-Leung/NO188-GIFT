extends RefCounted
## 三个小游戏共用的进度条。
##
## 原来三处各画各的：云画一根"完成度"、茶画一根"按住多久"、竹连条都没有、
## 只写了一行"进度 0/5"。三处**都把门槛写在了字里**（"到 75% 算过" /
## "3 秒后完成" / "0/5"），而**没有一处把门槛画在条上**——玩家盯着一条
## 填到头就赢的条，看不出自己还差多远，而那个差距正是这一屏的全部张力。
##
## 用 preload 而不是 class_name：`--script` 模式下 class_name 会拉编译期依赖
## （见 CLAUDE.md 已知陷阱）。

## 条的几何。`y_frac` / `w_frac` 按视口算，`h_px` 是像素——高度按视口取的话
## 换个分辨率就跟着变形，而一根 22px 的条在 720p 和 1080p 上本来是同一种东西。
static func rect(v: Vector2, y_frac: float, w_frac: float, h_px: float) -> Rect2:
	var bw: float = v.x * w_frac
	return Rect2(v.x * 0.5 - bw * 0.5, v.y * y_frac, bw, h_px)

## 门槛那一道刻痕的横坐标。**从 `rect` 自己算**：把这条算式抄到画笔那一侧、
## 或者从"视口宽乘一个数"另算一份，抄的那份和画的那条迟早漂。
static func threshold_x(rect: Rect2, threshold: float) -> float:
	return rect.position.x + rect.size.x * clampf(threshold, 0.0, 1.0)

## 刻痕要露出条外——画在条里面时它就是"条上的一道纹"，和进度条的边框、
## 分隔线长得一样，扫一眼分辨不出它是门槛。
const TICK_OVERHANG := 5.0

## 门槛刻痕的两个端点（上、下）。刻痕比条高 `TICK_OVERHANG * 2`，是"跨在条上"
## 而不是"画在条里"。纯函数，回归量得到它。
static func tick_span(rect: Rect2, threshold: float) -> PackedVector2Array:
	var x := threshold_x(rect, threshold)
	return PackedVector2Array([
		Vector2(x, rect.position.y - TICK_OVERHANG),
		Vector2(x, rect.end.y + TICK_OVERHANG),
	])

## 门槛下面那个数字的落位。第一版是画笔里写死的 `offset(-14, 宽度 28)`，
## 而 16px 的「75%」实测要 32px 宽——`draw_string` 那个宽度就是**裁切宽度**，
## 多出来的那半个百分号被切掉，图上只剩「75」。定妆照看见的。
## 而"这个标签该多宽"只有图能量；数字量得到的是那条会漏的量：
## `get_string_size()` 给这串字的宽度 ≤ 框宽（回归第 6h 节量的就是这一条）。
const TICK_LABEL_W := 64.0
const TICK_LABEL_FONT := 16
## 标签顶相对**条底**的下移。必须大于 `TICK_OVERHANG`，否则刻痕的下半截
## 从这串字里穿过去（第一版 20 差 1px，图上「75%」中间竖着一根金线）。
const TICK_LABEL_DY := 28.0

static func tick_label_rect(rect: Rect2, threshold: float) -> Rect2:
	var x: float = threshold_x(rect, threshold) - TICK_LABEL_W * 0.5
	# 门槛贴住条的某一头时，标签会掉出条外。夹回条内——夹了就不再以刻痕为中心，
	# 所以回归钉的是"标签完整落在条内"，不是"标签中心等于刻痕"。
	x = clampf(x, rect.position.x, rect.end.x - TICK_LABEL_W)
	return Rect2(x, rect.end.y + TICK_LABEL_DY - float(TICK_LABEL_FONT),
			TICK_LABEL_W, float(TICK_LABEL_FONT) + 6.0)

## 条 + 填充 + 门槛刻痕。门槛那一段底色要**比别处亮一点**：
## 玩家真正要读的不是"到门槛了没有"，而是"离门槛还有多远"，所以过了门槛
## 的那一截得看得出是另一块料。
static func draw_bar(ci: CanvasItem, rect: Rect2, ratio: float, threshold: float,
		fill_col: Color, track_col: Color, edge_col: Color, tick_col: Color) -> void:
	var t: float = clampf(threshold, 0.0, 1.0)
	# 门槛之后的那一截：底色提亮
	if t < 1.0:
		ci.draw_rect(Rect2(threshold_x(rect, t), rect.position.y,
				rect.size.x * (1.0 - t), rect.size.y),
				track_col.lightened(0.22), true)
	ci.draw_rect(rect, track_col, true)
	var f: float = clampf(ratio, 0.0, 1.0)
	# 填充不许盖过门槛刻痕那一根竖线，所以画完刻痕再收一次边
	ci.draw_rect(Rect2(rect.position.x, rect.position.y,
			rect.size.x * f, rect.size.y), fill_col, true)
	ci.draw_rect(rect, edge_col, false, 2)
	var span: PackedVector2Array = tick_span(rect, t)
	ci.draw_line(span[0], span[1], tick_col, 3.0)

## 一格一格的进度（竹：五根）。
##
## 分格而不是一根连续条：竹子的"进度"是**五件互相独立的事**，一根填到 60%
## 的连续条读成"有一根被砍掉了 60%"，而实际是三根倒了、两根还立着——
## 数量本身是这一屏的信息。
static func pip_width(rect: Rect2, n: int) -> float:
	if n <= 0:
		return 0.0
	return (rect.size.x - pip_gap(rect, n) * float(n - 1)) / float(n)

## 格与格之间的缝，占整条宽度的几成。缝按宽度取而不是按像素：固定 6px 的缝
## 在一条 700px 的条上是 0.9%、在一条 300px 的条上是 2%，窄屏上就糊成一片。
const PIP_GAP_FRAC := 0.012

static func pip_gap(rect: Rect2, n: int) -> float:
	return rect.size.x * PIP_GAP_FRAC if n > 1 else 0.0

## 第 i 格的矩形。纯函数：回归量的是它，不是"格宽乘 i 加上缝"那份算式。
static func pip_rect(rect: Rect2, n: int, i: int) -> Rect2:
	var pw := pip_width(rect, n)
	var g := pip_gap(rect, n)
	return Rect2(rect.position.x + float(i) * (pw + g), rect.position.y, pw, rect.size.y)

static func draw_pips(ci: CanvasItem, rect: Rect2, n: int, filled: int, current: int,
		fill_col: Color, empty_col: Color, edge_col: Color) -> void:
	for i in n:
		var r: Rect2 = pip_rect(rect, n, i)
		ci.draw_rect(r, fill_col if i < filled else empty_col, true)
		# 当前那根描一道白边——进度只报"几根倒了"，不报"现在轮到哪一根"
		if i == current:
			ci.draw_rect(r, edge_col, false, 3.0)
