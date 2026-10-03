extends CharacterBody3D
## Player3D — 3D自由骑行，W/S加减速，A/D转向

const MAX_SPEED = 15.0
const ACCEL = 8.0
const DECEL = 12.0
const REVERSE_SPEED = 5.0
const TURN_SPEED = 1.8

## 跟随机位。正后方 0 横向偏移时，一辆车在这个距离上正投影成一根竖条——
## 车架三角、两个轮子全都侧对镜头，认不出是自行车。CAM_SIDE 是唯一能
## 把车读成"车"的自由度，实测顶点投影宽高比 0.30（正后方）→ 0.86（现在），
## 判据在 tools/verify_camera_bike.gd。CAM_BACK / CAM_UP / LOOK_* 是扫出来
## 的：横向让开之后要相应把相机压低拉近，车的轮廓才铺得开。
const CAM_BACK = 3.2       # 沿车头方向往后
const CAM_UP = 2.3         # 抬高
const CAM_SIDE = 2.4       # 横向让开
const CAM_LOOK_AHEAD = 2.2
const CAM_LOOK_UP = 1.1

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
	var right = global_transform.basis.x
	var target_pos = global_position - forward * CAM_BACK + right * CAM_SIDE + Vector3(0, CAM_UP, 0)
	_cam.global_position = _cam.global_position.lerp(target_pos, 0.12)
	_cam.look_at(global_position + forward * CAM_LOOK_AHEAD + Vector3(0, CAM_LOOK_UP, 0), Vector3.UP)


func set_camera_locked(v: bool) -> void:
	_cam_locked = v


## 相机是不是被冻住了。`World3D._play_villain_scene()` 现在也会锁相机，
## 而它**必须**在收尾时解锁——漏掉的话车照跑、镜头定死在原地，
## 没有任何症状会指向"刚才那场反派戏没收干净"。
## 所以这条状态需要一个从外面读得到的出口。
func is_camera_locked() -> bool:
	return _cam_locked


func get_speed() -> float:
	return _speed


func set_can_move(v: bool) -> void:
	_can_move = v
	if not v:
		_speed = 0.0


func set_touch_direction(dir: Vector2) -> void:
	_touch_dir = dir


## 撞到世界硬边界时按比例掉速度。
##
## `World3D._apply_station_keepout()` 把位置摆回墙外之后，车本身并不知道自己撞了——
## `_speed` 还在，于是它会贴着墙"蹭"着走：位置每帧被推回、每帧又往里冲，
## 玩家看着像车卡在墙里抖。这道衰减让撞墙之后真的慢下来。
func damp_speed(f: float) -> void:
	_speed *= f
