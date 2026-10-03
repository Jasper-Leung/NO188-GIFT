extends Control
## GiftBox — 开始界面 / 礼物盒 (PRD §5.1)
## 居中礼物盒 + 标题 + 副标题 + 开启旅程按钮

@onready var _start_btn: Button = $StartBtn
@onready var _demo_btn: Button = $DemoBtn
@onready var _language_btn: Button = $LanguageBtn
@onready var _title: Label = $Title
@onready var _subtitle: Label = $Subtitle
@onready var _guide: Label = $Guide
@onready var _disclaimer: Label = $Disclaimer
@onready var _loading_bg: ColorRect = $LoadingLayer/LoadingBg
@onready var _loading_label: Label = $LoadingLayer/LoadingLabel

var _t = 0.0
var _opened = false
var _box_scale = 1.0
var _box_alpha = 1.0
var _box_center = Vector2.ZERO
var _road_preview_alpha = PREVIEW_ALPHA_DIM
var _road_preview_fit := PREVIEW_FIT_DIM
var _world_scene: PackedScene = null

var _road_data: RoadData = null
var _road_poly := PackedVector2Array()

## 标题页上一直挂着这张 8 字路网，只是压得很淡当底纹；按下"开启旅程"之后
## 才把它推到前景、放大、提亮。原来它只在开场动画里出现 1.5 秒——新玩家在
## 标题页停留的那几秒看到的是一片纯黑。
const PREVIEW_FIT := 0.62
const PREVIEW_FIT_DIM := 1.15
const PREVIEW_ALPHA_DIM := 0.20
const BG_COLOR := Color(0.1, 0.08, 0.12, 1.0)

## 「开启旅程」按下之后到 World3D 换上来之前的那段过场，一共有五段。
##
## 这五段是冷启动里**唯一一段纯机器等待**：礼物盒淡出、路网底纹推正、停一拍、
## 推回、然后换场景——合计 3.15 秒，而这几秒里玩家既动不了，也读不到任何新东西
## （他刚按完按钮，正在等）。带窗口的 `tools/measure_cold_start.gd` 量到的
## 「按钮按下→世界起来了」里，它占了四分之三。
##
## 现在压到 1.20 秒。路网底纹推正那一下留着——它是"按下开始 = 看清路线"这件事
## 唯一的兑现，砍掉就等于按了按钮什么也没发生；只是不再让它独占三秒。
const BOX_OUT_SEC := 0.22        # 礼物盒放大淡出
const ROAD_IN_SEC := 0.28        # 底纹从 DIM 推到前景
const ROAD_HOLD_SEC := 0.40      # 停一拍，让它真的被看清
const ROAD_OUT_SEC := 0.22       # 推回 DIM
const SWITCH_DELAY_SEC := 0.08   # 换场景前最后一点留白

## 上面五段加起来。这是回归钉的那一个数（verify_story 第 5 节对着文档核，
## measure_cold_start 从这张表重算一遍，两边不许漂）。
const START_TRANSITION_SEC := BOX_OUT_SEC + ROAD_IN_SEC + ROAD_HOLD_SEC + ROAD_OUT_SEC + SWITCH_DELAY_SEC


func _ready() -> void:
	_box_center = Vector2(get_viewport_rect().size.x / 2, 290)
	_start_btn.pressed.connect(_on_start_pressed)
	_demo_btn.pressed.connect(_on_demo_pressed)
	_language_btn.pressed.connect(_on_language_pressed)
	Localization.language_changed.connect(_apply_language)
	_apply_language()
	_start_btn.grab_focus()
	_road_data = RoadData.new()
	_road_poly = _build_road_poly()
	# 编辑模式下跳过开场动画直接进 World3D(开发者不需要点"开始")
	if GameManager.is_editor_mode():
		_world_scene = load("res://scenes/World3D.tscn")
		call_deferred("_do_change_scene")


func _do_change_scene() -> void:
	get_tree().change_scene_to_packed(_world_scene)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	# 底色必须自己画。原来是场景里一个全屏 ColorRect 子节点，而子节点永远画在
	# 父节点的 _draw() 之上——那张 ColorRect 把整个 _draw()（礼物盒 + 路网底纹）
	# 全盖住了，标题页一直是一块纯黑，按钮点下去那套缩放淡出动画其实谁也看不见。
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), BG_COLOR)

	# 路网压在最底，礼物盒压在上面
	_draw_road_preview()

	# 漂浮粒子
	for i in range(10):
		var px = _box_center.x + cos(_t * 0.7 + i * 0.8) * (70 + i * 14)
		var py = _box_center.y + sin(_t * 1.0 + i * 0.5) * (35 + i * 8) - i * 6
		var pa = 0.25 + sin(_t * 2.0 + i) * 0.15
		draw_circle(Vector2(px, py), 3.0, Color(1, 1, 1, pa))

	# 礼物盒
	var offset = Vector2(0, sin(_t * 1.5) * 6.0)
	var rot = sin(_t * 0.8) * 0.02
	draw_set_transform(_box_center + offset, rot, Vector2(_box_scale, _box_scale))

	var c = Color("C8443A")
	var ribbon = Color("F5C87E")
	var a = Color(1, 1, 1, _box_alpha)

	# 盒身
	draw_rect(Rect2(-42, -42, 84, 84), c * a)
	draw_rect(Rect2(-42, -42, 84, 84), Color(1, 1, 1, 0.5 * _box_alpha), false, 2)
	# 丝带竖
	draw_rect(Rect2(-7, -42, 14, 84), ribbon * a)
	# 丝带横
	draw_rect(Rect2(-42, -7, 84, 14), ribbon * a)
	# 蝴蝶结
	draw_circle(Vector2(-14, -44), 11, ribbon * a)
	draw_circle(Vector2(14, -44), 11, ribbon * a)
	draw_circle(Vector2(0, -42), 7, Color("E8B85A") * a)

	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _draw_road_preview() -> void:
	if _road_poly.is_empty() or _road_preview_alpha <= 0.001:
		return
	var vs = get_viewport_rect().size
	var cx = vs.x / 2.0
	var cy = vs.y / 2.0
	var a = _road_preview_alpha

	# 与 MiniMap 同一套投影：路网外接框归一化后居中
	var p0 = _road_poly[0]
	var mn = p0
	var mx = p0
	for p in _road_poly:
		mn = Vector2(min(mn.x, p.x), min(mn.y, p.y))
		mx = Vector2(max(mx.x, p.x), max(mx.y, p.y))
	var s = min(vs.x, vs.y) * _road_preview_fit / max(max(mx.x - mn.x, mx.y - mn.y), 0.01)
	var ox = cx - (mn.x + mx.x) * 0.5 * s
	var oy = cy - (mn.y + mx.y) * 0.5 * s

	var prev := Vector2(ox + p0.x * s, oy + p0.y * s)
	for i in range(1, _road_poly.size()):
		var curr := Vector2(ox + _road_poly[i].x * s, oy + _road_poly[i].y * s)
		draw_line(prev, curr, Color("8A8578", a), 6.0)
		draw_line(prev, curr, Color("C9A26B", a), 3.0)
		prev = curr

	for i in range(_road_data.stations.size()):
		if not _road_data.station_has_fragment(i):
			continue
		var sp = _road_data.get_station_world_pos(i)
		var mp = Vector2(ox + sp.x * s, oy + sp.z * s)
		var col: Color = _road_data.stations[i]["color"]
		col.a = a
		draw_circle(mp, 5.5, col)
		draw_circle(mp, 5.5, Color(1, 1, 1, a * 0.7), false, 1.2)

	# 标题页当底纹时不打这行字（会和标题区撞在一起），推到前景才出现
	if a < 0.5:
		return
	draw_string(ThemeDB.fallback_font, Vector2(cx - 100, vs.y - 120),
		Localization.t("road_preview"), HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color(0.96, 0.78, 0.49, a))


func _build_road_poly() -> PackedVector2Array:
	# 按弧长抽稀（3m 一点）：既降 draw call，也顺带削掉 GPS 采样抖动
	var pts := _road_data.points
	var poly := PackedVector2Array()
	if pts.is_empty():
		return poly
	poly.append(Vector2(pts[0].x, pts[0].z))
	var acc := 0.0
	for i in range(1, pts.size()):
		var p = Vector2(pts[i].x, pts[i].z)
		acc += (p - poly[poly.size() - 1]).length()
		if acc >= 3.0:
			poly.append(p)
			acc = 0.0
	poly.append(Vector2(pts[pts.size() - 1].x, pts[pts.size() - 1].z))
	return poly


func _apply_language() -> void:
	_title.text = Localization.t("game_title")
	_subtitle.text = Localization.t("subtitle")
	_guide.text = Localization.t("guide")
	_disclaimer.text = Localization.t("disclaimer")
	_start_btn.text = Localization.t("start")
	_demo_btn.text = Localization.t("demo_start")
	_language_btn.text = "%s  %s" % [Localization.t("language"), Localization.t("language_current")]
	_loading_label.text = Localization.t("loading")


func _on_language_pressed() -> void:
	Localization.set_language("zh" if Localization.is_english() else "en")


## 演示入口。**不播那 1.2 秒过场**——演示的人已经知道自己按了什么，
## 站着看礼物盒淡出是在花掉一条 90 秒里最贵的一段。
func _on_demo_pressed() -> void:
	if _opened:
		return
	_opened = true
	_start_btn.disabled = true
	_demo_btn.disabled = true
	AudioManager.play_sfx("open")
	_start_btn.visible = false
	_demo_btn.visible = false
	GameManager.enter_demo()
	_world_scene = load("res://scenes/World3D.tscn")
	_loading_bg.visible = true
	_loading_label.visible = true
	await get_tree().create_timer(0.1, false).timeout
	get_tree().change_scene_to_packed(_world_scene)


func _on_start_pressed() -> void:
	if _opened:
		return
	_opened = true
	_start_btn.disabled = true
	AudioManager.play_sfx("open")
	_start_btn.visible = false

	var tw = create_tween().set_parallel(true)
	tw.tween_property(self, "_box_scale", 2.5, BOX_OUT_SEC)
	tw.tween_property(self, "_box_alpha", 0.0, BOX_OUT_SEC)
	tw.tween_property(_title, "modulate:a", 0.0, BOX_OUT_SEC)
	tw.tween_property(_subtitle, "modulate:a", 0.0, BOX_OUT_SEC)
	tw.tween_property(_guide, "modulate:a", 0.0, BOX_OUT_SEC)
	tw.tween_property(_disclaimer, "modulate:a", 0.0, BOX_OUT_SEC)
	tw.tween_property(_language_btn, "modulate:a", 0.0, BOX_OUT_SEC)

	await tw.finished
	_language_btn.visible = false
	_disclaimer.visible = false
	queue_redraw()

	# 底纹推正：同时缩到正常尺寸并提亮，让"点开始"变成"看清路线"而不是凭空出图
	var tw2 = create_tween().set_parallel(true)
	tw2.tween_property(self, "_road_preview_alpha", 1.0, ROAD_IN_SEC)
	tw2.tween_property(self, "_road_preview_fit", PREVIEW_FIT, ROAD_IN_SEC)

	_world_scene = load("res://scenes/World3D.tscn")

	await get_tree().create_timer(ROAD_HOLD_SEC, false).timeout

	var tw3 = create_tween().set_parallel(true)
	tw3.tween_property(self, "_road_preview_alpha", 0.0, ROAD_OUT_SEC)
	tw3.tween_property(self, "_road_preview_fit", PREVIEW_FIT_DIM, ROAD_OUT_SEC)
	await tw3.finished

	_loading_bg.visible = true
	_loading_label.visible = true

	await get_tree().create_timer(SWITCH_DELAY_SEC, false).timeout
	get_tree().change_scene_to_packed(_world_scene)
