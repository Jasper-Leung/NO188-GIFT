extends Control
## Visual-novel style dialogue popup with typewriter effect.
## Played before each station mini-game.
##
## 排版:正文水平居中(中英文一致),面板尺寸跟随视口,长句自动缩字号,
## 仍然放不下就在 ScrollContainer 里自动往下滚,不会溢出面板。
##
## Usage:
##   _dialogue_popup.setup(speaker_name, lines_array, false)
##   _dialogue_popup.visible = true
##   var result = await _dialogue_popup.dialogue_done  # {was_skipped: bool, was_stolen: bool}
##   _dialogue_popup.visible = false
##
## was_stolen = 这一轮对白被另一个 setup() 顶掉了，调用方必须走收尾分支。
## 见 setup() 里 _chain_open 那段——漏掉它就是"提示圈照画、按键全死"。

var _lines: Array = []

signal dialogue_done(result: Dictionary)

## 有一轮 setup()→await dialogue_done 还没收到过信号。
##
## 这个弹窗全世界只有一份，World3D 里却有好条协程会 await 它（驿站对白、
## 序章、郑铎三场）。只要两条链在同一帧各跑一次 setup()，后一条会把前一条
## 的画面盖掉，而前一条的 await 永远等不到信号——协程就此挂死，带着它自己
## 的闩锁（_villain_playing）再也回不来。挂死的后果是铺子再也不能开、
## 提示圈却照画，玩家只能重开游戏。所以 setup() 必须主动把上一轮放出去。
var _chain_open: bool = false

const _CPS := 40.0          # characters per second
const _PANEL_CENTER_X := 0.5
const _PANEL_CENTER_Y := 0.55
const _MARGIN := 24.0
const _MAX_PANEL_W := 900.0
## 面板高度跟着语言走:中文一句通常 1~2 行,英文普遍 3~4 行。
## 固定成"最高语言"的高度会让中文框下方空出一大片,像没排完版。
const _PANEL_H_CN := 250.0
const _PANEL_H_EN := 280.0
const _BASE_FONT_CN := 20
const _BASE_FONT_EN := 18
const _MIN_FONT_CN := 14
const _MIN_FONT_EN := 12

var _line_idx: int = 0
var _typewriter_accum: float = 0.0
var _typewriter_done: bool = false

var _panel: Panel
var _speaker_label: Label
var _text_scroll: ScrollContainer
var _text_label: Label
var _skip_btn: Button
var _next_btn: Button


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_build_ui()
	Localization.language_changed.connect(_on_language_changed)
	visibility_changed.connect(_on_visibility_changed)
	get_viewport().size_changed.connect(_layout_panel)


## 铺满父节点。必须显式写 anchor_* / offset_*:只赋 anchors_preset 不会真正
## 改锚点,节点会缩回左上角并退化成最小尺寸(正文挤成一小列就是这个原因)。
func _stretch_full(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0


func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	_stretch_full(overlay)
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.anchor_left = _PANEL_CENTER_X
	_panel.anchor_top = _PANEL_CENTER_Y
	_panel.anchor_right = _PANEL_CENTER_X
	_panel.anchor_bottom = _PANEL_CENTER_Y

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.18, 0.95)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.set_border_width_all(1)
	style.border_color = Color(0.3, 0.3, 0.5, 0.6)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	# Panel 的 content_margin 只对 MarginContainer 生效,直接铺 full-rect 的子节点
	# 会被 content margin 吃掉,正文会贴到圆角边框上。
	var margin := MarginContainer.new()
	margin.name = "Margin"
	_stretch_full(margin)
	margin.add_theme_constant_override("margin_left", int(_MARGIN))
	margin.add_theme_constant_override("margin_top", int(_MARGIN))
	margin.add_theme_constant_override("margin_right", int(_MARGIN))
	margin.add_theme_constant_override("margin_bottom", int(_MARGIN))
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	_speaker_label = Label.new()
	_speaker_label.name = "SpeakerLabel"
	_speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speaker_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speaker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_speaker_label)

	_text_scroll = ScrollContainer.new()
	_text_scroll.name = "TextScroll"
	_text_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_text_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(_text_scroll)

	_text_label = Label.new()
	_text_label.name = "TextLabel"
	_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_scroll.add_child(_text_label)

	var btn_row := HBoxContainer.new()
	btn_row.name = "ButtonRow"
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(btn_row)

	_skip_btn = Button.new()
	_skip_btn.name = "SkipBtn"
	_skip_btn.pressed.connect(_on_skip_pressed)
	btn_row.add_child(_skip_btn)

	_next_btn = Button.new()
	_next_btn.name = "NextBtn"
	_next_btn.pressed.connect(_on_next_pressed)
	btn_row.add_child(_next_btn)

	_layout_panel()
	_apply_labels()


## 面板按视口比例收缩,小窗口(手机横屏)下不会超出屏幕。
func _layout_panel() -> void:
	if _panel == null:
		return
	var vp := get_viewport_rect().size
	var w := clampf(vp.x * 0.78, 360.0, _MAX_PANEL_W)
	var h := _PANEL_H_EN if Localization.is_english() else _PANEL_H_CN
	# 小屏(手机横屏)上再高就顶出画面了
	h = clampf(h, 170.0, maxf(vp.y * 0.62, 170.0))
	_panel.offset_left = -w * 0.5
	_panel.offset_top = -h * 0.5
	_panel.offset_right = w * 0.5
	_panel.offset_bottom = h * 0.5


func _base_font_size() -> int:
	return _BASE_FONT_EN if Localization.is_english() else _BASE_FONT_CN


func _min_font_size() -> int:
	return _MIN_FONT_EN if Localization.is_english() else _MIN_FONT_CN


func _set_text_font_size(size_px: int) -> void:
	_speaker_label.add_theme_font_size_override("font_size", size_px + 6)
	_text_label.add_theme_font_size_override("font_size", size_px)


func _apply_labels() -> void:
	if _speaker_label:
		_speaker_label.add_theme_color_override("font_color", Color(0.961, 0.784, 0.494, 1))
	if _text_label:
		_text_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1))
	if _skip_btn:
		_skip_btn.text = Localization.t("dialogue_skip")
	if _next_btn:
		_next_btn.text = Localization.t("dialogue_next")


func _on_language_changed() -> void:
	_apply_labels()
	_refit_current_line()


func _on_visibility_changed() -> void:
	if not visible:
		return
	_layout_panel()
	_apply_labels()
	_refit_current_line()


## lines: Array of strings (CN or EN based on current language)
## watched: if true, skip typewriter delay and show text instantly
func setup(speaker: String, lines: Array, watched: bool) -> void:
	# 上一轮还没收尾就被顶掉了（最常见的原因是同一次空格既推进对白又触发了打卡，
	# 因为 interact 是靠 Input.is_action_just_pressed 读的，set_input_as_handled()
	# 拦不住它）。先把旧的等待者放出去，它才知道自己该走收尾分支。
	if _chain_open:
		_chain_open = false
		dialogue_done.emit({"was_skipped": false, "was_stolen": true})
	_lines = lines
	_line_idx = 0
	_typewriter_accum = 0.0
	_typewriter_done = false
	_chain_open = true

	if _speaker_label:
		_speaker_label.text = speaker

	if watched:
		_show_line_instant()
	else:
		_show_line_start()


func _current_line() -> String:
	if _line_idx < 0 or _line_idx >= _lines.size():
		return ""
	return _lines[_line_idx]


func _show_line_start() -> void:
	if _text_label:
		_text_label.text = ""
	_set_text_font_size(_base_font_size())
	_typewriter_accum = 0.0
	_typewriter_done = false
	_scroll_to_bottom()
	if _next_btn:
		_next_btn.text = Localization.t("dialogue_next")


func _show_line_instant() -> void:
	var line := _current_line()
	if _text_label and not line.is_empty():
		_text_label.text = line
	_typewriter_done = true
	_scroll_to_bottom()
	_refit_current_line()
	if _next_btn:
		# 最后一句:按钮变成"开始游戏"
		_next_btn.text = Localization.t("dialogue_start")


## 英语句子普遍比中文长 3~4 倍。逐步缩小字号直到整句装得下,
## 到了下限仍装不下就交给 ScrollContainer 滚动,保证任何语言都不溢出面板。
func _refit_current_line() -> void:
	if _text_label == null or not visible:
		return
	var line := _current_line()
	if line.is_empty():
		return
	_text_label.text = line
	var size_px := _base_font_size()
	var floor_px := _min_font_size()
	_set_text_font_size(size_px)
	# 等一帧让容器把宽度定下来,Label 才能算出换行后的行数
	await get_tree().process_frame
	if not is_instance_valid(_text_label) or not visible:
		return
	# 布局还没排完(size.y 仍为 0)时不要缩字号,否则会一口气缩到下限
	var avail := _text_scroll.size.y
	while size_px > floor_px and avail > 1.0 and _text_height() > avail:
		size_px -= 1
		_set_text_font_size(size_px)
		await get_tree().process_frame
		if not is_instance_valid(_text_label) or not visible:
			return
		avail = _text_scroll.size.y
	_scroll_to_bottom()


func _text_height() -> float:
	var lines := _text_label.get_line_count()
	if lines <= 0:
		return 0.0
	var spacing := _text_label.get_theme_constant("line_spacing")
	return _text_label.get_line_height() * lines + spacing * (lines - 1)


## 打字机进行中时锁死"跟随底部",玩家松手后再放开滚轮手动翻看。
func _scroll_to_bottom() -> void:
	if _text_scroll == null or _text_label == null:
		return
	var bar := _text_scroll.get_v_scroll_bar()
	_text_scroll.scroll_vertical = int(bar.max_value)


func _process(delta: float) -> void:
	if not visible:
		return
	if _typewriter_done:
		return
	if _line_idx >= _lines.size():
		return

	_typewriter_accum += delta
	var chars := int(_typewriter_accum * _CPS)
	var full_line := _current_line()
	if _text_label:
		_text_label.text = full_line.substr(0, chars)
		_scroll_to_bottom()

	if chars >= full_line.length():
		if _text_label:
			_text_label.text = full_line
		_typewriter_done = true
		if _next_btn:
			_next_btn.text = Localization.t("dialogue_next")
		_refit_current_line()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Enter 键推进;正文区的滚轮交给 ScrollContainer 自己处理
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_on_next_pressed()


func _on_next_pressed() -> void:
	if not _typewriter_done:
		_show_line_instant()
		return

	_line_idx += 1
	if _line_idx >= _lines.size():
		_chain_open = false
		dialogue_done.emit({"was_skipped": false})
		visible = false
	else:
		_show_line_start()


func _on_skip_pressed() -> void:
	_chain_open = false
	dialogue_done.emit({"was_skipped": true})
	visible = false
