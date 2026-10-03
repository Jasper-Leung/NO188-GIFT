extends Control
## 第一次集齐五块碎片时弹的二选一面板 —— **这一趟的落点**。
##
## 以前这里什么都没有：`_on_all_collected()` 浮一句「顶栏的圆点还是空的」，
## 然后把操纵权还给玩家。信息量最大的那一刻（五件乐事到齐、五个字凑齐、
## 下一站是礼物）被当成了一个中局过场，而唯一的出口「收下明信片」藏在
## 暂停面板深处、没有任何一句话告诉玩家它在那儿。一趟 20~30 分钟，
## 评委玩不到终点就已经还回去了。
##
## 面板按 CLAUDE.md 里的规矩自己关自己：ESC = 「再骑一圈」，
## 键盘玩家不会被一个没有倒计时的模态困住（鼠标玩家有第二个按钮）。
##
## 显隐完全由事件驱动（不取决于存档），所以 UI 在 `_build_ui()` 里现建，
## 场景里只留一个 Control 桩 —— 和 `DialoguePopup` 同一套做法。

## keep_riding = true 是「再骑一圈」，false 是「收下明信片 · 结束这一趟」。
signal synthesis_choice(keep_riding: bool)

const _CENTER_X := 0.5
const _CENTER_Y := 0.46
const _MARGIN := 28.0
const _MAX_PANEL_W := 820.0
const _PANEL_H_CN := 300.0
const _PANEL_H_EN := 340.0

## 压暗层比对白弹窗（0.30）重：这个面板是**终点的门**，背后那个 8 字环路
## 恰恰是这个游戏卖的东西，遮太狠等于在最后一刻把商品收起来。
const _SCRIM_ALPHA := 0.55

var _title: Label
var _hint: Label
var _take_btn: Button
var _keep_btn: Button
var _panel: Panel


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_build_ui()
	Localization.language_changed.connect(_on_language_changed)
	visibility_changed.connect(_on_visibility_changed)
	get_viewport().size_changed.connect(_layout_panel)
	visible = false


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
	overlay.color = Color(0.0, 0.0, 0.0, _SCRIM_ALPHA)
	overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.anchor_left = _CENTER_X
	_panel.anchor_top = _CENTER_Y
	_panel.anchor_right = _CENTER_X
	_panel.anchor_bottom = _CENTER_Y

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
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	_title = Label.new()
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color(0.961, 0.784, 0.494, 1))
	vbox.add_child(_title)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(0.86, 0.86, 0.86, 1))
	vbox.add_child(_hint)

	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	_take_btn = Button.new()
	_take_btn.name = "TakePostcardBtn"
	_take_btn.custom_minimum_size = Vector2(0, 52)
	_take_btn.add_theme_font_size_override("font_size", 20)
	# focus_mode 默认就是 FOCUS_ALL，写出来是为了让"这一屏键盘能走通"
	# 这件事在读代码时看得见 —— CLAUDE.md 记着 OnboardingGuide ①过②不过、
	# ShopPanel 连①都不过，两次都是卡在第一屏。
	_take_btn.focus_mode = Control.FOCUS_ALL
	_take_btn.pressed.connect(_on_take_pressed)
	vbox.add_child(_take_btn)

	_keep_btn = Button.new()
	_keep_btn.name = "KeepRidingBtn"
	_keep_btn.custom_minimum_size = Vector2(0, 44)
	_keep_btn.add_theme_font_size_override("font_size", 17)
	_keep_btn.focus_mode = Control.FOCUS_ALL
	_keep_btn.pressed.connect(_on_keep_pressed)
	vbox.add_child(_keep_btn)

	_layout_panel()
	_apply_labels()


func _layout_panel() -> void:
	if _panel == null:
		return
	var vp := get_viewport_rect().size
	var w := clampf(vp.x * 0.72, 360.0, _MAX_PANEL_W)
	var h := _PANEL_H_EN if Localization.is_english() else _PANEL_H_CN
	h = clampf(h, 200.0, maxf(vp.y * 0.7, 200.0))
	_panel.offset_left = -w * 0.5
	_panel.offset_top = -h * 0.5
	_panel.offset_right = w * 0.5
	_panel.offset_bottom = h * 0.5


func _apply_labels() -> void:
	if _title:
		_title.text = Localization.t("collecting_message")
	if _hint:
		_hint.text = Localization.t("synthesis_choice_hint")
	if _take_btn:
		_take_btn.text = Localization.t("synthesis_take_postcard")
	if _keep_btn:
		_keep_btn.text = Localization.t("synthesis_keep_riding")


## 显示面板并把焦点交给主按钮。
##
## `grab_focus()` 不能省：视口里一个焦点都没有时，空格/回车谁也到不了，
## 连把鼠标悬停上去也不行（CLAUDE.md「三道门」那条）。
func open() -> void:
	_layout_panel()
	_apply_labels()
	visible = true
	if _take_btn:
		_take_btn.grab_focus()


func _on_visibility_changed() -> void:
	if not visible:
		return
	_layout_panel()
	_apply_labels()
	if _take_btn:
		_take_btn.grab_focus()


func _on_language_changed() -> void:
	_apply_labels()
	_layout_panel()


## ESC 收掉面板 = 选「再骑一圈」。
##
## 走 `_unhandled_input` 而不是 `_input`：有焦点的 Button 由 GUI 路由先收，
## 节点级回调不参与，两边不会各走一遍。键名是 `pause` 不是 `ui_cancel`
## —— 本工程 InputMap 里没有后者（`ShopPanel` 收 ESC 用的就是 pause）。
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		_emit(false)
		get_viewport().set_input_as_handled()


func _on_take_pressed() -> void:
	_emit(true)


func _on_keep_pressed() -> void:
	_emit(false)


func _emit(take_postcard: bool) -> void:
	close()
	synthesis_choice.emit(take_postcard)


## 收掉面板。
##
## 收面板的责任在**这一处**，不是散在每个回调里：`World3D._on_synthesis_choice()`
## 收到信号时已经把操纵权还回去了，而它不关面板的话，玩家会站在一个还亮着的
## 模态底下重新握住操纵权——屏幕在等他按键、圈也在等他按键，两个提示说的还不是
## 同一件事（CLAUDE.md「同一个键在同一帧里干两件事」那一族的反面）。
func close() -> void:
	visible = false
