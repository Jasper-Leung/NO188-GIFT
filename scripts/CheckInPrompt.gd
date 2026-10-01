extends Control
## CheckInPrompt — 接近打卡点/铺子时屏幕空间提示圈 + 触屏点击按钮
## 依赖 World3D._nearby_station_idx / _nearby_station_dist / _nearby_shop_idx /
## _nearby_shop_dist / _player_cam / _stations / _shop_open
##
## 碎片驿站是金色，铺子是青绿。两套驿站集合互不相交，优先级只是防御。
## 铺子面板开着时整个提示必须自己退场：本节点挂在 $HUDLayer（CanvasLayer 1），
## ShopPanel 挂在 World3D 下（隐式 CanvasLayer 0），不拦的话圈和按钮会画在面板上面。

signal check_in_pressed

const PROMPT_RANGE := 15.0
const COL_GOLD := Color(0.96, 0.78, 0.49)
const COL_SHOP := Color(0.60, 0.82, 0.77)

var _world: Node3D = null
var _is_touch = false
var _button: Button = null

## 按键被门控挡掉时的变灰提示。
## 键是 Localization key，不是现成的句子：顶栏那行用同一个 key 显示，
## 两处必须说同一件事，不能各写一套中文英文。
const BLOCK_HOLD_SEC := 0.9
var _blocked_key: String = ""
var _blocked_left: float = 0.0


func setup(world: Node3D) -> void:
	_world = world
	_is_touch = DisplayServer.is_touchscreen_available()
	_button = _create_button()
	add_child(_button)
	_button.pressed.connect(_on_button_pressed)
	Localization.language_changed.connect(_update_button)


func _create_button() -> Button:
	var btn = Button.new()
	btn.name = "CheckInButton"
	btn.text = Localization.t("touch_checkin_button")
	btn.custom_minimum_size = Vector2(220, 72)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.z_index = 20
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04, 1))
	btn.add_theme_color_override("font_hover_color", Color(0.08, 0.06, 0.04, 1))
	btn.add_theme_color_override("font_pressed_color", Color(0.08, 0.06, 0.04, 1))
	btn.add_theme_color_override("font_focus_color", Color(0.08, 0.06, 0.04, 1))
	btn.visible = false
	return btn


func _process(delta: float) -> void:
	if _blocked_left > 0.0:
		_blocked_left -= delta
		if _blocked_left <= 0.0:
			_blocked_key = ""
	queue_redraw()
	_update_button()


## 按键被挡：圈原地变灰，并在下面写清楚为什么。
##
## 这是"提示圈亮着、空格没反应"那类事故唯一能让玩家不至于去重开游戏的出口。
## 圈要变灰而不是消失——消失的话玩家会以为是自己走远了，下一次按键更没有对象。
func flash_blocked(key: String) -> void:
	_blocked_key = key
	_blocked_left = BLOCK_HOLD_SEC
	queue_redraw()


## 变灰态下圈和标签用的颜色。冷灰，和金色/青绿都拉得开，一眼看出"这一下没生效"。
const BLOCK_GREY := Color(0.62, 0.63, 0.66)


## [idx, dist, is_shop]；没有目标返回 []。
func _prompt_target() -> Array:
	if _world == null:
		return []
	if _world._shop_open:
		return []
	var frag_idx: int = int(_world._nearby_station_idx)
	if frag_idx >= 0 and float(_world._nearby_station_dist) <= PROMPT_RANGE:
		return [frag_idx, float(_world._nearby_station_dist), false]
	var shop_idx: int = int(_world._nearby_shop_idx)
	if shop_idx >= 0 and float(_world._nearby_shop_dist) <= PROMPT_RANGE:
		return [shop_idx, float(_world._nearby_shop_dist), true]
	return []


func _col(target: Array) -> Color:
	if _blocked_left > 0.0:
		return BLOCK_GREY
	return COL_SHOP if bool(target[2]) else COL_GOLD


## 提示语要说实话，而且要**跟得上顶栏**。
##
## 碎片驿站最多能打 3 次卡（GameManager.MAX_VISITS_PER_STATION），而顶栏的
## 「下一处」用的是 fragment_station_needs_visit()，第一次到访之后这站还剩两次。
## 所以三件事必须同时成立：
##   1. 回访时不能再说"完成乐事"——回访只给旅币不给碎片，说了就是骗玩家。
##   2. 但也不能一直说"歇一脚"——第三次到访是明信片完满评级的最后一格，
##      而完满是全游戏最强的重玩钩子。对着它说"歇一脚"等于在劝退。
##   3. 差几次要写出来，圈就画在驿站上，玩家没有理由再去顶栏对一次账。
func _label(target: Array) -> String:
	if bool(target[2]):
		return Localization.t("touch_shop_prompt") if _is_touch else Localization.t("desktop_shop_prompt")
	var st: int = int(target[0])
	if GameManager.is_collected(st):
		if _is_touch:
			return Localization.t("touch_revisit_button")
		var left: int = GameManager.MAX_VISITS_PER_STATION - GameManager.get_station_count(st)
		return Localization.t("desktop_revisit_prompt") % left
	return Localization.t("touch_checkin_prompt") if _is_touch else Localization.t("desktop_checkin_prompt")


func _button_text(target: Array) -> String:
	if bool(target[2]):
		return Localization.t("shop_enter_button")
	if GameManager.is_collected(int(target[0])):
		return Localization.t("touch_revisit_button")
	return Localization.t("touch_checkin_button")


func _draw() -> void:
	if not _world:
		return
	var target := _prompt_target()
	if target.is_empty():
		return
	var idx: int = target[0]
	var dist: float = float(target[1])
	var col := _col(target)
	var cam: Camera3D = _world._player_cam
	if not cam:
		return
	var station_pos: Vector3 = _world._stations[idx].position
	if cam.is_position_behind(station_pos):
		return
	var screen: Vector2 = cam.unproject_position(station_pos)
	var intensity: float = clampf(1.0 - dist / PROMPT_RANGE, 0.0, 1.0)
	var r := 28.0 + intensity * 18.0

	draw_arc(screen, r, 0, TAU, 48, Color(col, 0.5 + intensity * 0.4), 3.0)
	draw_arc(screen, r + 8, 0, TAU, 48, Color(1, 1, 1, 0.2 + intensity * 0.3), 1.5)

	# 被挡的那一下：把原来的提示词换成"为什么没生效"，字号大一档。
	# 不换的话玩家会读到"空格·完成乐事"然后照按，然后又没反应——那才是真的气人。
	var blocked := _blocked_left > 0.0
	var label := Localization.t(_blocked_key) if blocked else _label(target)
	var font := ThemeDB.fallback_font
	var fs := 16 if Localization.is_english() else 18
	if blocked:
		fs += 3
	var text_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	var text_pos := _label_pos(screen, r, text_w, fs)
	# 底板：贴着驿站时这句会翻到圈的上方，而圈上方正是底栏碎片格和驿站的木架 ——
	# 全屏最忙的一块。描边在这里救不回来（底板压不住底下的花纹），所以铺一层
	# 半透明深色，和 HUD 浮出来的那行驿站的话用同一块底板。
	var pad := 8.0
	var plate := Rect2(text_pos.x - pad, text_pos.y - float(fs) - pad * 0.6,
		text_w + pad * 2.0, float(fs) + pad * 1.2)
	draw_rect(plate, Color(0.06, 0.05, 0.07, 0.72))
	# 描边：提示文字直接画在浅蓝天空上时，浅色描边是唯一能让它读出来的办法
	# （米金 0.96/0.78/0.49 压在浅蓝上对比度约 1.6:1，远低于可读线）。
	draw_string(font, text_pos + Vector2(1, 0), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(0.06, 0.07, 0.10, 0.75))
	draw_string(font, text_pos + Vector2(-1, 0), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(0.06, 0.07, 0.10, 0.75))
	draw_string(font, text_pos + Vector2(0, 1), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(0.06, 0.07, 0.10, 0.75))
	draw_string(font, text_pos + Vector2(0, -1), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(0.06, 0.07, 0.10, 0.75))
	draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(col, 0.85 + intensity * 0.15))


## 提示文字该画在哪（返回 draw_string 的基线左端点）。
##
## 圈下方那一行是它平时的位置，可玩家越骑越近，站点的投影就越往画面下方跑 ——
## 贴着站停下时 `screen.y` 已经逼近屏底，文字整个掉到屏外，而那恰恰是玩家
## 最该读到"空格 · 完成乐事"的一刻。所以这里先把文字收进屏内：下方放得下
## 就放下方（保持平时的观感），放不下就翻到圈的上方。横向也收，驿站压在
## 画面最左/最右时整行同样会走丢。
func _label_pos(screen: Vector2, r: float, text_w: float, fs: int) -> Vector2:
	var below := screen.y + r + 32.0
	var y := below if below + float(fs) <= size.y - 4.0 else screen.y - r - 8.0
	y = clampf(y, float(fs) + 4.0, size.y - 4.0)
	var x := clampf(screen.x - text_w * 0.5, 4.0, maxf(size.x - text_w - 4.0, 4.0))
	return Vector2(x, y)


func _update_button() -> void:
	if not _world or not _is_touch or _button == null:
		_set_button_visible(false)
		return
	var target := _prompt_target()
	if target.is_empty():
		_set_button_visible(false)
		return
	if _world._paused or _world._check_in_in_progress or _world._all_done:
		_set_button_visible(false)
		return
	var idx: int = target[0]
	var dist: float = float(target[1])
	var cam: Camera3D = _world._player_cam
	if not cam:
		_set_button_visible(false)
		return
	var station_pos: Vector3 = _world._stations[idx].position
	if cam.is_position_behind(station_pos):
		_set_button_visible(false)
		return
	# 触屏上被挡的那一下同样要说人话，否则玩家会把这颗按钮当成坏了。
	# 原因句比按钮词长得多（"刚刚才结束 · 稍等一下" 12 个字 vs "完成乐事" 4 个），
	# 24px 下要 290px 而按钮只有 220 —— 换字号而不是让它撑开，按钮位置才不会跳。
	_button.text = Localization.t(_blocked_key) if _blocked_left > 0.0 \
			else _button_text(target)
	_button.add_theme_font_size_override("font_size",
			16 if _blocked_left > 0.0 and not Localization.is_english() else 24)
	var screen: Vector2 = cam.unproject_position(station_pos)
	var center = screen + Vector2(0, 92)
	center.x = clampf(center.x, _button.size.x * 0.5, size.x - _button.size.x * 0.5)
	center.y = clampf(center.y, _button.size.y * 0.5, size.y - _button.size.y * 0.5)
	_button.position = center - _button.size * 0.5
	_button.modulate.a = clampf(0.45 + (1.0 - dist / PROMPT_RANGE) * 0.55, 0.45, 1.0)
	_set_button_visible(true)


func _set_button_visible(v: bool) -> void:
	if _button != null and _button.visible != v:
		_button.visible = v


func _on_button_pressed() -> void:
	check_in_pressed.emit()
