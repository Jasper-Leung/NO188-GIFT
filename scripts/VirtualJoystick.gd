extends Control
## VirtualJoystick — 移动端虚拟摇杆 (PRD F-07 触屏兼容)
## 触屏设备：左下角常驻半透明基底，触摸后激活摇杆
## 桌面设备：完全隐藏（键盘控制）

signal joystick_input(dir: Vector2)

const MAX_RADIUS = 60.0
const KNOB_RADIUS = 22.0
const BASE_RADIUS = 70.0

var _active_touch = -1
var _center = Vector2.ZERO
var _knob_offset = Vector2.ZERO
var _is_touch_device = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 10
	_is_touch_device = DisplayServer.is_touchscreen_available()
	if not _is_touch_device:
		visible = false


func _draw() -> void:
	if _active_touch >= 0:
		var knob_pos = _center + _knob_offset
		draw_circle(_center, BASE_RADIUS, Color(1, 1, 1, 0.1), true)
		draw_arc(_center, BASE_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.28), 2.5, true)
		draw_circle(knob_pos, KNOB_RADIUS, Color(1, 1, 1, 0.55), true)
		draw_arc(knob_pos, KNOB_RADIUS, 0, TAU, 24, Color(1, 1, 1, 0.35), 1.5, true)
	else:
		var c = size / 2.0
		draw_circle(c, BASE_RADIUS, Color(1, 1, 1, 0.05), true)
		draw_arc(c, BASE_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.12), 1.5, true)
		draw_circle(c, KNOB_RADIUS, Color(1, 1, 1, 0.08), true)
		_draw_dir_hints(c)


func _draw_dir_hints(c: Vector2) -> void:
	var font = ThemeDB.fallback_font
	var col = Color(1, 1, 1, 0.18)
	var fs = 14
	_draw_key(font, c + Vector2(0, -BASE_RADIUS + 22), "W", fs, col)
	_draw_key(font, c + Vector2(0, BASE_RADIUS - 22), "S", fs, col)
	_draw_key(font, c + Vector2(-BASE_RADIUS + 22, 0), "A", fs, col)
	_draw_key(font, c + Vector2(BASE_RADIUS - 22, 0), "D", fs, col)


func _draw_key(font, pos: Vector2, text: String, fs: int, col: Color) -> void:
	var ts = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(font, pos - ts / 2.0, text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, col)


func _input(event: InputEvent) -> void:
	if not _is_touch_device:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _active_touch < 0:
			var gr = get_global_rect()
			if gr.has_point(event.position):
				_active_touch = event.index
				_center = event.position - gr.position
				_knob_offset = Vector2.ZERO
				queue_redraw()
				joystick_input.emit(Vector2.ZERO)
				get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _active_touch:
			_active_touch = -1
			_knob_offset = Vector2.ZERO
			queue_redraw()
			joystick_input.emit(Vector2.ZERO)
	elif event is InputEventScreenDrag and event.index == _active_touch:
		var gr = get_global_rect()
		var local = event.position - gr.position
		var delta = local - _center
		var dist = delta.length()
		_knob_offset = delta.normalized() * min(dist, MAX_RADIUS)
		queue_redraw()
		var norm = _knob_offset / MAX_RADIUS if MAX_RADIUS > 0 else Vector2.ZERO
		joystick_input.emit(norm)
		get_viewport().set_input_as_handled()
