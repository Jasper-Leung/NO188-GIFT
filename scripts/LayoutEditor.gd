extends Node3D
## LayoutEditor — 编辑模式主控制器 (激活条件见 GameManager.is_editor_mode())
##
## 设计目标:让开发者能在游戏世界里选中并调整驿站/植物,保存到
## res://layout.json,正式版本启动时由 World3D / VegBuilder 自动应用。
##
## 交互:
##   - WASD:相机水平移动(始终给相机,选中对象时不被劫持)
##   - R / F:相机上升 / 下降
##   - 方向键(无 Shift):平移选中对象 0.1m;Shift+方向键 1.0m;长按连续 3m/s,Shift 加速到 15m/s
##   - Q / E:绕 Y 轴旋转选中 ±5°
##   - [ / ]:植物 uniform 缩放 (× 1.05 / × 0.95)
##   - 鼠标左键:拾取最近的驿站或植物(同时把列表滚到对应项);点击同一对象或空白 → 取消选中
##   - 点击侧栏列表项:选中对应对象并把相机平滑飞过去
##   - X 或工具栏"取消选中":退出选择,把 WASD 还给相机
##   - Backspace:重置当前选中对象
##   - Ctrl+S:保存当前布局
##   - Esc:退出编辑器(切回 GiftBox)
##
## 注意:此节点只读快照,不做运行时编辑;点击"保存"才会把当前
## _stations 和 plants 快照写到 res://layout.json。

const SELECT_STATION_PX := 40.0
const SELECT_PLANT_PX := 30.0
# 驿站 GLB 模型 scale=10,视觉高度约 10-14 世界单位;采样这些 Y 偏移
# 让"点击视觉中心"命中,而不是只匹配底座。
const STATION_PICK_Y_OFFSETS: Array = [0.0, 3.0, 6.0, 9.0, 12.0]
const STEP_FINE := 0.1
const STEP_COARSE := 1.0
const ROT_STEP_DEG := 5.0
const SCALE_STEP := 1.05
const MIN_SCALE := 0.1
const MAX_SCALE := 10.0
const MOVE_SPEED := 6.0
const SHIFT_SPEED_MULT := 3.0
const CAMERA_HEIGHT := 100.0
const CAMERA_BACK := 80.0
const CAMERA_FOV := 60.0
const FOCUS_DISTANCE := 10.0
const FOCUS_DURATION := 0.25

var _world: Node3D = null
var _stations: Array = []
var _veg_builder: Node3D = null
var _road_builder: Node3D = null
var _hud: Control = null

var _camera: Camera3D = null
var _yaw: float = -PI * 0.5
var _pitch: float = -PI * 0.25
var _move_input := Vector3.ZERO
var _last_click_pos := Vector2.ZERO

# 选中状态:"station" / "plant" / null
var _selected_kind: String = ""
var _selected_station_idx: int = -1
var _selected_plant_idx: int = -1

# 选中对象的"原始快照",用于重置
var _selected_origin: Dictionary = {}

# 整局快照(用于"保存到 JSON"):stations = [{idx, pos, rot_y_deg}], plants = [...]
var _stations_snapshot: Array = []
var _plants_snapshot: Array = []
var _dirty: bool = false

# 相机定位动画 tween (在 list/wold 点击选中时使用)
var _focus_tween: Tween = null

# 选中高亮 MeshInstance
var _selection_marker: MeshInstance3D = null
# 拾取辅助:用 ImmediateMesh 画一个半透明体积圈(可选,这里用 box 高亮足够)


func setup(world: Node3D, stations: Array, veg_builder: Node3D, road_builder: Node3D) -> void:
	_world = world
	_stations = stations
	_veg_builder = veg_builder
	_road_builder = road_builder
	_take_snapshot()
	_spawn_camera()
	_spawn_selection_marker()
	_update_hud()


func bind_hud(hud: Control) -> void:
	_hud = hud
	if _hud == null:
		return
	# HUD 自身负责连信号;这里只把状态推过去
	if _hud.has_method("bind_editor"):
		_hud.bind_editor(self)


## 对单个 3D 点做屏幕距离判定:返回该屏幕点到 world_pos 的像素距离
func _screen_dist_to(world_pos: Vector3, screen_pos: Vector2) -> float:
	var screen := _camera.unproject_position(world_pos)
	return (screen - screen_pos).length()


func _pick_nearest(screen_pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1e9
	# 1) stations — 采样底座 + 多个 Y 偏移(对应模型视觉中心、屋顶)。
	#    GLB 模型 scale=10,座标 y=0 在底部,但视觉中心通常在 y≈5,屋顶 y≈12。
	#    只匹配底座会让"点视觉中心"落空,导致取消选中后无法再次选回同一驿站。
	for i in range(_stations.size()):
		var st: Node3D = _stations[i]
		var st_d := 1e9
		for y_off in STATION_PICK_Y_OFFSETS:
			var d := _screen_dist_to(st.global_position + Vector3(0, y_off, 0), screen_pos)
			if d < st_d:
				st_d = d
		if st_d < best_d and st_d <= SELECT_STATION_PX:
			best_d = st_d
			best = {"kind": "station", "idx": i}
	# 2) plants — 采样底座 + 按 scale 计算的视觉中心
	var items: Array = []
	if _veg_builder != null and _veg_builder.has_method("get_all_items"):
		items = _veg_builder.get_all_items()
		for i in range(items.size()):
			var item: Dictionary = items[i]
			var pos: Vector3 = item["pos"]
			var sc: float = float(item.get("scale", 1.0))
			var plant_d := _screen_dist_to(pos, screen_pos)
			# 中心采样:约 0.6×scale 高处
			var d2 := _screen_dist_to(pos + Vector3(0, sc * 0.6, 0), screen_pos)
			if d2 < plant_d:
				plant_d = d2
			if plant_d < best_d and plant_d <= SELECT_PLANT_PX:
				best_d = plant_d
				best = {"kind": "plant", "idx": i}
	return best


func _take_snapshot() -> void:
	# stations:World3D._stations 当前 pos 和 rot_y_override
	_stations_snapshot.clear()
	for i in range(_stations.size()):
		var st: Node3D = _stations[i]
		_stations_snapshot.append({
			"idx": i,
			"pos": st.position,
			"rot_y_deg": st.get_meta("rot_y_override", 0.0) if st.has_meta("rot_y_override") else 0.0,
		})
	# plants:从 VegBuilder.get_all_items() 取当前 pos/rot/scale
	_plants_snapshot.clear()
	if _veg_builder != null and _veg_builder.has_method("get_all_items"):
		_plants_snapshot = _veg_builder.get_all_items()


func _spawn_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "EditorCamera"
	_camera.fov = CAMERA_FOV
	add_child(_camera)
	_camera.current = true
	# 起始位置:路径中点上方较高 + 侧偏,看向中点(看到整条 8 字路线)
	if _road_builder != null and _road_builder.has_method("get_centerline"):
		var centerline = _road_builder.get_centerline()
		if centerline.size() > 0:
			var mid: Vector3 = centerline[centerline.size() / 2]
			_camera.global_position = mid + Vector3(CAMERA_BACK, CAMERA_HEIGHT, CAMERA_BACK)
			_camera.look_at(mid, Vector3.UP)
			var fwd: Vector3 = (_camera.global_transform.basis * Vector3.FORWARD).normalized()
			_yaw = atan2(-fwd.x, -fwd.z)
			_pitch = asin(fwd.y)
			_apply_yaw_pitch()



func _spawn_selection_marker() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(2.5, 5.0, 2.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.85, 0.2, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.85, 0.2, 0.6)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	_selection_marker = MeshInstance3D.new()
	_selection_marker.mesh = box
	_selection_marker.material_override = mat
	_selection_marker.visible = false
	add_child(_selection_marker)


var _proc_tick: int = 0
func _process(delta: float) -> void:
	_proc_tick += 1
	if _camera == null:
		return
	_apply_move_input(delta)
	_camera.global_position += _move_input
	_move_input = Vector3.ZERO
	# 选中对象时:长按方向键连续移动(per-press 0.1m + per-frame 速率)
	if _selected_kind != "":
		_apply_selection_continuous_move(delta)
	# 右键拖拽旋转视角
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mp := Input.get_last_mouse_velocity()
		if mp.length_squared() > 0.0:
			_yaw -= mp.x * 0.005
			_pitch -= mp.y * 0.005
			_pitch = clampf(_pitch, -PI * 0.49, PI * 0.49)
			_apply_yaw_pitch()


const SELECT_MOVE_SPEED := 3.0
const SELECT_MOVE_SPEED_BOOST := 15.0

func _apply_selection_continuous_move(delta: float) -> void:
	var speed := SELECT_MOVE_SPEED
	if Input.is_key_pressed(KEY_SHIFT):
		speed = SELECT_MOVE_SPEED_BOOST
	var step := speed * delta
	if Input.is_action_pressed("editor_move_fwd"):
		_move_selected(Vector3(0, 0, -step))
	if Input.is_action_pressed("editor_move_back"):
		_move_selected(Vector3(0, 0, step))
	if Input.is_action_pressed("editor_move_left"):
		_move_selected(Vector3(-step, 0, 0))
	if Input.is_action_pressed("editor_move_right"):
		_move_selected(Vector3(step, 0, 0))


func _apply_move_input(delta: float) -> void:
	# WASD 始终给相机(选中对象时也不被劫持)
	# 只有方向键在选中时专用于平移对象,跟 WASD 不冲突
	if _camera == null:
		return
	var speed := MOVE_SPEED
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= SHIFT_SPEED_MULT
	var forward := -_camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := _camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var move := Vector3.ZERO
	if Input.is_action_pressed("move_up"):
		move += forward
	if Input.is_action_pressed("move_down"):
		move -= forward
	if Input.is_action_pressed("move_left"):
		move -= right
	if Input.is_action_pressed("move_right"):
		move += right
	# 相机升降:R/F (不再用 Q/E,Q/E 专属旋转)
	if Input.is_action_pressed("editor_camera_up"):
		move += Vector3.UP
	if Input.is_action_pressed("editor_camera_down"):
		move -= Vector3.UP
	if move.length_squared() > 0.0:
		_move_input = move.normalized() * speed * delta


func _apply_yaw_pitch() -> void:
	var basis_y := Basis().rotated(Vector3.UP, _yaw)
	var basis_x := Basis().rotated(Vector3.RIGHT, _pitch)
	_camera.global_transform.basis = basis_y * basis_x


func _input(event: InputEvent) -> void:
	# 用 _input 而不是 _unhandled_input:
	# _input 在 GUI 派发之前触发,保证无论 HUD/侧栏/工具栏等 Control
	# 是否消费了事件,编辑器一定能拿到鼠标点击和键盘输入。
	#
	# 退出
	if event.is_action_pressed("editor_exit"):
		exit_to_gift_box()
		return
	# 保存
	if event.is_action_pressed("editor_save"):
		save_layout()
		return
	# 重置当前选中
	if event.is_action_pressed("editor_reset"):
		reset_selected()
		return
	# 取消选中(把 WASD 还给相机)
	if event.is_action_pressed("editor_deselect"):
		_clear_selection()
		get_viewport().set_input_as_handled()
		return
	# 平移选中(方向键,无 modifier 时为选中对象移动;不消费方向键移动相机)
	if _selected_kind != "":
		var step := STEP_FINE
		if Input.is_key_pressed(KEY_SHIFT):
			step = STEP_COARSE
		var moved := false
		if event.is_action_pressed("editor_move_fwd"):
			moved = _move_selected(Vector3(0, 0, -step)); get_viewport().set_input_as_handled()
		elif event.is_action_pressed("editor_move_back"):
			moved = _move_selected(Vector3(0, 0, step)); get_viewport().set_input_as_handled()
		elif event.is_action_pressed("editor_move_left"):
			moved = _move_selected(Vector3(-step, 0, 0)); get_viewport().set_input_as_handled()
		elif event.is_action_pressed("editor_move_right"):
			moved = _move_selected(Vector3(step, 0, 0)); get_viewport().set_input_as_handled()
		# 注意:方向键同时也是相机平移(WASD 没绑定方向键,只有 W/A/S/D)
		# 方向键绑定的 editor_move_* 只用于选中对象
		# 但 editor_move_fwd 绑的是 KEY_UP,没有 move_up 冲突 → 唯一消费方
		if moved:
			return
		# 旋转
		if event.is_action_pressed("editor_rotate_cw"):
			if _rotate_selected(ROT_STEP_DEG):
				get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("editor_rotate_ccw"):
			if _rotate_selected(-ROT_STEP_DEG):
				get_viewport().set_input_as_handled()
			return
		# 缩放
		if event.is_action_pressed("editor_scale_up"):
			if _scale_selected(SCALE_STEP):
				get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("editor_scale_down"):
			if _scale_selected(1.0 / SCALE_STEP):
				get_viewport().set_input_as_handled()
			return
	# 鼠标点击拾取(只处理世界区的左键点击;banner/侧栏/工具栏区交给 GUI)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if not _is_in_ui_region(mb.position):
				_handle_click(mb.position)


## 判断屏幕坐标是否在 EditorHUD 的 UI 区域(banner/侧栏/工具栏),
## 这些区域让 GUI 控件自己处理点击,编辑器不抢。
const UI_TOP_HEIGHT := 60.0
const UI_BOTTOM_HEIGHT := 56.0
const UI_RIGHT_WIDTH := 340.0

func _is_in_ui_region(screen_pos: Vector2) -> bool:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	# 顶部 banner + hint
	if screen_pos.y <= UI_TOP_HEIGHT:
		return true
	# 底部工具栏
	if screen_pos.y >= vp_size.y - UI_BOTTOM_HEIGHT:
		return true
	# 右侧侧栏
	if screen_pos.x >= vp_size.x - UI_RIGHT_WIDTH:
		return true
	return false


func _unhandled_input(_event: InputEvent) -> void:
	# 编辑器用 _input 接管输入,这里留空以避免重复处理
	pass


func _handle_click(screen_pos: Vector2) -> void:
	if _camera == null:
		return
	var best: Dictionary = _pick_nearest(screen_pos)
	# 点击空白 / 点击同一选中对象 → 取消选中(把 WASD 还给相机)
	if best.is_empty():
		_clear_selection()
		return
	if best["kind"] == _selected_kind and best["idx"] == _get_selected_idx():
		_clear_selection()
		return
	_select(best)


func _get_selected_idx() -> int:
	if _selected_kind == "station":
		return _selected_station_idx
	if _selected_kind == "plant":
		return _selected_plant_idx
	return -1


func _select(sel: Dictionary) -> void:
	_clear_selection()
	_selected_kind = sel["kind"]
	var target_world_pos := Vector3.ZERO
	if _selected_kind == "station":
		_selected_station_idx = sel["idx"]
		_selected_plant_idx = -1
		var st: Node3D = _stations[_selected_station_idx]
		_selected_origin = {
			"pos": st.position,
			"rot_y_deg": st.get_meta("rot_y_override", 0.0) if st.has_meta("rot_y_override") else 0.0,
		}
		_selection_marker.global_position = st.position + Vector3(0, 2.5, 0)
		target_world_pos = st.position
	elif _selected_kind == "plant":
		_selected_station_idx = -1
		_selected_plant_idx = sel["idx"]
		var items: Array = _veg_builder.get_all_items()
		var item: Dictionary = items[_selected_plant_idx]
		_selected_origin = {
			"pos": item["pos"],
			"rot_y_deg": item["rot_y_deg"],
			"scale": item["scale"],
		}
		_selection_marker.global_position = item["pos"] + Vector3(0, 1.0, 0)
		# 植物更小,缩小高亮框
		var sz: float = maxf(item["scale"], 1.0)
		_selection_marker.scale = Vector3(sz, sz, sz)
		target_world_pos = item["pos"]
	_selection_marker.visible = true
	# 任何来源的选中(列表点击 / 世界点击)都把相机平滑飞过去,
	# 远距离对象也能立刻看到,近距离几乎不动
	if target_world_pos != Vector3.ZERO:
		_focus_camera_on(target_world_pos)
	_update_hud()


## 把相机平滑飞到 target 附近,沿当前相机前向后退 FOCUS_DISTANCE
func _focus_camera_on(target: Vector3) -> void:
	if _camera == null:
		return
	# 如果相机离 target 已经很近(<FOCUS_DISTANCE 之内),不强制 tween,
	# 否则取消选中后用户无法在原位置再次选回同一对象。
	var current_to_target: float = _camera.global_position.distance_to(target)
	if current_to_target < FOCUS_DISTANCE * 1.5:
		return
	var forward: Vector3 = -_camera.global_transform.basis.z
	# 防止相机几乎朝正下方导致 look_at 与 up 共线
	if forward.y < -0.7:
		forward = Vector3(0, -0.5, -1).normalized()
	var desired_pos: Vector3 = target - forward * FOCUS_DISTANCE
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = create_tween()
	_focus_tween.tween_property(_camera, "global_position", desired_pos, FOCUS_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _clear_selection() -> void:
	_selected_kind = ""
	_selected_station_idx = -1
	_selected_plant_idx = -1
	_selected_origin = {}
	if _selection_marker:
		_selection_marker.visible = false
	# 取消选中时立即终止相机 focus tween — 否则相机继续朝上一个 target 平移,
	# 在用户再次点击同一屏幕位置时,世界点已经移走,选不中。
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = null
	_update_hud()


func _move_selected(delta: Vector3) -> bool:
	if _selected_kind == "station" and _selected_station_idx >= 0:
		var st: Node3D = _stations[_selected_station_idx]
		# 重新贴地形 Y
		var new_pos := st.position + delta
		if _world != null and _world.has_method("_get_terrain_height"):
			new_pos.y = _world._get_terrain_height(new_pos.x, new_pos.z) + 0.05
		st.position = new_pos
		_selection_marker.global_position = st.position + Vector3(0, 2.5, 0)
		_mark_dirty()
		_update_hud()
		return true
	elif _selected_kind == "plant" and _selected_plant_idx >= 0:
		var items: Array = _veg_builder.get_all_items()
		var item: Dictionary = items[_selected_plant_idx]
		var new_pos: Vector3 = item["pos"] + delta
		if _world != null and _world.has_method("_get_terrain_height"):
			new_pos.y = _world._get_terrain_height(new_pos.x, new_pos.z)
		item["pos"] = new_pos
		_apply_plant_transform_change(item)
		_selection_marker.global_position = new_pos + Vector3(0, 1.0, 0)
		_mark_dirty()
		_update_hud()
		return true
	return false


func _rotate_selected(delta_deg: float) -> bool:
	if _selected_kind == "station" and _selected_station_idx >= 0:
		var st: Node3D = _stations[_selected_station_idx]
		var cur: float = st.get_meta("rot_y_override", 0.0) if st.has_meta("rot_y_override") else 0.0
		var nxt := fmod(cur + delta_deg + 1800.0, 360.0)
		if nxt < 0.0:
			nxt += 360.0
		st.set_meta("rot_y_override", nxt)
		# 立即应用:旋转 GLB 模型(若已加载)
		for child in st.get_children():
			if child is Node3D and child.name != "StationNameLabel":
				child.rotation.y = deg_to_rad(nxt)
		_mark_dirty()
		_update_hud()
		return true
	elif _selected_kind == "plant" and _selected_plant_idx >= 0:
		var items: Array = _veg_builder.get_all_items()
		var item: Dictionary = items[_selected_plant_idx]
		var cur: float = item["rot_y_deg"]
		var nxt := fmod(cur + delta_deg + 1800.0, 360.0)
		if nxt < 0.0:
			nxt += 360.0
		item["rot_y_deg"] = nxt
		_apply_plant_transform_change(item)
		_mark_dirty()
		_update_hud()
		return true
	return false


func _scale_selected(factor: float) -> bool:
	if _selected_kind != "plant" or _selected_plant_idx < 0:
		return false
	var items: Array = _veg_builder.get_all_items()
	var item: Dictionary = items[_selected_plant_idx]
	var nxt: float = clampf(item["scale"] * factor, MIN_SCALE, MAX_SCALE)
	item["scale"] = nxt
	_apply_plant_transform_change(item)
	var mat = _selection_marker
	mat.scale = Vector3(maxf(nxt, 1.0), maxf(nxt, 1.0), maxf(nxt, 1.0))
	_mark_dirty()
	_update_hud()
	return true


func _reset_selected() -> void:
	# 重置后立刻退出选中,避免"对象已选中 → 用户点击同一对象 → toggle 取消"
	# 让用户能直接再次点选(而不是必须连点两次才"再选中")。
	if _selected_kind == "station" and _selected_station_idx >= 0:
		var st: Node3D = _stations[_selected_station_idx]
		st.position = _selected_origin["pos"]
		if st.has_meta("rot_y_override"):
			st.remove_meta("rot_y_override")
		for child in st.get_children():
			if child is Node3D and child.name != "StationNameLabel":
				child.rotation.y = 0.0
		_mark_dirty()
	elif _selected_kind == "plant" and _selected_plant_idx >= 0:
		var items: Array = _veg_builder.get_all_items()
		var item: Dictionary = items[_selected_plant_idx]
		item["pos"] = _selected_origin["pos"]
		item["rot_y_deg"] = _selected_origin["rot_y_deg"]
		item["scale"] = _selected_origin["scale"]
		_apply_plant_transform_change(item)
		_mark_dirty()
	_clear_selection()


## 植物修改后同步到 MultiMesh 实例
func _apply_plant_transform_change(item: Dictionary) -> void:
	var pdata = item["_pdata"]
	var chunk_idx: int = item["_chunk"]
	var inner: Dictionary = item["_item"]
	inner["pos"] = item["pos"]
	inner["scale"] = item["scale"]
	inner["basis"] = Basis().rotated(Vector3.UP, deg_to_rad(item["rot_y_deg"]))
	# 重新写 MultiMesh transform
	var mmis: Array = pdata["mmis"][chunk_idx]
	if mmis.is_empty():
		return
	# 通过 _chunks_plants[].mmis[chunk] 反查 MultiMesh 索引 -> 直接重写所有 mmi 的所有 instance
	# 简化:让 VegBuilder 重写整个 chunk 的 transform
	if _veg_builder != null and _veg_builder.has_method("rewrite_chunk_transforms"):
		_veg_builder.rewrite_chunk_transforms(pdata["name"], chunk_idx)


func _mark_dirty() -> void:
	_dirty = true
	if _hud != null and _hud.has_method("set_dirty"):
		_hud.set_dirty(true)


func save_layout() -> void:
	# 把当前 stations / plants 写回 JSON
	var stations_out := []
	for i in range(_stations.size()):
		var st: Node3D = _stations[i]
		stations_out.append({
			"idx": i,
			"pos": st.position,
			"rot_y_deg": st.get_meta("rot_y_override", 0.0) if st.has_meta("rot_y_override") else 0.0,
		})
	var plants_out := []
	if _veg_builder != null and _veg_builder.has_method("get_all_items"):
		var items: Array = _veg_builder.get_all_items()
		for it in items:
			plants_out.append({
				"type": it["type"],
				"pos": it["pos"],
				"rot_y_deg": it["rot_y_deg"],
				"scale": it["scale"],
				"seg_idx": it["seg_idx"],
			})
	var err := LayoutData.save(stations_out, plants_out)
	if err != OK:
		push_warning("LayoutEditor: 保存失败 err=%s" % err)
	_dirty = false
	if _hud != null:
		if _hud.has_method("set_dirty"):
			_hud.set_dirty(false)
		if _hud.has_method("set_status"):
			_hud.set_status("已保存 res://layout.json" if err == OK else "保存失败 err=%s" % err)


func _exit_to_gift_box() -> void:
	# 有未保存改动时弹个确认;无改动直接退出
	if _dirty:
		# 简化:直接退出并打印提示
		push_warning("LayoutEditor: 退出编辑模式,有未保存改动")
	GameManager.go_to_gift_box()


## --- 对外公开方法(HUD 调用) ---

## 自由相机的世界坐标。草皮靠它定中心：编辑模式玩家被钉在出生点，
## 跟着玩家铺草会让整张可见地图都是光秃的。
func get_camera_position() -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	return _camera.global_position


func get_stations_snapshot() -> Array:
	return _stations_snapshot


func get_plants_snapshot() -> Array:
	return _plants_snapshot


func get_station_name(idx: int) -> String:
	return _station_name(idx)


func exit_to_gift_box() -> void:
	_exit_to_gift_box()


func reset_selected() -> void:
	_reset_selected()


func deselect() -> void:
	_clear_selection()


func select_from_hud(sel: Dictionary) -> void:
	_select(sel)


func _update_hud() -> void:
	if _hud == null:
		return
	if _hud.has_method("set_selection_info"):
		var info := {}
		if _selected_kind == "station" and _selected_station_idx >= 0:
			var st: Node3D = _stations[_selected_station_idx]
			info = {
				"kind": "station",
				"label": "驿站 #%d %s" % [_selected_station_idx + 1, _station_name(_selected_station_idx)],
				"pos": st.position,
				"rot_y_deg": st.get_meta("rot_y_override", 0.0) if st.has_meta("rot_y_override") else 0.0,
				"scale": 1.0,
			}
		elif _selected_kind == "plant" and _selected_plant_idx >= 0:
			var items: Array = _veg_builder.get_all_items()
			var item: Dictionary = items[_selected_plant_idx]
			info = {
				"kind": "plant",
				"label": "%s #%d" % [item["type"], _selected_plant_idx],
				"pos": item["pos"],
				"rot_y_deg": item["rot_y_deg"],
				"scale": item["scale"],
			}
		else:
			info = {"kind": "", "label": "(未选中)", "pos": Vector3.ZERO, "rot_y_deg": 0.0, "scale": 1.0}
		_hud.set_selection_info(info)
	# 同步侧栏列表选中项(世界点击 → 列表滚动高亮;列表点击 → 列表高亮自洽)
	if _hud.has_method("set_selected_list_item"):
		var list_idx: int = -1
		if _selected_kind == "station":
			list_idx = _selected_station_idx
		elif _selected_kind == "plant":
			list_idx = _selected_plant_idx
		_hud.set_selected_list_item(_selected_kind, list_idx)
	if _hud.has_method("set_dirty"):
		_hud.set_dirty(_dirty)


func _station_name(idx: int) -> String:
	if _road_builder == null:
		return ""
	var rd = _road_builder.get_road_data()
	if rd == null or idx < 0 or idx >= rd.stations.size():
		return ""
	var s = rd.stations[idx]
	return s.get("name_en", s.get("name", "")) if Localization.is_english() else s.get("name", "")