extends Control
## OnboardingGuide — 首次进入游戏时显示的新手引导面板
## 根据设备类型显示键盘或触屏操作说明
## 点击"开始骑行"关闭，玩家移动解禁

var _is_touch: bool = false

signal dismissed


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_is_touch = DisplayServer.is_touchscreen_available()
	if GameManager.onboarding_shown:
		visible = false
		return
	Localization.language_changed.connect(_refresh_ui)
	_build_ui()
	visible = true
	modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.4)


func _build_ui() -> void:
	# 压暗是为了让文字读得出来，不是为了藏住世界。原来 0.88 几乎把 3D 场景
	# 抹成了黑屏——玩家第一次进游戏看到的第一样东西不是自行车和路，是一张
	# 浮在黑底上的按键表。留出两成多的亮度，世界就一直在后面。
	var bg = ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.06, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 面板收窄，两侧各留出一条：世界得看得见，不然压暗的意义只是"别看"
	var panel = Panel.new()
	panel.anchor_left = 0.30
	panel.anchor_top = 0.12
	panel.anchor_right = 0.70
	panel.anchor_bottom = 0.88
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Panel 默认是透明 StyleBox。压暗从 0.88 降到 0.55 之后，字要靠这块底板
	# 才压得住后面的草地和天空
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.05, 0.04, 0.09, 0.92)
	plate.set_corner_radius_all(10)
	plate.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", plate)
	add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 32.0
	vbox.offset_top = 32.0
	vbox.offset_right = -32.0
	vbox.offset_bottom = -32.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	# 10 会让加了名词表之后的内容比面板高（桌面端 7 行按键 + 4 行名词，
	# 面板可用高度只有 483px）。6 刚好收进来，再小两行就要贴边了。
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var title = _make_label(Localization.t("onboarding_title"), _font_size(30, 28), Color(0.961, 0.784, 0.494))
	vbox.add_child(title)

	var subtitle = _make_label(Localization.t("onboarding_subtitle"), _font_size(14, 13), Color(0.65, 0.65, 0.65))
	vbox.add_child(subtitle)

	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 10)
	spacer1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer1)

	# 「这是什么」排在按键前面。顶栏从第一帧就摆着旅币 / 已过 n/16 驿 / 心神 /
	# 下一处，玩家能学会怎么骑车，却不知道自己在干什么——这是首屏最该补的一课。
	var glossary_title = _make_label(Localization.t("glossary_title"), _font_size(18, 17), Color(0.85, 0.85, 0.85))
	vbox.add_child(glossary_title)

	var spacer_g = Control.new()
	spacer_g.custom_minimum_size = Vector2(0, 4)
	spacer_g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer_g)

	_add_glossary(vbox)

	var spacer1b = Control.new()
	spacer1b.custom_minimum_size = Vector2(0, 12)
	spacer1b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer1b)

	var section_title = _make_label(Localization.t("controls_title"), _font_size(18, 17), Color(0.85, 0.85, 0.85))
	vbox.add_child(section_title)

	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 4)
	spacer2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer2)

	if _is_touch:
		_add_touch_controls(vbox)
	else:
		_add_keyboard_controls(vbox)

	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 16)
	spacer3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer3)

	var start_btn = Button.new()
	start_btn.text = Localization.t("start_ride")
	start_btn.custom_minimum_size = Vector2(180, 48)
	start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_btn.add_theme_font_size_override("font_size", _font_size(22, 20))
	start_btn.pressed.connect(_on_start_pressed)
	vbox.add_child(start_btn)

	var hint_text = Localization.t("touch_hint") if _is_touch else Localization.t("desktop_hint")
	var hint = _make_label(hint_text, _font_size(12, 11), Color(0.45, 0.45, 0.45))
	vbox.add_child(hint)


## 四行名词解释。复用按键表的两列排版，但左列窄一些——这些是词不是键位。
func _add_glossary(vbox: VBoxContainer) -> void:
	var rows = [
		["glossary_lvbi", "glossary_lvbi_desc"],
		["glossary_mood", "glossary_mood_desc"],
		["glossary_station", "glossary_station_desc"],
		["glossary_fragment", "glossary_fragment_desc"],
	]
	for row in rows:
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(hbox)

		var term = _make_label(Localization.t(row[0]), _font_size(15, 14), Color(0.961, 0.784, 0.494))
		term.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		term.custom_minimum_size = Vector2(76, 0)
		hbox.add_child(term)

		var desc = _make_label(Localization.t(row[1]), _font_size(15, 14), Color(0.78, 0.78, 0.78))
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(desc)


func _add_keyboard_controls(vbox: VBoxContainer) -> void:
	var rows = [
		["W / ↑", Localization.t("key_forward")],
		["S / ↓", Localization.t("key_back")],
		["A / ←", Localization.t("key_left")],
		["D / →", Localization.t("key_right")],
		["Space", Localization.t("key_check_in")],
		["ESC", Localization.t("key_pause")],
		["M", Localization.t("key_mute")],
	]
	_add_control_rows(vbox, rows)


func _add_touch_controls(vbox: VBoxContainer) -> void:
	var rows = [
		[Localization.t("touch_joystick_key"), Localization.t("touch_joystick_desc")],
		[Localization.t("touch_checkin_key"), Localization.t("touch_checkin_desc")],
		[Localization.t("touch_buttons_key"), Localization.t("touch_buttons_desc")],
	]
	_add_control_rows(vbox, rows)


func _add_control_rows(vbox: VBoxContainer, rows: Array) -> void:
	for row in rows:
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 16)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(hbox)

		var key_label = Label.new()
		key_label.text = "  " + row[0]
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.add_theme_font_size_override("font_size", _font_size(15, 14))
		key_label.add_theme_color_override("font_color", Color(0.85, 0.65, 0.35))
		key_label.custom_minimum_size = Vector2(100, 0)
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(key_label)

		var desc_label = Label.new()
		desc_label.text = row[1]
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.add_theme_font_size_override("font_size", _font_size(15, 14))
		desc_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
		desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(desc_label)


func _make_label(text: String, font_size: int, col: Color) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", col)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _font_size(zh: int, en: int) -> int:
	return en if Localization.is_english() else zh


func _refresh_ui() -> void:
	if not visible:
		return
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build_ui()


func _on_start_pressed() -> void:
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	await tw.finished
	visible = false
	modulate.a = 1.0
	GameManager.onboarding_shown = true
	if has_signal("dismissed"):
		emit_signal("dismissed")
