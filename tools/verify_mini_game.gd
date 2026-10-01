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

## 喂给 _gui_input 的鼠标事件。走这条真实入口而不是直接调 _update_draw，
## 是为了连"按下必须落在起点容差内"这道门一起测。
func _mb(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	return e

func _mm(pos: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	return e

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

	# 6: 屏幕上的字必须和代码真的那么干。
	#
	# --script 模式下 autoload 标识符的解析不可靠（见 CLAUDE.md），
	# 所以 Localization 也走 root.get_node()，不是直接写类名。
	var _loc: Node = root.get_node_or_null("Localization")
	_check(_loc != null, "拿得到 Localization")
	if _loc == null:
		for s in stubs:
			s.free()
		quit(1)
		return
	#
	#
	#
	# 这一族 bug 有个讨厌的性质：**每一处单独看都像对的**。文案写着"松开即失败"，
	# 代码写着松开只是把进度清零；标题写着"竹子倒下时按"，代码写着引导期提前按
	# 就算数、而且那句引导还明写着"现在就可以按"——同一屏上两句话互相拆台。
	# 玩家按了没事，于是判定"这游戏假"，而不是"这句写错了"。
	# 所以这里量的是**机制本身**，文案只拿来对答案：机制变了而字没跟上（或反过来），
	# 两边一定有一边红。

	# 6a. 茶：松手到底会不会判失败？
	var tea_stub := StubWorld.new()
	stubs.append(tea_stub)
	var tea: Control = load("res://scripts/mini_games/MiniGameTea.gd").new()
	tea._world_ref = tea_stub
	tea.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(tea)
	await process_frame
	# 按住 1.2 秒（不到 3 秒），然后松手
	var tdown := InputEventKey.new()
	tdown.pressed = true
	tdown.keycode = KEY_SPACE
	tdown.physical_keycode = KEY_SPACE
	tea._gui_input(tdown)
	var tea_frames := 0
	while tea._hold_time < 1.2 and tea_frames < 600:
		await physics_frame
		tea_frames += 1
	_check(tea._hold_time > 0.5, "茶：按住时水位真的在涨（%.2fs）" % tea._hold_time)
	var tup := InputEventKey.new()
	tup.pressed = false
	tup.keycode = KEY_SPACE
	tup.physical_keycode = KEY_SPACE
	tea._gui_input(tup)
	_check(tea._hold_time == 0.0, "茶：松手把进度退回零（实际 %.2f）" % tea._hold_time)
	_check(tea_stub.state == -2, "茶：松手**没有**判失败（宿主 state=%d，应仍是 MG_RUNNING）"
			% tea_stub.state)
	_check(tea_stub.state != 1, "茶：松手不触发 CANCELLED")
	# 所以那句提示就不许承诺失败
	var tea_hint: String = _loc.t("mg_tea_hint_release")
	_check(not tea_hint.contains("失败") and not tea_hint.to_lower().contains("fail"),
			"茶：提示不许承诺失败，实际「%s」——机制是退回零" % tea_hint)
	_check(tea._done == false, "茶：松手没有直接判成功")
	if is_instance_valid(tea):
		tea.queue_free()
	await process_frame

	# 6b. 竹：引导期提前按到底算不算数？
	var bam_stub := StubWorld.new()
	stubs.append(bam_stub)
	var bam: Control = load("res://scripts/mini_games/MiniGameBamboo.gd").new()
	bam._world_ref = bam_stub
	bam.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bam)
	await process_frame
	_check(bam._intro_active, "竹：开局先有引导期")
	var bearly := InputEventKey.new()
	bearly.pressed = true
	bearly.keycode = KEY_SPACE
	bearly.physical_keycode = KEY_SPACE
	bam._gui_input(bearly)
	_check(bam._window_active, "竹：引导期按空格直接开砍（不必等它倒下）")
	_check(bam_stub.state == -2, "竹：这一下砍中了，没有被判失败（state=%d）" % bam_stub.state)
	# 于是标题就不许说"等它倒下"
	var bam_title: String = _loc.t("mg_bamboo_title")
	var bam_intro: String = _loc.t("mg_bamboo_intro")
	_check(not bam_title.contains("倒下") and not bam_title.contains("falls"),
			"竹：标题不许说「倒下时再按」，实际「%s」——窗口一起来就能砍" % bam_title)
	_check(bam_intro.contains("现在") or bam_intro.to_lower().contains("now"),
			"竹：引导明说现在就能按，实际「%s」" % bam_intro)
	if is_instance_valid(bam):
		bam.queue_free()
	await process_frame

	# 6c. 禽：那个"还剩多久"是真的在变吗？
	# 原来这里画的是 `max(1, int(_show_timer) + 1)`，而 SHOW_DURATION = 0.8 ——
	# int() 之后恒为 0，+1 之后恒为 1，一个从头到尾钉死的"倒计时"。
	# draw_* 在 headless 下一笔不落盘，所以量不到像素；把读数抽成
	# countdown_fraction()（画的就是它）之后，"它在变"就成了可断言的东西。
	var bird: Control = load("res://scripts/mini_games/MiniGameBird.gd").new()
	var bird_stub := StubWorld.new()
	stubs.append(bird_stub)
	bird._world_ref = bird_stub
	bird.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bird)
	await process_frame
	var f0: float = bird.countdown_fraction()
	var samples: Array[float] = [f0]
	var bframes := 0
	while bird._state == 0 and bframes < 200:
		await physics_frame
		bframes += 1
		samples.append(bird.countdown_fraction())
	var distinct := {}
	for v in samples:
		distinct[v] = true
	_check(samples.size() >= 4, "禽：展示期采到 %d 个样本" % samples.size())
	_check(distinct.size() >= 3, "禽：读数真的在变，取到 %d 个不同的值" % distinct.size())
	var mono := true
	for i in range(1, samples.size()):
		if samples[i] > samples[i - 1]:
			mono = false
	_check(mono, "禽：读数单调不增 %s" % str(samples))
	_check(f0 <= 1.0 and f0 > 0.0, "禽：开局读数在 (0,1]，实际 %.3f" % f0)
	_check(samples[samples.size() - 1] < 0.35, "禽：收尾时读数真的掉下来了（%.3f）"
			% samples[samples.size() - 1])

	# 6e. 禽：四只鸟是四**只**鸟吗？
	# 原来 _draw_bird_silhouette() 只收一个颜色，四只鸟的头/身/翼/尾是同一套
	# 坐标——所以这个"记住哪一只"的游戏考的是记住一个色号，而那个色号只闪
	# SHOW_DURATION 秒。形状搬进 BIRD_SHAPES 之后，"四只长得不一样"就能断言了。
	# 签名里只有几何、没有颜色，所以两两不同 == 形状真的不同。
	var sigs: Array[String] = []
	for i in range(4):
		sigs.append(bird.silhouette_signature(i))
	var dupes := 0
	for i in range(4):
		for j in range(i + 1, 4):
			if sigs[i] == sigs[j]:
				dupes += 1
	_check(dupes == 0, "禽：四只鸟的剪影两两不同（重复 %d 对）" % dupes)
	_check(bird.BIRD_SHAPES.size() == 4,
			"禽：形状表和 BIRD_COLS 一样是 4 只（%d）" % bird.BIRD_SHAPES.size())
	# 窗口得够"看清一只鸟 → 记住 → 再回头扫四个选项"用。原来是 0.8s。
	_check(bird.SHOW_DURATION >= 1.2,
			"禽：展示期 %.1fs 够认一只鸟（原来 0.8s）" % bird.SHOW_DURATION)
	var empty := 0
	for i in range(bird.BIRD_SHAPES.size()):
		if (bird.BIRD_SHAPES[i] as Array).size() < 3:
			empty += 1
	_check(empty == 0, "禽：没有哪只鸟只剩一两笔（%d 只是空壳）" % empty)

	# 6f. 表里那一行多边形，展开出来到底是几个点？
	# headless 下引擎根本不调 _draw，于是 _poly 里写错的东西一次都不会被执行：
	# 我把 Vector2(p) 当成"单参数构造"用了两轮，跑 --headless 全绿，
	# 带窗口跑一进选项页就是满屏 "Nonexistent 'Vector2' constructor"——
	# 而五局里唯独禽是在**第二屏**才画多边形，连实机截图也未必当场看见。
	# 所以直接调 _poly，把"展开成几个点、全是不是有限值"变成能断言的东西。
	var poly_bad := 0
	var poly_rows := 0
	for i in range(bird.BIRD_SHAPES.size()):
		for prim in (bird.BIRD_SHAPES[i] as Array):
			var pa: Array = prim
			var kind: String = pa[0]
			if kind != "p" and kind != "q" and kind != "L":
				continue
			var flat: Array = pa.slice(1, pa.size() - 1) if kind == "L" else pa.slice(1)
			poly_rows += 1
			if flat.size() < 6 or flat.size() % 2 != 0:
				poly_bad += 1
				continue
			var pv: PackedVector2Array = bird._poly(Vector2(600, 400), 1.0, flat)
			if pv.size() != flat.size() / 2:
				poly_bad += 1
				continue
			var finite := true
			for v in pv:
				if not is_finite(v.x) or not is_finite(v.y):
					finite = false
			if not finite:
				poly_bad += 1
	_check(poly_bad == 0, "禽：%d 行多边形全部展开成有限坐标（坏了 %d 行）"
			% [poly_rows, poly_bad])
	if is_instance_valid(bird):
		bird.queue_free()
	await process_frame

	# 6d. 「第十八驿」是世界里的第 18 座驿站吗？不是 —— 那是旅店的名字。
	# 顶栏写的是「已过 n/16 驿」，明信片背面写「第十八驿在我这儿」，
	# 玩家只会把两个数字对着算，然后认定其中一个是 bug。引号和"旅店"是解法：
	# 让它读起来像专名而不是序号。
	var back_keep: String = _loc.t("back_keep")
	var rd = load("res://scripts/road_data.gd")
	var station_total: int = (rd.new().get("stations") as Array).size()
	_check(station_total == 16, "世界上一共 %d 座驿站" % station_total)
	_check(back_keep.contains("「") or back_keep.to_lower().contains("inn"),
			"「%s」要读得出是店名而不是驿站序号" % back_keep)

	# 7. 云影台(7)：完成度必须真的来自"描过"，不能来自"晃过"。
	# 旧版 _update_draw 每被调一次就记 `段长 * 0.1`，而它不记得哪几段已经记过，
	# 于是按住空格在第 0 段上左右晃 60 次就能冲到 78.1%，越过 75% 的及格线——
	# 一个描边游戏，不描边也能赢。这里从真实的 _gui_input 入口喂鼠标事件，
	# 不走 _update_draw 本身，免得拿被测函数测自己。
	#
	# 三种走法：原地晃（不许赢）、顺次描完（必须赢）、一甩跳到末尾（必须也
	# 能描完——甩过去的那几段要一起记上，否则 _next_seg 卡死在没描到的那段上，
	# 后面整条云再也描不完，把"不许刷分"改成了"不许玩"）。
	var cloud: Control = load("res://scripts/mini_games/MiniGameCloud.gd").new()
	var cloud_stub := StubWorld.new()
	stubs.append(cloud_stub)
	cloud._world_ref = cloud_stub
	cloud.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cloud)
	await process_frame

	var cpts: Array = cloud._path_world
	var cnseg: int = cpts.size() - 1
	var cp0: Vector2 = cpts[0]
	var cp1: Vector2 = cpts[1]
	var cseg0: float = cp0.distance_to(cp1)
	var ctotal: float = cloud._total_path_length

	# 原地晃：按下 -> 在第 0 段中点两侧来回 60 次 -> 松手
	cloud._gui_input(_mb(cp0, true))
	var cmid: Vector2 = (cp0 + cp1) * 0.5
	var cwig: Vector2 = (cp1 - cp0).normalized() * 20.0
	for i in range(60):
		cloud._gui_input(_mm(cmid + cwig * (1.0 if i % 2 == 0 else -1.0)))
	var wig_ratio: float = cloud._drawn_ratio
	cloud._gui_input(_mb(cp0, false))
	_check(cseg0 / ctotal < cloud.SUCCESS_THRESHOLD,
			"云：光描一段本来就够不着及格线（%.1f%% < %.0f%%）"
			% [cseg0 / ctotal * 100.0, cloud.SUCCESS_THRESHOLD * 100.0])
	_check(is_equal_approx(wig_ratio, cseg0 / ctotal),
			"云：在同一段上晃 60 次只记一次（%.1f%%，理论 %.1f%%）"
			% [wig_ratio * 100.0, cseg0 / ctotal * 100.0])
	_check(cloud_stub.state == MG_RUNNING,
			"云：原地晃 60 次不判成功（报上来的是 %d）" % cloud_stub.state)

	# 顺次描完：沿路径密集插值走一遍
	cloud_stub.state = MG_RUNNING
	cloud._drawn_ratio = 0.0
	cloud._followed_length = 0.0
	cloud._next_seg = 0
	cloud._gui_input(_mb(cp0, true))
	for i in range(cnseg):
		var ca: Vector2 = cpts[i]
		var cb: Vector2 = cpts[i + 1]
		for s in range(1, 13):
			cloud._gui_input(_mm(ca.lerp(cb, float(s) / 12.0)))
	cloud._gui_input(_mb(cp0, false))
	_check(cloud._drawn_ratio >= cloud.SUCCESS_THRESHOLD,
			"云：顺次描完全程算过（%.1f%%）" % (cloud._drawn_ratio * 100.0))
	_check(cloud_stub.state == 0, "云：描完松手结算 SUCCESS（报上来的是 %d）" % cloud_stub.state)

	# 一甩到底
	cloud_stub.state = MG_RUNNING
	cloud._drawn_ratio = 0.0
	cloud._followed_length = 0.0
	cloud._next_seg = 0
	cloud._gui_input(_mb(cp0, true))
	cloud._gui_input(_mm(cpts[cnseg]))
	cloud._gui_input(_mb(cp0, false))
	_check(cloud._drawn_ratio >= cloud.SUCCESS_THRESHOLD,
			"云：一甩到底也能描完（%.1f%%）——被跳过的段一起记上了"
			% (cloud._drawn_ratio * 100.0))
	_check(cloud_stub.state == 0, "云：甩到底也结算 SUCCESS（报上来的是 %d）" % cloud_stub.state)
	if is_instance_valid(cloud):
		cloud.queue_free()
	await process_frame

	for s in stubs:
		s.free()
	print("[verify_mini_game] ", "PASS" if _failures == 0 else "FAIL", " failures=", _failures)
	quit(0 if _failures == 0 else 1)
