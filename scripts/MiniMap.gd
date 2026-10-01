extends Control
## MiniMap — 右上角小地图，显示路网/驿站/玩家

const MAP_SIZE = 180.0
const MAP_PAD = 8.0

## 未收碎片站的金色，和 CheckInPrompt 的碎片提示圈同一个值：顶栏、屏幕提示圈、
## 小地图三处指的必须是同一批地方，颜色不一样玩家会以为是两套东西。
const FRAG_GOLD := Color(0.96, 0.78, 0.49)
## 下一处的白环。它套在最近的那颗未收碎片站外面，是"往这儿骑"的唯一图示。
const NEXT_RING := Color(1, 1, 1, 0.9)
const PULSE_HZ := 1.7

var road_data: RoadData
var player: CharacterBody3D

var _min_x: float = 0.0
var _max_x: float = 0.0
var _min_z: float = 0.0
var _max_z: float = 0.0
var _scale: float = 1.0
var _ox: float = 0.0
var _oy: float = 0.0


func setup(rd: RoadData, p: CharacterBody3D) -> void:
	road_data = rd
	player = p
	_compute_bounds()


func _compute_bounds() -> void:
	if not road_data or road_data.points.is_empty():
		return
	var pts = road_data.points
	_min_x = pts[0].x
	_max_x = pts[0].x
	_min_z = pts[0].z
	_max_z = pts[0].z
	for p in pts:
		_include_bounds(p)
	for branch in road_data.branch_points:
		for p in branch:
			_include_bounds(p)
	var w = _max_x - _min_x
	var h = _max_z - _min_z
	if w < 0.01: w = 1.0
	if h < 0.01: h = 1.0
	_scale = min(MAP_SIZE / w, MAP_SIZE / h)
	_ox = (MAP_SIZE - w * _scale) * 0.5 + MAP_PAD
	_oy = (MAP_SIZE - h * _scale) * 0.5 + MAP_PAD


func _include_bounds(p: Vector3) -> void:
	if p.x < _min_x: _min_x = p.x
	if p.x > _max_x: _max_x = p.x
	if p.z < _min_z: _min_z = p.z
	if p.z > _max_z: _max_z = p.z


func _w2m(pos: Vector3) -> Vector2:
	var mx = (pos.x - _min_x) * _scale + _ox
	var my = (pos.z - _min_z) * _scale + _oy
	return Vector2(mx, my)


func _draw_road_line(pts: Array) -> void:
	if pts.size() < 2:
		return
	var prev = _w2m(pts[0])
	for i in range(1, pts.size()):
		var curr = _w2m(pts[i])
		draw_line(prev, curr, Color(0.45, 0.40, 0.28, 0.9), 1.2)
		prev = curr


## 最近的、还没收的碎片站；全齐了返回 -1。
##
## 必须和 HUD3D._next_fragment_target() 用**同一条规则**（最近的、还欠一次
## 到访的碎片站）。这两处一旦分家，就会出现刚修掉过的那类事故：顶栏说
## "下一处 358m"、小地图却高亮着另一颗——玩家信谁都会骑错，而且没有任何
## 一处会告诉他错了。判据本身在 GameManager.fragment_station_needs_visit()，
## 这里连"是不是碎片站"那一半都一起问，免得三处各抄一半又分家。
func _next_frag_idx() -> int:
	var best := -1
	var best_d := INF
	for i in range(road_data.stations.size()):
		if not GameManager.fragment_station_needs_visit(i):
			continue
		var d: float = player.global_position.distance_to(road_data.get_station_world_pos(i))
		if d < best_d:
			best_d = d
			best = i
	return best


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not road_data or not player:
		return

	draw_rect(Rect2(MAP_PAD - 4, MAP_PAD - 4, MAP_SIZE + 8, MAP_SIZE + 8),
			Color(0.08, 0.10, 0.06, 0.88), true)
	draw_rect(Rect2(MAP_PAD - 4, MAP_PAD - 4, MAP_SIZE + 8, MAP_SIZE + 8),
			Color(0.5, 0.45, 0.3, 0.6), false, 1.5)

	_draw_road_line(road_data.points)
	for branch in road_data.branch_points:
		_draw_road_line(branch)

	# 还欠到访的碎片站要读起来像"目标"，不像"被灰掉的一档"。
	# 旧画法是深灰圆点 + 一圈细线，在深色底上几乎看不见——玩家盯小地图盯半天
	# 也找不到还剩几块，而顶栏明明写着"下一处 358m"。改成实心金点 + 呼吸光晕。
	#
	# 「已经收过」不再等于「不用再去」：完满评级要每站三次，所以收过的那几座
	# 在刷满之前仍然画成目标，只是外面套一圈进度弧，读得出还差几次。
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU * PULSE_HZ)
	var next_idx := _next_frag_idx()

	for i in range(road_data.stations.size()):
		var spos = _w2m(road_data.get_station_world_pos(i))
		var col: Color = road_data.stations[i]["color"]
		var has_frag = road_data.station_has_fragment(i)
		if not has_frag:
			draw_circle(spos, 3, Color(0.5, 0.5, 0.45, 0.7))
		elif GameManager.fragment_station_needs_visit(i):
			draw_circle(spos, 6.0 + pulse * 2.0, Color(FRAG_GOLD, 0.10 + pulse * 0.14))
			draw_circle(spos, 4.0, FRAG_GOLD)
			draw_circle(spos, 4.0, Color(0.12, 0.10, 0.06, 0.9), false, 1.0)
			# 已经到访过的，外圈再画一段进度弧：整圈 = MAX_VISITS 次
			if GameManager.is_collected(i):
				var done: int = GameManager.get_station_count(i)
				if done > 0 and done < int(GameManager.MAX_VISITS_PER_STATION):
					draw_arc(spos, 8.0, -PI * 0.5,
							-PI * 0.5 + TAU * float(done) / float(GameManager.MAX_VISITS_PER_STATION),
							20, Color(1, 1, 1, 0.85), 2.0)
			if i == next_idx:
				draw_arc(spos, 9.0 + pulse * 1.5, 0.0, TAU, 28, NEXT_RING, 1.6)
		else:
			# 刷满了：保留驿站本色 + 白边，是"去过的地方"，不该再和目标抢注意力。
			draw_circle(spos, 4.5, col)
			draw_circle(spos, 4.5, Color(1, 1, 1, 0.55), false, 1.2)

	var ppos = _w2m(player.position)
	var ry = player.rotation.y
	var fwd = Vector2(-sin(ry), -cos(ry))
	var perp = Vector2(-fwd.y, fwd.x)
	var tip = ppos + fwd * 6
	var bl = ppos - fwd * 3 + perp * 3
	var br = ppos - fwd * 3 - perp * 3
	draw_colored_polygon(PackedVector2Array([tip, bl, br]), Color(1, 0.25, 0.15, 1))
