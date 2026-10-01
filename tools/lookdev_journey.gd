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
func _snap(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	var err: int = img.save_png("%s/%s.png" % [SAVE_DIR, name])
	var c := img.get_pixel(SHOT.x / 2, SHOT.y / 2)
	_ck("%02d %s（中心像素 %s）" % [_shots + 1, name, str(c)],
			err == OK and img.get_width() == SHOT.x and c.a > 0.0)
	_shots += 1


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
	var p: Vector3 = st - away * (float(_world.STATION_PASS_RADIUS) - 0.5)
	p.y = _world._get_terrain_height(p.x, p.z)
	_world._player.global_position = p
	# Player3D 的前方是 -basis.z，所以要车头指向站，角度得取反再转半圈
	_world._player.global_rotation = Vector3(0.0,
			atan2(st.x - p.x, st.z - p.z) + PI, 0.0)
	# 相机必须跟上，否则拍到的是"相机还停在传送前"的画面。
	# 关键不在 set_camera_locked，而在 set_can_move：Player3D._update_camera
	# 只在 _physics_process 的 `if not _can_move: return` 之后才跑，
	# 玩家一旦不能移动，相机就永远不更新。序章把 _can_move 设成 false，
	# 而本脚本从不把它放回 true —— 于是传送之后相机钉在原地，车在画面里
	# 缩成一半大（量过：107px vs 正常 226px）。
	# 下面 run() 里在序章之后统一把玩家放回"能骑"的状态。
	_world._last_global_pos = _world._player.global_position
	_world._has_last_pos = true
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
	await _snap("04_ride_骑行中")

	# ---- 05 靠近碎片驿站：地面提示 ----
	_teleport(4)
	await create_timer(1.0).timeout
	_ck("碎片站 4 有打卡提示", _world._check_in_prompt.visible)
	_check_arrival_reachable(4)
	_check_bike_on_screen()
	await _snap("05_prompt_打卡提示")

	# 05c 贴到 1.2m：站点的投影被推到画面下半，提示文字最容易掉出屏外。
	# 只拍可送达机位那张的话这一屏永远看不出来，而那恰恰是玩家最该读到按键提示的一刻。
	# 所以这一张是**故意的**极端机位：玩家最近只能到 6m（离路 18m - 软边界 12m），
	# 这里比那还近 4.8m，是压力测试不是玩家视角，别拿它当"到站长什么样"。
	_world._player.position = _world._stations[4].position + Vector3(0, 1.0, 1.2)
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
	# 把它摆到第三圈就成立，转场期间玩家没动它也不会被改回去。
	_world._odometer_units = 3.0 * _world._total_arclen
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
	await _snap("12b_day_正午")
	# 转场 9 秒（DayCycle.FADE_SEC），按墙钟等 —— 这台机器帧数不等于秒数
	await create_timer(11.0).timeout
	var dusk_t: float = float(_world._day_cycle.get_t())
	_ck("骑满两圈之后天色真的走到黄昏（不是还在半路上）", dusk_t == 1.0,
			"t=%f" % dusk_t)
	# 太阳压到 9° 之后影子该拉得很长，而且方向和正午那档差了一截。
	# 这一屏不校验数字（verify_day_cycle.gd 已经逐条量过了），只看整张图凑不凑。
	await _snap("12c_dusk_黄昏")

	# ---- 13 集齐合成 ----
	_gm.seen_villain = 3
	for i in _world._stations.size():
		_gm.seen_stations[i] = true
	for i in [4, 7, 10, 13, 14]:
		_gm.check_in(i)
	_world._on_all_collected()
	await create_timer(1.2).timeout
	await _snap("13_collect_集齐合成")

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
