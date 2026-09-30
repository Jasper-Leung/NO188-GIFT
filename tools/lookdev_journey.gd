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
func _teleport(station_idx: int) -> void:
	_world._close_shop()
	_world._player.position = _world._stations[station_idx].position + Vector3(0, 1.0, 3.0)
	_world._last_global_pos = _world._player.global_position
	_world._has_last_pos = true
	_world._nearby_station_idx = -1
	_world._nearby_shop_idx = -1
	_world._interact_cooldown = 0.0
	_world._recheck_armed = true
	_world._nearby_station_dist = 999.0
	_world._nearby_shop_dist = 999.0


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

	# ---- 04 骑行中的 HUD ----
	_teleport(0)
	await create_timer(1.0).timeout
	_check_next_target_arrow()
	await _snap("04_ride_骑行中")

	# ---- 05 靠近碎片驿站：地面提示 ----
	_teleport(4)
	await create_timer(1.0).timeout
	_ck("碎片站 4 有打卡提示", _world._check_in_prompt.visible)
	await _snap("05_prompt_打卡提示")

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

	await _free_scene(endcard)
	_gm._clear_save()
	print("\n截图目录: %s" % ProjectSettings.globalize_path(SAVE_DIR))
	print("[lookdev_journey] %s  (失败项 %d, 共 %d 张)" % [
			"PASS" if _fails == 0 else "FAIL", _fails, _shots])
	quit(0 if _fails == 0 else 1)
