extends Control
## PostcardBack — 明信片背面（Feature 4）
## 包含：落款区、邮编区、用户可编辑文字区

var _back_text: String = ""
const MAX_CHARS := 200

# 正文排版。全部抽成不碰画笔的纯函数，回归量的是它们 —— headless 下一笔都不落盘。
const SPLIT_FRAC := 0.22
const MSG_PAD := 24.0
const FONT_MIN := 36
const FONT_MAX := 84
const LINE_GAP := 10.0

const LAND_COL = Color("F4F2EA")
const INK_COL = Color("4A3520")
const ACCENT_COL = Color("C9A26B")

func _ready() -> void:
	Localization.language_changed.connect(refresh_text)
	queue_redraw()

## 切语言时重画。_draw 里全部走 Localization.t()，重画一次就够了。
func refresh_text() -> void:
	queue_redraw()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y

	# 底色
	draw_rect(Rect2(0, 0, w, h), LAND_COL)

	# 外框
	draw_rect(Rect2(0, 0, w, h), ACCENT_COL.darkened(0.2), false, 8)
	# 内框
	draw_rect(Rect2(16, 16, w - 32, h - 32), INK_COL, false, 2)

	# 顶部标题
	draw_string(ThemeDB.fallback_font, Vector2(48, 84),
		Localization.t("postcard_back_title"), HORIZONTAL_ALIGNMENT_LEFT, -1, 44, INK_COL)
	draw_line(Vector2(40, 104), Vector2(w - 40, 104), INK_COL, 2)

	# 分割线
	var split_y := h * SPLIT_FRAC
	draw_line(Vector2(40, split_y), Vector2(w - 40, split_y), ACCENT_COL.darkened(0.3), 2)

	# 背面文字区
	var msg_rect := _message_box(w, h)
	draw_rect(msg_rect, Color(INK_COL, 0.04), true)
	draw_rect(msg_rect, INK_COL, false, 1)

	# 玩家写的正文。SubViewport 里没有 TextEdit 盖着（那层只存在于编辑器的
	# 覆盖层中），所以必须在这里真的画出来，否则导出的背面永远是空白框。
	_draw_message(msg_rect)

	if _back_text.length() > 0:
		# 底部落款
		draw_string(ThemeDB.fallback_font, Vector2(w - 680, h - 44),
			Localization.t("postcard_back_from"), HORIZONTAL_ALIGNMENT_LEFT, -1, 36, INK_COL)

	# 底部路牌
	var sign_x: float = w * 0.5 - 100
	var sign_y: float = h - 110
	draw_rect(Rect2(sign_x, sign_y, 200, 50), LAND_COL, true)
	draw_rect(Rect2(sign_x, sign_y, 200, 50), INK_COL, false, 2)
	draw_string(ThemeDB.fallback_font, Vector2(sign_x + 56, sign_y + 36),
		"No.188", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, INK_COL)


## 正文框。抽出来是为了让回归能在 headless 下量它 —— 画笔里写死了的话
## 任何尺寸断言都只能跟着抄一遍。
func _message_box(w: float, h: float) -> Rect2:
	var split_y := h * SPLIT_FRAC
	return Rect2(40.0, split_y + 24.0, w - 80.0, h - split_y - 160.0)


## 整段话按宽度断成行（先按 \n 分段，再逐段断）。
func _wrap_text(font: Font, text: String, font_size: int, max_w: float) -> Array[String]:
	var out: Array[String] = []
	for para in text.split("\n"):
		out.append_array(_wrap_line(font, para, font_size, max_w))
	return out


## 正文字号：从 FONT_MAX 往下找第一个**整块放得下**的号（步长 4px）。
## 原来写死 36 —— 200 字在 682px 高的框里只占四五行、留下大半张空纸，
## 缩到编辑器那 450px 宽的预览里，那行字只剩八个像素高，玩家读不到自己写了什么。
func _message_font_size(font: Font, text: String, max_w: float, max_h: float) -> int:
	if text.is_empty():
		return FONT_MIN
	var fs := FONT_MAX
	while fs > FONT_MIN:
		var lines := _wrap_text(font, text, fs, max_w)
		if lines.size() * (font.get_height(fs) + LINE_GAP) <= max_h:
			return fs
		fs -= 4
	return FONT_MIN


## 手写换行把 _back_text 画进 msg_rect。按宽度断行（中文可任意断，西文按空格断）。
func _draw_message(msg_rect: Rect2) -> void:
	if _back_text.is_empty():
		return
	var font := ThemeDB.fallback_font
	var max_w := msg_rect.size.x - MSG_PAD * 2.0
	var max_h := msg_rect.size.y - MSG_PAD * 2.0
	var font_size := _message_font_size(font, _back_text, max_w, max_h)
	var lines := _wrap_text(font, _back_text, font_size, max_w)
	var line_h := font.get_height(font_size) + LINE_GAP

	# 字号变大之后块矮了，顶在框的上沿会读成"上半张纸有字、下半张空着"，
	# 所以整块在框里上下居中。
	var y := msg_rect.position.y + MSG_PAD + (max_h - lines.size() * line_h) * 0.5 \
			+ font.get_ascent(font_size)
	for i in range(lines.size()):
		draw_string(font, Vector2(msg_rect.position.x + MSG_PAD, y), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK_COL)
		y += line_h


## CJK 逐字断行，西文尽量在词间断。
##
## 原来那一版是"先把 ch 放进去、再看超没超"，于是只在空格处检查的西文
## **会冲出去一整个词**才收尾（实测一行 1969px，框只有 1792px，右端那一截
## 被框沿吃掉）。现在改成"先试着放，放不下就收尾"——检查永远发生在
## 越界之前，所以每一行都真的在 max_w 之内。
func _wrap_line(font: Font, text: String, font_size: int, max_w: float) -> Array[String]:
	var out: Array[String] = []
	var cur := ""
	for i in range(text.length()):
		var ch := text[i]
		if not cur.is_empty() and _text_w(font, cur + ch, font_size) > max_w:
			# 挪到下一行的那个词要比留下的那半行短，否则说明这段文字根本没有
			# 词结构（URL 之类），老实按字断。
			var sp: int = cur.rfind(" ")
			if sp * 2 > cur.length():
				out.append(cur.substr(0, sp))
				cur = cur.substr(sp + 1)
			else:
				out.append(cur)
				cur = ""
			if ch == " ":
				continue
		cur += ch
	if not cur.is_empty():
		out.append(cur)
	return out


func _text_w(font: Font, s: String, font_size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func set_back_text(t: String) -> void:
	_back_text = t.substr(0, MAX_CHARS)
	queue_redraw()


func get_back_text() -> String:
	return _back_text
