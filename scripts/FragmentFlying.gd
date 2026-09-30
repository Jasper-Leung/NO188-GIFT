extends Node2D

var FRAGMENT_COLORS = [
	Color("B0C4DE"),
	Color("8FB35A"),
	Color("C9A26B"),
	Color("6E9C6B"),
	Color("E8A04F"),
]
var FRAGMENT_NAMES = ["云", "茶", "琴", "竹", "禽"]

var _idx = 0
var _from = Vector2.ZERO
var _to = Vector2.ZERO
var _total_dist = 0.0
var _travelled = 0.0
var auto_free_on_complete = true


func setup(idx: int, from_pos: Vector2, to_pos: Vector2) -> void:
	_idx = idx
	_from = from_pos
	_to = to_pos
	_total_dist = (_to - _from).length()
	position = _from


func _draw() -> void:
	# 防御性 clamp:FRAGMENT_COLORS/FRAGMENT_NAMES 只有 5 项,
	# 调用方传错 idx(比如传了 station idx 而不是 slot idx)就静默退化,
	# 不至于渲染时崩 "Invalid access of index 'N' on Array"。
	var safe_idx: int = clamp(_idx, 0, FRAGMENT_COLORS.size() - 1) if _idx >= 0 else 0
	var col = FRAGMENT_COLORS[safe_idx]
	var name = FRAGMENT_NAMES[safe_idx]
	var t = clampf(_travelled / _total_dist, 0.0, 1.0) if _total_dist > 0 else 0.0
	var scale_fac = 1.0 + sin(t * PI) * 0.35
	var alpha = 1.0 if t < 0.8 else 1.0 - (t - 0.8) / 0.2
	var r = 24.0 * scale_fac
	var ctr = Vector2.ZERO
	draw_circle(ctr, r + 8, Color(col.r, col.g, col.b, alpha * 0.25))
	draw_circle(ctr, r + 3, Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, alpha * 0.6))
	draw_circle(ctr, r, Color(col.r, col.g, col.b, alpha))
	draw_arc(ctr, r, 0, TAU, 24, Color(1, 1, 1, alpha * 0.8), 2)
	var fs = 18.0 * scale_fac
	draw_string(ThemeDB.fallback_font, ctr + Vector2(-8 * scale_fac, 7 * scale_fac), name, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1, alpha))


func _physics_process(delta: float) -> void:
	var speed = 900.0
	_travelled += speed * delta
	var t = clampf(_travelled / _total_dist, 0.0, 1.0) if _total_dist > 0 else 0.0
	position = _from.lerp(_to, t)
	rotation = sin(t * PI * 4.0) * 0.3
	queue_redraw()
	if t >= 1.0:
		if auto_free_on_complete:
			queue_free()
		else:
			set_physics_process(false)
