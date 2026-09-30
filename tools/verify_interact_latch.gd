extends SceneTree
## verify_interact_latch.gd — 交互闩锁 / 对白抢占 的回归
##
## 这组断言拦的是玩家报上来的那一屏：顶栏「下一处 → 358m」、脚下的铺子提示圈
## 还在亮、按空格毫无反应、只有重开游戏才恢复。
##
## 根因是一条 await 链挂死了：郑铎三场和驿站打卡共用同一个对白弹窗，而
## `interact`（空格）和 `ui_accept`（推进对白）是同一个键。DialoguePopup 的
## set_input_as_handled() 只挡事件传播，Input.is_action_just_pressed() 早就
## 被 OS 输入管线写进单例了——于是"推进对白的那一下空格"顺手开了一场打卡，
## 打卡那边的 setup() 把郑铎正在播的那一轮顶掉，郑铎的协程就此永远挂着，
## `_villain_playing` 再也回不到 false。
##
## 那个闩锁最阴的地方：它只挡 `_can_open_shop`，而 644 行那个早退列表里
## **没有**它，所以 `_nearby_shop_idx` 照算、提示圈照画。玩家看到的就是
## "圈在那儿、怎么按都没反应"，唯一的解法是重开游戏。
##
## 四道断言，分头钉住这个链路：
##   1  闸：郑铎在播时按空格不该开打卡
##   2  释放：setup() 顶掉一轮未收尾的对白时，必须把旧等待者放出去
##   3  收尾：被顶掉的郑铎戏必须自己把 `_villain_playing` 清掉
##   4  口径：回访站不再重播对白/小游戏、不再谎报"获得碎片"，提示圈说实话
##
## 用法： godot --headless --path . --script tools/verify_interact_latch.gd

const SHOT_DIR := "user://lookdev_journey"

var _fails := 0
var _gm: Node = null
var _world: Node = null


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_fails += 1
		print("[FAIL] ", label + ("（" + detail + "）" if detail != "" else ""))


func _ensure_autoloads() -> void:
	for n in {"GameManager": "res://scripts/GameManager.gd",
			"AudioManager": "res://scripts/AudioManager.gd",
			"Localization": "res://scripts/Localization.gd"}:
		if root.get_node_or_null(n) == null:
			var node: Node = load(n).new()
			node.name = n
			root.add_child(node)


func _initialize() -> void:
	Engine.max_fps = 60
	_ensure_autoloads()
	_gm = root.get_node("GameManager")
	_gm._clear_save()
	_gm.headless_mode = true
	_gm.onboarding_shown = true
	_gm.prologue_done = true
	root.size = Vector2i(1280, 720)
	root.add_child(load("res://scenes/World3D.tscn").instantiate())
	_run.call_deferred()


func _teleport(station_idx: int) -> void:
	_world._close_shop()
	_world._player.position = _world._stations[station_idx].position + Vector3(0, 1.0, 3.0)
	_world._last_global_pos = _world._player.global_position
	_world._has_last_pos = true
	_world._interact_cooldown = 0.0
	_world._recheck_armed = true
	_world._check_in_in_progress = false
	_world._mini_game_state = -1


func _run() -> void:
	await process_frame
	_world = root.get_child(root.get_child_count() - 1)
	_gm._clear_save()

	var shop_data = load("res://scripts/shop_data.gd")
	var shop_idx := -1
	for i in range(16):
		if shop_data.shop_at_station(i) != "":
			shop_idx = i
			break

	# ---------- 1 闸：郑铎在播时按空格不许开打卡 ----------
	_teleport(4)
	await process_frame
	await process_frame
	_ck("起始：站在碎片站 4 旁，按空格能打卡", _world._can_start_check_in(4))
	_world._villain_playing = true
	await process_frame
	_ck("郑铎在播时按空格被拦住", not _world._can_start_check_in(4),
			"这条漏了就会同时推进对白和打卡，两条协程抢同一个弹窗")
	_world._villain_playing = false

	# ---------- 2 释放：顶掉一轮未收尾的对白必须把旧等待者放出去 ----------
	var dp = _world._dialogue_popup
	var stolen: Array = []
	dp.dialogue_done.connect(func(r): stolen.append(r), CONNECT_ONE_SHOT)
	dp.setup("郑铎", ["一", "二"], false)
	dp.visible = true
	await process_frame
	_ck("第一轮对白开着、还没收到 dialogue_done",
			stolen.is_empty(), "不该这么早就发信号")
	# 模拟打卡那边在同一帧接管了同一个弹窗。
	# 第二个监听必须在这次 setup() **之后**才接：那一次 setup() 自己会发出
	# 抢占信号，先接上的话会被它吃掉，测的就不是"新那轮"了。
	dp.setup("云台", ["驿站对白"], false)
	await process_frame
	_ck("被顶掉的那一轮拿到了 dialogue_done", stolen.size() == 1,
			"拿不到的话 await 在这里的协程就永远挂着")
	_ck("信号里带 was_stolen=true",
			stolen.size() == 1 and bool(stolen[0].get("was_stolen", false)),
			str(stolen))
	var fresh: Array = []
	dp.dialogue_done.connect(func(r): fresh.append(r), CONNECT_ONE_SHOT)
	_ck("抢占信号不误伤新那轮", fresh.is_empty(), "还没轮到它")
	dp.visible = false
	await process_frame
	dp._on_skip_pressed()
	await process_frame
	# 正常收尾的两个 emit 点都不带 was_stolen 键，所以判据的缺省必须是 false
	# ——和 World3D 里 result.get("was_stolen", false) 的缺省一致，
	# 含义是"没被顶掉，按正常流程往下走"。
	_ck("正常收尾（跳过）也放出了信号",
			fresh.size() == 1 and not bool(fresh[0].get("was_stolen", false)),
			str(fresh))

	# ---------- 3 收尾：被顶掉的郑铎戏自己把闩锁清掉 ----------
	# 必须先把 World3D 自己的 headless 关掉：_play_villain_scene() 开头就
	# `if _headless_mode: return`，留着它这条链根本不会挂起，测的就等于没测。
	_gm._clear_save()
	_world._headless_mode = false
	_teleport(4)
	await process_frame
	_world._villain_playing = true
	_world._play_villain_scene(0)      # 挂起在第一段对白上
	await process_frame
	await process_frame
	_ck("郑铎第一段对白正在播",
			_world._dialogue_popup.visible and _world._villain_playing,
			"对白没起来的话这一节是空测")
	# 打卡那边抢走弹窗（真实世界里就是那一下空格同时干了两件事）
	_world._dialogue_popup.setup("云台", ["驿站对白"], false)
	await create_timer(0.5).timeout
	_ck("被顶掉的郑铎戏把 _villain_playing 清掉了", not _world._villain_playing,
			"漏了这一句，铺子从此再也开不了，提示圈却还照画")
	_world._dialogue_popup._on_skip_pressed()
	await process_frame
	_world._headless_mode = true

	# ---------- 4 口径：回访不再重播、不再谎报碎片 ----------
	_gm._clear_save()
	_teleport(4)
	await process_frame
	_gm.check_in(4)                   # 第 1 次：拿到碎片
	_ck("首次到访：顶栏的「下一处」不再指这一站",
			_world._hud3d._next_fragment_target().get("idx", -1) != 4)
	_teleport(4)
	await process_frame
	_ck("回访站仍可打卡（歇一脚，不是死路）", _world._can_start_check_in(4),
			"环数上限 3 次，回访是设计内的")
	_ck("回访时提示圈说的是「歇一脚」不是「完成乐事」",
			_visit_prompt_label().contains("歇"),
			_visit_prompt_label())
	# 跑一遍完整回访序列：1.0s 运镜 + 1.5s 定格 + 0.4s 收尾 ≈ 2.9s，
	# 面板在 ~2.5s 亮起、~2.9s 自己收掉，所以按墙钟等到序列结束再断言。
	var lvbi_before: int = _gm.lvbi
	_world._do_check_in(4)
	await create_timer(4.0).timeout
	_ck("回访序列跑完了", not _world._check_in_in_progress)
	_ck("回访没有重播小游戏", _world._mini_game_node == null
			and _world._mini_game_state != _world.MG_RUNNING,
			"回访是歇一脚，不该再考一次")
	# _popup_text 在面板收掉之后仍然留着最后写的字，所以断字比断可见性稳
	_ck("回访面板说的是「已经收过了」",
			_world._popup_text.text == _root_loc().t("revisit_note"),
			"面板上写着：%s" % _world._popup_text.text)
	_ck("回访不再谎报「获得碎片」", not _world._popup_fragment.visible)
	_ck("回访照样发旅币", _gm.lvbi > lvbi_before,
			"%d → %d" % [lvbi_before, _gm.lvbi])
	_ck("回访打卡次数累到 2", _gm.get_station_count(4) == 2,
			"实际 %d" % _gm.get_station_count(4))

	# ---------- 5 铺子最终可达 ----------
	_teleport(shop_idx)
	await process_frame
	await process_frame
	_ck("铺子能开（回归的终点：不再需要重开游戏）",
			_world._can_open_shop(_world._nearby_shop_idx))

	_gm._clear_save()
	print("\n[verify_interact_latch] %s  (失败 %d)" % [
			"PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)


func _root_loc() -> Node:
	return root.get_node("Localization")


## 问提示圈自己现在打算写哪句话（走的是它自己的 _label()，不是重演一遍逻辑）
func _visit_prompt_label() -> String:
	var cp = _world._check_in_prompt
	var t: Array = cp._prompt_target()
	return "" if t.is_empty() else str(cp._label(t))
