extends Node3D
## World3D — 3D骑行主场景

var _terrain_builder: Node3D
var _road_builder: Node3D
var _player: CharacterBody3D
var _stations: Array[Node3D] = []
var _check_in_in_progress = false
var _all_done = false
## 打卡/小游戏刚结束后的输入静默期（秒）。
## 竹子等小游戏就是"按空格"玩的，序列一结束玩家手上往往还在按空格——
## 而空格同时是全局 "interact" 动作，不加静默期的话下一次空格会
## 立刻再触发一次驿站打卡（相机重新飞过去、小游戏又开一轮）。
var _interact_cooldown: float = 0.0
const INTERACT_COOLDOWN_SEC := 1.0
## 上一次打卡结束时玩家所在的世界坐标。
## 只靠上面的静默期挡不住连按空格——玩家按完竹子小游戏还在连按，
## 冷却一过那次按键照样触发新一轮打卡。所以再加一条确定性规则：
## 打卡后必须"骑出一段距离"才允许再次打卡。
##
## 判定用的是"曾经骑开过"这个闩锁，不是"此刻离得有多远"：
## 旧版每帧重新比距离，玩家绕一圈骑回驿站、停在和刚才同一个点时
## 距离又变回 0，于是这个驿站再也点不动——表现就是"失败后再也不能交互"。
## 闩锁一旦打开就一直保持，直到下一次打卡结束才重新上锁。
var _last_check_in_pos := Vector3(INF, INF, INF)
const RECHECK_IN_MIN_DIST := 8.0
var _recheck_armed: bool = true
var _bike_rear_wheel: Node3D
var _bike_front_wheel: Node3D
var _bike_model: Node3D
const BIKE_SCALE := 0.012
var _wheel_base_rot_rear: float = 0.0
var _wheel_base_rot_front: float = 0.0
const WHEEL_RADIUS := 0.34
var _has_last_pos := false
var _last_global_pos := Vector3.ZERO
var _wheel_angle := 0.0
const FRONT_Z = -0.55
const REAR_Z = 0.55
const FA_X = 0.40
const RA_X = -0.50
const WY = 0.34
var _nearby_station_idx: int = -1
var _nearby_station_dist: float = 999.0
var _nearby_shop_idx: int = -1
var _nearby_shop_dist: float = 999.0
var _shop_open: bool = false
var _shop_panel: Control = null
## 站号 -> 此刻是否在 PASS_RADIUS 内。路过话只在"进圈"那一帧冒一次，
## 停在里面不动不会每秒重弹一次。
var _pass_inside: Dictionary = {}
## 反派场次已武装（1-based，与 GameManager.seen_villain 对齐）。
## 里程只增不减，所以按阈值一次性武装就够了，不用每帧重扫里程。
var _villain_armed: Array = []
var _villain_playing := false
const STATION_PASS_RADIUS := 15.0
## 五件乐事怎么轮着上。preload 而不是 class_name —— `--script` 模式下
## class_name 会拉编译期依赖（见 CLAUDE.md 已知陷阱）。
const MiniGamePicker = preload("res://scripts/mini_games/MiniGamePicker.gd")
var _cam_look_at_target: Vector3 = Vector3.ZERO
var _cam_look_at_active: bool = false
var _paused: bool = false
var _total_arclen: float = 1.0
var _odometer_units: float = 0.0
## 远景山线与昼夜切换。环路只有 1228.8m、满速一圈 82 秒，不换天色的话一趟
## 十分钟就是七遍同一片地 —— 详见 DayCycle.gd。
var _ridge: FarRidge = null
var _day_cycle: Node3D = null
var _road_points_2d: PackedVector2Array = []
var _boundary_intensity: float = 0.0
var _station_mesh_pending: Array = []
var _station_load_timer: float = 0.0
var _last_check_in_idx: int = -1
## 打卡弹窗当前装的是哪一套文案。失败面板和驿站正文要分开，
## 否则 _apply_language 切语言时会把"未完成"提示刷成驿站介绍。
const POPUP_NONE := 0
const POPUP_STATION := 1
const POPUP_FAILED := 2
var _popup_mode: int = POPUP_NONE
## Headless 模式下跳过对话弹窗（无人点击按钮），避免 await 永久挂起
var _headless_mode: bool = false
## Headless 模式下跳过对话弹窗（无人点击按钮），避免 await 永久挂起
var _dialogue_watched: Array[int] = []
var _layout_data: Dictionary = {}
## LayoutEditor 实例（仅编辑模式非空）。只为了拿到草皮的中心点。
var _editor: Node3D = null
const STATION_LOAD_DISTANCE := 300.0
const STATION_LOAD_INTERVAL := 0.5

const SOFT_BOUND := 12.0
const HARD_BOUND := 25.0
const PUSH_STRENGTH := 12.0
const PUSH_INCREASE := 1.5

const STATION_GLB_CONFIG: Array = [
	{"path": "res://assets/models/station_0.glb", "scale": 10.0, "label_y": 12.0, "glow_y": 8.0, "glow_range": 12.0},
	{"path": "res://assets/models/station_1.glb", "scale": 10.0, "label_y": 10.0, "glow_y": 7.0, "glow_range": 10.0},
	{"path": "res://assets/models/station_2.glb", "scale": 10.0, "label_y": 14.0, "glow_y": 10.0, "glow_range": 15.0, "rot_y": 180.0},
	{"path": "res://assets/models/station_3.glb", "scale": 10.0, "label_y": 10.0, "glow_y": 7.0, "glow_range": 10.0, "rot_y": 180.0},
	{"path": "res://assets/models/station_4.glb", "scale": 10.0, "label_y": 11.0, "glow_y": 8.0, "glow_range": 12.0, "rot_y": -120.0},
	{"path": "res://assets/models/tree.glb", "scale": 8.0, "label_y": 14.0, "glow_y": 10.0, "glow_range": 12.0, "rot_y": 0.0},
	# 6..12：程序化设计的 7 个新驿站建筑（驿楼 / 茶寮 / 岭台 / 神苑 / 凉亭 / 廊 / 亭灯）
	# 全部由 Blender 5.2.2 手工建模并 GLB 导出，尺寸按米、Y 轴向上，与 station_0..4 同坐标系
	{"path": "res://assets/models/station_驿楼.glb", "scale": 10.0, "label_y": 11.0, "glow_y": 7.0, "glow_range": 14.0},
	{"path": "res://assets/models/station_茶寮.glb", "scale": 10.0, "label_y": 10.0, "glow_y": 7.0, "glow_range": 12.0},
	{"path": "res://assets/models/station_岭台.glb", "scale": 10.0, "label_y": 12.0, "glow_y": 8.0, "glow_range": 14.0},
	{"path": "res://assets/models/station_神苑.glb", "scale": 10.0, "label_y": 9.0, "glow_y": 6.0, "glow_range": 10.0},
	{"path": "res://assets/models/station_凉亭.glb", "scale": 12.0, "label_y": 8.0, "glow_y": 5.0, "glow_range": 10.0},
	{"path": "res://assets/models/station_廊.glb", "scale": 10.0, "label_y": 8.0, "glow_y": 5.0, "glow_range": 10.0},
	{"path": "res://assets/models/station_亭灯.glb", "scale": 14.0, "label_y": 10.0, "glow_y": 6.0, "glow_range": 10.0},
]

## 屋顶的暖中性色。口径和 glTF 的 baseColorFactor 一致（也就是当初在 Blender 里
## 填的那几个数），不是 Godot 的 albedo_color —— 见 _tint_station_roofs() 里那道
## linear_to_srgb。
##
## 7 个手工模型原本共用同一种青瓦 (0.14,0.15,0.19)，是整个暖色调里唯一一块冷灰：
## 太阳照上去亮面渲到 0.72 那一档的白蓝，糊在奶油色墙面上像贴了片别人的屋顶。
## 换成深暖灰——不抢朱红门、不跟木色墙打架，只把冷色拿掉，让屋顶重新读成
## "压住房子的那一片"。
##
## 贴图模型 (station_0..4) 的屋顶烤在 basecolor 里、没有独立材质，天然匹配不上，
## 不会被动 —— 5 个模型一个整片材质的差别是照片，运行时乘色只会把它压平。
const STATION_ROOF_TINT := {
	"roof": Color(0.175, 0.150, 0.115),
	"roof_2": Color(0.245, 0.215, 0.170),
}

@onready var _check_in_popup: Control = $HUDLayer/CheckInPopup
@onready var _popup_name: Label = $HUDLayer/CheckInPopup/Panel/VBox/NameLabel
@onready var _popup_event: Label = $HUDLayer/CheckInPopup/Panel/VBox/EventLabel
@onready var _popup_text: Label = $HUDLayer/CheckInPopup/Panel/VBox/TextLabel
@onready var _popup_fragment: Label = $HUDLayer/CheckInPopup/Panel/VBox/FragmentLabel
@onready var _collecting_label: Label = $HUDLayer/CollectingLabel
@onready var _joystick: Control = $JoystickLayer/VirtualJoystick
@onready var _minimap: Control = $HUDLayer/MiniMap
@onready var _check_in_prompt: Control = $HUDLayer/CheckInPrompt
@onready var _fragment_bar: Control = $FragmentBarLayer/FragmentBar
@onready var _player_cam: Camera3D = $Player3D/Camera3D
@onready var _pause_panel: Control = $PausePanel
@onready var _env_audio: Node3D = $EnvironmentAudio
@onready var _veg_builder: Node3D = $VegBuilder
@onready var _grass_scatter: Node3D = $GrassScatter
@onready var _tree_scatter: Node3D = $TreeScatter
@onready var _hud3d: Control = $HUD3D
@onready var _onboarding: Control = $OnboardingGuide
@onready var _mini_game_layer: CanvasLayer = $MiniGameLayer
@onready var _dialogue_popup: Control = $HUDLayer/DialoguePopup


func _ready() -> void:
	_headless_mode = GameManager.headless_mode
	GameManager.set_state(GameManager.State.ROAMING)
	AudioManager.play_bgm()

	_terrain_builder = $TerrainBuilder
	_road_builder = $RoadBuilder
	_road_builder.set_terrain_builder(_terrain_builder)
	_player = $Player3D
	var road_data = _road_builder.get_road_data()
	_player.look_at(road_data.points[6])
	_minimap.setup(road_data, _player)
	_hud3d.setup(road_data, _player)
	for p in road_data.points:
		_road_points_2d.append(Vector2(p.x, p.z))

	_check_in_popup.visible = false
	_collecting_label.visible = false
	_pause_panel.visible = false
	_popup_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_popup_event.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_popup_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_popup_fragment.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_popup_name.add_theme_font_size_override("font_size", _popup_font_size(32, 28))
	_popup_event.add_theme_font_size_override("font_size", _popup_font_size(20, 18))
	_popup_text.add_theme_font_size_override("font_size", _popup_font_size(18, 16))
	_popup_fragment.add_theme_font_size_override("font_size", _popup_font_size(22, 20))

	# 启动时统一读一次 layout.json,stations 和 plants 都从这里取覆盖
	_layout_data = LayoutData.load()

	_setup_stations()
	_build_bike()
	_init_progress_arclen()
	_ridge = FarRidge.new()
	_ridge.name = "FarRidge"
	add_child(_ridge)
	_setup_day_cycle()

	GameManager.all_fragments_collected.connect(_on_all_collected)
	GameManager.all_fragments_maxed_reached.connect(_on_all_maxed)
	Localization.language_changed.connect(_apply_language)
	_joystick.joystick_input.connect(_on_joystick_input)
	_check_in_prompt.setup(self)
	_check_in_prompt.check_in_pressed.connect(_on_check_in_pressed)
	_setup_shop()

	if _env_audio != null:
		var station_positions: Array = []
		for st in _stations:
			station_positions.append(st.position)
		_env_audio.setup(station_positions)
		_env_audio.set_player(_player)

	if _veg_builder != null:
		var plant_overrides := {}
		if not _layout_data.is_empty():
			plant_overrides = LayoutData.get_plant_overrides_by_type(_layout_data)
		_veg_builder.setup(_road_builder.get_road_data().points, _terrain_builder, _player,
			_road_builder.get_all_centerlines(), _station_protection_positions(), plant_overrides)

	if _grass_scatter != null:
		# 用全部驿站，不是 _station_protection_positions()：那个只给 7/10 两个
		# （灌木要为亭子让视线），草要避开每一个驿站的铺装地面。
		var all_station_pos: Array = []
		for st in _stations:
			all_station_pos.append(st.position)
		_grass_scatter.setup(_terrain_builder, _road_builder.get_all_centerlines(),
			all_station_pos)

	if _tree_scatter != null:
		# 行道树和草皮用同一份中心线与同一份驿站净空：树脚下就是草，
		# 两者让位判据不一致的话会出现"树长在草让开的空地中间"。
		var tree_protect: Array = []
		for st in _stations:
			tree_protect.append(st.position)
		_tree_scatter.setup(_terrain_builder, _road_builder.get_all_centerlines(),
			tree_protect)

	_setup_onboarding()

	# 按已播到的场次武装反派对白：armed 的含义是「还没播过」，
	# 即 i > seen_villain（seen_villain 是 1-based 的已播场次）。
	# 编辑模式也建：_try_villain_scene() 按序号取，空数组会踩 OOB。
	for i in range(1, GameManager.VILLAIN_SCENE_COUNT + 1):
		_villain_armed.append(i > GameManager.seen_villain)

	# 编辑模式入口(必须放在所有 setup 完成后,LayoutEditor 需要 stations 和 plants 列表)
	if GameManager.is_editor_mode():
		_setup_editor()
	# 序章压在 Onboarding 之后播，不叠屏。不 await：_ready() 不能挂起。
	elif not GameManager.prologue_done:
		_play_prologue()


func _setup_onboarding() -> void:
	if GameManager.onboarding_shown:
		_onboarding.visible = false
		return
	_player.set_can_move(false)
	_onboarding.dismissed.connect(_on_onboarding_dismissed)


## 编辑模式入口:禁用玩家移动 + 暂停默认 UI + 实例化 LayoutEditor / EditorHUD
func _setup_editor() -> void:
	# 屏蔽正常的玩家玩法与教程
	_player.set_can_move(false)
	_player.set_camera_locked(true)
	_onboarding.visible = false
	if _pause_panel:
		_pause_panel.visible = false
	_paused = false  # 编辑器自身控制暂停逻辑,不要让游戏暂停
	# 实例化编辑器节点
	var editor := Node3D.new()
	_editor = editor
	editor.name = "LayoutEditor"
	editor.set_script(load("res://scripts/LayoutEditor.gd"))
	add_child(editor)
	editor.setup(self, _stations, _veg_builder, _road_builder)
	# 编辑相机在 100m 高空俯视，而淡出带量的是"到相机的距离"，
	# 100m 起步就超过游戏里的 fade_end 了，整圈草会全淡成 0、整片树会被
	# visibility_range 判在范围外直接消失。真正的修法在
	# _stream_focus_pos()：那里每帧按当前相机位置调 set_fade_for_camera。
	# HUD:作为独立 CanvasLayer 的子节点
	var editor_layer := CanvasLayer.new()
	editor_layer.name = "EditorLayer"
	add_child(editor_layer)
	var hud_scene: PackedScene = load("res://scenes/EditorHUD.tscn")
	if hud_scene != null:
		var hud: Control = hud_scene.instantiate()
		editor_layer.add_child(hud)
		editor.bind_hud(hud)
	# 编辑模式下隐藏默认 HUD 层(按钮、进度等),只留主世界 + 编辑器覆盖层
	_hud3d.visible = false
	_joystick.visible = false
	_minimap.visible = false
	_check_in_prompt.visible = false


## 流式焦点（草皮与行道树共用）。编辑模式跟 LayoutEditor 的自由相机——编辑模式
## 玩家被钉在出生点，跟着玩家铺草/铺树会让整张可见地图都是光秃的；正常游戏跟玩家。
func _stream_focus_pos() -> Vector3:
	if _editor != null and _editor.has_method("get_camera_position"):
		var cam: Vector3 = _editor.get_camera_position()
		var flat := Vector3(cam.x, 0.0, cam.z)
		# 俯视相机离地 100m，而草/树的淡出带量的是"到相机的距离"，不外扩的话
		# 整圈草会判成 fade=0、整片树会判在 range 之外直接消失。
		# 相机每帧都在动，所以这里也得每帧重算。
		_grass_scatter.set_focus(flat)
		_grass_scatter.set_fade_for_camera(cam)
		if _tree_scatter != null:
			_tree_scatter.set_focus(flat)
			_tree_scatter.set_fade_for_camera(cam)
		return Vector3(cam.x, _terrain_builder.get_height_at(cam.x, cam.z), cam.z)
	return _player.global_position


func _station_protection_positions() -> Array:
	# 节点 8 云影台(idx 7) + 节点 11 茶烟小筑(idx 10) 需要清灌木
	var positions: Array = []
	if _stations.size() > 10:
		positions.append(_stations[7].position)
		positions.append(_stations[10].position)
	return positions


func _station_name(idx: int) -> String:
	var station = _road_builder.get_road_data().stations[idx]
	return station.get("name_en", station.get("name", "")) if Localization.is_english() else station.get("name", "")


func _station_event(idx: int) -> String:
	var station = _road_builder.get_road_data().stations[idx]
	return station.get("event_en", station.get("event", "")) if Localization.is_english() else station.get("event", "")


func _station_text(idx: int) -> String:
	var station = _road_builder.get_road_data().stations[idx]
	return station.get("text_en", station.get("text", "")) if Localization.is_english() else station.get("text", "")


func _station_fragment(idx: int) -> String:
	var station = _road_builder.get_road_data().stations[idx]
	return station.get("fragment_en", station.get("fragment", "")) if Localization.is_english() else station.get("fragment", "")


## 把 fragment 名字映射到 0..4 的 slot idx,用于 FragmentFlying 与 FragmentBar。
## 返回 -1 表示没匹配。中英文都要认:_station_fragment 在英文界面下返回的是
## fragment_en,只认中文的话英文界面每张碎片都收不到飞行动画。
func _fragment_slot_idx(frag_name: String) -> int:
	const FRAGMENT_ORDER_ZH := ["云", "茶", "琴", "竹", "禽"]
	const FRAGMENT_ORDER_EN := ["Cloud", "Tea", "Music", "Bamboo", "Bird"]
	var i := FRAGMENT_ORDER_ZH.find(frag_name)
	return i if i >= 0 else FRAGMENT_ORDER_EN.find(frag_name)


func _get_terrain_height(wx: float, wz: float) -> float:
	if _terrain_builder and _terrain_builder.has_method("get_height_at"):
		return _terrain_builder.get_height_at(wx, wz)
	return 0.0


func _init_progress_arclen() -> void:
	_total_arclen = _road_builder.get_road_data().total_arclength()


## 昼夜切换的接线。灯和 Environment 都是 World3D.tscn 里的既有节点，
## DayCycle 只是按里程去改它们 —— 不新建场景，所以导出/存档都不受影响。
func _setup_day_cycle() -> void:
	_day_cycle = load("res://scripts/DayCycle.gd").new()
	_day_cycle.name = "DayCycle"
	add_child(_day_cycle)
	_day_cycle.setup(
		get_node_or_null("DirectionalLight3D") as DirectionalLight3D,
		get_node_or_null("FillLight3D") as DirectionalLight3D,
		get_node_or_null("WorldEnvironment") as WorldEnvironment,
		_ridge)
	_day_cycle.dusk_began.connect(_on_dusk_began)


func _on_dusk_began() -> void:
	# 不说话的话玩家只会以为显卡掉了。走驿站路过那一行（同一条浮出/收走的通道），
	# 免得再造一套一次性提示。
	if _hud3d != null:
		_hud3d.show_pass_line(Localization.t("dusk_began"))


func _setup_stations() -> void:
	var road_data = _road_builder.get_road_data()
	var station_count = road_data.stations.size()

	for i in range(station_count):
		var st = Node3D.new()
		st.name = "Station%d" % (i + 1)

		var pos = road_data.get_station_world_pos(i)
		var ground_y = _get_terrain_height(pos.x, pos.z)
		pos.y = ground_y
		# 应用 layout.json 中的位置 / 旋转覆盖(若有)
		var override: Dictionary = LayoutData.get_station_override(_layout_data, i)
		if not override.is_empty():
			if override.has("pos"):
				var ov_pos: Vector3 = override["pos"]
				# 重新贴地形 Y,避免 layout 与运行时地形变化时位置悬空
				ov_pos.y = _get_terrain_height(ov_pos.x, ov_pos.z)
				pos = ov_pos
			if override.has("rot_y_deg"):
				st.set_meta("rot_y_override", float(override["rot_y_deg"]))
		st.position = pos
		add_child(st)
		_stations.append(st)

		var has_fragment = road_data.station_has_fragment(i)
		var col: Color = road_data.stations[i]["color"]
		var name = _station_name(i)
		var model_idx = road_data.station_model_idx(i)

		if model_idx >= 0 and model_idx < STATION_GLB_CONFIG.size():
			# 只建 label + glow，GLB 模型走近时加载
			var cfg = STATION_GLB_CONFIG[model_idx]
			_add_label(st, name, cfg.get("label_y", 6.0), 48, has_fragment)
			_add_glow(st, col, Vector3(0, cfg.get("glow_y", 4.0), 0), 0.5, cfg.get("glow_range", 12.0))
			_station_mesh_pending.append({
				"st": st,
				"path": cfg.path,
				"cfg": cfg,
				"col": col,
				"name": name,
				"has_fragment": has_fragment,
			})
		else:
			_build_station_generic(st, col, name, has_fragment)


func _update_station_streaming(delta: float) -> void:
	if _station_mesh_pending.is_empty():
		return
	_station_load_timer += delta
	if _station_load_timer < STATION_LOAD_INTERVAL:
		return
	_station_load_timer = 0.0

	var to_load = []
	for entry in _station_mesh_pending:
		var d = _player.position.distance_to(entry.st.position)
		if d <= STATION_LOAD_DISTANCE:
			to_load.append({"entry": entry, "d": d})

	if to_load.is_empty():
		return
	to_load.sort_custom(func(a, b): return a.d < b.d)

	var entry = to_load[0].entry
	var path: String = entry.path
	if not ResourceLoader.exists(path):
		push_warning("Station GLB not found: " + path)
		_build_station_generic(entry.st, entry.col, entry.name, entry.has_fragment)
		_station_mesh_pending.erase(entry)
		return

	var scene: PackedScene = load(path)
	if scene == null:
		push_warning("Station GLB load failed: " + path)
		_build_station_generic(entry.st, entry.col, entry.name, entry.has_fragment)
		_station_mesh_pending.erase(entry)
		return

	var model = scene.instantiate()
	var scale = entry.cfg.get("scale", 1.0)
	model.scale = Vector3(scale, scale, scale)
	# rot_y 优先用 layout.json 里的 override,否则用 STATION_GLB_CONFIG 默认值
	var rot_y: float = entry.cfg.get("rot_y", 0.0)
	if entry.st.has_meta("rot_y_override"):
		rot_y = entry.st.get_meta("rot_y_override")
	model.rotation.y = deg_to_rad(rot_y)
	entry.st.add_child(model)
	_tint_station_roofs(model)
	# 兼容模式：静态场景 GLB 关闭阴影投射，避免与玩家阴影重叠产生残影
	_disable_translatable(model)
	var mi = _find_mesh_instance(model)
	if mi != null and mi.mesh != null:
		var aabb = mi.mesh.get_aabb()
		print("[World3D] Station GLB: " + path + " — AABB P=" + str(aabb.position) + " S=" + str(aabb.size) + " scale=" + str(scale))
	else:
		print("[World3D] WARNING: No mesh found in " + path)

	_station_mesh_pending.erase(entry)


## 只换屋顶材质，其余一律不碰。
##
## 手工模型的材质名是 "<站名>_roof" / "<站名>_roof_2"，7 个文件命名一致，所以按后缀
## 认就够；13 个模型各自的材质差别是资产本身，乘色压平就没了。材质必须 duplicate：
## GLB 导入出来的是缓存里的共享资源，直接改 albedo 会连带改掉别的站。
##
## STATION_ROOF_TINT 和 glTF 的 baseColorFactor 同一口径，Godot 导入后读到的却是
## linear_to_srgb(0.14) = 0.41，不是 0.14。少了这道转换的话填 0.175 会被
## srgb_to_linear 压到 0.026，比原来的墙暗 30 倍，背光那一面直接渲成纯黑——
## 屋顶成了个洞，比原来的冷灰更糟。
func _tint_station_roofs(model: Node) -> void:
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null:
				continue
			for suffix in STATION_ROOF_TINT:
				if not mat.resource_name.ends_with("_" + suffix):
					continue
				var dup := mat.duplicate() as StandardMaterial3D
				var c: Color = STATION_ROOF_TINT[suffix].linear_to_srgb()
				dup.albedo_color = Color(c.r, c.g, c.b, mat.albedo_color.a)
				mi.set_surface_override_material(s, dup)


func _build_station_generic(st: Node3D, col: Color, name: String, has_fragment: bool) -> void:
	var pole_h := 8.0 if has_fragment else 5.0
	if has_fragment:
		_add_glow_box(st, col, 3.0, 6.0, 3.0, 3.0)

	var pole = CSGCylinder3D.new()
	pole.radius = 0.15
	pole.height = pole_h
	pole.position = Vector3(0, pole_h * 0.5, 0)
	pole.material = _mat(Color(0.45, 0.38, 0.28))
	st.add_child(pole)

	var sign = CSGBox3D.new()
	sign.size = Vector3(2.5, 1.2, 0.15) if has_fragment else Vector3(1.8, 0.9, 0.1)
	sign.position = Vector3(0, pole_h + 0.6, 0)
	sign.material = _mat(Color(0.9, 0.9, 0.85))
	st.add_child(sign)

	_add_label(st, name, pole_h + 0.6, 48 if has_fragment else 32, has_fragment)

	if has_fragment:
		_add_glow(st, col, Vector3(0, pole_h + 1, 0), 0.5, 10.0)


func _add_glow_box(st: Node3D, col: Color, w: float, h: float, d: float, y: float) -> void:
	var b = CSGBox3D.new()
	b.size = Vector3(w, h, d)
	b.position = Vector3(0, y, 0)
	b.material = _mat_emissive(col, 0.3)
	st.add_child(b)


func _add_glow(st: Node3D, col: Color, pos: Vector3, energy: float, r: float) -> void:
	var g = OmniLight3D.new()
	g.light_color = col
	g.light_energy = energy
	g.omni_range = r
	g.position = pos
	st.add_child(g)


func _add_label(st: Node3D, text: String, y: float, fs: int, has_fragment: bool) -> void:
	var label = Label3D.new()
	label.name = "StationNameLabel"
	label.text = text
	label.font_size = fs
	label.position = Vector3(0, y, 0.1)
	label.modulate = Color(0.1, 0.1, 0.1, 1.0) if has_fragment else Color(0.4, 0.4, 0.4, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.002
	st.add_child(label)


func _mat(c: Color, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _mat_emissive(c: Color, strength: float = 0.3) -> StandardMaterial3D:
	var m = _mat(c)
	m.emission_enabled = true
	m.emission = c * strength
	return m


func _physics_process(_delta: float) -> void:
	if _paused:
		return
	# 心神雾的叙事脉冲：只在对白弹窗或结果面板亮着的时候冲上叙事档。
	# 判据直接读两个弹窗的真实可见性，不另设标志位——标志位一旦漏清就是
	# 玩家顶着 0.52 的雾跑完全程（这正是改动前的样子）。
	if _hud3d.has_method("set_mood_pulse"):
		_hud3d.set_mood_pulse(_dialogue_popup.visible or _check_in_popup.visible)
	if _interact_cooldown > 0.0:
		# 夹到 0：不再让它在整局里一路减成负无穷，调试时静默期数值才有意义
		_interact_cooldown = maxf(_interact_cooldown - _delta, 0.0)
	# 骑开闩锁：只要曾经骑离上次收尾点 RECHECK_IN_MIN_DIST 米，就一直允许再次打卡。
	# 放在所有门控之前结算——玩家骑到哪都要算，哪怕那一刻附近没有驿站。
	if not _recheck_armed \
			and _player.position.distance_to(_last_check_in_pos) > RECHECK_IN_MIN_DIST:
		_recheck_armed = true
	if _veg_builder != null:
		_veg_builder.tick(_delta)
	if _grass_scatter != null or _tree_scatter != null:
		# 心神系数只收「看得见的半径」：草是 shader 的两个 uniform，树是
		# visibility_range_end，都不碰驻留半径，所以每帧推一次是零流式成本。
		# 必须在这里推——set_fade_for_camera 只有编辑模式（俯视相机）会调，
		# 正常玩法下淡出带在 setup() 时写一次就不再更新。
		# 顺序很重要：要在 _stream_focus_pos() 之前推，否则它会用旧系数去算
		# 编辑模式的相机带。
		var vis := GameManager.get_visibility_factor()
		if _grass_scatter != null:
			_grass_scatter.set_visibility_factor(vis)
		if _tree_scatter != null:
			_tree_scatter.set_visibility_factor(vis)
		# 焦点只算一次：_stream_focus_pos() 在编辑模式下会顺手改两套流式的
		# 淡出带，算两遍是白跑（而且草和树必须拿到同一个焦点，否则会错位）。
		var stream_focus := _stream_focus_pos()
		if _grass_scatter != null:
			_grass_scatter.set_focus(stream_focus)
			_grass_scatter.tick(_delta)
		if _tree_scatter != null:
			_tree_scatter.set_focus(stream_focus)
			_tree_scatter.tick(_delta)
	_update_station_streaming(_delta)
	var terrain_y = _get_terrain_height(_player.position.x, _player.position.z)
	# 8 字交叉处两条 ribbon 在同一 2D 位置，
	# get_road_height_at_xy() 找最近中心线段会跳变；ribbon_height 用 max 天然连续
	var road_y = _road_builder.get_road_ribbon_height(_player.position.x, _player.position.z)
	if not is_finite(road_y):
		road_y = _road_builder.get_road_height_at_xy(_player.position.x, _player.position.z)
	var ground_y = terrain_y + 0.05
	if is_finite(road_y):
		ground_y = road_y + 0.05
	_player.position.y = ground_y

	# 1. 本帧位移（里程 + 轮子滚动共用，仅计前进量，不含边界回弹）
	var current_pos = _player.global_position
	var move_vec = current_pos - _last_global_pos if _has_last_pos else Vector3.ZERO
	if _has_last_pos and move_vec.length() > 0.001:
		_odometer_units += move_vec.length()
	if _total_arclen > 1.0:
		var km := minf(_odometer_units / _total_arclen * GameManager.TOTAL_ROUTE_KM, GameManager.TOTAL_ROUTE_KM)
		GameManager.set_progress_km(km)
		GameManager.earn_km(km)
		# 骑满两圈之后天色转成黄昏。里程表是按前进量累的，所以绕 8 字交叉点
		# 或者回头路都照算，不靠"我在第几个点上"这种会漂的判据。
		if _day_cycle != null:
			_day_cycle.set_laps(_odometer_units / _total_arclen, _delta)

	# 2. 软边界回弹（F-07）
	_apply_boundary_force(_delta)

	# 3. 更新 _last_global_pos（在回弹后，确保下帧 move_vec 只含前进量）
	_last_global_pos = _player.global_position
	_has_last_pos = true

	# 用前进分量推算轮子滚动角度（前进/后退都会滚，停止不滚）
	var delta_angle := 0.0
	var forward_dir = -_player.global_transform.basis.z.normalized()
	var forward_dist = move_vec.dot(forward_dir)
	if abs(forward_dist) > 0.0001:
		delta_angle = forward_dist / WHEEL_RADIUS
	if abs(delta_angle) > 0.00001:
		_wheel_angle = fmod(_wheel_angle + delta_angle, TAU)

	if _bike_rear_wheel is CSGCylinder3D or _bike_front_wheel is CSGCylinder3D:
		# 程序化车轮：global_transform（CSG cylinder 需 Z=90° 对齐车轴）
		var player_pos = _player.global_position
		var player_basis = _player.global_transform.basis
		var oriented = (
			player_basis
			* Basis().rotated(Vector3(1, 0, 0), _wheel_angle)
			* Basis().rotated(Vector3(0, 0, 1), PI * 0.5)
		)
		var rear_off = player_basis.x * RA_X + player_basis.y * WY + player_basis.z * REAR_Z
		var front_off = player_basis.x * FA_X + player_basis.y * WY + player_basis.z * FRONT_Z
		if _bike_rear_wheel:
			_bike_rear_wheel.global_transform = Transform3D(oriented, player_pos + rear_off)
		if _bike_front_wheel:
			_bike_front_wheel.global_transform = Transform3D(oriented, player_pos + front_off)
	else:
		# GLB 车轮：局部绕 X 轴旋转（保留模型原有朝向）
		if _bike_rear_wheel:
			_bike_rear_wheel.rotation.x = _wheel_angle + _wheel_base_rot_rear
		if _bike_front_wheel:
			_bike_front_wheel.rotation.x = _wheel_angle + _wheel_base_rot_front

	if _cam_look_at_active and _player_cam:
		_player_cam.look_at(_cam_look_at_target, Vector3.UP)

	# 打卡流程 / 小游戏进行中一律不响应 interact。
	# 小游戏的按键不会被 set_input_as_handled() 从 Input 单例里抹掉，
	# 所以这里除了 _check_in_in_progress 还要显式挡一次小游戏运行态。
	#
	# 郑铎戏也在这张单子里：它和打卡是同一类状态（一段接管了空格的过场），
	# 而这一格原来漏了它，于是脚下的圈照画 —— 圈上写着「空格 · 完成乐事」，
	# 玩家按下去推进的却是对白，`_on_interact_blocked()` 还顺手把圈变灰成
	# 「这里现在进不去」。同一个键在同一帧里干了两件互相拆台的事，
	# 而圈和那句话一起把玩家指向一个这一趟按不出来的交互。
	# 清成 -1 就一起收掉：`_prompt_target()` 返回空（圈不画），
	# `_interact_blocked_reason()` 也跟着返回空串（不冒那句话）。
	if _check_in_in_progress or _all_done or _mini_game_state == MG_RUNNING \
			or _villain_playing:
		_nearby_station_idx = -1
		_nearby_shop_idx = -1
		return

	var road_data = _road_builder.get_road_data()
	var station_count = road_data.stations.size()
	var best_idx = -1
	var best_dist = 999.0
	var best_shop_idx = -1
	var best_shop_dist = 999.0
	for i in range(station_count):
		# 路过 +3 对所有驿站都发 —— 铺子和普通驿站一样能换旅币。
		# 必须写在 fragment 的 continue 之前，否则铺子永远拿不到这笔钱。
		var d = _player.position.distance_to(_stations[i].position)
		if d <= STATION_PASS_RADIUS:
			GameManager.on_station_pass(i)
			# 非碎片驿（11 座风景站 + 3 家铺子）路过时浮一句它自己那行 text。
			# 这些文案一直写在 road_data 里，但原来只有打卡弹窗读得到 ——
			# 而非碎片站根本不能打卡，于是 16 站里有 11 站的文字玩家一次也读不到。
			# 只在进圈那一帧发，靠 _pass_inside 边沿触发。
			if not road_data.station_has_fragment(i) and not _pass_inside.get(i, false):
				var line := _station_text(i)
				if line != "" and _hud3d != null and _hud3d.has_method("show_pass_line"):
					_hud3d.show_pass_line(line)
		_pass_inside[i] = d <= STATION_PASS_RADIUS
		var shop_name: String = ShopData.shop_at_station(i)
		if shop_name != "" and d < best_shop_dist:
			best_shop_dist = d
			best_shop_idx = i
		if not road_data.station_has_fragment(i):
			continue
		# 已达最大打卡次数的驿站不再出现提示
		if GameManager.is_station_exhausted(i):
			continue
		if d < best_dist:
			best_dist = d
			best_idx = i
	_nearby_station_idx = best_idx if best_dist < STATION_PASS_RADIUS else -1
	_nearby_station_dist = best_dist
	_nearby_shop_idx = best_shop_idx if best_shop_dist < STATION_PASS_RADIUS else -1
	_nearby_shop_dist = best_shop_dist

	# 面板开着却骑出了铺子范围就自动收摊，不然玩家被困在面板上。
	if _shop_open and _nearby_shop_idx < 0:
		_close_shop()

	# 两道门（静默期 + 必须骑开）统一收在 _can_start_check_in 里：
	# 静默期挡住收尾那一刻还在按的那次，骑开门保证连按空格不会链式触发新一轮。
	# 碎片驿站优先：两套驿站集合互不相交，elif 只是防御。
	if Input.is_action_just_pressed("interact"):
		if _can_start_check_in(_nearby_station_idx):
			_do_check_in(_nearby_station_idx)
		elif _can_open_shop(_nearby_shop_idx):
			_open_shop(_nearby_shop_idx)
		else:
			_on_interact_blocked()

	_try_villain_scene()


func _apply_boundary_force(delta: float) -> void:
	if _road_points_2d.is_empty():
		return
	var pp = Vector2(_player.position.x, _player.position.z)
	var nearest = Vector2.ZERO
	var nearest_dist = 9999.0
	for rp in _road_points_2d:
		var d = pp.distance_to(rp)
		if d < nearest_dist:
			nearest_dist = d
			nearest = rp
	if nearest_dist <= SOFT_BOUND + 0.001:
		_boundary_intensity = 0.0
		if _hud3d != null and _hud3d.has_method("set_boundary_intensity"):
			_hud3d.set_boundary_intensity(0.0)
		return
	var dir = (pp - nearest).normalized()
	var over = nearest_dist - SOFT_BOUND
	var push = PUSH_STRENGTH * clampf(over / (HARD_BOUND - SOFT_BOUND), 0.0, 1.0) + maxf(over - (HARD_BOUND - SOFT_BOUND), 0.0) * PUSH_INCREASE
	_player.position.x -= dir.x * push * delta
	_player.position.z -= dir.y * push * delta
	_boundary_intensity = clampf(over / (HARD_BOUND - SOFT_BOUND), 0.0, 1.0)
	if _hud3d != null and _hud3d.has_method("set_boundary_intensity"):
		_hud3d.set_boundary_intensity(_boundary_intensity)


## 打卡统一门控 —— 空格(键盘)、触屏按钮、驿站模型点击三个入口都必须过这一关。
## 之前 _on_station_check_in 是裸调用 _do_check_in，能绕过下面每一道闸；
## 一旦将来把它接上"点击驿站模型打卡"，就会复现"刚收尾又立刻重新打卡"的老问题。
func _can_start_check_in(station_idx: int) -> bool:
	if station_idx < 0 or station_idx != _nearby_station_idx:
		return false                          # 必须站在可打卡驿站旁
	if _check_in_in_progress or _all_done:
		return false                          # 打卡序列中 / 全收集收尾中
	if _mini_game_state == MG_RUNNING:
		return false                          # 小游戏进行中(它的按键会漏进 interact)
	# 郑铎戏正在播对白时同样不能打卡。对白弹窗靠 ui_accept 推进，而 interact 也是
	# 空格/回车，两者是同一个键；DialoguePopup.set_input_as_handled() 只挡事件
	# 传播，Input.is_action_just_pressed("interact") 早被 OS 输入管线写进单例了。
	# 于是「推进对白的那一下空格」会顺手开一场打卡，两条协程抢同一个弹窗——
	# 郑铎那条就此挂死，_villain_playing 再也回不到 false，铺子从此再也开不了，
	# 而提示圈照画、空格全死，只能重开游戏。这里必须显式挡一次。
	if _villain_playing:
		return false
	if _paused or _onboarding.visible:
		return false
	if _interact_cooldown > 0.0:
		return false                          # 收尾静默期
	return _recheck_armed                     # 必须骑开过，挡住连按空格


## 按键被门控挡掉时，给玩家一句人话。
##
## 之前这里是纯静默：按空格、什么也不发生。这在"附近根本没有目标"的时候是对的，
## 但在提示圈明明亮着的时候就是事故——玩家没法区分"我按错了"和"这游戏坏了"，
## 唯一能想到的解法是重开。实测真有人卡在铺子门口一小时才发现要重启。
##
## 返回空串表示不提示（周围压根没有可交互的东西，闷声不响才是对的）。
## 判断顺序和 _can_start_check_in / _can_open_shop 的判断顺序保持一致，
## 免得"提示说的原因"和"实际挡住的原因"不是同一件事。
func _interact_blocked_reason() -> String:
	if _prompt_target_station() < 0 and _prompt_target_shop() < 0:
		return ""                          # 附近啥也没有，不打扰
	if _interact_cooldown > 0.0:
		return "blocked_cooldown"          # 收尾静默期
	if not _recheck_armed and _prompt_target_station() >= 0:
		return "blocked_recheck"           # 必须先骑开
	return "blocked_busy"


## 提示圈认的目标：半径内的那一站。
## 半径必须和 CheckInPrompt.PROMPT_RANGE 一致（那边是 15.0）。这里写死一份而不是
## 直接引用那边的常量：CheckInPrompt 没有 class_name，跨脚本按类名取常量会让
## --script 下的验证脚本在编译期拉依赖、报 `Identifier not found: Localization`
## 然后整个 SceneTree 挂死不退出（见 CLAUDE.md 已知陷阱）。改那边要记得改这里。
const PROMPT_RADIUS := 15.0

func _prompt_target_station() -> int:
	var i: int = _nearby_station_idx
	if i < 0 or _nearby_station_dist > PROMPT_RADIUS:
		return -1
	return i


func _prompt_target_shop() -> int:
	var i: int = _nearby_shop_idx
	if i < 0 or _nearby_shop_dist > PROMPT_RADIUS:
		return -1
	return i


## 按键被挡时的反馈：提示圈原地变灰 + 顶栏给一行原因。
## 两处都给是因为玩家的眼睛在圈上，不在顶栏。
func _on_interact_blocked() -> void:
	var key := _interact_blocked_reason()
	if key == "":
		return
	if _check_in_prompt.has_method("flash_blocked"):
		_check_in_prompt.flash_blocked(key)
	if _hud3d.has_method("show_blocked_hint"):
		_hud3d.show_blocked_hint(key)


## ===================== 铺子（驿铺 / 茶铺 / 灯铺） =====================

## 纯 UI + GameManager，不需要 3D 资源。运行时 load 而不是写类型注解：
## World3D 被大量 --script 验证脚本实例化，class_name / 注解会触发编译期拉依赖。
func _setup_shop() -> void:
	_shop_panel = load("res://scripts/ShopPanel.gd").new()
	_shop_panel.closed.connect(_close_shop)
	add_child(_shop_panel)


## 开店门控。与打卡共用「附近 / 没暂停 / 不在收尾」这套判据，
## 但不受 _recheck_armed 与静默期约束 —— 买杯茶不该被上一次打卡卡住。
func _can_open_shop(station_idx: int) -> bool:
	if station_idx < 0 or station_idx != _nearby_shop_idx:
		return false
	if _shop_open or _check_in_in_progress or _all_done:
		return false
	if _mini_game_state == MG_RUNNING or _villain_playing:
		return false
	if _paused or _onboarding.visible:
		return false
	if _interact_cooldown > 0.0:
		return false
	return true


func _open_shop(station_idx: int) -> void:
	var shop_name: String = ShopData.shop_at_station(station_idx)
	if shop_name == "" or _shop_panel == null:
		return
	_shop_open = true
	_shop_panel.setup(shop_name)   # setup() 自己置 visible，不必再设一遍
	_player.set_can_move(false)
	AudioManager.play_sfx("open")


func _close_shop() -> void:
	if not _shop_open:
		return
	_shop_open = false
	if _shop_panel != null:
		_shop_panel.visible = false
	_player.set_can_move(not _paused and not _check_in_in_progress and not _all_done)


## 播放驿站对话，对话框关闭后返回。
## was_skipped=true 表示玩家按了跳过按钮。
## was_stolen=true 表示这一轮被别人的 setup() 顶掉了（见 DialoguePopup._chain_open），
## 此时弹窗已经归别人，调用方要立刻收手，不要再往下走小游戏/发碎片。
func _play_dialogue(idx: int) -> Dictionary:
	if _headless_mode:
		return {"was_skipped": true}
	var rd = _road_builder.get_road_data()
	var lines = rd.station_dialogue(idx)
	if lines.is_empty():
		return {"was_skipped": false}
	_dialogue_popup.setup(_station_name(idx), lines, false)
	_dialogue_popup.visible = true
	var result = await _dialogue_popup.dialogue_done
	# 被顶掉时不要去关别人的弹窗
	if not bool(result.get("was_stolen", false)):
		_dialogue_popup.visible = false
	return result


func _do_check_in(idx: int) -> void:
	_check_in_in_progress = true
	_nearby_station_idx = -1
	_player.set_can_move(false)
	_player.set_camera_locked(true)

	var road_data = _road_builder.get_road_data()
	var s = road_data.stations[idx]
	var station_pos = _stations[idx].position
	var cam_target = station_pos + Vector3(-4, 5, 6)

	# 「这一站还欠我一块碎片吗」是玩家进度，不是站的属性。
	# road_data.station_has_fragment(idx) 说的是"这站有碎片"（静态，16 站里固定 5 站），
	# 拿它当"还没收过"用会让第 2/3 次到访重播整段对白 + 小游戏 + 再报一次
	# 「获得碎片 云」——而 HUD 的"下一处"用的是 is_collected，早就把这站从目标里
	# 摘掉了。于是顶栏说"下一处 358m"、脚下的圈却还在亮着，两边对不上，
	# 玩家按空格只会被拖回小游戏，看起来就像卡死。
	var is_first_visit: bool = road_data.station_has_fragment(idx) \
			and not GameManager.is_collected(idx)

	_cam_look_at_target = station_pos
	_cam_look_at_active = true

	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_player_cam, "global_position", cam_target, 1.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished

	await get_tree().create_timer(1.5, false).timeout  # 定格 1.5s

	# 视觉小说对话（首次到访的碎片驿站才有；回访和对白为空的驿站直接跳过）
	if is_first_visit:
		var dialogue_result = await _play_dialogue(idx)
		# dialogue_result.was_skipped=true 时玩家按了跳过，直接进小游戏
		if bool(dialogue_result.get("was_stolen", false)):
			# 弹窗被郑铎戏抢走了，这趟打卡不能再往下走（再走就会去关别人的弹窗）
			_finish_check_in()
			return

	# 小游戏挑战。**每一趟都有一件乐事**，不再只是首次到访。
	# 原来 `if is_first_visit:` 一刀切掉后两次，可完满评级要的正是三次——
	# 玩家第三次骑到云影台，圈上写着「再访 · 还差 1 次」，走进去却只有一句
	# 「这件已经收过了」。现在按 MiniGamePicker 轮换，同一趟的三件不重样。
	# 非碎片驿站 _run_mini_game() 返回 SKIP，这一整段照走不误。
	#
	# 对白仍然只在首次到访：驿站的开场白是它的自我介绍，回访再念一遍只会
	# 把顶栏那 3 次的进度感冲掉，而每趟都有的乐事已经把那三次填满了。
	const SUCCESS := 0
	const CANCELLED := 1
	const SKIP := 2
	var mini_result := SKIP
	mini_result = await _run_mini_game(idx)
	if mini_result != SKIP:
		# 必须放在 CANCELLED 分支之前：失败那趟也要留一点旅币，别让玩家觉得白挨。
		GameManager.on_mini_game(idx, mini_result == SUCCESS)
	if mini_result == CANCELLED:
		# 失败也必须给一屏。5 个小游戏失败时都是 _on_mini_game_done(CANCELLED)
		# + queue_free() 同帧收工，遮罩一没了玩家就被扔回 3D 世界，
		# 既不知道是输了还是被踢出去，也不知道这个驿站还能不能再玩。
		# 统一在 World3D 这边补一屏，5 个小游戏不用各写一遍。
		_show_failed_panel(idx)
		await get_tree().create_timer(MINI_GAME_FAIL_HOLD_SEC, false).timeout
		_check_in_popup.visible = false
		_finish_check_in()
		return

	_last_check_in_idx = idx
	_popup_mode = POPUP_STATION
	_popup_name.text = _station_name(idx)
	_popup_event.text = _station_event(idx)
	_popup_text.text = _station_text(idx)

	# 回访不要再报一次「获得碎片：云」——碎片早就在顶栏的槽位里了，
	# 再报一遍等于骗玩家说刚拿到新东西。改成一句"这件已经收过了"。
	# check_in() 还是要调的：它才是发回访旅币（LVBI_REPEAT_CHECKIN）和累计次数的地方。
	var frag := _station_fragment(idx) if is_first_visit else ""
	if not is_first_visit and road_data.station_has_fragment(idx):
		_popup_text.text = Localization.t("revisit_note")
	if frag and frag != "":
		_popup_fragment.text = Localization.t("fragment_obtained") + frag
		_popup_fragment.visible = true
	else:
		_popup_fragment.visible = false

	_check_in_popup.visible = true
	await get_tree().process_frame  # 让 layout 算一次 rect

	if frag and frag != "":
		AudioManager.play_sfx("collect")
		var slot_idx := _fragment_slot_idx(frag)
		if slot_idx < 0:
			push_warning("World3D: 未知的 fragment 名字 '%s',跳过飞行动画" % frag)
		else:
			var ff = preload("res://scripts/FragmentFlying.gd").new()
			var from_pos = _check_in_popup.get_global_rect().get_center()
			var to_pos = _fragment_bar.get_slot_global_center(slot_idx)
			ff.setup(slot_idx, from_pos, to_pos)
			$FragmentBarLayer.add_child(ff)
		await get_tree().create_timer(1.0, false).timeout  # 飞入完成
	GameManager.check_in(idx)

	await get_tree().create_timer(0.4, false).timeout
	_check_in_popup.visible = false
	_finish_check_in()


## 打卡序列收尾（成功与取消/失败共用）。
## 除了解锁，还要给 interact 一段静默期：空格同时是全局 "interact" 动作，
## 而竹子这类小游戏就是按空格玩的——序列一结束玩家手上往往还在按，
## 不静默的话下一次空格会立刻重新触发一次驿站打卡。
## （只靠静默期就够：just_pressed 只在按下那一帧为真，同帧就会被挡掉）
## 小游戏挑战失败后，失败面板停留的时长（秒）。
## 面板只是给玩家一个"刚才发生了什么"的交代：确认是输了而不是被踢出去，
## 并且告诉他这个驿站还能再玩。停留期间吃掉按键，避免惯性乱按把面板跳掉。
const MINI_GAME_FAIL_HOLD_SEC := 1.8

func _show_failed_panel(idx: int) -> void:
	_last_check_in_idx = idx
	_popup_mode = POPUP_FAILED
	_popup_name.text = _station_name(idx)
	_popup_event.text = Localization.t("mg_failed")
	_popup_text.text = Localization.t("mg_failed_hint")
	_popup_fragment.visible = false
	_check_in_popup.visible = true


func _finish_check_in() -> void:
	_cam_look_at_active = false
	_player.set_camera_locked(false)
	_player.set_can_move(true)
	_check_in_in_progress = false
	_interact_cooldown = INTERACT_COOLDOWN_SEC
	_last_check_in_pos = _player.position
	_recheck_armed = false   # 重新上锁：这一次打卡结束前必须先骑开


func _popup_font_size(zh: int, en: int) -> int:
	return en if Localization.is_english() else zh


func _apply_language() -> void:
	_collecting_label.text = Localization.t("collecting_message")
	if _last_check_in_idx >= 0 and _check_in_popup.visible:
		var idx = _last_check_in_idx
		_popup_name.text = _station_name(idx)
		if _popup_mode == POPUP_FAILED:
			# 切语言时别把失败文案刷回驿站正文，否则"未完成"提示会被冲掉
			_popup_event.text = Localization.t("mg_failed")
			_popup_text.text = Localization.t("mg_failed_hint")
			_popup_fragment.visible = false
		else:
			_popup_event.text = _station_event(idx)
			_popup_text.text = _station_text(idx)
			var frag = _station_fragment(idx)
			_popup_fragment.text = Localization.t("fragment_obtained") + frag if frag != "" else ""
			_popup_fragment.visible = frag != ""
	for i in range(_stations.size()):
		var label = _stations[i].get_node_or_null("StationNameLabel")
		if label is Label3D:
			label.text = _station_name(i)


func _on_joystick_input(dir: Vector2) -> void:
	if _player:
		_player.set_touch_direction(dir)


func _on_station_check_in(station_idx: int) -> void:
	if _can_start_check_in(station_idx):
		_do_check_in(station_idx)


## 第一次集齐五块碎片。**不是结束** —— 顶栏、脚下的圈、小地图此刻都已经
## 切到「再访 · 还差 2 次」，导航重新指向还欠到访的驿站，玩家当然可以继续骑。
## 这里只放一小段合成动画 + 一句话，把"礼物成形了，但乐事还能再收"讲清楚。
func _on_all_collected() -> void:
	_player.set_can_move(false)
	_player.set_camera_locked(true)
	_collecting_label.text = Localization.t("collecting_message")
	_collecting_label.visible = true
	AudioManager.play_sfx("synthesis")
	_spawn_synthesis_animation()
	await get_tree().create_timer(2.5, false).timeout
	_collecting_label.visible = false
	# 收尾：把操纵权和相机还回去，并给一段静默期 ——
	# 玩家手上多半还按着空格，闩锁不在这一刻放下就会立刻再触发一轮打卡。
	_player.set_camera_locked(false)
	_player.set_can_move(true)
	_interact_cooldown = INTERACT_COOLDOWN_SEC
	_hud3d.show_pass_line(Localization.t("revisit_available"))


## 五座碎片驿站各刷满 —— **这一趟到此为止**。
##
## 原来这个函数是接在 all_fragments_collected（五站各收过**一次**）上的，
## 于是玩家在第一次集齐的那一刻就被锁死 2.5 秒弹去结算页，
## 而顶栏 / 脚下提示圈 / 小地图从那一刻之前就一直在说「再访 · 还差 N 次」。
## 一个从首屏起就兑现不了的承诺，加上一个谁也走不到的"完满"评级。
func _on_all_maxed() -> void:
	_all_done = true
	_player.set_can_move(false)
	_player.set_camera_locked(true)
	_collecting_label.text = Localization.t("synthesis_done_message")
	_collecting_label.visible = true
	AudioManager.play_sfx("synthesis")
	if _env_audio != null:
		_env_audio.stop_all()
	_spawn_synthesis_animation()
	await get_tree().create_timer(2.5, false).timeout
	_collecting_label.visible = false
	GameManager.go_to_end_card()


func _spawn_synthesis_animation() -> void:
	# 结束条件从"五站各收过一次"改成"五站各刷满三次"之后，这函数一趟里会被调用
	# 两次（第一次集齐一次、走满一次）。而 FragmentFlying 设的是 auto_free_on_complete
	# = false，播完也不会自己走 —— 第二层叠在第一层上就是十块碎片卡在屏中央。
	# 任何一条分支在 await 之前都要先把自己留下的节点收干净，理由同
	# CLAUDE.md 里那条"提前 return 的分支必须清自己的闩锁"。
	for old in get_children():
		if old.name == "SynthesisLayer":
			old.queue_free()
	var layer = CanvasLayer.new()
	layer.name = "SynthesisLayer"
	add_child(layer)
	var vs = get_viewport().get_visible_rect().size
	var from_positions = [
		Vector2(0, 0),
		Vector2(vs.x, 0),
		Vector2(0, vs.y),
		Vector2(vs.x, vs.y),
		Vector2(vs.x * 0.5, -50),
	]
	var spacing = 90
	var start_x = vs.x * 0.5 - spacing * 2
	var center_y = vs.y * 0.5
	for i in range(5):
		var ff = preload("res://scripts/FragmentFlying.gd").new()
		var to_pos = Vector2(start_x + i * spacing, center_y)
		ff.auto_free_on_complete = false
		ff.setup(i, from_positions[i], to_pos)
		layer.add_child(ff)


func _build_bike() -> void:
	# 资产在 res://assets/bike.glb（不在 models/ 下）。本地 AABB 50.7×114.5×198.1，
	# 乘 BIKE_SCALE=0.012 之后是 1.37m 高、2.38m 长的实车尺寸。
	# 旧的程序化 CSG 兜底已经删掉：它引用的 WY / RA_X / REAR_Z 从来没定义过，
	# 一旦真被调用就是运行时报错，留在那儿只是看着像还有条退路。
	var bike_path = "res://assets/bike.glb"
	if not ResourceLoader.exists(bike_path):
		push_error("bike.glb not found at " + bike_path)
		return
	var bike_scene: PackedScene = load(bike_path)
	if bike_scene == null:
		push_error("bike.glb 加载失败")
		return
	var bike = bike_scene.instantiate()
	bike.scale = Vector3(BIKE_SCALE, BIKE_SCALE, BIKE_SCALE)
	_player.add_child(bike)
	_bike_model = bike
	_bike_rear_wheel = _find_wheel_node(bike, ["rearwheel", "wheel_rear", "rear_wheel", "后轮"])
	_bike_front_wheel = _find_wheel_node(bike, ["frontwheel", "wheel_front", "front_wheel", "前轮"])
	if _bike_rear_wheel:
		_wheel_base_rot_rear = _bike_rear_wheel.rotation.x
	if _bike_front_wheel:
		_wheel_base_rot_front = _bike_front_wheel.rotation.x


func _find_wheel_node(bike: Node, name_hints: Array) -> Node3D:
	for child in bike.get_children():
		var cn = child.name.to_lower()
		for hint in name_hints:
			if cn.contains(hint.to_lower()):
				return child
	# 递归一层
	for child in bike.get_children():
		if child is Node3D:
			for gc in child.get_children():
				var gcn = gc.name.to_lower()
				for hint in name_hints:
					if gcn.contains(hint.to_lower()):
						return gc
	return null


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.mesh != null:
		return node
	for child in node.get_children():
		var result = _find_mesh_instance(child)
		if result:
			return result
	return null


# 递归遍历 node 树下所有 MeshInstance3D，关闭阴影投射
# 驿站/树木等静态场景 GLB 不投射阴影，避免与玩家阴影重叠产生残影
func _disable_translatable(node: Node) -> void:
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_translatable(child)


func _on_check_in_pressed() -> void:
	# 触屏按钮和键盘空格共用这条路：先问碎片驿站，再问铺子。
	if _can_start_check_in(_nearby_station_idx):
		_do_check_in(_nearby_station_idx)
	elif _can_open_shop(_nearby_shop_idx):
		_open_shop(_nearby_shop_idx)
	else:
		_on_interact_blocked()


func _unhandled_input(event: InputEvent) -> void:
	# _shop_open 要在这里也挡一次：ShopPanel 自己会 set_input_as_handled()，
	# 但传播顺序不由我们保证，漏掉就把暂停面板叠在铺子上面。
	if _onboarding.visible or _shop_open or _villain_playing:
		return
	if event.is_action_pressed("pause"):
		if _check_in_in_progress or _all_done:
			return
		toggle_pause()


func toggle_pause() -> void:
	_paused = not _paused
	_pause_panel.visible = _paused
	AudioManager.set_paused_bgm(_paused)
	_player.set_can_move(not _paused and not _check_in_in_progress and not _all_done and not _shop_open)


func resume_game() -> void:
	if _paused:
		toggle_pause()


func _on_onboarding_dismissed() -> void:
	_player.set_can_move(not _check_in_in_progress and not _all_done)


## ===================== 小游戏注入（状态机模式） =====================
## _mini_game_state: -1=未运行, MG_RUNNING=运行中, 0=成功, 1=取消
## 结果码与小游戏脚本内的 SUCCESS(0)/CANCELLED(1) 保持一致；
## 运行中必须用 -2 哨兵，不能用 0（0 会和小游戏的 SUCCESS 撞车，导致成功永不退出轮询）
## 小游戏节点通过 _on_mini_game_done(result) 回调，不依赖信号+queue_free时序

const MG_RUNNING := -2
## 小游戏无结果时的兜底超时（秒）。必须按墙钟计时，不能用帧数：
## 60FPS 下 600 帧只有 10 秒，而竹子小游戏满负荷要
## 0.8s 引导 + 5×(1.2s 窗口 + 0.4s 间隔) ≈ 8.8 秒，余量只有 ~1.2 秒。
const MINI_GAME_TIMEOUT_SEC := 30.0
var _mini_game_state: int = -1
var _mini_game_node: Node = null

func _run_mini_game(station_idx: int) -> int:
	_mini_game_state = -1
	var rd = _road_builder.get_road_data()
	if not rd.station_has_fragment(station_idx):
		return 2  # SKIP
	# 哪一件乐事由 MiniGamePicker 算：按 (碎片槽位 + 第几次到访) 轮换，
	# 第一次到访拿到的还是这座驿站自己的那件。原来这里是一张
	# 「驿站 → 固定小游戏」的表，而调用方只在首次到访时才进它，
	# 于是三次到访里有两次是空的。
	#
	# `get_station_count()` 此刻还是**本次之前**的次数——`GameManager.check_in()`
	# 要等小游戏和弹窗都走完才调，所以这里拿到的正好是「这是第几次来」。
	var slot: int = rd.FRAGMENT_SLOT_STATION_IDX.find(station_idx)
	if slot < 0:
		return 2  # SKIP
	var script_path: String = MiniGamePicker.script_for(
			slot, GameManager.get_station_count(station_idx))
	_mini_game_node = load(script_path).new()
	# 注入回调节点引用，让小游戏能通知完成
	_mini_game_node._world_ref = self
	# 关键1：脚本 .new() 出来的 Control 默认 size=(0,0)，画不出也收不到 _gui_input，
	# 必须在入树前铺满全屏（入树后 _ready 里的布局计算才拿得到正确 size）
	_mini_game_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 关键2：Tea/Bamboo/Zither 依赖空格/数字键，_gui_input 收键盘必须有焦点
	_mini_game_node.focus_mode = Control.FOCUS_ALL
	# 背板 + 藏 HUD。5 个小游戏原本都是裸 Control 直接盖在 3D 世界上面，
	# 马路、行道树、远处山脊整片透上来，顶栏还压在小游戏标题上——这是玩家
	# 注意力最集中的一屏，背景抢戏就是设计事故。收在这一处而不是各小游戏里。
	_push_mini_game_chrome()
	_mini_game_layer.add_child(_mini_game_node)
	_mini_game_node.grab_focus()
	_mini_game_state = MG_RUNNING
	# 按墙钟轮询（旧版按 600 帧计，60FPS 下只有 10 秒，会在玩家还没砍完时强杀）
	var deadline_ms := Time.get_ticks_msec() + int(MINI_GAME_TIMEOUT_SEC * 1000.0)
	while Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame
		if _mini_game_state != MG_RUNNING:
			break
	if _mini_game_state == MG_RUNNING:
		push_warning("World3D: 小游戏 %ds 无结果，按取消处理" % int(MINI_GAME_TIMEOUT_SEC))
		_mini_game_state = 1  # CANCELLED
	# 清理节点
	if _mini_game_node != null and is_instance_valid(_mini_game_node):
		_mini_game_node.queue_free()
		_mini_game_node = null
	_pop_mini_game_chrome()
	return _mini_game_state


## 小游戏那一屏的"外壳"：全屏背板 + 藏顶栏。
##
## 收成一对 public 方法而不是内联在 _run_mini_game 里，是因为 lookdev_journey
## 截图时会绕过 _run_mini_game 直接把小游戏塞进 layer。逻辑内联的话，
## 定妆照拍出来的就永远是没有背板的那一屏，看图的人以为游戏本来就这样。
func _push_mini_game_chrome() -> void:
	if not _mini_game_layer.has_node("MiniGameBackdrop"):
		_mini_game_layer.add_child(_make_mini_game_backdrop())
		# 背板必须压在小游戏节点下面：先 move 到最前，add_child 时它已经更靠后
		_mini_game_layer.move_child(_mini_game_layer.get_node("MiniGameBackdrop"), 0)
	_hud3d.visible = false


func _pop_mini_game_chrome() -> void:
	var bg := _mini_game_layer.get_node_or_null("MiniGameBackdrop")
	if bg != null:
		_mini_game_layer.remove_child(bg)
		bg.queue_free()
	_hud3d.visible = true


## 小游戏背板。不是全黑：小游戏自己的面板都是深色，再压一层全黑会让
## 面板和背景糊在一起分不出层次。0.93 足以盖掉世界、留住一点点环境色。
func _make_mini_game_backdrop() -> ColorRect:
	var bg := ColorRect.new()
	bg.name = "MiniGameBackdrop"
	bg.color = Color(0.04, 0.035, 0.05, 0.93)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg


## 小游戏节点调用此方法通知完成
func _on_mini_game_done(result: int) -> void:
	if _mini_game_state == MG_RUNNING:  # 只在运行中接受结果
		_mini_game_state = result


## ===================== 序章与郑铎三场 =====================

## 序章：第一次开局压在 Onboarding 之后播，只播一次（GameManager 落盘）。
func _play_prologue() -> void:
	if _onboarding.visible:
		# 等它关，别让两张全屏面板叠在一起。
		# 此时还在 _ready() 内、没走过任何一帧，dismissed 不可能已经发出。
		await _onboarding.dismissed
	_onboarding.visible = false
	if _headless_mode:
		# 头less 没人点按钮，await 会永久挂起；只落盘不留屏。
		GameManager.mark_prologue_done()
		return
	_player.set_can_move(false)
	var lines := [
		Localization.t("prologue_1"),
		Localization.t("prologue_2"),
		Localization.t("prologue_3"),
	]
	_dialogue_popup.setup(Localization.t("prologue_speaker"), lines, false)
	_dialogue_popup.visible = true
	var result = await _dialogue_popup.dialogue_done
	if not bool(result.get("was_stolen", false)):
		_dialogue_popup.visible = false
	_player.set_can_move(not _paused and not _check_in_in_progress and not _all_done)
	GameManager.mark_prologue_done()


## 郑铎三场。seen 是"路过多少座驿"，parts 按顺序播；speaker 可换（第三场中段换玩家）。
## 文案全是 Localization key，不在这份表里写死任何台词。
##
## 门槛原来写的是 km = 50/100/150。按真实换算（1228.8m 一圈摊到 188km）这是
## 开局第 25/50/75 秒——整条反派线会在玩家还没到过第一座碎片驿站的时候全部灌完，
## 而且顶栏那个数被划掉之后玩家连"还剩几场"都看不见。换成驿数：顶栏正挂着
## 「已过 n/16 驿」，玩家能看着它爬，三场也真的摊在了这一圈的不同位置上。
const VILLAIN_SCENES: Array = [
	{
		"seen": 4,
		"parts": [
			{"speaker": "villain_speaker", "lines": ["villain_1_1", "villain_1_2", "villain_1_3"]},
		],
	},
	{
		"seen": 8,
		"parts": [
			{"speaker": "villain_speaker", "lines": ["villain_2_1", "villain_2_2", "villain_2_3"]},
		],
	},
	{
		"seen": 12,
		"parts": [
			{"speaker": "villain_speaker", "lines": ["villain_3_1", "villain_3_2"]},
			{"speaker": "player_speaker", "lines": ["villain_3_player"]},
			{"speaker": "villain_speaker", "lines": ["villain_3_3"]},
		],
	},
]


## 每帧轮询里程阈值。里程只增不减，所以阈值一次性消费掉。
## 「路过够多的驿」只是触发条件，真门是 GameManager.claim_villain_scene() 的严格顺序检查。
func _try_villain_scene() -> void:
	if _villain_armed.is_empty() or _villain_playing:
		return
	if _check_in_in_progress or _all_done or _mini_game_state == MG_RUNNING:
		return
	if _shop_open:
		return
	var seen := GameManager.get_seen_station_count()
	for i in VILLAIN_SCENES.size():
		if not _villain_armed[i]:
			continue
		if seen < int(VILLAIN_SCENES[i]["seen"]):
			continue
		_villain_armed[i] = false
		if GameManager.claim_villain_scene(i + 1):
			# _play_villain_scene 是协程：它自己在结尾清 _villain_playing。
			# 这里不能同步清 —— 不 await 的话调用只跑到第一个 await 就返回了。
			_villain_playing = true
			_play_villain_scene(i)
		return


func _play_villain_scene(scene_idx: int) -> void:
	if _headless_mode:
		_villain_playing = false
		return
	_player.set_can_move(false)
	var scene: Dictionary = VILLAIN_SCENES[scene_idx]
	for part in scene["parts"]:
		var lines: Array = []
		for key in part["lines"]:
			lines.append(Localization.t(str(key)))
		_dialogue_popup.setup(Localization.t(str(part["speaker"])), lines, false)
		_dialogue_popup.visible = true
		var result = await _dialogue_popup.dialogue_done
		if bool(result.get("was_stolen", false)):
			# 弹窗被别人抢走了，本场就此中止。
			#
			# 这一句是整个游戏最贵的一行代码：_villain_playing 一旦漏在这里，
			# 它就永远是 true —— _can_open_shop 被它挡死（铺子再也不能开），
			# 但 644 行那个早退列表里没有它，所以 _nearby_shop_idx 照算、
			# 提示圈照画。玩家看到的就是"圈在那儿、怎么按都没反应"，
			# 唯一的解法是重开游戏。任何提前 return 都必须先把它清掉。
			push_warning("World3D: 郑铎第 %d 场被其他对白打断，提前收尾" % (scene_idx + 1))
			break
		_dialogue_popup.visible = false
	_player.set_can_move(not _paused and not _check_in_in_progress and not _all_done)
	_villain_playing = false
