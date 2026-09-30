extends Node3D
## Bike — 程序化自行车3D模型（CSG构建）
##
## 车架用 CSGCylinder3D/CSGBox3D 搭建；前后轮是独立 CSGCylinder3D，
## 不放进 CSGCombiner3D，这样每帧只改两个轮子的 transform 就能让它们转动，
## 不会触发整个车架 CSG 重算。

@export var wheel_radius: float = 0.35  ## 车轮半径（米），控制车轮滚动速率
@export var debug_speed: float = 0.0    ## 调试速度（米/秒）：车子静止时若需测试轮子滚动可填正数（如 3.0）

var _setup_done := false
var _has_last_pos := false
var _last_global_pos := Vector3.ZERO
var _wheel_angle := 0.0

var _rear_wheel: Node3D
var _front_wheel: Node3D
var _initial_wheel_basis := {}


func _ready() -> void:
	if not is_inside_tree():
		await tree_entered
	_do_setup()


func _do_setup() -> void:
	if _setup_done:
		return

	var bb = get_node_or_null("BB")
	var seat_cl = get_node_or_null("SeatCluster")
	var head_bot = get_node_or_null("HeadBottom")

	if not bb or not seat_cl or not head_bot:
		push_warning("Bike: 未找到骨架根节点 (BB / SeatCluster / HeadBottom)")
		return

	_set_tube(bb.get_node_or_null("DownTube_P"),     Vector3( 0.83,  0.20,  0.00))
	_set_tube(bb.get_node_or_null("SeatTube_P"),     Vector3( 0.00,  0.48,  0.08))
	_set_tube(seat_cl.get_node_or_null("TopTube_P"), Vector3( 0.83,  0.07, -0.08))
	_set_tube(bb.get_node_or_null("ChainStayL_P"),   Vector3(-0.62,  0.20,  0.06))
	_set_tube(bb.get_node_or_null("ChainStayR_P"),   Vector3(-0.62,  0.20, -0.06))
	_set_tube(seat_cl.get_node_or_null("SeatStayL_P"),Vector3(-0.62, 0.20,  0.06))
	_set_tube(seat_cl.get_node_or_null("SeatStayR_P"),Vector3(-0.62, 0.20, -0.06))
	_set_tube(head_bot.get_node_or_null("ForkL_P"),  Vector3( 0.62,  0.00,  0.06))
	_set_tube(head_bot.get_node_or_null("ForkR_P"),  Vector3( 0.62,  0.00, -0.06))

	_rear_wheel = get_node_or_null("RearWheel")
	_front_wheel = get_node_or_null("FrontWheel")
	for w in [_rear_wheel, _front_wheel]:
		if w:
			# CSGCylinder3D 默认高度沿 Y 轴（立柱）。绕 Z 轴旋转 90° 让高度轴
			# 变成 X 轴（横向），车轮就变成垂直圆盘，轴朝左右。
			var init_basis = w.transform.basis.rotated(Vector3(0, 0, 1), PI * 0.5)
			w.transform.basis = init_basis
			_initial_wheel_basis[w] = init_basis

	_setup_done = true


## 纯本地坐标下连接管件：自动计算长度、中心点与朝向
func _set_tube(pos3d: Node3D, target_bike_local: Vector3) -> void:
	if pos3d == null:
		return

	var parent_node = pos3d.get_parent() as Node3D
	if parent_node == null:
		return

	var target_in_parent = parent_node.transform.affine_inverse() * target_bike_local
	var from_in_parent = pos3d.position
	var diff = target_in_parent - from_in_parent
	var dist = diff.length()
	if dist < 0.001:
		return

	var dir = diff / dist

	var y_axis = dir
	var helper = Vector3.BACK if abs(y_axis.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var x_axis = y_axis.cross(helper).normalized()
	var z_axis = x_axis.cross(y_axis).normalized()
	var align_basis = Basis(x_axis, y_axis, z_axis)

	if pos3d is CSGCylinder3D:
		var cyl = pos3d as CSGCylinder3D
		cyl.height = dist
		cyl.position = (from_in_parent + target_in_parent) * 0.5
		cyl.transform.basis = align_basis
	else:
		pos3d.transform.basis = align_basis
		for child in pos3d.get_children():
			if child is CSGCylinder3D:
				child.height = dist
				child.position = Vector3(0, dist * 0.5, 0)


func _process(delta: float) -> void:
	if not _setup_done or not is_inside_tree():
		return

	var delta_angle: float = 0.0

	# 1. 只有车子实际产生前后位移时才计算滚动角速度
	var current_pos = global_position
	if _has_last_pos:
		var move_vec = current_pos - _last_global_pos
		# 车体前进方向 = -Z 轴（与 Player3D 的 forward = -basis.z 一致）
		var forward_dir = -global_transform.basis.z.normalized()
		var forward_dist = move_vec.dot(forward_dir)
		if abs(forward_dist) > 0.0001:
			delta_angle = forward_dist / wheel_radius
	_last_global_pos = current_pos
	_has_last_pos = true

	# 2. 调试速度（车子静止且设置了 debug_speed 时可用于原地空转测试）
	if abs(delta_angle) < 0.0001 and abs(debug_speed) > 0.0001:
		delta_angle = (debug_speed * delta) / wheel_radius

	# 3. 车子不动时不转；车子移动时沿 X 轴（横向车轴）向前翻滚
	if abs(delta_angle) > 0.00001:
		_wheel_angle += delta_angle
		_wheel_angle = fmod(_wheel_angle, TAU)

		for w in [_rear_wheel, _front_wheel]:
			if w and w in _initial_wheel_basis:
				# 绕 X 轴旋转（横向车轴），让轮子向前滚动
				w.transform.basis = _initial_wheel_basis[w].rotated(Vector3(1, 0, 0), _wheel_angle)
