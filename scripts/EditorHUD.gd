extends Control
## EditorHUD — 编辑模式侧栏 UI (LayoutEditor 配套)
##
## 布局:左侧空出给 3D 世界,右侧 340px 宽侧栏 + 顶部 banner + 底部工具条

signal save_pressed
signal reset_pressed
signal deselect_pressed
signal exit_pressed
signal object_selected(sel)

var _editor: Node3D = null
var _stations_list: ItemList = null
var _plants_list: ItemList = null
var _status_label: Label = null
var _dirty_label: Label = null
var _selection_label: Label = null
var _pos_label: Label = null
var _rot_label: Label = null
var _scale_label: Label = null

const PANEL_WIDTH := 340


func _ready() -> void:
	# 顶层必须 IGNORE:否则世界视图区(无子控件的空白区域)的鼠标点击会被 HUD 吃掉,
	# 永远进不到 LayoutEditor._unhandled_input → _handle_click,左键选不中物体。
	# 子控件(banner/侧栏/工具栏)各自仍为 STOP,UI 自身交互不受影响。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	# 顶部 banner
	var banner := Panel.new()
	banner.name = "Banner"
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_bottom = 38.0
	banner.modulate = Color(1, 1, 1, 0.85)
	add_child(banner)

	var title := Label.new()
	title.text = "EDIT MODE — 关卡布局编辑器"
	title.position = Vector2(12, 8)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.96, 0.78, 0.49, 1))
	banner.add_child(title)

	_dirty_label = Label.new()
	_dirty_label.name = "DirtyLabel"
	_dirty_label.text = ""
	_dirty_label.position = Vector2(420, 8)
	_dirty_label.add_theme_font_size_override("font_size", 14)
	_dirty_label.add_theme_color_override("font_color", Color(1, 0.7, 0.3, 1))
	banner.add_child(_dirty_label)

	var hint := Label.new()
	hint.text = "WASD 平移相机  方向键移选中  Q/E 旋转  [/] 缩放  Backspace 重置  X 取消选中  Ctrl+S 保存  Esc 退出"
	hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 44.0
	hint.offset_bottom = 60.0
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)

	# 右侧侧栏
	var side_root := Panel.new()
	side_root.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	side_root.offset_left = -PANEL_WIDTH
	side_root.offset_top = 70.0
	side_root.offset_bottom = -56.0
	add_child(side_root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8.0
	vbox.offset_top = 8.0
	vbox.offset_right = -8.0
	vbox.offset_bottom = -8.0
	vbox.add_theme_constant_override("separation", 6)
	side_root.add_child(vbox)

	var list_title := Label.new()
	list_title.text = "对象列表"
	list_title.add_theme_font_size_override("font_size", 14)
	list_title.add_theme_color_override("font_color", Color(0.96, 0.78, 0.49, 1))
	vbox.add_child(list_title)

	# Tab 切换
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	vbox.add_child(hbox)
	var tab_stations := Button.new()
	tab_stations.text = "驿站 (16)"
	tab_stations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(tab_stations)
	var tab_plants := Button.new()
	tab_plants.text = "植物"
	tab_plants.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(tab_plants)

	# 列表 — 用 size_flags_vertical=EXPAND_FILL 自动占满剩余空间
	# focus_mode=FOCUS_NONE 防止 ItemList 抢走方向键焦点(否则按方向键会变成列表导航,
	# 没法移动选中对象)
	_stations_list = ItemList.new()
	_stations_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stations_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stations_list.focus_mode = Control.FOCUS_NONE
	_stations_list.item_selected.connect(_on_station_item_selected)
	vbox.add_child(_stations_list)

	_plants_list = ItemList.new()
	_plants_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_plants_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plants_list.focus_mode = Control.FOCUS_NONE
	_plants_list.visible = false
	_plants_list.item_selected.connect(_on_plant_item_selected)
	vbox.add_child(_plants_list)

	tab_stations.pressed.connect(_on_tab_stations)
	tab_plants.pressed.connect(_on_tab_plants)

	# 当前选中信息
	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 2)
	vbox.add_child(info_box)

	_selection_label = Label.new()
	_selection_label.text = "未选中"
	_selection_label.add_theme_font_size_override("font_size", 13)
	_selection_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	info_box.add_child(_selection_label)

	_pos_label = Label.new()
	_pos_label.text = "pos: —"
	_pos_label.add_theme_font_size_override("font_size", 12)
	_pos_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	info_box.add_child(_pos_label)

	_rot_label = Label.new()
	_rot_label.text = "rot: —"
	_rot_label.add_theme_font_size_override("font_size", 12)
	_rot_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	info_box.add_child(_rot_label)

	_scale_label = Label.new()
	_scale_label.text = "scale: —"
	_scale_label.add_theme_font_size_override("font_size", 12)
	_scale_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	info_box.add_child(_scale_label)

	# 底部工具条
	var toolbar := Panel.new()
	toolbar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	toolbar.offset_top = -56.0
	toolbar.offset_bottom = 0.0
	toolbar.modulate = Color(1, 1, 1, 0.85)
	add_child(toolbar)

	var toolbar_hbox := HBoxContainer.new()
	toolbar_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	toolbar_hbox.offset_left = 8.0
	toolbar_hbox.offset_top = 10.0
	toolbar_hbox.offset_right = -8.0
	toolbar_hbox.offset_bottom = -10.0
	toolbar_hbox.add_theme_constant_override("separation", 6)
	toolbar.add_child(toolbar_hbox)

	var save_btn := Button.new()
	save_btn.text = "保存 (Ctrl+S)"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_on_save_pressed)
	toolbar_hbox.add_child(save_btn)

	var reset_btn := Button.new()
	reset_btn.text = "重置选中 (R)"
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.pressed.connect(_on_reset_pressed)
	toolbar_hbox.add_child(reset_btn)

	var deselect_btn := Button.new()
	deselect_btn.text = "取消选中 (X)"
	deselect_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deselect_btn.pressed.connect(_on_deselect_pressed)
	toolbar_hbox.add_child(deselect_btn)

	var exit_btn := Button.new()
	exit_btn.text = "退出 (Esc)"
	exit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exit_btn.pressed.connect(_on_exit_pressed)
	toolbar_hbox.add_child(exit_btn)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toolbar_hbox.add_child(_status_label)


func _on_tab_stations() -> void:
	_stations_list.visible = true
	_plants_list.visible = false


func _on_tab_plants() -> void:
	_stations_list.visible = false
	_plants_list.visible = true


func _on_save_pressed() -> void:
	emit_signal("save_pressed")


func _on_reset_pressed() -> void:
	emit_signal("reset_pressed")


func _on_deselect_pressed() -> void:
	emit_signal("deselect_pressed")


func _on_exit_pressed() -> void:
	emit_signal("exit_pressed")


func _on_station_item_selected(idx: int) -> void:
	emit_signal("object_selected", {"kind": "station", "idx": idx})


func _on_plant_item_selected(idx: int) -> void:
	emit_signal("object_selected", {"kind": "plant", "idx": idx})


func bind_editor(editor: Node3D) -> void:
	_editor = editor
	# 填列表
	if _stations_list != null:
		var stations = editor.get_stations_snapshot()
		_stations_list.clear()
		for st in stations:
			var sname: String = editor.get_station_name(st.get("idx", 0))
			var p: Vector3 = st.get("pos", Vector3.ZERO)
			_stations_list.add_item("#%d  %s  (%.1f, %.1f)" % [st["idx"] + 1, sname, p.x, p.z])
	if _plants_list != null:
		var plants = editor.get_plants_snapshot()
		_plants_list.clear()
		for i in range(plants.size()):
			var p: Dictionary = plants[i]
			_plants_list.add_item("#%d  %s  (%.1f, %.1f)  s=%.2f" % [i, p["type"], p["pos"].x, p["pos"].z, p["scale"]])
	# 信号
	save_pressed.connect(editor.save_layout)
	reset_pressed.connect(editor.reset_selected)
	deselect_pressed.connect(editor.deselect)
	exit_pressed.connect(editor.exit_to_gift_box)
	object_selected.connect(editor.select_from_hud)


func set_selection_info(info: Dictionary) -> void:
	if _selection_label == null:
		return
	_selection_label.text = info.get("label", "(未选中)")
	var pos: Vector3 = info.get("pos", Vector3.ZERO)
	_pos_label.text = "pos: (%.2f, %.2f, %.2f)" % [pos.x, pos.y, pos.z]
	_rot_label.text = "rot: %.1f°" % info.get("rot_y_deg", 0.0)
	_scale_label.text = "scale: %.2f" % info.get("scale", 1.0)


func set_dirty(d: bool) -> void:
	if _dirty_label == null:
		return
	_dirty_label.text = "● 未保存改动" if d else "已保存"


func set_status(s: String) -> void:
	if _status_label:
		_status_label.text = s


## LayoutEditor._update_hud 调用:让对应的 ItemList 选中(并尽可能滚到可见区),
## 起到"世界选中 → 列表高亮"的反向同步作用。
## Godot 4.6 ItemList 没有 set_current / set_v_scroll 之类的公开 API,
## "current" 是内部状态只跟键鼠导航挂钩。所以只能 select(idx) 高亮;
## 滚动用 get_v_scroll_bar().value 直接设 Range 值(每项约 28px,
## layout 改了就调一下 _LIST_ITEM_HEIGHT)。
const _LIST_ITEM_HEIGHT := 28
func set_selected_list_item(kind: String, idx: int) -> void:
	if kind == "station" and idx >= 0 and _stations_list != null:
		_stations_list.visible = true
		_plants_list.visible = false
		if idx < _stations_list.item_count:
			_stations_list.select(idx)
			_stations_list.deselect_all()
			_stations_list.select(idx)
			_stations_list.get_v_scroll_bar().value = idx * _LIST_ITEM_HEIGHT
	elif kind == "plant" and idx >= 0 and _plants_list != null:
		_stations_list.visible = false
		_plants_list.visible = true
		if idx < _plants_list.item_count:
			_plants_list.select(idx)
			_plants_list.deselect_all()
			_plants_list.select(idx)
			_plants_list.get_v_scroll_bar().value = idx * _LIST_ITEM_HEIGHT