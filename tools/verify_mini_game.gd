extends SceneTree
## verify_mini_game.gd — 无头验证小游戏注入链路（隔离模式，不加载 World3D 全场景）
## 验证点：
##   1. 5 个小游戏脚本都能实例化为 Control
##   2. 铺满全屏 anchors 后 size > 0（修复前 size=(0,0)，画不出也收不到 _gui_input）
##   3. 结果码契约：小游戏发 SUCCESS(0)/CANCELLED(1)，宿主用 -2 作"运行中"哨兵，
##      0 不再与"运行中"撞车（修复前成功会卡满 600 帧轮询）
##   4. 琴音林(Zither) 端到端：注入 stub 宿主，输入超时后回调 CANCELLED(1)
##   5. 质量下限：5 个小游戏都能用 ESC 取消（键盘玩家必须永远有出路）

const MG_RUNNING := -2  # 与 World3D.gd 中的哨兵一致

class StubWorld:
	extends Node
	var state: int = MG_RUNNING
	var received: Array = []
	func _on_mini_game_done(result: int) -> void:
		if state == MG_RUNNING:  # 与 World3D._on_mini_game_done 同一门控逻辑
			state = result
		received.append(result)

const GAMES := {
	7: "res://scripts/mini_games/MiniGameCloud.gd",
	10: "res://scripts/mini_games/MiniGameTea.gd",
	13: "res://scripts/mini_games/MiniGameZither.gd",
	14: "res://scripts/mini_games/MiniGameBamboo.gd",
	4: "res://scripts/mini_games/MiniGameBird.gd",
}

var _failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("[OK] ", label)
	else:
		_failures += 1
		print("[FAIL] ", label)

func _initialize() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var stubs: Array = []  # 持有 stub 引用，退出前统一 free，避免 ObjectDB 泄漏警告

	# 1+2: 全部小游戏可实例化，且注入方式下 size 铺满
	for idx in GAMES:
		var node: Control = load(GAMES[idx]).new()
		_check(node is Control, "驿站%d 小游戏是 Control" % idx)
		# 模拟 World3D._run_mini_game 的注入步骤
		var s := StubWorld.new()
		stubs.append(s)
		node._world_ref = s
		node.set_anchors_preset(Control.PRESET_FULL_RECT)
		node.focus_mode = Control.FOCUS_ALL
		layer.add_child(node)
		await process_frame
		_check(node.size.x > 100.0 and node.size.y > 100.0,
			"驿站%d 小游戏 size=%s 铺满全屏" % [idx, str(node.size)])
		_check(node.focus_mode == Control.FOCUS_ALL,
			"驿站%d 小游戏 focus_mode=FOCUS_ALL（可收键盘）" % idx)
		node.queue_free()
		await process_frame

	# 4: Zither 端到端 —— 不输入，INPUT_TIMEOUT(2.5s) 后应回调 CANCELLED(1)
	var stub := StubWorld.new()
	stubs.append(stub)
	var zither: Control = load(GAMES[13]).new()
	zither._world_ref = stub
	zither.set_anchors_preset(Control.PRESET_FULL_RECT)
	zither.focus_mode = Control.FOCUS_ALL
	layer.add_child(zither)
	var frames := 0
	while stub.state == MG_RUNNING and frames < 1200:  # 20s 上限
		await process_frame
		frames += 1
	_check(stub.state == 1, "Zither 无输入超时后宿主收到 CANCELLED(1)，实际 state=%d（%d 帧）" % [stub.state, frames])
	_check(not stub.received.is_empty(), "Zither 回调确实到达宿主: %s" % str(stub.received))
	# 关键回归：若成功码 0 被当"运行中"，这里 received 含 0 时 state 会卡死 —— 上面循环 1200 帧上限会曝光
	if is_instance_valid(zither):
		zither.queue_free()

	# 5: 质量下限 —— 五个小游戏都必须能用 ESC 取消。
	# 取消按钮是 _draw() 画的假按钮，键盘点不到。原来茶/琴/竹三个都不接 ESC：
	# 茶最糟，既放弃不了又失败不了（长按 3 秒必然成功），键盘玩家唯一出路是
	# 干等 World3D 的 30s 超时。这里逐个注入一个 ESC 事件，要求都回 CANCELLED(1)。
	for idx in GAMES:
		var s2 := StubWorld.new()
		stubs.append(s2)
		var mg: Control = load(GAMES[idx]).new()
		mg._world_ref = s2
		mg.set_anchors_preset(Control.PRESET_FULL_RECT)
		mg.focus_mode = Control.FOCUS_ALL
		layer.add_child(mg)
		await process_frame
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.echo = false
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		mg._gui_input(ev)
		_check(s2.state == 1, "驿站%d ESC 取消回 CANCELLED(1)，实际 state=%d" % [idx, s2.state])
		if is_instance_valid(mg):
			mg.queue_free()
		await process_frame

	for s in stubs:
		s.free()
	print("[verify_mini_game] ", "PASS" if _failures == 0 else "FAIL", " failures=", _failures)
	quit(0 if _failures == 0 else 1)
