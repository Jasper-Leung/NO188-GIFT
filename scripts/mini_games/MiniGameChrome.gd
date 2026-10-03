extends RefCounted
## 小游戏那一屏的「取消」按钮。云/茶/琴三处各画了一份，连禽都在
## `_gui_input` 里留了同一块矩形当点击热区、却**什么都没画**——
## 于是那个角落是一块看得见、点得着、但读不出是什么的地方。
##
## 颜色原来一律是 `fill Color(0.4, 0.3, 0.3)` + `border Color(0.8, 0.3, 0.3)`，
## 即**警报红**。而「取消」在这一屏是最不费事的一个动作：ESC 也能按，
## 取消之后驿站还能再来一次，`MAX_VISITS_PER_STATION` 一次都没少。
## 全工程真正在报警的红是 `HUD3D.set_boundary_intensity()` 那圈边界警告
## （`Color(0.75, 0.12, 0.12)`）和竹子那根砍伐窗口的倒计时——
## 玩家学会「红 = 出事了」之后，再在角落里看见一块红，
## 读出来的是「取消这件事有代价」，而它没有。
##
## 所以这块按钮是**中性**的：一块不透明的深灰小片 + 一圈暖灰边 + 米白字。
## 不透明是刻意的：五个小游戏的背景亮度差得远（云那屏的天是亮的、
## 竹那屏的底是暗的），半透明底板算出来的对比度随背景漂，
## 而"这个字在五屏上都读得出来"只有让底板自己说了算才立得住。
##
## 用 preload 而不是 class_name（见 CLAUDE.md 已知陷阱）。

## 三处共用的落位。纯函数：回归量的是它，不是 `w - 160` 那份算式
## （四份抄开的 `Rect2(w - 160, h - 60, 140, 44)` 迟早有一份先改）。
## 右边留 20、下边留 16——离屏边近但没贴着，贴边会被读成系统按钮。
const CANCEL_W := 140.0
const CANCEL_H := 44.0
const CANCEL_MARGIN_X := 20.0
const CANCEL_MARGIN_Y := 16.0

static func cancel_rect(v: Vector2) -> Rect2:
	return Rect2(v.x - CANCEL_W - CANCEL_MARGIN_X,
		v.y - CANCEL_H - CANCEL_MARGIN_Y, CANCEL_W, CANCEL_H)

## 三档中性色。饱和度都压在 0.14 以下——这是"它读作惰性的一块板"的那个量，
## 回归量的是它，而旧的 `Color(0.8, 0.3, 0.3)` 饱和度 0.63、红通道比另两路
## 高 0.50，那是警报的语言。
const FILL := Color(0.20, 0.19, 0.18)
const BORDER := Color(0.58, 0.55, 0.50)
const LABEL := Color(0.94, 0.92, 0.86)

## 字号与基线。`draw_string` 的 position.y 是**基线**、不是行盒顶，
## 而基线往上走一个字身、往下留一点降部——所以"基线放在按钮高度的 68%"
## 是错的：22px 的字身会从按钮顶沿上面探出去，而一个只看控件尺寸的
## 断言量不到这件事（框还在按钮里，探出去的是字形）。
## 这里的量法是**真的字形盒**：用字体的真实 ascent/descent 算，
## 画笔和回归读同一个盒子，换字体换字号之后这条会自己变红。
const LABEL_FONT := 22
## 基线离按钮**下沿**有多远（按按钮高度取）。
const BASELINE_UP := 0.30

static func label_rect(rect: Rect2) -> Rect2:
	var f: Font = ThemeDB.fallback_font
	var asc: float = f.get_ascent(LABEL_FONT)
	var dsc: float = f.get_descent(LABEL_FONT)
	var baseline: float = rect.end.y - rect.size.y * BASELINE_UP
	return Rect2(rect.position.x, baseline - asc, rect.size.x, asc + dsc)

static func draw_cancel(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, FILL, true)
	ci.draw_rect(rect, BORDER, false, 2.0)
	# 基线取字形盒的**下沿减降部**，而不是盒子的顶——`draw_string` 要的是基线
	var base_y: float = label_rect(rect).end.y - ThemeDB.fallback_font.get_descent(LABEL_FONT)
	ci.draw_string(ThemeDB.fallback_font, Vector2(rect.position.x, base_y),
		Localization.t("mg_cancel"), HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x, LABEL_FONT, LABEL)
