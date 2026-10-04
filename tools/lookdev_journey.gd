extends SceneTree
## lookdev_journey.gd — 一个新玩家从进游戏到拿到明信片会看到的每一屏
##
## 和 lookdev_stations.gd 同样的规矩：**不能加 --headless，也不能加 --quit-after**。
## 这里拍的是"玩家视角"本身（3D 画面 + HUD + 全屏面板叠在一起），dummy renderer
## 拍出来是纯色，等于什么都没验。
##
## 与其他 lookdev 的分工：
##   lookdev_grass / lookdev_trees / lookdev_stations  看场景本身好不好看
##   lookdev_journey                                   看**拼接起来之后**玩家读不读得懂
##   ——尤其是 HUD 叠上去之后还剩多少 3D 画面、面板有没有把字挡住。
##
## 用法： godot --path . --script tools/lookdev_journey.gd
##
## 12b_dusk_黄昏 这一屏是**唯一**看得到世界光照的地方：光照全在环境层，
## 别的 lookdev 都不管它，而 DayCycle 的黄昏常量只能靠这张图判对错。

const SAVE_DIR := "user://lookdev_journey"
const SHOT := Vector2i(1280, 720)
const WAIT_SEC := 2.5

## 五个碎片驿站 → 各自的小游戏脚本。索引取自 World3D._run_mini_game()。
const MG := {
	4: {"name": "禽", "script": "res://scripts/mini_games/MiniGameBird.gd"},
	7: {"name": "云", "script": "res://scripts/mini_games/MiniGameCloud.gd"},
	10: {"name": "茶", "script": "res://scripts/mini_games/MiniGameTea.gd"},
	13: {"name": "琴", "script": "res://scripts/mini_games/MiniGameZither.gd"},
	14: {"name": "竹", "script": "res://scripts/mini_games/MiniGameBamboo.gd"},
}

var _shots := 0
var _fails := 0
var _gm: Node = null
var _loc: Node = null
var _world: Node = null


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_fails += 1
		print("[FAIL] ", label + ("（" + detail + "）" if detail != "" else ""))


func _ensure_autoloads() -> void:
	var paths := {
		"GameManager": "res://scripts/GameManager.gd",
		"AudioManager": "res://scripts/AudioManager.gd",
		"Localization": "res://scripts/Localization.gd",
	}
	for n in paths:
		if root.get_node_or_null(n) == null:
			var node: Node = load(paths[n]).new()
			node.name = n
			root.add_child(node)


func _initialize() -> void:
	Engine.max_fps = 60
	_ensure_autoloads()
	_gm = root.get_node("GameManager")
	_loc = root.get_node("Localization")
	_gm._clear_save()
	_loc.set_language("zh")
	root.size = SHOT
	_run.call_deferred()


## 渲染三帧再导 PNG：queue_redraw / 材质编译都到下一帧才落地。
## 图返回出去给 12b/12c 那两条量像素——判据要落在画出来的那张上，
## 而不是落在喂给着色器的那几个数上（sky_curve 之类的旋钮全对而画面一片平，
## 这一族已经栽过一次）。
func _snap(name: String) -> Image:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	var err: int = img.save_png("%s/%s.png" % [SAVE_DIR, name])
	var c := img.get_pixel(SHOT.x / 2, SHOT.y / 2)
	_ck("%02d %s（中心像素 %s）" % [_shots + 1, name, str(c)],
			err == OK and img.get_width() == SHOT.x and c.a > 0.0)
	_shots += 1
	return img


## 玩家真正看得见的那条天带，从图上量。
##
## **取样框是按真实机位算出来的，不是拍脑袋取的**：相机 fov 70（竖向）、
## `Player3D._update_camera` 让它俯 12.5°（看向车上方 1.1m、往前 2.2m 那一点，
## 而相机在 2.3m），于是屏幕顶端正好是**仰角 +22.5°**、地平线落在 y 比例 0.321。
## 顶部 62px 是 `HUD3D` 那条衬底（`SCRIM_H`），所以取样从 y 比例 0.10 起
## （仰角 15.5°）——再往上量到的是顶栏，不是天。
##
## 横方向只取左边五列：右边是小地图和那一片高过头顶的草，
## 取到它们就不是"天是什么颜色"而是"草是什么颜色"了。
##
## 纵向这四行量的是**渐变**，从带顶一路量到最靠近地平线那一行。算出来的 0.321
## 是**海平面地平线**在屏上的位置，而真实的地面轮廓线比它高得多——实测这条带
## 整条都在天上：正午那张从 fy 0.086 的 sRGB(81,104,205) 一路泛白到 fy 0.22 的
## (205,212,221)，再往下才是草地（0.23 起）。
const SKY_ROWS := [0.10, 0.14, 0.18, 0.22]
const SKY_COLS := [0.06, 0.14, 0.22, 0.30, 0.38]

## 「天是不是蓝的」要单独取一行，**不能沿用 SKY_ROWS 的最后一行**。
##
## 最后那行落在**地平线霾**上，而霾是设计成近白的（`DAY_SKY_HORIZON` 本身就是
## (0.72,0.85,0.97) 那一档淡青白）——拿它问"红是不是明显低于蓝"，量到的是
## sRGB(205,212,221)、r/b = 0.93，于是判据红，可天其实蓝得很好。
## 第一版就是这么错的：**同一段渐变它量得出（171→652 的相对亮度，一路上来），
## 同一行取色它量错了**——因为"有没有层次"问的是两端之差、"是不是蓝"问的是单行色相，
## 而两端里靠近地平线的那一端按设计就不蓝。可推广的一条：**同一个取样框上的两个判据
## 不一定量的是同一件事**，取样框对了不代表每条判据都对。
##
## 取 0.12：仍在 `SCRIM_H`(62px = 0.086) 之下，且离草地边沿（≈0.19）还隔着七行。
## 那里正午是 sRGB(92,114,205)、r/b = 0.45；同一行黄昏是 (118,5,8)、r/b = 15.5。
const SKY_HUE_ROW := 0.12

## `verify_mood_mask.gd` 第 9 节声明的「顶栏衬底的最坏背景」，sRGB 口径。
##
## 那边是无头回归，量不到像素，所以"那个数还够不够用"只有这里能量到。
## 它**不是**把那边的常量抄一份来比颜色，而是拿**渲出来的天**去比它声明的亮度——
## 两边不等就是"衬底底下那一带比声明的最坏情况还亮"，那条回归就该重新量了。
## 这个数**不许往下调**：`SCRIM_TOP_ALPHA = 0.90` 当初取值的唯一理由就是那边
## 第 9 节里"最坏背景比字还亮、所以只能靠 alpha 救"这条，而 alpha 的下限
## （≥0.855 才够 4.5:1）是从这个数解出来的。"实测值变好看了"从来不是把
## 下限放低的理由——所以改动之后这里保留原值当一个**故意保守的界**，
## 由上面那条断言去盯真实的天空：一旦天真的亮过它，那边就该重新量，
## 而不是把这儿改小。
const SCRIM_WORST_BG := Color(198.0 / 255.0, 210.0 / 255.0, 237.0 / 255.0)


## WCAG 相对亮度。输入是 sRGB 口径——`Image.get_pixel()` 给的就是 sRGB。
static func _wcag_lum(c: Color) -> float:
	return 0.2126 * _s2l(c.r) + 0.7152 * _s2l(c.g) + 0.0722 * _s2l(c.b)


static func _s2l(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


## **路面**：全场唯一大面积、近水平、朝天的表面，任何一张骑行截图里占 40%~60%，
## 所以它的色相是"第一眼"。框是按 12b 那一档的真实机位量的，不是拍脑袋取的：
## 地平线在 fy 0.321，往下先过中景草地（约 0.45~0.58），沥青从 0.60 起铺满
## 整个下半屏，底栏碎片格在 0.85 以下——所以 0.62~0.82 这一段整块都是裸沥青，
## 横向取 0.12~0.62 避开右侧那条白边线和更外面的路肩砾石带。
const ROAD_BOX := Rect2(0.12, 0.62, 0.50, 0.20)

## **正对照**：同一帧的草地，必须明显偏绿而不是偏蓝。
##
## 没有这一条，"把路面调成纯灰"也能让下面那两条绿——而**纯灰的路面本身就是
## 病**（沥青偏蓝就已经在读成水泥地了，全灰读成的是一条塑料跑道）。
## 框取 fy 0.47~0.55、fx 0.10~0.26：那是路左边的中景草坡，
## 实测 sRGB(162,168,87)、`b−r = −78`，离门槛一个数量级。
const GRASS_BOX := Rect2(0.10, 0.47, 0.16, 0.08)

## 一个框里逐像素的色相统计，返回 `[b−r 的中位数, 饱和度的中位数]`。
##
## **两个量都必须逐像素算完再取中位数，不能"先取各通道的中位数再相减"。**
## 路面中间有白色虚线、边上那条白色实线，而逐通道中位数各自可能被那条白线
## 拉到不同的一侧去——量出来的是一个既不对应任何像素、也不对应任何面的数。
## 逐像素算完再排序，中位数落在**某一个真实像素**上，于是它至少是一个
## 玩家真的看得见的颜色差。同族的一条见 CLAUDE.md：量像素的代码里选错函数
## （`absi` 是整数函数），等于把尺子自己折断了。
func _region_hue(img: Image, box: Rect2) -> Array:
	var x0: int = clampi(int(float(SHOT.x) * box.position.x), 0, SHOT.x - 1)
	var y0: int = clampi(int(float(SHOT.y) * box.position.y), 0, SHOT.y - 1)
	var x1: int = clampi(x0 + int(float(SHOT.x) * box.size.x), 0, SHOT.x)
	var y1: int = clampi(y0 + int(float(SHOT.y) * box.size.y), 0, SHOT.y)
	var brs: Array[float] = []
	var sats: Array[float] = []
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c := img.get_pixel(x, y)
			brs.append(c.b - c.r)
			var mx: float = maxf(c.r, maxf(c.g, c.b))
			var mn: float = minf(c.r, minf(c.g, c.b))
			sats.append((mx - mn) / maxf(mx, 0.001))
	return [_median(brs), _median(sats)]


func _median(v: Array[float]) -> float:
	if v.is_empty():
		return 0.0
	var s: Array[float] = v.duplicate()
	s.sort()
	return s[s.size() / 2]


## 某一行的平均颜色。
func _sky_row(img: Image, fy: float) -> Color:
	var y: int = clampi(int(float(SHOT.y) * fy), 0, SHOT.y - 1)
	var acc := Vector3.ZERO
	for fx in SKY_COLS:
		var p := img.get_pixel(clampi(int(float(SHOT.x) * fx), 0, SHOT.x - 1), y)
		acc += Vector3(p.r, p.g, p.b)
	var m := acc / float(SKY_COLS.size())
	return Color(m.x, m.y, m.z, 1.0)


## 天带里的纵向落差：从带顶那一行到地平线那一点的相对亮度差。
##
## 这就是"天是一整片的"那句话在像素上的样子。实测同一机位同一组天空常量，
## 场景雾画不画天（`fog_sky_affect` 0.3 → 0）、天空色按不按 sRGB 换算，
## 三档量出来是 **7% / 3% / 21%**——门槛取 12%，三档分得开。
func _sky_gradient(img: Image) -> float:
	var lo: float = _sky_row(img, SKY_ROWS[0]).get_luminance()
	var hi: float = _sky_row(img, SKY_ROWS[SKY_ROWS.size() - 1]).get_luminance()
	return absf(hi - lo) / maxf(lo, 0.001)


func _free_scene(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()
	await process_frame
	await process_frame


## 把玩家挪到某个驿站边上，顺手把里程计和邻近状态摆成刚到站的样子。
##
## 摆位必须是玩家**真能站到**的地方。原来写的是「站心 + 3m」，那是建筑内部：
## 站心离路 18m，而边界力在离路 12m 就开始推，玩家最近只能到 6m。
## 于是定妆照里 04/05 两张糊着一面占满画面的墙 —— 车看不见、路看不见、
## 打卡提示被几何挡在后面。这几张图是要给评审看的，它当时把一个
## 玩家遇不到的状态当成了"到站长什么样"。
## 现在按提示圈刚亮那一刻的真实位置摆：站心距 = STATION_PASS_RADIUS - 0.5，
## 站在站心与最近中心线的连线上，正对站。
func _teleport(station_idx: int) -> void:
	_world._close_shop()
	var st: Vector3 = _world._stations[station_idx].position
	var road := _nearest_centerline(st)
	var away := Vector3(st.x - road.x, 0.0, st.z - road.z)
	if away.length() < 0.001:
		away = Vector3(0.0, 0.0, 1.0)
	away = away.normalized()
	_face_station(station_idx, float(_world.STATION_PASS_RADIUS) - 0.5, away)
	_world._last_global_pos = _world._player.global_position
	_world._has_last_pos = true
	_world._nearby_station_idx = -1
	_world._nearby_shop_idx = -1
	_world._interact_cooldown = 0.0
	_world._recheck_armed = true
	_world._nearby_station_dist = 999.0
	_world._nearby_shop_dist = 999.0


## 把车摆到「站心往外 dist 米」的位置，并且**车头对准站**。
##
## 对准这一步是定妆照的前提，不是修饰：相机在车后方沿车头方向看，
## 车头歪着的时候站根本不在画面里——`05c_prompt_贴脸` 曾经拍到一片草地和树行，
## 而它要证明的恰恰是"站贴到脸上时那行提示字不许掉出屏外"。
func _face_station(station_idx: int, dist: float, away := Vector3.INF) -> void:
	var st: Vector3 = _world._stations[station_idx].position
	if away == Vector3.INF:
		var road := _nearest_centerline(st)
		away = Vector3(st.x - road.x, 0.0, st.z - road.z)
		if away.length() < 0.001:
			away = Vector3(0.0, 0.0, 1.0)
		away = away.normalized()
	var p: Vector3 = st - away * dist
	p.y = _world._get_terrain_height(p.x, p.z)
	_world._player.global_position = p
	# Player3D 的前方是 -basis.z，所以要车头指向站，角度得取反再转半圈
	_world._player.global_rotation = Vector3(0.0,
			atan2(st.x - p.x, st.z - p.z) + PI, 0.0)
	_world._nearby_station_idx = -1
	_world._nearby_shop_idx = -1
	_world._interact_cooldown = 0.0
	_world._recheck_armed = true
	_world._nearby_station_dist = 999.0
	_world._nearby_shop_dist = 999.0


func _nearest_centerline(p: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var bd := 1e9
	for cl in _world._road_builder.get_all_centerlines():
		for q in cl:
			var d: float = Vector2(q.x - p.x, q.z - p.z).length()
			if d < bd:
				bd = d
				best = q
	return best


## 挪到离所有「还欠一次到访」的碎片驿站都最远的路面上。
##
## 反派戏的落点闸（`World3D._too_close_to_target()`）就是拿这个距离判的，
## 所以拍反派戏的那一屏必须站到它真的会起播的地方——否则拍出来的是"没触发"
## 的空画面，而那正是这一屏唯一需要看的东西。
func _teleport_open_road() -> Vector3:
	var best := Vector3.ZERO
	var best_d := -1.0
	for line in _world._road_builder.get_all_centerlines():
		for p in line:
			var d := 1e9
			for i in _world._stations.size():
				if not _gm.fragment_station_needs_visit(i):
					continue
				var sp: Vector3 = _world._stations[i].position
				d = minf(d, Vector2(p.x - sp.x, p.z - sp.z).length())
			if d > best_d:
				best_d = d
				best = p
	var pos := Vector3(best.x, _world._get_terrain_height(best.x, best.z), best.z)
	_world._player.global_position = pos
	_world._last_global_pos = _world._player.global_position
	_world._has_last_pos = true
	_world._nearby_station_idx = -1
	_world._nearby_shop_idx = -1
	_world._interact_cooldown = 0.0
	_world._recheck_armed = true
	_world._nearby_station_dist = 999.0
	_world._nearby_shop_dist = 999.0
	return pos


func _push_space() -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_SPACE
		ev.physical_keycode = KEY_SPACE
		ev.pressed = pressed
		Input.parse_input_event(ev)


## 「下一处」的方向箭头必须真的在指方向，而不只是显示站名和距离。
##
## 要拦的是这一种失败：8 字环自闭合，骑反了距离会一直不变，玩家在交叉点上
## 完全看不出自己骑反了。所以把车头硬掰到"背对目标"那一侧，标签里必须出现 ↓；
## 再掰回正对，必须变成 ↑。只测 HUD3D._arrow_glyph 那个 static 等于拿自己测自己，
## 这里走的是真 HUD 真玩家真 RoadData。
func _check_next_target_arrow() -> void:
	var hud = _world._hud3d
	var player = _world._player
	if hud == null or player == null:
		_ck("方向箭头：拿到 HUD 与玩家", false)
		return
	var t: Dictionary = hud._next_fragment_target()
	if t.is_empty():
		_ck("方向箭头：有一处未收的碎片驿站", false)
		return
	var target: Vector3 = hud._road_data.get_station_world_pos(t["idx"])
	var to: Vector3 = target - player.global_position
	to.y = 0.0

	# 车头正对目标 → ↑
	player.look_at(target, Vector3.UP)
	hud._update_next_label()
	_ck("车头正对目标时箭头是 ↑", _arrow_in(hud._next_label.text) == "↑", _arrow_in(hud._next_label.text))

	# 车头背对目标 → ↓
	player.look_at(player.global_position - to, Vector3.UP)
	hud._update_next_label()
	_ck("车头背对目标时箭头是 ↓", _arrow_in(hud._next_label.text) == "↓", _arrow_in(hud._next_label.text))

	# 车头正右方 → →
	player.look_at(player.global_position + Vector3(to.z, 0.0, -to.x), Vector3.UP)
	hud._update_next_label()
	_ck("目标在正右方时箭头是 →", _arrow_in(hud._next_label.text) == "→", _arrow_in(hud._next_label.text))


## 底栏那五格：未收的时候**看得见自己在收集什么吗**。
##
## 原来未收的一格画的是「灰圆盘 + 同一个灰的图标 + 一个灰的问号」——
## 图标被问号整个盖住，于是五格在图上是五个一模一样的灰方块，
## 玩家只知道"还差 5 个"，不知道那 5 个是什么、哪一格是下一处要去的那件。
## （`.tscn` 里每个 Slot 底下还挂着一个写着全角问号的占位 Label，
## 屏上于是同时有两个问号，一个在盘心、一个在名字那一行。）
##
## 判据分**两条通道**，取并集：盘边那一圈环的**颜色**、盘内图标的**形状**。
## 这是玩家真正用的两条——22px 的盘上那五个图标本来就得凑近才认得出轮廓，
## 而"下一处要去的是哪一件"是扫一眼就要知道的，所以产品那一侧也是这么改的：
## 细线交给"凑近看"，环交给"扫一眼看"。
##
## 只量颜色不成立：茶(8FB35A) 与竹(6E9C6B) 本来就是两块很近的绿，环上量出来
## 只差 0.015，而它们靠形状（杯 / 竹）分开——这是设计好的，不是缺陷。
## 只量形状也不成立：图标退回同一个灰，形状照样两两不同，可五格于是又是
## "五块一样的灰方块里各画一件不同的东西"，扫一眼仍然分不出谁是谁。
## 两条一起量才对得上"玩家分不分得开"这句话。
##
## 这一族的前两版都量错了，错法是同一个：**量了一个不是玩家读的那个量**。
## ①第一版量「40×40 框里饱和度 ≥0.10 的像素占几成」，门槛 3%，报 55.9%；
## 突变把图标退回纯灰之后它报 57.9% 照样全绿——槽底板是半透明的、底下就是
## 3D 场景，蓝天和草地从盘外渗进来，量的是背景。
## ②第二版把圆盘改成不透明、改量「盘内半径 15px 的平均色两两差 ≥0.05」，
## 背景是挡住了，可图标只有 1~2px 的细线，摊在 700 多个像素里被稀释到
## 0.004，两两差只剩 0.025——门槛立不住，不是产品坏了，是尺子太粗。
## ③现在两条通道都取"整片"而不是"细线平均"：环是一整圈连续的色，
## 形状是一整片墨，两边都是一个像素就是一个值，不存在稀释。
##
## 取样用 Slot 自己的 `get_global_rect()`，**不许拿 120px 间距手算**：
## `HBox` 是 `alignment = 1`（居中）而 Slot 的 `custom_minimum_size` 才是 120，
## 实测间距 124、盘心 (392/516/640/764/888, 660)。手算的那一版差 8~28px，
## 量到的是隔壁那格。
##
## 实测：颜色分得开 5/10 对、形状 10/10 对（0.227~0.410）。
## 纯灰那一版：颜色 0/10、形状 ~0。
func _check_fragbar_slots_coloured(img: Image) -> void:
	var fb: Node = _world.get_node_or_null("FragmentBarLayer/FragmentBar")
	if fb == null:
		_ck("底栏五格未收时各带自己的颜色", false, "找不到 FragmentBar 节点")
		return
	var row: Node = fb.get_node_or_null("HBox")
	if row == null:
		_ck("底栏五格未收时各带自己的颜色", false, "FragmentBar 下没有 HBox")
		return
	# 环：`FragmentBar.RIM_W` 那一圈**盘外**的实心色盘（圆盘 22 + 5 = 27），
	# 取 23~26.5。**取盘外不是为了好看，是为了量得到环自己**：云是实心多边形、
	# 竹的梢伸到半径 25，盘内 19~21 那一圈被它们压住，把环退回灰色照样量到
	# "五格分得开"（那次突变就是这么溜过去的）。这一圈里没有一根图标笔画。
	const R_IN := 23.0
	const R_OUT := 26.5
	# 形状：盘内半径 15px（图标都在这一圈里，色盘和角标都在外面）
	const R_ICON := 15.0
	var rings: Array = []
	var inks: Array = []
	for i in row.get_child_count():
		var slot: Control = row.get_child(i)
		var rect: Rect2 = slot.get_global_rect()
		var ctr := rect.position + rect.size * 0.5
		var ring_acc := Vector3.ZERO
		var ring_n := 0
		var lums: Array = []
		var offs: Array = []
		for dy in range(-28, 29):
			for dx in range(-28, 29):
				var ix: int = clampi(int(ctr.x) + dx, 0, img.get_width() - 1)
				var iy: int = clampi(int(ctr.y) + dy, 0, img.get_height() - 1)
				var c: Color = img.get_pixel(ix, iy)
				var d: float = sqrt(float(dx * dx + dy * dy))
				if d >= R_IN and d <= R_OUT:
					ring_acc += Vector3(c.r, c.g, c.b)
					ring_n += 1
				if float(dx * dx + dy * dy) <= R_ICON * R_ICON:
					lums.append(0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
					offs.append(Vector2i(dx, dy))
		if ring_n == 0 or lums.is_empty():
			_ck("底栏第 %d 格的取样框取到像素" % (i + 1), false, "环或盘内没采到像素")
			return
		rings.append(ring_acc / float(ring_n))
		# 墨 = 比**这一格自己的中位亮度**高 0.035 以上。用中位数而不是某个常数：
		# 底栏底下是 3D 场景加一层心神遮罩，同一个 0.13 的盘在草地上读成 0.20、
		# 在沥青上读成 0.09，写死一个阈值有一半的机位是错的。
		#
		# **阈值从排序后的表上取，掩码必须回到空间顺序上填。**第一版直接在
		# `lums.sort()` 之后按 k 生成掩码，于是两格比的是"第 k 暗的像素对第 k 暗的
		# 像素"——那比的是**亮度分布**，不是形状，五格各画各的却报出 0.014 的
		# "形状差"。判据量错了东西的时候它不会红，它会安静地报一个很小的数。
		lums.sort()
		var med: float = lums[lums.size() / 2]
		var ink := PackedByteArray()
		ink.resize(lums.size())
		for k in offs.size():
			var o: Vector2i = offs[k]
			var ix2: int = clampi(int(ctr.x) + o.x, 0, img.get_width() - 1)
			var iy2: int = clampi(int(ctr.y) + o.y, 0, img.get_height() - 1)
			var c2: Color = img.get_pixel(ix2, iy2)
			var l2: float = 0.2126 * c2.r + 0.7152 * c2.g + 0.0722 * c2.b
			ink[k] = 1 if l2 > med + 0.035 else 0
		inks.append(ink)

	var worst := ""
	var bad := 0
	var by_colour := 0
	for i in inks.size():
		for j in range(i + 1, inks.size()):
			var cd: float = (rings[i] as Vector3).distance_to(rings[j] as Vector3)
			var ink_i: PackedByteArray = inks[i]
			var ink_j: PackedByteArray = inks[j]
			var diff := 0
			for k in ink_i.size():
				if ink_i[k] != ink_j[k]:
					diff += 1
			var sd: float = float(diff) / float(ink_i.size())
			if cd >= 0.05:
				by_colour += 1
			if cd < 0.05 and sd < 0.05:
				bad += 1
				worst += " %d/%d(色 %.3f 形 %.3f)" % [i + 1, j + 1, cd, sd]
	_ck("底栏五格未收时两两分得开（颜色或形状至少有一条够）", bad == 0,
			"分不开的有 %d 对：%s" % [bad, worst])
	# 正对照。**只写上面那一条的话，一个把环画成纯灰的版本照样全绿**——
	# 形状那一路还是十对全过。可推广的一条：并集里的每一路都得单独配一条
	# "这一路真的在承重"的断言，否则它可以悄悄死掉而没人知道。
	# 门槛取 3（实测 5）：要能抓住"环整条退成灰"（0 对），又留得住渲染上的浮动。
	_ck("底栏五格的环真的在承重（靠颜色分开的 ≥3 对）", by_colour >= 3,
			"实际 %d/10 对" % by_colour)


func _arrow_in(label_text: String) -> String:
	for a in ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]:
		if label_text.contains(a):
			return a
	return ""


## 车必须在画面里，而且要够大。
##
## 这条是被"看不到车"那句评审意见逼出来的，但量完发现车一直都在：
## 世界 AABB 1.52×1.68×2.58m，投影 182×226px（屏宽的 14%、屏高的 31%），
## 全速 15m/s 与静止完全一样（相机的 lerp 在 60FPS 下稳态滞后就是设计值 6.0m）。
## 当初看不出来是因为**定妆照把玩家摆在了建筑内部**（见 _teleport），
## 一面米色墙糊满画面，什么都看不见 —— 是量具的问题，不是车的问题。
## 那条 0.6 的对白遮罩又叠了一层，把整个世界压成近黑（已改成 0.30）。
## 这里把"车在屏内且够大"钉死，免得以后再被机位问题连累。
func _check_bike_on_screen() -> void:
	var cam: Camera3D = _world._player.get_node_or_null("Camera3D")
	if cam == null:
		_ck("车在屏内：拿到相机", false)
		return
	var meshes: Array = []
	_collect_meshes(_world._player, meshes)
	if meshes.is_empty():
		_ck("车在屏内：玩家身上有网格", false)
		return
	var all := AABB()
	var first := true
	for m in meshes:
		var mi: MeshInstance3D = m
		var b: AABB = mi.global_transform * mi.get_aabb()
		if first:
			all = b
			first = false
		else:
			all = all.merge(b)
	var vs: Vector2 = cam.get_viewport().get_visible_rect().size
	var minx := 1e9
	var maxx := -1e9
	var miny := 1e9
	var maxy := -1e9
	for i in range(8):
		var p: Vector2 = cam.unproject_position(all.get_endpoint(i))
		minx = min(minx, p.x)
		maxx = max(maxx, p.x)
		miny = min(miny, p.y)
		maxy = max(maxy, p.y)
	var bw := maxx - minx
	var bh := maxy - miny
	_ck("车整个在画面内（%.0f,%.0f)-(%.0f,%.0f / 屏 %s）" % [minx, miny, maxx, maxy, str(vs)],
			minx >= 0.0 and miny >= 0.0 and maxx <= vs.x and maxy <= vs.y)
	# 低于 100px 高就等于"看得见但认不出是辆车"，评审看到的就是一条黑线
	_ck("车在画面里够大（%.0f×%.0fpx，至少要 100px 高）" % [bw, bh], bh >= 100.0)
	_ck("车的画面位置（车心 %s，相机 %s，距离 %.2fm，俯角 %.1f°）" % [
			str(all.get_center()), str(cam.global_position),
			cam.global_position.distance_to(all.get_center()),
			rad_to_deg(atan2(cam.global_position.y - all.get_center().y,
					Vector2(cam.global_position.x - all.get_center().x,
					cam.global_position.z - all.get_center().z).length()))],
			true)


func _collect_meshes(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_collect_meshes(c, out)


## 拍到站的图之前，先证明这一站的车是**真能骑到的位置**上拍的。
##
## 站心离路 18m，边界力（SOFT_BOUND=12m）会把玩家推回来，所以玩家最近只能到
## 站心 6m。摆位一旦比这更近，拍出来的就不是玩家会看到的画面 —— 而这正是当初
## "到站看不见车、看不见路"的来源。这里把摆位钉死在真可达范围内。
func _check_arrival_reachable(station_idx: int) -> void:
	var p: Vector3 = _world._player.global_position
	var st: Vector3 = _world._stations[station_idx].position
	var road := _nearest_centerline(st)
	var d_station := Vector2(p.x - st.x, p.z - st.z).length()
	var d_road := Vector2(p.x - road.x, p.z - road.z).length()
	_ck("到站机位是真可达的（离路 %.1fm ≤ 软边界 %.0fm）" % [d_road, _world.SOFT_BOUND],
			d_road <= float(_world.SOFT_BOUND) + 0.01)
	# 而且必须真的在判定半径内，否则提示圈根本没亮，那张图也不算数
	_ck("到站机位确实触发了判定（站心距 %.1fm < 半径 %.0fm）" % [
			d_station, _world.STATION_PASS_RADIUS],
			d_station < float(_world.STATION_PASS_RADIUS))


func _run() -> void:
	print("=== 新玩家全流程定妆照 ===")
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	# ---- 01 标题页（主场景 GiftBox）----
	var gift = load("res://scenes/GiftBox.tscn").instantiate()
	root.add_child(gift)
	await create_timer(WAIT_SEC).timeout
	await _snap("01_title_标题页")
	await _free_scene(gift)

	# ---- 02 操作说明（新玩家进 3D 的第一屏）----
	_gm.onboarding_shown = false
	_gm.headless_mode = true      # 别让它自己往下走序章，先单独拍操作说明
	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	await create_timer(WAIT_SEC).timeout
	_ck("World3D 起了 16 座驿站", _world._stations.size() == 16)
	await _snap("02_onboarding_操作说明")

	# ---- 03 序章对白 ----
	_gm.onboarding_shown = true
	_gm.prologue_done = false
	_world._headless_mode = false
	_world._onboarding.visible = false
	var lines := [
		_loc.t("prologue_1"), _loc.t("prologue_2"), _loc.t("prologue_3"),
	]
	_world._dialogue_popup.setup(_loc.t("prologue_speaker"), lines, false)
	_world._dialogue_popup.visible = true
	await create_timer(0.6).timeout
	await _snap("03_prologue_序章对白")
	_world._dialogue_popup.visible = false
	_gm.mark_prologue_done()
	# 序章把玩家冻住了，而本脚本要拍的是"玩家已经在路上"的那些屏。
	# 不放回来的话 Player3D._update_camera 整个不会跑，相机永远不跟传送走，
	# 于是后面每一张站点的图都是"相机停在传送前"的样子。
	_world._player.set_can_move(true)
	_world._player.set_camera_locked(false)

	# ---- 04 骑行中的 HUD ----
	_teleport(0)
	await create_timer(1.0).timeout
	_check_next_target_arrow()
	_check_arrival_reachable(0)
	_check_bike_on_screen()
	var img_ride: Image = await _snap("04_ride_骑行中")
	_check_fragbar_slots_coloured(img_ride)

	# ---- 04a 暂停面板：唯一一处改过行数的地方 ----
	# 画质档位往这一列里加了一个按钮和一行提示，而 VBox 装不下时**不报错**，
	# 只把最下面那两行顶出面板下沿——最下面那两行正好就是新加的那两行。
	# 尺寸断言量的是"VBox 最小高度 ≤ 面板内容区"，量不到那行 12px 的字在
	# 画面上读不读得出来，所以这一屏要图。
	#
	# **英文那一屏才是卡边的一份**：提示 33 个中文字占 396px，一行放得下；
	# 英文 108 个字符约 650px，同一个框宽下折成两行。只拍中文的话英文界面
	# 下的排版就没人看着了。
	var panel: Control = _world.get_node_or_null("PausePanel")
	if panel != null:
		# 走**真的** `toggle_pause()`，不要直接写 `visible = true`：这一屏要拍的
		# 是"玩家按 ESC 之后看到的那一屏"，而直接置 visible 跳过了 `set_can_move`
		# 与音频那一整套，底下的世界会停在一个玩家根本看不到的状态上。
		_world.toggle_pause()
		await _snap("04a_pause_暂停面板")
		_loc.set_language("en")
		panel.call("_apply_language")
		await _snap("04a_pause_EN")
		_loc.set_language("zh")
		panel.call("_apply_language")
		_world.toggle_pause()

	# ---- 04b 反派戏打断：入场提示 + 镜头收束 ----
	# 这一屏以前一张图都没有：`lookdev_journey` 开头就把 `seen_villain` 顶到 3
	# 把三场全跳过去了，于是新增的入场提示只有数字守着、没有图守着。
	# 提示是一句"手机响了。"——它压在玩家正看着的骑行画面上，
	# 位置/底板/和顶栏的关系只有看图才知道。
	for i in [0, 1, 2, 3]:
		_gm.on_station_pass(i)
	var open_v: Vector3 = _teleport_open_road()
	_world._villain_armed = [true, true, true]
	# 断言必须等它真的起播：`_try_villain_scene()` 是在 `_physics_process` 的
	# 末尾判的，瞬移完同一帧去读必然还读不到。
	var t_v := Time.get_ticks_msec()
	while not _world._villain_playing and Time.get_ticks_msec() - t_v < 3000:
		await process_frame
	_ck("反派戏真的起播了（不然这一屏拍的是空画面）",
			_world._villain_playing, "位置 %s" % str(open_v))
	await create_timer(1.0).timeout
	await _snap("04b_villain_打断入场")
	# 整场推完，把相机和操作权还回去——不然后面每一屏都停在被冻住的镜头上。
	var guard_v := Time.get_ticks_msec()
	while _world._villain_playing and Time.get_ticks_msec() - guard_v < 20000:
		_push_space()
		await process_frame
		_push_space()
		await process_frame
	_ck("反派戏推完后相机锁还回去了", not _world._player.is_camera_locked(),
			"locked=%s" % str(_world._player.is_camera_locked()))
	await create_timer(0.5).timeout

	# ---- 05 靠近碎片驿站：地面提示 ----
	_teleport(4)
	await create_timer(1.0).timeout
	_ck("碎片站 4 有打卡提示", _world._check_in_prompt.visible)
	_check_arrival_reachable(4)
	_check_bike_on_screen()
	await _snap("05_prompt_打卡提示")

	# 05c 贴到墙外最近的那一点：站点的投影被推到画面下半，提示文字最容易掉出屏外。
	# 只拍可送达机位那张的话这一屏永远看不出来，而那恰恰是玩家最该读到按键提示的一刻。
	# 「最近」按 `station_keepout_radius()` 算——车骑不进亭子的占地，
	# 这一张就是玩家真能停到的极限机位，不是硬写的 1.2m 那种到不了的姿势。
	var r_close: float = _world.station_keepout_radius(4)
	_face_station(4, r_close + 0.6)
	_world._last_global_pos = _world._player.global_position
	await create_timer(1.0).timeout
	_ck("贴脸时提示圈还在", _world._check_in_prompt.visible)
	await _snap("05c_prompt_贴脸")

	# ---- 05d 回访：三处都要说出"还差几次" ----
	# 完满评级要求每座碎片驿站去过 MAX_VISITS 次。可这一屏以前什么都不说：
	# 顶栏在第一次拿到碎片之后就把"下一处"摘掉了，底栏的碎片格收过之后三次
	# 长得一模一样，脚下提示圈还写着"歇一脚"。三处都不改的话，全游戏最强的
	# 重玩钩子在画面上根本不存在。
	_gm.collected[4] = 1
	await create_timer(0.8).timeout
	_ck("回访时顶栏说的是「再访 · 还差 2 次」",
			str(_world._hud3d._next_label.text).contains(_loc.t("visits_left_n") % 2),
			str(_world._hud3d._next_label.text))
	var cp = _world._check_in_prompt
	var tgt: Array = cp._prompt_target()
	_ck("回访时脚下提示圈写的是还差几次",
			not tgt.is_empty() and str(cp._label(tgt)).contains(
					_loc.t("desktop_revisit_prompt") % 2),
			"圈上写着：%s" % str(cp._label(tgt)))
	await _snap("05d_revisit_回访提示")
	_gm.collected[4] = 0

	# ---- 05b 路过风景驿：浮一句它自己的话 ----
	# 站 1 是非碎片、非铺子的普通驿，HUD 会在进圈那一帧浮出 road_data 里那行 text。
	# 这一屏专门拍它：这套话玩家以前一次也读不到（只有打卡弹窗读，而普通驿不能打卡），
	# 所以必须有一张图能判"浮出来了、没压住别的东西、3 秒后自己收走"。
	_teleport(1)
	await create_timer(1.0).timeout
	_ck("路过普通驿时浮出了那一行", str(_world._hud3d._pass_label.text) != "",
			"text=" + str(_world._hud3d._pass_label.text))
	await _snap("05b_pass_路过风景驿")
	await create_timer(3.0).timeout
	_ck("3.2 秒后那行自己收走", str(_world._hud3d._pass_label.text) == "")
	_teleport(4)
	await create_timer(0.5).timeout

	# ---- 06 驿站对白 ----
	var rd = load("res://scripts/road_data.gd").new()
	var dlines = rd.station_dialogue(4)
	_world._dialogue_popup.setup(_world._station_name(4), dlines, false)
	_world._dialogue_popup.visible = true
	await create_timer(0.6).timeout
	await _snap("06_dialogue_驿站对白")
	_world._dialogue_popup.visible = false

	# ---- 07..11 五个小游戏 ----
	# 走 World3D._run_mini_game() 同一套挂载方式，只是不同步等它结束，
	# 拍完自己收掉，免得 check-in 的 await 链被拖住。
	for idx in [4, 7, 10, 13, 14]:
		var info: Dictionary = MG[idx]
		var mg = load(str(info["script"])).new()
		mg._world_ref = _world
		mg.set_anchors_preset(Control.PRESET_FULL_RECT)
		mg.focus_mode = Control.FOCUS_ALL
		# 背板/藏顶栏走 World3D 自己那对方法，别在这里重演一遍：这里重演的话，
		# 改游戏那一屏时定妆照会拍到旧版，玩家和评审看到的就不是真东西。
		_world._push_mini_game_chrome()
		_world._mini_game_layer.add_child(mg)
		mg.grab_focus()
		# 云/禽是"先看再答"，给它一点时间进到要作答的那一屏
		await create_timer(1.6 if int(idx) in [4, 7] else 0.9).timeout
		await _snap("minigame_%s" % str(info["name"]))
		_world._pop_mini_game_chrome()
		mg.queue_free()
		await process_frame

	# ---- 12 小铺 ----
	_gm.lvbi = 120
	_teleport(0)
	await create_timer(0.8).timeout
	_world._open_shop(int(_world._nearby_shop_idx))
	await create_timer(0.6).timeout
	_ck("驿铺面板开了", _world._shop_panel.visible)
	await _snap("12_shop_驿铺")
	_world._close_shop()

	# ---- 12b/12c 正午 vs 黄昏：同一机位两张 ----
	# 这一屏没法用别的办法验。光照全在环境层，headless 的 dummy renderer 拍不出
	# 颜色；而 DayCycle 那几个黄昏常量是照着断言挑的、不是照着渲出来的图挑的 ——
	# AGX 会把中间调提亮并去饱和，数字全对也完全可能渲成一片橙的糊。这条改动
	# 动了太阳方向、环境光、雾、远景山线四样，只有看图能判它们凑在一起对不对。
	#
	# _odometer_units 是**累加器**（World3D 只在玩家位移时往上加），所以站着不动
	# 把它摆到门槛之后 0.5 圈就成立，转场期间玩家没动它也不会被改回去。
	# 跟着 `DUSK_FROM_LAP` 走而不是写死一个圈数：门槛一挪（现在 2.0 → 1.0，
	# 因为一趟从 20~30 分钟缩到 3.1 分钟），这一屏得跟着代表"玩家真的会看到的那一段"。
	_world._odometer_units = (_world._day_cycle.DUSK_FROM_LAP + 0.5) * _world._total_arclen
	# 机位必须是**真实跟随相机**（Player3D._update_camera 的第三人称机位）。
	# 旧版把人按到离地 1m 处平视，拍出来是一堵草墙：车小到只剩一个红点，
	# 地平线压在画面上沿，判不出黄昏到底把光打成了什么样——而这正是这一屏
	# 唯一存在的理由。停到路面上、车头顺着路走，真相机会自己落到车后上方，
	# 于是前景是路、中景是车、远景是山和天，三样都量得到。
	var rd_dusk: Object = _world._road_builder.get_road_data()
	var pts: Array = rd_dusk.points
	var di: int = int(pts.size() * 0.18)
	var p_on: Vector3 = pts[di]
	var fwd: Vector3 = pts[(di + 1) % pts.size()] - pts[di - 1]
	fwd.y = 0.0
	fwd = fwd.normalized()
	_world._player.position = p_on
	_world._last_global_pos = _world._player.global_position
	_world._has_last_pos = true
	_world._player.look_at(p_on + fwd * 100.0, Vector3.UP)
	_world._player.set_camera_locked(false)
	# 相机是 lerp(0.12) 跟过去的，等它真的落位再拍，
	# 不然拍到的是"相机还在半路上"的中间态。
	await create_timer(1.5).timeout
	# 这两张图的全部意义就是看光，所以车必须在画面里且够大，
	# 否则"天变了没有"和"车去哪了"分不开。
	_check_bike_on_screen()
	# 正午那一张要和黄昏那张**同一个机位**，否则两帧之间混进了机位差，
	# 看的人分不清哪些变化是天色给的、哪些是视角给的。
	var img_day: Image = await _snap("12b_day_正午")
	# 转场 9 秒（DayCycle.FADE_SEC），按墙钟等 —— 这台机器帧数不等于秒数
	await create_timer(11.0).timeout
	var dusk_t: float = float(_world._day_cycle.get_t())
	_ck("骑满一圈之后天色真的走到黄昏（不是还在半路上）", dusk_t == 1.0,
			"t=%f" % dusk_t)
	# 太阳压到 9° 之后影子该拉得很长，而且方向和正午那档差了一截。
	# 这一屏不校验数字（verify_day_cycle.gd 已经逐条量过了），只看整张图凑不凑。
	var img_dusk: Image = await _snap("12c_dusk_黄昏")

	# ---- 12d 那条天带在像素上到底有没有层次 ----
	#
	# 这一族是本项目最典型的"数字全绿而画面是坏的"：`ProceduralSkyMaterial`
	# 的每个旋钮都设了、`DayCycle` 的黄昏常量全对、`verify_day_cycle.gd` 逐条
	# 量过颜色和方向——而天是一整片灰蓝纸。原因有两个，都是**只有像素能量到**的：
	#   ① 场景的雾画天（`fog_sky_affect` 0.3 + 近白的雾色）；
	#   ② 天空色在引擎里是辐照度、直接当线性值用，而那六个常量照着显示器写成
	#      了 sRGB——`DAY_SKY_HORIZON` 渲出来接近纯白，再被 AGX 的高光肩去一次饱和。
	# 而"天是蓝的还是灰的""黄昏有没有烧起来"这两件事，也没有任何一个常数能量。
	_ck("正午那档的天在像素上是有层次的，不是「一整片」（带内纵向落差 ≥ 12%）",
			_sky_gradient(img_day) >= 0.12,
			"实测 %.0f%%  顶行 %s 地平线行 %s" % [_sky_gradient(img_day) * 100.0,
			str(_sky_row(img_day, SKY_ROWS[0])), str(_sky_row(img_day,
			SKY_ROWS[SKY_ROWS.size() - 1]))])
	_ck("黄昏那档的天在像素上也是有层次的（上暗下亮）",
			_sky_gradient(img_dusk) >= 0.12,
			"实测 %.0f%%  顶行 %s 地平线行 %s" % [_sky_gradient(img_dusk) * 100.0,
			str(_sky_row(img_dusk, SKY_ROWS[0])), str(_sky_row(img_dusk,
			SKY_ROWS[SKY_ROWS.size() - 1]))])
	# 下面两条问的是**色相**，取样行是 SKY_HUE_ROW 而不是 SKY_ROWS 的末行——
	# 理由写在那个常量上：末行落在设计成近白的地平线霾上，量到的是霾不是天。
	# 「正午到黄昏只有曝光变化」这句话的判据就在这里：如果黄昏只是把正午调暗，
	# 那么两档的**红蓝比**会差不多。真的走到黄昏，那一行该由红压过蓝。
	var day_row: Color = _sky_row(img_day, SKY_HUE_ROW)
	var dusk_row: Color = _sky_row(img_dusk, SKY_HUE_ROW)
	_ck("正午那档的天真的是蓝的（红明显低于蓝，不是被洗成灰白）",
			day_row.r < day_row.b * 0.75,
			"y 比例 %.2f  r=%.0f b=%.0f 比 %.2f" % [SKY_HUE_ROW, day_row.r * 255.0,
			day_row.b * 255.0, day_row.r / maxf(day_row.b, 0.001)])
	_ck("走到黄昏是换了颜色而不是只降了曝光（同一行由红压过蓝）",
			dusk_row.r > dusk_row.b,
			"正午 %s → 黄昏 %s" % [str(day_row), str(dusk_row)])
	# 上一条只判**方向**，于是它对"红压过蓝"这件事的**程度**完全免疫：
	# 实测那一行是 sRGB(0.377, 0.007, 0.030) 时它照样绿——0.377 > 0.030。
	# 而那一行之所以是那样，是因为 Godot 4 的 `ProceduralSkyMaterial` 只有物理
	# 散射一种模型，`sky_horizon_color` 是**乘在散射结果上的滤镜**而不是天色：
	# 太阳压到 9° 时散射自己就是深红带，再乘一层饱和橙，两个红相乘、
	# 小通道被压两遍，绿和蓝在物理上归零。渲出来是一张红色滤色片而不是天。
	# 成因那一条（滤镜不许自己先饱和）在 `verify_day_cycle.gd` 里，
	# 这里量的是**结果**——两档的天都得留住自己的次通道，
	# 判据是"次通道压过主通道的百分之几"，不是"谁大谁小"。
	var dusk_gr: float = dusk_row.g / maxf(dusk_row.r, 0.001)
	var dusk_br: float = dusk_row.b / maxf(dusk_row.r, 0.001)
	_ck("黄昏的天留住绿与蓝（不是一张红色滤色片）",
			dusk_gr >= 0.10 and dusk_br >= 0.10,
			"g/r=%.3f b/r=%.3f  实测 %s" % [dusk_gr, dusk_br, str(dusk_row)])
	# 正对照：正午那档**绿蓝都压过红**，黄昏这一档**绿蓝都被红压过**。
	# 第一版写的是 `(day.b > day.r) != (dusk.r > dusk.b)`——那正好是上面两条
	# 断言各自已经钉死的那一件事，于是两个布尔量恒相等，这条**恒红**：
	# 它量的是"两条断言有没有都成立"，不是"两档天是不是两档色相"。
	# 改成**加绿那一路**：上面三条一次都没碰过 g，所以
	# 「黄昏发暗绿/橄榄」（r>g>b，b/r 和 g/r 都合规）这一档只有这条拦得住。
	_ck("黄昏的天和正午的天不是同一档色相（一档蓝绿、一档暖红）",
			day_row.g > day_row.r and day_row.b > day_row.r
			and dusk_row.g < dusk_row.r and dusk_row.b < dusk_row.r,
			"正午 (r=%.3f g=%.3f b=%.3f)  黄昏 (r=%.3f g=%.3f b=%.3f)"
			% [day_row.r, day_row.g, day_row.b, dusk_row.r, dusk_row.g, dusk_row.b])
	# 跨脚本的一条：顶栏衬底声明的最坏背景（verify_mood_mask.gd 第 9 节）还够用吗。
	# 取 SKY_ROWS[0] 那一行，因为它正好落在衬底下沿（fy 0.086）之下几像素——
	# 衬底自己的 alpha 在那里已经淡到接近 0，量到的基本就是裸天，
	# 而"衬底底下有多亮"问的正是裸天。
	var band_day: Color = _sky_row(img_day, SKY_ROWS[0])
	var band_dusk: Color = _sky_row(img_dusk, SKY_ROWS[0])
	var bg_lum: float = _wcag_lum(SCRIM_WORST_BG)
	_ck("顶栏衬底声明的最坏背景还够用（衬底底下那一带真的比它暗）",
			_wcag_lum(band_day) < bg_lum and _wcag_lum(band_dusk) < bg_lum,
			"声明 %.3f（sRGB %s）  正午实测 %.3f  黄昏实测 %.3f" % [bg_lum,
			str(SCRIM_WORST_BG), _wcag_lum(band_day), _wcag_lum(band_dusk)])

	# ---- 12e 路面本身的色相 ----
	#
	# 这一族是"数字全绿而画面是坏的"里最容易被漏掉的一个：路面着色器里
	# 每个常量都取自实测沥青样本、每条无头回归都量的是源码文本，
	# 而渲出来的沥青**蓝得发紫**，读成的是水泥地不是路面。
	# 第五轮已经把三个成因逐一排除（EMISSION 归零纹丝不动、
	# `ambient_light_sky_contribution` 归到 0.62 并转暖后逐像素不变、
	# `SPECULAR = 0` 只掉 3 个单位），所以剩下的是漫反射本身。
	#
	# 阈值 12 与 0.12 都取自实测基线的**一半**：实测 `b−r` 中位数 25、
	# 饱和度 0.263，所以 12 / 0.12 各自留着两倍余量——渲染管线动一次
	# （换 tonemap、换环境光）不至于当场翻面，而现在的这一档离门槛两倍远。
	var road: Array = _region_hue(img_day, ROAD_BOX)
	_ck("正午路面不偏蓝（|b−r| 中位 ≤ 12，现在读成的是水泥地不是沥青）",
			absi(int(round(road[0] * 255.0))) <= 12,
			"实测 b−r = %+.0f（%d 像素的中位数）" % [road[0] * 255.0,
			int(float(SHOT.x) * ROAD_BOX.size.x) * int(float(SHOT.y) * ROAD_BOX.size.y)])
	_ck("正午路面自己的饱和度收敛（中位 ≤ 0.12）", road[1] <= 0.12,
			"实测 %.3f" % road[1])
	# 正对照：同一帧的草地必须明显偏绿。
	# 少了它，上面两条只钉住"路面不是蓝的"，而"路面是灰的"照样全绿。
	var grass: Array = _region_hue(img_day, GRASS_BOX)
	_ck("正对照：同一帧的草地明显偏绿（|b−r| ≥ 25，尺子分得开蓝和绿）",
			absi(int(round(grass[0] * 255.0))) >= 25,
			"实测 b−r = %+.0f  饱和度 %.3f" % [grass[0] * 255.0, grass[1]])

	# ---- 13 集齐合成 ----
	_gm.seen_villain = 3
	for i in _world._stations.size():
		_gm.seen_stations[i] = true
	for i in [4, 7, 10, 13, 14]:
		_gm.check_in(i)
	_world._on_all_collected()
	await create_timer(1.2).timeout
	await _snap("13_collect_集齐合成")

	# ---- 13b 集齐二选一面板 ----
	# 这一屏带的是玩家看得见的**字**（两个按钮 + 一句"这一趟已经跑通了"），
	# 而尺寸对了不代表读得出来 —— 同 CLAUDE.md 里明信片背面那条。
	# `_on_all_collected()` 演完 2.5 秒合成动画才弹面板，所以这里只能等墙钟。
	var waited := 0.0
	while not _world._synthesis_choice_open and waited < 8.0:
		await create_timer(0.1).timeout
		waited += 0.1
	_ck("集齐面板弹出来了", _world._synthesis_choice_open,
			"等了 %.1fs" % waited)
	await create_timer(0.4).timeout
	await _snap("13b_synthesis_集齐二选一")
	# 按钮上的字读得出来吗？渲染完把面板中央那条带子切出来量对比度，
	# 判据是"不是一片纯底色"——空 Label 和没排上版的 Label 都是那副样子。
	_ck("集齐面板这一屏有字", _world._synthesis_panel.get_node_or_null(
			"Panel/Margin/VBox/Hint").text != "",
			"提示那行是空的，面板上只有两个没字的按钮")
	# 选「再骑一圈」：这一屏拍的是**继续骑下去**的世界，也是判断
	# 顶栏「再访 · 还差 2 次」在集齐之后长什么样的唯一机会。
	_world._on_synthesis_choice(false)
	await create_timer(0.6).timeout
	_ck("选「再骑一圈」之后操纵权回到玩家手上", _world._player._can_move)
	# 集齐是中局不是终局 —— 选完「再骑一圈」之后这一趟**没有**结束。
	# 判据钉在这里而不是 13d：13d 那时已经刷满，`_all_done` 为 true 是对的，
	# 拿它去守"集齐"会守错时刻、而看不出来这条是不是真的在守。
	_ck("集齐之后这一趟没有结束（还能继续骑）", not _world._all_done,
			"_all_done=%s" % _world._all_done)
	await _snap("13c_after_再骑一圈")

	# ---- 13d 五座都走满之后顶栏 ----
	# 满访那一档本来**没有一张图**：`_on_all_maxed()` 锁死之后 2.5 秒就跳结算页，
	# 而它给顶栏写的那句收尾话（`hud_all_done`）只活这 2.5 秒。
	# 于是那一栏在所有定妆照里要么还是「再访 · 还差 2 次」，要么是整行空掉——
	# 数字上（`verify_minimap.gd` §10）钉住了，图上没人看过。
	for i in [4, 7, 10, 13, 14]:
		_gm.check_in(i)
		_gm.check_in(i)
	_ck("五座都走满了", _gm.all_fragments_maxed())
	# 刷满才是终局：`_all_done` 在这一刻才翻过去（2.5 秒后跳结算页）。
	# 上面那句守的是"集齐不算"，这一句守的是"刷满确实算" —— 两个时刻缺一不可。
	_ck("刷满这一趟才真的结束", _world._all_done, "_all_done=%s" % _world._all_done)
	# 顶栏这一栏刷成什么，此刻才说得清
	_ck("顶栏那一栏刷满后是收尾那句，不是空的",
			str(_world._hud3d._next_label.text).strip_edges() != "",
			"text=%s" % str(_world._hud3d._next_label.text))
	await create_timer(0.6).timeout
	await _snap("13d_maxed_走满顶栏")

	# ---- 14 终局二选一 ----
	_world.queue_free()
	await create_timer(0.3).timeout
	var endcard = load("res://scenes/EndCard.tscn").instantiate()
	root.add_child(endcard)
	await create_timer(1.5).timeout
	if endcard._ending_overlay != null:
		endcard._ending_overlay.visible = true
	await create_timer(0.5).timeout
	await _snap("14_ending_终局二选一")

	# ---- 15 明信片 ----
	# 走 _choose_ending 而不是手动把覆盖层藏掉：抉择有真后果（背面写不写、
	# 封口的蜡掰不掰），绕开它拍出来的就不是玩家会看到的那张卡。
	endcard._choose_ending("keep")
	await create_timer(0.8).timeout
	await _snap("15_postcard_明信片")

	# ---- 16 明信片背面 ----
	endcard._show_back_editor()
	# 打几个字再看图：缩略图是「所见即导出」的那张背面，只拍初始帧的话，
	# 看到的还是选完那一句，看不出打字会不会同步过去。手动发信号是因为
	# 程序化赋 .text 不发 text_changed（_on_back_confirmed 里也是这么绕的）。
	endcard._back_text_edit.text = "妈，这条路我替你走完了。\n第十八驿还在，山也还在。"
	endcard._back_text_edit.text_changed.emit()
	# 缩略图按累计 delta 节流 0.12s，等墙钟不等帧
	await create_timer(0.8).timeout
	await _snap("16_postcard_back_背面写字")

	# 这一屏的判据只有像素能量 —— "所见即导出"的意思是玩家认得出自己写的字，
	# 而 verify_postcard_ending.gd 量的是控件尺寸，尺寸对了不代表里面真有内容
	# （SubViewport 回读拿到空帧时预览就是一块纯色，尺寸一模一样）。
	# 所以回读这一帧，在预览那一块上量"有没有墨"：深色像素占比 + 明暗跨度。
	# 两个都量，因为两种失败长得不一样 —— 全是背景色是回读失败，有纹路但
	# 明暗挤在一起是卡片上字太小、缩到读不出来。
	var thumb: Control = endcard._back_thumb
	var img: Image = root.get_texture().get_image()
	var tx := int(thumb.global_position.x)
	var ty := int(thumb.global_position.y)
	var tw := int(thumb.size.x)
	var th := int(thumb.size.y)
	_ck("预览在这一屏真的摆得下（≥400px 宽）", tw >= 400,
			"%.0fx%.0f @ (%.0f,%.0f)" % [tw, th, tx, ty])
	var ink := 0
	var lo := 1.0
	var hi := 0.0
	var n := 0
	# 墨落在几条横带上：一张空卡是 0 条，写了字的卡至少是"抬头 + 正文 + 落款"
	# 三条。只数总量的话，一道划痕或一个焦点环也能凑够。
	var bands := {}
	for y in range(ty, mini(ty + th, img.get_height())):
		for x in range(tx, mini(tx + tw, img.get_width())):
			var c := img.get_pixel(x, y)
			var lum := c.get_luminance()
			if lum < 0.45:
				ink += 1
				bands[(y - ty) / 24] = true
			lo = minf(lo, lum)
			hi = maxf(hi, lum)
			n += 1
	_ck("预览里有墨（不是一块纯色 = SubViewport 回读到空帧）",
			n > 0 and float(ink) / float(n) > 0.004,
			"%.2f%% 的像素暗于 0.45（%d/%d）" % [100.0 * float(ink) / float(n), ink, n])
	_ck("墨铺在好几条横带上（不是一块噪声）", bands.size() >= 3,
			"落在 %d 条 24px 横带上" % bands.size())
	_ck("预览的明暗拉得开（字和纸分得开，不是一团糊）", hi - lo > 0.25,
			"跨度 %.3f（%.3f~%.3f）" % [hi - lo, lo, hi])

	await _free_scene(endcard)
	_gm._clear_save()
	print("\n截图目录: %s" % ProjectSettings.globalize_path(SAVE_DIR))
	print("[lookdev_journey] %s  (失败项 %d, 共 %d 张)" % [
			"PASS" if _fails == 0 else "FAIL", _fails, _shots])
	quit(0 if _fails == 0 else 1)
