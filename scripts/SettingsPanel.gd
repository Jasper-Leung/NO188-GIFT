extends Control
## 设置面板 —— 音量 / 画面 / 操作说明，三个入口里的那一个。
##
## **挂载：`World3D/SettingsPanel`，初始 visible=false。** 两个入口都调 `open()`：
##   · 暂停菜单那一行「设置」（`PausePanel`）—— 玩家想改设置时世界是冻着的；
##   · 顶栏右上角那个「?」（`HUD3D`）—— **这个按钮原来压根没接线**，
##     `show_help()` 零调用者，于是玩家中途想再看一眼操作说明没有任何办法。
##     它原来指着的那块 `HUD3D/HelpOverlay` 面板也删了：它是一份**写死中文**的
##     键位表（英文界面下那十行仍然是中文），而键位表现在只有一个出处。
##
## 为什么单独一块面板而不是往暂停菜单里加行：量过了 —— 720p 下那一列
## 中文 need=432 / 可用 464，英文 need=451 / 可用 464，**英文只剩 13px**。
## 再加一行（28px + 10px 间隔）就静默溢出，而溢出量不到任何数值断言：
## 控件照样互不叠、按钮的 `focus_mode` 照样是 FOCUS_ALL，只是最下面那几行
## 被顶出面板下沿（CLAUDE.md 陷阱清单里"VBox 装不下时不报错"那条）。
## 所以**新的一行都放这儿**，暂停菜单那一列反而因为收掉了三档静音按钮
## 空出了 114px。
##
## 内容装在 `ScrollContainer` 里：这一屏的行数以后还会长（重绑定键位之类），
## 而"内容比容器高"在 ScrollContainer 里是**它本来的活**，不像 VBox 那样
## 把最后一行顶出去。所以这里量的是**关闭按钮那一行不许被顶出屏**，
## 而不是"整列装得下"。

var _scroll: ScrollContainer = null
var _body: VBoxContainer = null
var _bgm_slider: HSlider = null
var _sfx_slider: HSlider = null
var _bgm_value: Label = null
var _sfx_value: Label = null
var _resolution_btn: Button = null
var _window_btn: Button = null
var _vsync_btn: Button = null
var _close_btn: Button = null
var _built := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Localization.language_changed.connect(_refresh)


func open() -> void:
	if not _built:
		_build()
	# 每次打开都对齐一次：玩家可能在暂停菜单里改过画质，也可能中途按过顶栏
	# 那个静音按钮（它现在改的是音量 0）。开着面板不动的话，滑杆停在一个
	# 早就不是当前值的数上，而玩家会以为那才是真的。
	_sync_from_state()
	visible = true
	_close_btn.grab_focus()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _on_bg_input(event: InputEvent) -> void:
	if visible and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			close()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 建


func _build() -> void:
	_built = true

	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.04, 0.08, 0.86)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_bg_input)
	add_child(bg)

	var panel := Panel.new()
	panel.name = "Panel"
	panel.anchor_left = 0.13
	panel.anchor_top = 0.05
	panel.anchor_right = 0.87
	panel.anchor_bottom = 0.95
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 24.0
	vbox.offset_top = 16.0
	vbox.offset_right = -24.0
	vbox.offset_bottom = -16.0
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := _label(Localization.t("settings_title"), 26, Color(0.961, 0.784, 0.494))
	title.name = "TitleLabel"
	vbox.add_child(title)

	# ---- 滚动区：只有它里面允许长出屏，标题与关闭按钮永远留在屏内 ----
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	vbox.add_child(_scroll)

	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	_scroll.add_child(_body)

	_build_audio()
	_build_video()
	_build_controls()

	_close_btn = Button.new()
	_close_btn.name = "CloseBtn"
	_close_btn.custom_minimum_size = Vector2(0, 40)
	_close_btn.add_theme_font_size_override("font_size", 18)
	_close_btn.pressed.connect(close)
	vbox.add_child(_close_btn)


func _build_audio() -> void:
	_body.add_child(_section(Localization.t("section_audio")))
	_bgm_slider = _add_slider("BgmSlider", Localization.t("vol_bgm"))
	_bgm_slider.value_changed.connect(_on_bgm_changed)
	_sfx_slider = _add_slider("SfxSlider", Localization.t("vol_sfx"))
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_bgm_value = _value_label_for(_bgm_slider)
	_sfx_value = _value_label_for(_sfx_slider)


func _build_video() -> void:
	_body.add_child(_section(Localization.t("section_video")))
	_resolution_btn = _add_button("ResolutionBtn", Localization.t("resolution"))
	_resolution_btn.pressed.connect(_on_resolution_pressed)
	_window_btn = _add_button("WindowBtn", Localization.t("window_mode"))
	_window_btn.pressed.connect(_on_window_pressed)
	_vsync_btn = _add_button("VsyncBtn", Localization.t("vsync"))
	_vsync_btn.pressed.connect(_on_vsync_pressed)


## 键位表**不是**这里抄的：`GameManager.player_control_rows()` 是冷启动的
## `OnboardingGuide` 与这一屏共用的那一份，而它背后是真正注册进 InputMap 的
## `PLAYER_ACTIONS`。以前屏上那份键位表存在过四种实现、四处手抄。
func _build_controls() -> void:
	_body.add_child(_section(Localization.t("controls_title")))
	var rows: Array = GameManager.touch_control_rows() \
			if DisplayServer.is_touchscreen_available() else GameManager.player_control_rows()
	for row in rows:
		_body.add_child(_control_row(str(row[0]), str(row[1])))


func _control_row(keys: String, desc: String) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	var k := _label(keys, 15, Color(0.85, 0.65, 0.35))
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.custom_minimum_size = Vector2(130, 0)
	hbox.add_child(k)
	var d := _label(desc, 15, Color(0.88, 0.88, 0.88))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(d)
	return hbox


# ---------------------------------------------------------------- 音量


func _add_slider(name: String, label_text: String) -> HSlider:
	var hbox := HBoxContainer.new()
	hbox.name = name + "Row"
	hbox.add_theme_constant_override("separation", 12)

	var lbl := _label(label_text, 15, Color(0.85, 0.85, 0.85))
	lbl.custom_minimum_size = Vector2(92, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(lbl)

	var sl := HSlider.new()
	sl.name = name
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.custom_minimum_size = Vector2(260, 24)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(sl)

	var val := _label("100%", 15, Color(0.961, 0.784, 0.494))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.custom_minimum_size = Vector2(56, 0)
	hbox.add_child(val)

	_body.add_child(hbox)
	return sl


## 滑杆右边那个报百分比的 Label。它是**那一行里的第三个子节点**
## （名称 / 滑杆 / 数值），所以按滑杆的下标推，不按"最后一个子节点"——
## 那两种写法在行里加东西时各自会静默取错一个，而取错了不会报错，
## 只剩下一行不再更新的百分数。
func _value_label_for(slider: HSlider) -> Label:
	var row := slider.get_parent() as HBoxContainer
	return row.get_child(slider.get_index() + 1) as Label


func _on_bgm_changed(v: float) -> void:
	AudioManager.set_bgm_volume(v)
	_sync_value_labels()


func _on_sfx_changed(v: float) -> void:
	AudioManager.set_sfx_volume(v)
	_sync_value_labels()


# ---------------------------------------------------------------- 画面


func _add_button(name: String, label_text: String) -> Button:
	var btn := Button.new()
	btn.name = name
	btn.custom_minimum_size = Vector2(0, 30)
	btn.add_theme_font_size_override("font_size", 16)
	btn.text = "%s  %s" % [label_text, ""]
	_body.add_child(btn)
	return btn


func _on_resolution_pressed() -> void:
	QualitySettings.set_resolution(
			(QualitySettings.resolution_idx + 1) % QualitySettings.RESOLUTIONS.size(), true)
	_sync_from_state()


func _on_window_pressed() -> void:
	QualitySettings.set_window_mode(
			(QualitySettings.window_mode + 1) % QualitySettings.WINDOW_MODE_NAMES.size(), true)
	_sync_from_state()


func _on_vsync_pressed() -> void:
	QualitySettings.set_vsync(
			(QualitySettings.vsync_mode + 1) % QualitySettings.VSYNC_NAMES.size(), true)
	_sync_from_state()


# ---------------------------------------------------------------- 同步


## 把当前真状态拉回屏上。**每一处状态变化都调它**，而它是唯一读
## `AudioManager` / `QualitySettings` 的地方 —— 面板上的数与真的那个数
## 不许各说各话（CLAUDE.md 已知陷阱里"顶栏 HBox 那一行由文字长度决定"那族的同一条）。
func _sync_from_state() -> void:
	if _bgm_slider != null:
		_bgm_slider.set_value_no_signal(AudioManager.bgm_volume())
	if _sfx_slider != null:
		_sfx_slider.set_value_no_signal(AudioManager.sfx_volume())
	_sync_value_labels()
	if _resolution_btn != null:
		_resolution_btn.text = "%s  %s" % [Localization.t("resolution"),
				Localization.t(QualitySettings.resolution_name_key())]
	if _window_btn != null:
		_window_btn.text = "%s  %s" % [Localization.t("window_mode"),
				Localization.t(QualitySettings.window_mode_name_key())]
	if _vsync_btn != null:
		_vsync_btn.text = "%s  %s" % [Localization.t("vsync"),
				Localization.t(QualitySettings.vsync_name_key())]


func _sync_value_labels() -> void:
	if _bgm_value != null:
		_bgm_value.text = "%d%%" % roundi(AudioManager.bgm_volume() * 100.0)
	if _sfx_value != null:
		_sfx_value.text = "%d%%" % roundi(AudioManager.sfx_volume() * 100.0)


func _refresh() -> void:
	if not _built:
		return
	_rebuild_texts()
	_sync_from_state()


## 换语言要重建的只有**字**，控件骨架不动 —— 所以这里只改那几处 text，
## 不重跑 `_build()`（重跑会把玩家刚拖到一半的滑杆弹回原处）。
func _rebuild_texts() -> void:
	(get_node("Panel/VBox/TitleLabel") as Label).text = Localization.t("settings_title")
	_close_btn.text = Localization.t("settings_close")
	for c in _body.get_children():
		if c is Label and c.has_meta("section_key"):
			(c as Label).text = Localization.t(str(c.get_meta("section_key")))
	var labels := {
		"BgmSliderRow": "vol_bgm", "SfxSliderRow": "vol_sfx",
	}
	for row_name in labels.keys():
		var row := _body.get_node_or_null(str(row_name))
		if row is HBoxContainer:
			(row.get_child(0) as Label).text = Localization.t(str(labels[row_name]))
	for pair in [["ResolutionBtn", "resolution"], ["WindowBtn", "window_mode"], ["VsyncBtn", "vsync"]]:
		var btn := _body.get_node_or_null(str(pair[0]))
		if btn is Button:
			(btn as Button).text = "%s  %s" % [Localization.t(str(pair[1])), ""]


func _section(text_key: String) -> Label:
	var lbl := _label(Localization.t(text_key), 19, Color(0.85, 0.85, 0.85))
	# 存**key** 不存译好的字：换语言时按 key 重取，存字就永远停在旧语言上。
	lbl.set_meta("section_key", text_key)
	return lbl


func _label(text: String, font_size: int, col: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", col)
	return lbl
