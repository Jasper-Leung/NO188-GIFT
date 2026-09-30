extends CharacterBody3D
## Player3D — 3D自由骑行，W/S加减速，A/D转向

const MAX_SPEED = 15.0
const ACCEL = 8.0
const DECEL = 12.0
const REVERSE_SPEED = 5.0
const TURN_SPEED = 1.8

var _speed: float = 0.0
var _can_move = true
var _cam_locked = false
var _touch_dir = Vector2.ZERO

@onready var _cam: Camera3D = $Camera3D


func _physics_process(delta: float) -> void:
	if not _can_move:
		return

	var vert = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	var horiz = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")

	if _touch_dir.length() > 0.1:
		vert = -_touch_dir.y
		horiz = _touch_dir.x

	if vert < -0.1:
		_speed = min(_speed + ACCEL * delta, MAX_SPEED)
	elif vert > 0.1:
		_speed = max(_speed - DECEL * delta, -REVERSE_SPEED)
	else:
		if _speed > 0:
			_speed = max(_speed - DECEL * 0.3 * delta, 0.0)
		else:
			_speed = min(_speed + DECEL * 0.3 * delta, 0.0)

	var turn_factor = 0.0
	if abs(_speed) > 0.5:
		turn_factor = clamp(abs(_speed) / 3.0, 0.0, 1.0)
	rotate_y(-horiz * TURN_SPEED * delta * turn_factor * sign(_speed))

	var forward = -global_transform.basis.z
	position += forward * _speed * delta
	# Y 由 World3D._physics_process 根据地形高度设置，这里不再覆盖
	# 边界由 World3D._apply_boundary_force 软回弹处理（F-07），此处不再硬 clamp

	_update_camera(delta)


func _update_camera(delta: float) -> void:
	if not _cam:
		return
	if _cam_locked:
		return
	var forward = -global_transform.basis.z
	var target_pos = global_position - forward * 6.0 + Vector3(0, 4.0, 0)
	_cam.global_position = _cam.global_position.lerp(target_pos, 0.12)
	_cam.look_at(global_position + forward * 3.0 + Vector3(0, 1.0, 0), Vector3.UP)


func set_camera_locked(v: bool) -> void:
	_cam_locked = v


func get_speed() -> float:
	return _speed


func set_can_move(v: bool) -> void:
	_can_move = v
	if not v:
		_speed = 0.0


func set_touch_direction(dir: Vector2) -> void:
	_touch_dir = dir
