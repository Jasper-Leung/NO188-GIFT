extends Control

const FRAGMENT_COLORS = [
	Color("B0C4DE"),
	Color("8FB35A"),
	Color("C9A26B"),
	Color("6E9C6B"),
	Color("E8A04F"),
]

const FragmentIconScript = preload("res://scripts/FragmentIcon.gd")

var _slots = []
var _collected = [false, false, false, false, false]
var _hint_popup: Control = null
var _hint_title: Label = null
var _hint_icon: Control = null
var _hint_note: Label = null
var _closing_hint = false
var _hint_idx = -1
var _animating_slot = -1
var _anim_timer = 0.0


func _ready() -> void:
	var container = $HBox
	for i in range(5):
		var p = container.get_child(i)
		_slots.append(p)
	Localization.language_changed.connect(_apply_language)
	_hint_popup = _create_hint_popup()
	get_parent().call_deferred("add_child", _hint_popup)
	_hint_popup.visible = false
	await get_tree().process_frame
	for p in _slots:
		p.pivot_offset = p.size * 0.5
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var lp = get_local_mouse_position()
			for i in range(5):
				if _slots[i].get_rect().has_point(lp):
					if _collected[i]:
						_show_hint(i)
					return


func _process(delta: float) -> void:
	# slot i 对应的驿站 idx 是 RoadData.FRAGMENT_SLOT_STATION_IDX[i],
	# 不能直接 is_collected(i) — 否则驿站 idx 4/7/10/13/14 的碎片永远不会点亮。
	for i in range(RoadData.FRAGMENT_SLOT_STATION_IDX.size()):
		var now = GameManager.is_fragment_collected(i)
		if _collected[i] != now:
			_collected[i] = now
			queue_redraw()
			if now:
				_start_slot_bounce(i)
				var lbl = _slots[i].get_node_or_null("FragLabel")
				if lbl != null:
					lbl.text = _fragment_name(i)

	if _animating_slot >= 0:
		_anim_timer += delta
		var dur = 0.45
		var t = clampf(_anim_timer / dur, 0.0, 1.0)
		var ef = 1.0 + sin(t * PI * 0.5) * 2.0 * (1.0 - t)
		_slots[_animating_slot].scale = Vector2(ef, ef)
		if t >= 1.0:
			_slots[_animating_slot].scale = Vector2.ONE
			_animating_slot = -1
			_anim_timer = 0.0


func _apply_language() -> void:
	for i in range(5):
		if not _collected[i]:
			continue
		var lbl = _slots[i].get_node_or_null("FragLabel")
		if lbl != null:
			lbl.text = _fragment_name(i)
	if _hint_popup != null and _hint_popup.visible:
		_update_hint_text(_hint_idx)


func _fragment_name(idx: int) -> String:
	return Localization.t("fragment_%d" % idx)


func _fragment_tip(idx: int) -> String:
	return Localization.t("fragment_tip_%d" % idx)


func _draw() -> void:
	for i in range(5):
		var collected = _collected[i]
		var p = _slots[i]
		var rect = p.get_global_rect()
		var local = rect.position - global_position
		var ctr = local + rect.size / 2.0
		var r = 22.0
		if collected:
			var col = FRAGMENT_COLORS[i]
			draw_circle(ctr, r + 8, Color(col.r, col.g, col.b, 0.2))
			draw_circle(ctr, r + 3, Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, 0.5))
			_draw_fragment_icon(ctr, i, col, 1.0)
			_draw_visit_pips(ctr, r, i)
		else:
			var gray = Color(0.35, 0.35, 0.35, 0.55)
			draw_circle(ctr, r, gray)
			_draw_fragment_icon(ctr, i, gray, 0.6)
			draw_string(ThemeDB.fallback_font, ctr + Vector2(-7, 6), "?", HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.5, 0.5, 0.5))


## 圆外面那排小点：这件碎片到访了几次。
##
## 完满评级要求每座碎片驿站去过 MAX_VISITS_PER_STATION 次，可这一排圆点原先
## 收过之后**三次长得一模一样** —— 玩家既看不到"这里还能再来两次"，回访之后
## 也看不到自己推进了什么。对着最强的重玩钩子毫无反馈，钩子就等于不存在。
## 点亮几个由存档算，未收的那几格不画（还没到访，没有次数可报）。
func _draw_visit_pips(ctr: Vector2, r: float, slot_idx: int) -> void:
	var max_visits: int = int(GameManager.MAX_VISITS_PER_STATION)
	var left: int = GameManager.fragment_slot_visits_left(slot_idx)
	var done: int = maxi(max_visits - left, 0)
	var pip_r := 3.5
	var gap := 10.0
	# 三颗点排在圆的正下方。r+8 是外圈光晕，压在它下面才不会被光晕吃掉
	var base_y := ctr.y + r + 12.0
	for k in max_visits:
		var p := Vector2(ctr.x + (float(k) - float(max_visits - 1) * 0.5) * gap, base_y)
		if k < done:
			draw_circle(p, pip_r, Color(0.96, 0.88, 0.62, 0.95))
		else:
			# 没到的点画成空心：还差几次这件事本身就是要给玩家看的信息。
			# 底栏底下就是 3D 场景（常常正好是一片深色树冠），所以空心点先垫一圈
			# 近黑再描金边 —— 单独一道金边压在深色上会整个消失掉。
			draw_circle(p, pip_r + 1.0, Color(0.10, 0.08, 0.05, 0.8))
			draw_circle(p, pip_r, Color(0.30, 0.26, 0.18, 0.9))
			draw_arc(p, pip_r, 0.0, TAU, 14, Color(0.96, 0.88, 0.62, 0.7), 1.0)


func _draw_fragment_icon(ctr: Vector2, idx: int, col: Color, alpha: float) -> void:
	match idx:
		0: _draw_cloud(ctr, col, alpha)
		1: _draw_teacup(ctr, col, alpha)
		2: _draw_guqin(ctr, col, alpha)
		3: _draw_bamboo(ctr, col, alpha)
		4: _draw_bird(ctr, col, alpha)


## 云：和 `Postcard._draw_cloud` / `FragmentIcon._draw_cloud` 同一套鼓包、同一段
## 轮廓算法。原来这里是三个同半径的圆叠出来的，攒齐之后明信片上却是另一朵云 ——
## 玩家一路看着它在顶栏长大，最后带走的那张纸上认不出是同一件东西。
## 逐列取最上面的鼓包，别改成「每团各画半圆」（会自交，三角化出 0 面积）。
func _draw_cloud(c: Vector2, col: Color, a: float) -> void:
	var bumps := [
		[Vector2(-26.0, 5.0), 13.0],
		[Vector2(-9.0, -6.0), 19.0],
		[Vector2(10.0, -2.0), 15.0],
		[Vector2(24.0, 6.0), 9.0],
	]
	var sc := 0.44
	var base_y := 13.0 * sc
	var x0 := c.x - 38.0 * sc
	var x1 := c.x + 32.0 * sc
	var poly := PackedVector2Array()
	const STEPS := 48
	for i in range(STEPS + 1):
		var x := lerpf(x0, x1, float(i) / float(STEPS))
		var top := base_y
		for b in bumps:
			var r := float(b[1]) * sc
			var dx := x - (c.x + float(b[0].x) * sc)
			if absf(dx) < r:
				top = minf(top, c.y + float(b[0].y) * sc - sqrt(r * r - dx * dx))
		poly.append(Vector2(x, top))
	poly.append(Vector2(x1, c.y + base_y))
	poly.append(Vector2(x0, c.y + base_y))
	draw_colored_polygon(poly, Color(col.r, col.g, col.b, a))
	draw_arc(c + Vector2(-9.0 * sc, -6.0 * sc), 12.0 * sc, PI * 1.12, PI * 1.62, 10,
			Color(1, 1, 1, a * 0.7), 1.5)


func _draw_teacup(c: Vector2, col: Color, a: float) -> void:
	draw_arc(c + Vector2(0, 2), 10.0, 0, PI, 16, Color(col.r, col.g, col.b, a), 2)
	draw_line(c + Vector2(-10, 2), c + Vector2(-10, -4), Color(col.r, col.g, col.b, a), 2)
	draw_line(c + Vector2(10, 2), c + Vector2(10, -4), Color(col.r, col.g, col.b, a), 2)
	draw_arc(c + Vector2(0, -4), 10.0, PI, TAU, 16, Color(col.r, col.g, col.b, a), 2)
	draw_arc(c + Vector2(-14, -2), 4.0, -PI * 0.3, PI * 0.3, 8, Color(col.r, col.g, col.b, a), 1.5)
	draw_arc(c + Vector2(-3, -10), 3.0, PI, TAU, 8, Color(1, 1, 1, a * 0.5), 1.0)


func _draw_guqin(c: Vector2, col: Color, a: float) -> void:
	var pts = [
		c + Vector2(-18, 3), c + Vector2(-10, -5), c + Vector2(0, -7),
		c + Vector2(10, -5), c + Vector2(18, 3)
	]
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], Color(col.r, col.g, col.b, a), 2)
	draw_line(pts[0], pts[4], Color(col.r, col.g, col.b, a), 2)
	for j in range(4):
		var y = -4.0 + j * 2.5
		draw_line(c + Vector2(-14, y), c + Vector2(14, y), Color(1, 1, 1, a * 0.4), 1)


func _draw_bamboo(c: Vector2, col: Color, a: float) -> void:
	for s in range(-1, 2):
		var bx = c.x + s * 9
		for n in range(4):
			var by = c.y - 14 + n * 10
			draw_line(Vector2(bx, by - 10), Vector2(bx, by + 4), Color(col.r, col.g, col.b, a), 2.5)
			draw_line(Vector2(bx - 4, by), Vector2(bx + 4, by), Color(col.r, col.g, col.b, a), 1.5)


func _draw_bird(c: Vector2, col: Color, a: float) -> void:
	draw_arc(c + Vector2(0, 2), 9.0, 0, TAU, 16, Color(col.r, col.g, col.b, a), 2)
	draw_line(c + Vector2(9, 2), c + Vector2(18, -2), Color(col.r, col.g, col.b, a), 2)
	draw_line(c + Vector2(12, -4), c + Vector2(17, -9), Color(col.r, col.g, col.b, a), 1.5)
	draw_line(c + Vector2(12, -4), c + Vector2(14, -8), Color(col.r, col.g, col.b, a), 1.5)
	draw_arc(c + Vector2(18, -2), 3.0, -PI * 0.2, PI * 0.8, 8, Color(col.r, col.g, col.b, a), 1.5)


func _create_hint_popup() -> Control:
	var overlay = Control.new()
	overlay.z_index = 100
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.gui_input.connect(_on_hint_overlay_input)

	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.06, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)

	var panel = Panel.new()
	panel.z_index = 10
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -230.0
	panel.offset_top = -220.0
	panel.offset_right = 230.0
	panel.offset_bottom = 220.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 36.0
	vbox.offset_top = 28.0
	vbox.offset_right = -36.0
	vbox.offset_bottom = -28.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var title = Label.new()
	title.name = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)
	_hint_title = title

	var icon = FragmentIconScript.new()
	icon.name = "IconHost"
	icon.custom_minimum_size = Vector2(180, 180)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon)
	_hint_icon = icon

	var note = Label.new()
	note.name = "NoteLabel"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(380, 0)
	note.add_theme_font_size_override("font_size", 18)
	note.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1))
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(note)
	_hint_note = note

	var hint = Label.new()
	hint.name = "HintLabel"
	hint.text = Localization.t("hint_close")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hint)

	return overlay


func _show_hint(idx: int) -> void:
	if _hint_popup.visible or _closing_hint:
		return
	_hint_idx = idx
	_update_hint_text(idx)
	var col = FRAGMENT_COLORS[idx]
	_hint_title.add_theme_color_override("font_color", col)
	_hint_icon.fragment_idx = idx
	_hint_icon.color = col
	_hint_icon.alpha = 1.0
	_hint_icon.queue_redraw()
	_hint_popup.visible = true
	_hint_popup.modulate.a = 0.0
	_hint_popup.scale = Vector2(0.9, 0.9)
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_hint_popup, "modulate:a", 1.0, 0.25)
	tw.tween_property(_hint_popup, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)


func _update_hint_text(idx: int) -> void:
	var col = FRAGMENT_COLORS[idx]
	_hint_title.text = _fragment_name(idx)
	_hint_title.add_theme_color_override("font_color", col)
	_hint_note.text = _fragment_tip(idx)


func _on_hint_overlay_input(_event: InputEvent) -> void:
	if not _hint_popup.visible or _closing_hint:
		return
	if _event is InputEventMouseButton:
		var mb = _event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_close_hint()
			get_viewport().set_input_as_handled()
	elif _event is InputEventKey:
		var k = _event as InputEventKey
		if k.pressed and k.keycode == KEY_ESCAPE:
			_close_hint()
			get_viewport().set_input_as_handled()


func _close_hint() -> void:
	_closing_hint = true
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_hint_popup, "modulate:a", 0.0, 0.25)
	tw.tween_property(_hint_popup, "scale", Vector2(0.92, 0.92), 0.25)
	await tw.finished
	_hint_popup.visible = false
	_hint_popup.modulate.a = 1.0
	_hint_popup.scale = Vector2.ONE
	_closing_hint = false


func _start_slot_bounce(idx: int) -> void:
	if idx < 0 or idx >= _slots.size():
		return
	if _animating_slot >= 0:
		_slots[_animating_slot].scale = Vector2.ONE
	_animating_slot = idx
	_anim_timer = 0.0


func get_slot_global_center(idx: int) -> Vector2:
	if idx < 0 or idx >= _slots.size():
		return Vector2.ZERO
	return _slots[idx].get_global_rect().get_center()
