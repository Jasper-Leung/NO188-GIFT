extends Control
## PostcardBack — 明信片背面（Feature 4）
## 包含：落款区、邮编区、用户可编辑文字区

var _back_text: String = ""
const MAX_CHARS := 200

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
	var split_y := h * 0.22
	draw_line(Vector2(40, split_y), Vector2(w - 40, split_y), ACCENT_COL.darkened(0.3), 2)

	# 背面文字区
	var msg_rect := Rect2(40, split_y + 24, w - 80, h - split_y - 160)
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


## 手写换行把 _back_text 画进 msg_rect。按宽度断行（中文可任意断，西文按空格断），
## 超出 rect 高度就停——200 字上限已经保证这里画得下。
func _draw_message(msg_rect: Rect2) -> void:
	if _back_text.is_empty():
		return
	var font := ThemeDB.fallback_font
	var font_size := 36
	var line_h := font.get_height(font_size) + 16.0
	var pad := 24.0
	var max_w := msg_rect.size.x - pad * 2.0
	var max_lines := int((msg_rect.size.y - pad * 2.0) / line_h)

	var lines: Array[String] = []
	for para in _back_text.split("\n"):
		lines.append_array(_wrap_line(font, para, font_size, max_w))

	var y := msg_rect.position.y + pad + font.get_ascent(font_size)
	for i in range(mini(lines.size(), max_lines)):
		draw_string(font, Vector2(msg_rect.position.x + pad, y), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK_COL)
		y += line_h


## CJK 逐字断行，西文按空格断词；超长单词（URL 之类）再退回逐字断。
func _wrap_line(font: Font, text: String, font_size: int, max_w: float) -> Array[String]:
	var out: Array[String] = []
	var cur := ""
	for i in range(text.length()):
		var ch := text[i]
		cur += ch
		if ch != " " and not _is_cjk(ch):
			continue
		if cur.length() > 1 and font.get_string_size(cur, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_w:
			var last := cur.substr(cur.length() - 1, 1)
			out.append(cur.substr(0, cur.length() - 1))
			cur = last
	if not cur.is_empty():
		out.append(cur)
	return out


func _is_cjk(ch: String) -> bool:
	var c := ch.unicode_at(0)
	return (c >= 0x3000 and c <= 0x9FFF) or (c >= 0xFF00 and c <= 0xFFEF)


func set_back_text(t: String) -> void:
	_back_text = t.substr(0, MAX_CHARS)
	queue_redraw()


func get_back_text() -> String:
	return _back_text
