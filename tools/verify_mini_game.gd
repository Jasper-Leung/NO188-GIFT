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

## 6. 五件乐事各在自己的地方，且琴弦顺着琴身长边
##
## 这一节量的是两件**只能量几何、量不了像素**的事：
##
## · 琴的命中区。四根弦以前是竖着插在一条又宽又短的琴身上的（每根命中区
##   是一条竖列），古琴的弦是平行于长轴的。竖列 vs 横带在屏幕上都能画出来、
##   都能点、都能弹对，所以前面 5 节全绿——它量的是"能不能玩"，
##   量不到"这看起来是不是一把琴"。判据取「命中区宽 > 高」，
##   把旧代码放回去立刻红。
## · 景对不对得上站。这一条只能读源码文本：小游戏的 `_draw()` 在 headless 下
##   一笔都不落盘，屏幕上是茶烟小筑的暖黄还是竹雨庭的夜雨，没有断言能看见。
##   而"五件乐事用同一片黑幕"正是原来的毛病，风景全丢。所以这里核对每个小游戏
##   引用的主题常量是不是它自己那件乐事的——抄错一个下标，图上就串了地方。
const THEME_OF := {
	7: "CLOUD", 10: "TEA", 13: "ZITHER", 14: "BAMBOO", 4: "BIRD",
}


func _section_backdrops() -> void:
	print("\n---- 6. 五件乐事的景 + 琴弦方向 ----")
	_check(load("res://scripts/mini_games/MiniGameBackdrop.gd") != null,
		"MiniGameBackdrop 存在")
	for idx in GAMES:
		var src := FileAccess.get_file_as_string(GAMES[idx])
		var want: String = str(THEME_OF[idx])
		_check(src.contains("MiniGameBackdrop." + want),
			"驿站%d 用的是 %s 那片景（不是别的乐事的）" % [idx, want])

	# 琴弦方向。这一条量的是 `_string_rects()` 这个不碰画笔的纯函数，
	# **不是** `_note_rects`：后者在 `_draw()` 里填，而 `--headless` 根本不调
	# `_draw()`，去读它量到的是"headless 不调 _draw"这条已知事实。也不把
	# 节点挂进树里等帧 —— 挂进去就得 await，调用方不 await 的话整节会在
	# 第一个 await 处静默挂住，然后由主协程照常打一行 PASS（实测踩过）。
	var z: Control = load(GAMES[13]).new()
	z.size = Vector2(1280.0, 1280.0)
	var rects: Array = z.call("_string_rects")
	_check(rects.size() == 4, "琴有 4 根弦的命中区（实际 %d）" % rects.size())
	var widest := 0
	for i in rects.size():
		var r: Rect2 = rects[i]
		if r.size.x > r.size.y:
			widest += 1
		_check(r.size.x > r.size.y,
			"第%d根弦的命中区是横带（宽 %.0f > 高 %.0f = 弦顺着琴身长边）"
			% [i + 1, r.size.x, r.size.y])
	# 全部四根都得是横带。留一个汇总判据是有意的：上面那圈是逐根的，
	# 少印一行也照样看得见，但"0 根是横带"这种整体结论不该靠人加总。
	_check(widest == rects.size(),
		"四根弦全都顺着琴身长边（%d/%d 根是横带）" % [widest, rects.size()])
	z.free()


## 五件乐事在 15 趟打卡里的完整排布。判据不是"轮换"这两个字，是四条能各自
## 变红的性质：
##   · **首次到访拿到的还是这座驿站自己的那件**（云影台仍然是描云）。
##     MiniGamePicker.SCRIPTS 是一份**独立副本**，和 RoadData 的驿站表、碎片顺序
##     三处各写一遍；这里拿真实的 road_data.gd 逐格对拍，抄错一处立刻红。
##   · 同一座驿站连着三次**不重样**（否则第三次是原样重播）。
##   · 15 局里每件乐事**正好 3 次**（不多不少，重玩钩子的分量才稳）。
##   · `script_for()` 和 `game_for()` 指回同一件事（两张出口不许漂）。
func _section_rotation() -> void:
	print("\n---- 7. 三次到访轮换五件乐事 ----")
	var picker = load("res://scripts/mini_games/MiniGamePicker.gd")
	_check(picker != null, "MiniGamePicker 存在")
	if picker == null:
		return
	var scripts: Array = picker.SCRIPTS
	_check(scripts.size() == 5, "五件乐事各一件（实际 %d）" % scripts.size())
	for i in scripts.size():
		_check(ResourceLoader.exists(str(scripts[i])),
			"第%d件 %s 在磁盘上" % [i + 1, str(scripts[i]).get_file()])

	# runtime load 而**不是** `var rd: RoadData` 类型注解 —— 注解会在编译期把
	# road_data.gd 拖进来，而它引用了 Localization autoload，`--script` 模式下
	# 解析不可靠（见 CLAUDE.md 已知陷阱）。
	var rd = load("res://scripts/road_data.gd").new()
	var stations: Array = rd.stations
	var slot_of: Array = rd.FRAGMENT_SLOT_STATION_IDX
	_check(slot_of.size() == scripts.size(),
		"驿站表(%d) 和乐事表(%d) 一样长" % [slot_of.size(), scripts.size()])
	const FRAG_ORDER := ["云", "茶", "琴", "竹", "禽"]
	for slot in mini(slot_of.size(), scripts.size()):
		var st_idx: int = slot_of[slot]
		var frag: String = str(stations[st_idx].get("fragment", "?"))
		_check(frag == FRAG_ORDER[slot],
			"槽位%d 确实是驿站%d，它身上写的是「%s」（该是「%s」）"
			% [slot, st_idx, frag, FRAG_ORDER[slot]])
		# GAMES 是本文件顶部那张「驿站→自己的那件」表。它原本就是产品的真值，
		# 现在成了轮换表「首次到访不变」这条性质的对照。
		_check(str(GAMES.get(st_idx, "")) == str(scripts[slot]),
			"驿站%d 第一次到访玩的是它自己那件（%s）"
			% [st_idx, str(scripts[slot]).get_file()])
		_check(picker.game_for(slot, 0) == slot,
			"槽位%d 第 1 次到访 = 槽位自己" % slot)

	# 同一座驿站连着三次不重样
	for slot in scripts.size():
		var seen := {}
		var dup := -1
		for visit in 3:
			var g: int = picker.game_for(slot, visit)
			if seen.has(g):
				dup = visit
			seen[g] = true
			_check(picker.script_for(slot, visit) == str(scripts[g]),
				"槽位%d 第%d次到访：script_for 和 game_for 指同一件（%s）"
				% [slot, visit + 1, str(scripts[g]).get_file()])
		_check(dup < 0, "槽位%d 连着三次不重样（重复出现在第 %d 次）" % [slot, dup + 1])

	# 15 局里每件正好 3 次
	var tally := {}
	for slot in scripts.size():
		for visit in 3:
			var g: int = picker.game_for(slot, visit)
			tally[g] = int(tally.get(g, 0)) + 1
	var all_three := true
	for i in scripts.size():
		if int(tally.get(i, 0)) != 3:
			all_three = false
	_check(all_three,
		"15 局里每件乐事正好 3 次（%s）" % str(tally))


func _check(cond: bool, label: String) -> void:
	if cond:
		print("[OK] ", label)
	else:
		_failures += 1
		print("[FAIL] ", label)


## WCAG 相对亮度。比值一律取 max/min —— 见 CLAUDE.md 陷阱清单里
## 「谁除以谁」那一条：合成后不一定更暗，写死方向会得到一堆小于 1 的比值。
## Color 存的是 sRGB，要先 `srgb_to_linear` 再按 0.2126/0.7152/0.0722 加权。
func _wcag_lum(c: Color) -> float:
	var lin: Color = c.srgb_to_linear()
	var r: float = lin.r
	var g: float = lin.g
	var b: float = lin.b
	return 0.2126 * r + 0.7152 * g + 0.0722 * b


## 两个量差得有多开。**相对差而不是绝对差**：包围盒 96px 和 88px 在 44px 的
## 选项格里是"一样宽"，而 96px 和 30px 不是。
func _rel_diff(a: float, b: float) -> float:
	return absf(a - b) / maxf(maxf(absf(a), absf(b)), 0.001)

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
	# 6a-1. 壶里的水位量得到吗？
	#
	# 这一屏除进度条之外**唯一的**反馈就是壶里那层水，而它原来是画笔里一行
	# 算式（`pot_c.y + ry*0.86 - 2*ry*0.86*fill`）。`--headless` 根本不调 `_draw`，
	# 于是"注水时壶里真的有水在涨""水是贴着壶壁涨的"两件事都没人能断言——
	# 把它抽成 `water_top_frac()` / `water_line_y()` 之后，量的是**壶身全高的
	# 几成**，和壶画多大无关。
	var tea_script: Object = load(GAMES[10])
	var half: float = tea_script.water_top_frac(0.5)
	_check(half >= 0.45 and half <= 0.55,
		"茶：注水到一半时水位线落在壶身 %.0f%% 高处（0.45~0.55）" % (half * 100.0))
	# 单调不减：水位不许自己往下退。而"松手退回零"是 `_hold_time` 清零，
	# 画笔读的是同一个 fill —— 判据顺手把那件事也钉住了。
	var wmono := true
	var wstrict := true
	var wprev: float = tea_script.water_top_frac(0.0)
	for s in range(1, 11):
		var wf: float = tea_script.water_top_frac(float(s) / 10.0)
		if wf < wprev - 0.0001:
			wmono = false
		if wf <= wprev:
			wstrict = false
		wprev = wf
	_check(wmono, "茶：壶内水位单调不减（0%→100% 十个采样点）")
	_check(wstrict, "茶：注水时水位真的在涨，不是十个采样点同一个数")
	# 空壶压在壶底、满壶接近壶口，且两头都**在壶身之内**。
	var w0: float = tea_script.water_top_frac(0.0)
	var w1: float = tea_script.water_top_frac(1.0)
	_check(w0 > 0.0 and w0 <= 0.15 and w1 >= 0.85 and w1 < 1.0,
		"茶：空壶 %.0f%% / 满壶 %.0f%%，两头都还在壶身之内" % [w0 * 100.0, w1 * 100.0])
	# 画面坐标那一层：水面 y 必须跟着壶一起缩放，壶画大了水面不许跑到壶外。
	# 壶的几何走 `pot_center()` / `pot_scale()` / `POT_RY`——**和画笔同一个函数**，
	# 回归里自己再抄一份 `minf(w,h)/400` 就是这个项目吃过的那类亏。
	var water_geo_ok := true
	var water_why: String = ""
	for vp2 in [[1280.0, 720.0], [1920.0, 1080.0], [800.0, 1280.0]]:
		# 逐项取出来再拼：GDScript 的 Vector2 **没有**单参数构造，
		# `var tv: Vector2 = vp2`（vp2 是 Array）会抛 "Trying to assign value
		# of type 'Array'…"——而那一抛把整个 _initialize 协程打断，`quit()`
		# 再也走不到，于是脚本不报错地挂在那儿（第一版就这么挂了 4 分钟）。
		var tv := Vector2(vp2[0], vp2[1])
		var pc: Vector2 = tea_script.pot_center(tv)
		# pot_scale 折进 POT_RY：壶半高 = POT_RY × min(宽,高)/400
		var ry2: float = float(tea_script.POT_RY) * tea_script.pot_scale(tv)
		var y_lo: float = tea_script.water_line_y(pc, ry2, 0.0)
		var y_mid: float = tea_script.water_line_y(pc, ry2, 0.5)
		var y_hi: float = tea_script.water_line_y(pc, ry2, 1.0)
		# 壶身竖直范围：心 ± ry
		if not (y_hi < y_mid and y_mid < y_lo) \
				or y_hi < pc.y - ry2 or y_lo > pc.y + ry2:
			water_geo_ok = false
			water_why = "%d×%d：水 %.0f/%.0f/%.0f，壶 %.0f..%.0f" % [int(tv.x), int(tv.y),
				y_lo, y_mid, y_hi, pc.y - ry2, pc.y + ry2]
	_check(water_geo_ok,
		"茶：水面在壶身之内并随注水上移（%dx%d / %dx%d / %dx%d 三档）%s"
		% [1280, 720, 1920, 1080, 800, 1280, water_why])
	# 水和进度条**读同一个值**。原来两处各写一遍 `clampf(_hold_time / HOLD_DURATION…)`，
	# 漏改一处就是"条满了壶还空着"，而同一屏上没有任何东西能指出这件事。
	tea._hold_time = float(tea.HOLD_DURATION) * 0.5
	var live_fill: float = tea.fill_fraction()
	_check(absf(live_fill - 0.5) < 0.001,
		"茶：按住一半时间时 fill_fraction() = %.2f" % live_fill)
	_check(tea_script.water_top_frac(live_fill) >= 0.45
			and tea_script.water_top_frac(live_fill) <= 0.55,
		"茶：壶里的水读的就是那一个值（水位 %.0f%%）"
		% (tea_script.water_top_frac(live_fill) * 100.0))
	# 水汽：三颗随时间上浮、越飘越淡、一轮走完从壶口重新冒出来。
	# 原来那三颗是画在原地不动的灰圆点、alpha 一路不变，读起来像壶上溅了
	# 三滴脏水。而 headless 下一笔都不落盘，所以位置/半径/透明度都得在
	# 纯函数里算，回归量纯函数、画笔调纯函数。
	_check(int(tea_script.STEAM_COUNT) >= 3,
		"茶：壶口冒着 %d 颗水汽" % int(tea_script.STEAM_COUNT))
	var p0: Dictionary = tea_script.steam_puff(0, 0.0, 1.0)
	var p1: Dictionary = tea_script.steam_puff(0, 0.25, 1.0)
	var a0: float = float(p0["a"])
	var a1: float = float(p1["a"])
	_check(a0 > 0.0 and a1 > 0.0 and a1 < a0,
		"茶：水汽越飘越淡（alpha %.3f → %.3f，0.25s 后）" % [a0, a1])
	var up0: Vector2 = p0["pos"]
	var up1: Vector2 = p1["pos"]
	_check(up1.y < up0.y and (up0.y - up1.y) > 0.001,
		"茶：水汽真的在上浮（y %.1f → %.1f，0.25s 走了 %.1f）"
		% [up0.y, up1.y, up0.y - up1.y])
	# 循环：正好飘完一轮（STEAM_SPAN / STEAM_RISE 秒）之后回到同一处。
	# 不循环的话它就是一颗从壶口冒出来、飘到顶就不见了的点。
	var period: float = float(tea_script.STEAM_SPAN) / float(tea_script.STEAM_RISE)
	var sp0: Dictionary = tea_script.steam_puff(0, 0.0, 1.0)
	var sp1: Dictionary = tea_script.steam_puff(0, period, 1.0)
	_check((sp0["pos"] as Vector2).is_equal_approx(sp1["pos"] as Vector2)
			and absf(float(sp0["r"]) - float(sp1["r"])) < 0.0001
			and absf(float(sp0["a"]) - float(sp1["a"])) < 0.0001,
		"茶：水汽飘完一轮（%.2fs）回到同一处，是循环不是一次性" % period)
	# 三颗得是三颗：同相的话那就是同一个点画了三遍
	# 位置和**相位**分开量：x 上那 ±16 的横向偏移本来就恒在（三个排开的口子），
	# 只量 x 的话"三颗同相"照样全绿——而同相的三颗是同一缕烟画了三遍。
	# 相位看的是同一时刻三颗的 alpha：错开相时它是一串 0.34 / 0.23 / 0.11。
	var px: Array[float] = []
	var palpha: Array[float] = []
	for i in range(int(tea_script.STEAM_COUNT)):
		var pxi: Dictionary = tea_script.steam_puff(i, 0.0, 1.0)
		px.append((pxi["pos"] as Vector2).x)
		palpha.append(float(pxi["a"]))
	var px_distinct := {}
	for v in px:
		px_distinct[snappedf(v, 0.01)] = true
	_check(px_distinct.size() == px.size(),
		"茶：%d 颗水汽各在各的位置 x=%s（不是同一个点画三遍）"
		% [px.size(), str(px)])
	var pa_distinct := {}
	for v in palpha:
		pa_distinct[snappedf(v, 0.001)] = true
	_check(pa_distinct.size() == palpha.size(),
		"茶：三颗水汽错开相冒出来（同一时刻的 alpha %s，不是一起冒的）" % str(palpha))
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

	# 6b-1. 四张卡上，每只鸟都读得出来吗？
	#
	# 乌鸦原来是 (0.11, 0.11, 0.14) 的纯黑压在 CARD_BG 上，WCAG 只有 1.47:1。
	# 这是个"从四只里认出刚才那一只"的记忆游戏，而四只里有一只认不出来，
	# 等于这一局的题面少了一条。
	#
	# 比值一律按 WCAG 公式真算（相对亮度 + 谁除以谁取 max/min），不是"看着差不多"。
	# **量的是描边而不是本体**，理由要写在这里，否则下一个人会以为可以改回去：
	# 四只的本体在**同一块卡底**上不可能四条一起过 3.0。相对亮度算出来是
	# 白鹭 0.78 / 麻雀 0.155 / 燕子 0.107 / 乌鸦 0.025，卡底 0.041；
	# 白鹭逼卡底 ≤ (0.78+0.05)/3 − 0.05 = 0.227，乌鸦逼卡底 ≥ 3(0.025+0.05) − 0.05
	# = 0.136，而燕子(0.107)离乌鸦(0.025)只有 2.5:1 —— 卡底在 0.136~0.227
	# 这个区间里，燕子对谁都到不了 3 倍。硬凑只有两条路：把乌鸦提亮
	# （它就不再是乌鸦）或者把另外三只刷成米白（颜色就不再认人）。所以乌鸦
	# 那一格过线的是描边，而"描边 vs 卡底"这一条对四张卡一模一样。
	var card_bg: Color = bird.CARD_BG
	var bg_lum: float = _wcag_lum(card_bg)
	var rim_pass := 0
	var rim_worst := INF
	for i in range(4):
		var rl: float = _wcag_lum(bird.BIRD_RIM_COLS[i])
		var rc: float = (maxf(rl, bg_lum) + 0.05) / (minf(rl, bg_lum) + 0.05)
		if rc >= 3.0:
			rim_pass += 1
		rim_worst = minf(rim_worst, rc)
		_check(rc >= 3.0,
			"禽：第%d张卡的描边对底色 %.1f:1（≥3.0，body %.3f）"
			% [i + 1, rc, _wcag_lum(bird.BIRD_COLS[i])])
	# 汇总一条：少印一行照样看得见，但"0 张卡过线"这种整体结论不该靠人加总。
	_check(rim_pass == 4,
		"禽：四张卡的描边全都过 3.0（%d/4，最差 %.1f:1）" % [rim_pass, rim_worst])

	# 乌鸦**必须仍然是四只里最暗的那只**。把它提亮它就不再是乌鸦，
	# 而"哪只是哪一只"是这一局的全部题面。
	var blums: Array[float] = []
	for i in range(4):
		blums.append(_wcag_lum(bird.BIRD_COLS[i]))
	var dark_idx := 0
	for i in range(1, 4):
		if blums[i] < blums[dark_idx]:
			dark_idx = i
	_check(dark_idx == 3,
		"禽：最暗的仍然是乌鸦（第 %d 只，本体相对亮度 %.3f）" % [dark_idx + 1, blums[dark_idx]])
	var next_dark := INF
	for i in range(4):
		if i != dark_idx:
			next_dark = minf(next_dark, blums[i])
	_check(blums[dark_idx] * 3.0 <= next_dark,
		"禽：乌鸦压得住（本体 %.3f ≤ 次暗那只 1/3 = %.3f）"
		% [blums[dark_idx], next_dark / 3.0])
	# 描边还要和自己的本体分得开：描边和本体撞在一起的话，勾出来的还是那
	# 一坨深炭灰，只是被描边的颜色又描了一遍。
	var crow_sep: float = (maxf(blums[3], _wcag_lum(bird.BIRD_RIM_COLS[3])) + 0.05) \
			/ (minf(blums[3], _wcag_lum(bird.BIRD_RIM_COLS[3])) + 0.05)
	_check(crow_sep >= 3.0,
		"禽：乌鸦的浅描边和它自己的深炭灰本体分得开 %.1f:1（≥3.0）" % crow_sep)
	# 最亮的那一只不靠描边也得自己读得出来——它是四只里唯一本体就够亮的，
	# 而"白鹭本来就是白的"是这屏的直觉，不该由描边替它撑着。
	var light_idx := 0
	for i in range(1, 4):
		if blums[i] > blums[light_idx]:
			light_idx = i
	var light_c: float = (maxf(blums[light_idx], bg_lum) + 0.05) \
			/ (minf(blums[light_idx], bg_lum) + 0.05)
	_check(light_c >= 3.0,
		"禽：最亮的那只（第 %d 只）本体对底色就有 %.1f:1（≥3.0）"
		% [light_idx + 1, light_c])

	# 四只鸟不只是"四串不同的字"，还得**认得出来**。
	# `silhouette_signature()` 只证伪"两串字完全一样"：把雀的尾尖从 -37 挪到
	# -40 就是一对不同的签名，而两个色块在 44px 的选项格里读起来一模一样。
	# 判据落在剪影自己的几何上：每一对至少在 {包围盒宽, 包围盒高, 面积, 长宽比}
	# 里的**两项**相对差 ≥ 12%。两项是必须的——只要有一项分得开，四只里就可以
	# 混进一对"一高一矮同宽"的，而那正是"两只鸟长得像"的症状。
	const DISTINCT := 0.12
	var boxes: Array[Rect2] = []
	var areas: Array[float] = []
	var aspects: Array[float] = []
	for i in range(4):
		boxes.append(bird.silhouette_bbox(i))
		areas.append(bird.silhouette_area(i))
		aspects.append(bird.silhouette_aspect(i))
	var pairs_ok := 0
	for i in range(4):
		for j in range(i + 1, 4):
			var diffs: Array[float] = [
				_rel_diff(boxes[i].size.x, boxes[j].size.x),
				_rel_diff(boxes[i].size.y, boxes[j].size.y),
				_rel_diff(areas[i], areas[j]),
				_rel_diff(aspects[i], aspects[j]),
			]
			var far := 0
			for d in diffs:
				if d >= DISTINCT:
					far += 1
			if far >= 2:
				pairs_ok += 1
			_check(far >= 2,
				"禽：第%d只和第%d只认得出来（四项里 %d 项差 ≥%.0f%%：宽 %.0f%% / 高 %.0f%% / 面积 %.0f%% / 长宽比 %.0f%%）"
				% [i + 1, j + 1, far, DISTINCT * 100.0, diffs[0] * 100.0,
				diffs[1] * 100.0, diffs[2] * 100.0, diffs[3] * 100.0])
	_check(pairs_ok == 6, "禽：六对全都认得出来（%d/6）" % pairs_ok)

	# 又是读源码文本那几条（和核 `MiniGameBackdrop.<THEME>` 同一个办法）：
	# 上面量的是两张表和几个纯函数，**量不到画笔有没有真的用它们**——
	# `--headless` 下一笔都不落盘，描边写进表里而画笔不调，图上还是那只
	# 1.47:1 的黑鸦，而这一节全绿。
	var birdsrc: String = FileAccess.get_file_as_string(GAMES[4])
	_check(birdsrc.contains("_paint_silhouette(bird_idx, c, sc, BIRD_RIM_COLS[bird_idx],"),
		"禽：画笔真的把描边那一遍画出来了（不是只把颜色写进表里）")
	_check(birdsrc.contains("draw_rect(r, CARD_BG, true)"),
		"禽：选项卡填的就是回归当尺子的那个 CARD_BG（不是另一个字面量）")

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

	# 6g. 三个小游戏的画，读得出自己的标题吗？
	#
	# 这一族的毛病不是画得难看，是**画出来的东西和标题说的不是一回事**：
	# 琴那一屏的标题原来写「记住音符顺序并重复」，屏上一个字都没提琴，
	# 琴身是一块收分的木色多边形加四根线——读成"一块有四根线的板子"；
	# 竹那五根是 `draw_rect(..., 12, ...)` 的等宽竖条，竹节那四条线也才 12px 宽，
	# 画在一条 12px 的条上等于没有，于是标题写"竹子一冒头就按空格"而屏上没有竹子；
	# 云更荒唐：背景那五片云是三个圆叠出来的圆鼓鼓一团，**而要描的那条轨迹是
	# 一串手抄的八边形顶点**——同一屏上同一件事两套画法。
	#
	# 量的是几何本身（纯函数，不碰画笔——headless 根本不调 `_draw`）。
	# 但"读不读得出来"终究要靠 `lookdev_journey.gd` 的 `minigame_*.png` 看图，
	# 这里守的是**改不回去**：几何一旦退回八边形/等宽条/无名板子，下面立刻红。

	# --- 云：轮廓不是多边形 ---
	var cloud2: Control = load("res://scripts/mini_games/MiniGameCloud.gd").new()
	var c2stub := StubWorld.new()
	stubs.append(c2stub)
	cloud2._world_ref = c2stub
	cloud2.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cloud2)
	await process_frame
	var outline: PackedVector2Array = cloud2.cloud_outline(cloud2.CLOUD_CIRCLES,
			cloud2.OUTLINE_SAMPLES, cloud2.FLAT_Y)
	var turns: Array[float] = []
	var min_r := INF
	for i in outline.size():
		var q0: Vector2 = outline[(i - 1 + outline.size()) % outline.size()]
		var q1: Vector2 = outline[i]
		var q2: Vector2 = outline[(i + 1) % outline.size()]
		turns.append(absf(rad_to_deg(angle_difference((q2 - q1).angle(), (q1 - q0).angle()))))
		min_r = minf(min_r, q1.length())
	var corners := 0
	var max_turn := 0.0
	var concave := 0
	for i in outline.size():
		var q0: Vector2 = outline[(i - 1 + outline.size()) % outline.size()]
		var q1: Vector2 = outline[i]
		var q2: Vector2 = outline[(i + 1) % outline.size()]
		if turns[i] <= 30.0:
			continue
		# **只数凸角**。多边形的招牌是凸角——八边形 8/8 全是外凸的。
		# 凹角是相邻两团在谷底交接出来的那道棱，而**那正是评审要的东西**：
		# 「在相邻鼓包之间留出真正的凹口」。两条判据原本互相拆台——
		# 顶边凹口要求谷底有折角，而"不是多边形"那条把折角也记成尖角。
		# 现在这组量到 10 凸 / 5 凹；退回八边形时 8 个仍然全是凸的，那条照样红。
		if (q1 - q0).cross(q2 - q1) < 0.0:
			concave += 1
			continue
		corners += 1
		max_turn = maxf(max_turn, turns[i])
	# 判据是**凸角占顶点的比例**，不是"有没有尖角"：多边形每一个顶点都是尖角，
	# 而一朵云本来就有几处圆与圆交接的棱。旧的八边形是 8/8 = 100%，
	# 判据是"凸角不到三分之一"，于是退回八边形必红。
	_check(corners * 3 < outline.size(),
			"云：描的轮廓不是多边形——%d/%d 个凸角（最大 %.0f°，另有 %d 个谷底凹棱），八边形是 8/8"
			% [corners, outline.size(), max_turn, concave])
	# 云底是一条平边：连着的几个点落在同一条最低线上
	var ymax := -INF
	for q in outline:
		ymax = maxf(ymax, q.y)
	var on_flat := 0
	for q in outline:
		if q.y >= ymax - 0.5:
			on_flat += 1
	_check(on_flat >= 3, "云：底边是平的（%d 个点压在那条线上，至少 3 个）" % on_flat)
	# 每条射线都得打到某个圆：打空的话轮廓退化成一圈默认点，是个星芒而不是一朵云
	_check(min_r > 15.0, "云：轮廓没有退化（最短半径 %.1f > 15）" % min_r)
	# 键盘通路：相邻轨迹点必须隔得开一个 KEY_STEP 以上，否则光标整步走会卡在两点之间
	var min_step := INF
	for i in range(1, cloud2._path_world.size()):
		min_step = minf(min_step, (cloud2._path_world[i - 1] as Vector2)
				.distance_to(cloud2._path_world[i] as Vector2))
	_check(min_step > cloud2.KEY_STEP,
			"云：相邻轨迹点隔 %.1fpx > KEY_STEP %.0fpx（键盘整步走得过去）"
			% [min_step, cloud2.KEY_STEP])
	# 轮廓要**撑满板子**。原来缩放写死 `minf(size.x, size.y) / 300.0`，
	# 而那个 300 是照 720p 手调的：实测轮廓外接盒 130×67，在 1280×720 上
	# 缩成 312px 宽，压在 896px 宽的板子正中间——板子四周空出一大片，
	# 玩家要描的那朵云只占三分之一宽。这一条量的是"轮廓外接盒 / 板子"的比例。
	var board2: Rect2 = cloud2.area_rect(cloud2.size.x, cloud2.size.y)
	var pmin := Vector2(INF, INF)
	var pmax := Vector2(-INF, -INF)
	for q in cloud2._path_world:
		var v: Vector2 = q
		pmin = pmin.min(v)
		pmax = pmax.max(v)
	var frac_x: float = (pmax.x - pmin.x) / board2.size.x
	var frac_y: float = (pmax.y - pmin.y) / board2.size.y
	# 判据是"**卡住的那一维**填满 FIT_FRAC"，不是"两维都填满"：
	# 轮廓本身是 130×67 的两比一，而无头视口是正方的（板子 896×896），
	# 于是它被宽度卡住、纵向只到 46%——那是形状该有的样子，不是没铺开。
	# 真正要拦的是"两头都不满"：那个才是缩放写死的症状。
	_check(maxf(frac_x, frac_y) >= float(cloud2.FIT_FRAC) - 0.02,
			"云：轮廓把板子用满了（横向 %.0f%% / 纵向 %.0f%%，卡住的那维到 %.0f%%）"
			% [frac_x * 100.0, frac_y * 100.0, float(cloud2.FIT_FRAC) * 100.0])
	_check(frac_x <= 0.95 and frac_y <= 0.95,
			"云：轮廓没冲出板子（横向 %.0f%% / 纵向 %.0f%%，各不超过 95%%）"
			% [frac_x * 100.0, frac_y * 100.0])
	# 卡住的那一维要**跟着板子的长宽比翻面**。轮廓是 130×67（比 1.94），
	# 16:9 的板子比值 1.78 还窄一点，所以那里仍然卡在横向；得换一块
	# 比云还宽的板子（1600×720，比值 2.22）才看得见翻面。
	# 用轮廓自己的外接盒，不是 `pmax - pmin` —— 后者已经乘过正方板子的
	# 缩放了，再乘一次就成了 500% 这种数。
	var omin := Vector2(INF, INF)
	var omax := Vector2(-INF, -INF)
	for q in outline:
		var v2: Vector2 = q
		omin = omin.min(v2)
		omax = omax.max(v2)
	var ospan: Vector2 = omax - omin
	var wide: Rect2 = cloud2.area_rect(1600.0, 720.0)
	var sc_w: float = cloud2.fit_scale(outline, wide.size)
	var fx_w: float = ospan.x * sc_w / wide.size.x
	var fy_w: float = ospan.y * sc_w / wide.size.y
	_check(fy_w > fx_w and absf(fy_w - float(cloud2.FIT_FRAC)) < 0.02,
			"云：比云还宽的板子上改成纵向卡满（横向 %.0f%% / 纵向 %.0f%%）"
			% [fx_w * 100.0, fy_w * 100.0])
	# 底被压平过，所以轮廓绕原点并不对称：按原点缩放再摆到板心，云会整体偏上，
	# 板子下沿空出一条。量的是轮廓外接盒的中心离板心有多远。
	var off: Vector2 = (pmin + pmax) * 0.5 - board2.get_center()
	_check(off.length() < board2.size.x * 0.02,
			"云：轮廓在板子里是居中的（偏了 %.1fpx，容差 %.1fpx）"
			% [off.length(), board2.size.x * 0.02])
	# 6h 要用这两个常量，而 6h 排在各段 queue_free() 之后——先存成局部量，
	# 别在后面那一节再去戳一个已经释放的实例
	var cloud_thresh: float = cloud2.SUCCESS_THRESHOLD
	# 云要读得出是**一朵**云，不是一座土包。原来的判据只管"不是多边形"和
	# "底边是平的"，而那两条对一座外凸的土包同样成立——评审读到的就是那座土包。
	# 尺子取评审自己给的那把：剪影面积 / 凸包面积 = 1.0 就是完全凸。
	# 凹口深度用"每个边界点到凸包边界的最大距离"，**不能**在 r(θ) 上数谷：
	# 平底那一段是直线，它的半径在 x=0 处最小，会被当成一个假凹口
	# （第一版就栽在这儿，量出来 2 峰 1 谷、深 4.74，而那 4.74 是平底自己）。
	var c_om := Vector2(INF, INF)
	var c_ox := Vector2(-INF, -INF)
	for q in outline:
		var vq: Vector2 = q
		c_om = c_om.min(vq)
		c_ox = c_ox.max(vq)
	var c_hull: Array[Vector2] = cloud2.convex_hull(outline)
	var c_area := 0.0
	var c_hn := outline.size()
	for i in c_hn:
		c_area += outline[i].x * outline[(i + 1) % c_hn].y \
				- outline[(i + 1) % c_hn].x * outline[i].y
	c_area = absf(c_area) * 0.5
	var c_harea := 0.0
	for i in c_hull.size():
		c_harea += c_hull[i].x * c_hull[(i + 1) % c_hull.size()].y \
				- c_hull[(i + 1) % c_hull.size()].x * c_hull[i].y
	c_harea = absf(c_harea) * 0.5
	var c_iou: float = c_area / c_harea if c_harea > 1e-6 else 0.0
	var c_depth: float = cloud2.max_notch_depth(outline, c_hull)
	# 门槛是量出来的：旧的 CLOUD_CIRCLES 是 iou=0.925、深 4.74（一座土包），
	# 改过之后 iou≈0.92 而深 ≈ 12。凸度比深度卡得更死——一座土包哪怕
	# 有一个浅谷，iou 也几乎不动。
	_check(c_iou <= 0.93,
			"云：轮廓不是一个外凸的土包（剪影/凸包 = %.4f ≤ 0.93；完全凸是 1.0）" % c_iou)
	_check(c_depth >= 9.0,
			"云：相邻鼓包之间留出了真正的凹口（最深 %.1f ≥ 9.0，旧的只有 4.74）" % c_depth)
	# 正对照：上面那两条量的是"鼓包之间凹不凹"，得有一条直接数凹口，
	# 否则"整团一起缩小、深度也跟着缩到门槛下"这类退法照样绿。
	_check(cloud2.top_notches(outline) >= 2,
			"云：顶边上有 %d 个凹口（要求 ≥2，旧的 CLOUD_CIRCLES 是 0）"
			% cloud2.top_notches(outline))
	if is_instance_valid(cloud2):
		cloud2.queue_free()
	await process_frame

	# --- 琴：弦必须按**琴身在该 y 处的实际半宽**裁，雁足必须挂在木头之下 ---
	#
	# 评审读到的是"四条线加四个悬在半空的金色小方块"。两个成因都量得出来：
	# ① 弦原来画到 `board.end.x - 18`，而琴身是内收的多边形——靠外那两根弦
	#    在 x ≈ 0.70·W 之后就已经出了木头，那一段连同两端的琴码/雁柱一起悬空。
	#    靠内那两根（cy ± 0.125H）本来就通宽，所以只是四根里有两根坏掉，
	#    看起来像"四个方块悬在半空"而不是全崩。
	# ② 雁足的落点写死 `tail_h * 0.55`，而琴腹下沿在那个 x 处是
	#    `tail_h * 0.82` 上下——**两只脚整只埋在木头里，一根墨都没露出来**。
	#    这一条评审没看见，是顺着①的坐标往下算时撞上的。
	# 两处都是同一族：**拿尺寸常量的倍数去代替那条真实边界**。修法是抽
	# `body_span_at()` 这个不碰画笔的纯函数，量出来再落笔。
	var zit3: Control = load("res://scripts/mini_games/MiniGameZither.gd").new()
	var z3stub := StubWorld.new()
	stubs.append(z3stub)
	zit3._world_ref = z3stub
	zit3.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(zit3)
	await process_frame
	var zb: Rect2 = zit3._board_rect()
	var zbody: PackedVector2Array = zit3.body_poly(zb)
	var zrow: float = zb.size.y / float(zit3.NOTE_COUNT)
	var z_bad := 0
	var z_worst := INF
	for i in range(zit3.NOTE_COUNT):
		var zy: float = zb.position.y + zrow * (float(i) + 0.5)
		var sp: Vector2 = zit3.string_span(zb, zbody, zy)
		var raw: Vector2 = zit3.body_span_at(zbody, zy)
		# 每根弦两端都必须在木头里，且至少内缩 STRING_INSET。
		# 内缩是**往里**移：左端往右、右端往左，所以是 sp.x - raw.x 和
		# raw.y - sp.y。第一版两个都写反了，四根弦于是全被判成"越界"——
		# 极性写反的断言会红得很有说服力，而那不是产品坏了
		var inset_l: float = sp.x - raw.x
		var inset_r: float = raw.y - sp.y
		if inset_l < float(zit3.STRING_INSET) - 0.5 or inset_r < float(zit3.STRING_INSET) - 0.5:
			z_bad += 1
		z_worst = minf(z_worst, minf(inset_l, inset_r))
		if sp.y - sp.x < 10.0:
			z_bad += 1
	_check(z_bad == 0, "琴：四根弦都按琴身在该 y 处的实际宽度裁了（%d 根越界或短于 10px，最靠边的那根两端各内缩 %.1fpx / 要求 ≥ %.0fpx）" % [z_bad, z_worst, float(zit3.STRING_INSET)])
	# 弦不许短到读成"四个点"。旧的 x1 画到 board.end.x - 18，而现在按琴身收分
	# 之后靠外那两根会短一截——短可以，但得还是一根**贯通的线**。
	var z_short := INF
	for i in range(zit3.NOTE_COUNT):
		var zy2: float = zb.position.y + zrow * (float(i) + 0.5)
		var sp2: Vector2 = zit3.string_span(zb, zbody, zy2)
		z_short = minf(z_short, sp2.y - sp2.x)
	_check(z_short >= zb.size.x * 0.55,
			"琴：最短的那根弦还是贯通的（%.0fpx ≥ 板宽的 55%%，即 %.0fpx）"
			% [z_short, zb.size.x * 0.55])
	# 雁足：每一个顶点都必须落在琴腹下沿之外。木头是按 x 收的，
	# 所以要在**每个顶点自己的 x** 上竖着求下沿——第一版拿
	# `body_span_at`（横向的）去比 y，算出来 drop = 590px，
	# 两只半米长的脚挂在琴底下，而断言照样绿
	var zfa: Vector2 = zit3.foot_anchor(zb, zbody)
	var zfd: float = zb.size.y * 0.16
	var zfps: Array = zit3.foot_polys(zfa, zfd)
	var z_foot_out := 0
	var z_foot_pt := 0
	var z_deep := 0.0
	for fp in zfps:
		for v in fp:
			var v3: Vector2 = v
			z_foot_pt += 1
			var vs: Vector2 = zit3.body_vspan_at(zbody, v3.x)
			if v3.y >= vs.y - 1.0:
				z_foot_out += 1
			z_deep = maxf(z_deep, v3.y - vs.y)
	_check(z_foot_out == z_foot_pt, "琴：雁足整只挂在琴腹之下（%d/%d 个顶点露在木头外面；旧的落点是 tail_h*0.55，两只脚整只埋着，一根墨都没露）" % [z_foot_out, z_foot_pt])
	# 正对照 + 量级：脚画了、露在木头外面、且是**一对脚**的量级而不是半米。
	# 只测"没埋进去"的话，一个 `_draw` 里把画脚那行删掉的版本也照样绿；
	# 而上面那条横向跨度当竖直落差用时 drop 报到 590px，屏上是两根悬空的棍。
	_check(zfps.size() == 2 and z_foot_pt >= 6 and z_deep > 4.0 and z_deep < zfd * 1.6,
			"琴：两只雁足都画出来了、露出木头 %.0fpx（脚高 %.0fpx，要求 4~%.0fpx；横向跨度当竖直落差用时量到 590px）" % [z_deep, zfd, zfd * 1.6])
	if is_instance_valid(zit3):
		zit3.queue_free()
	await process_frame

	# --- 竹：收分的竹身 + 竹节 + 砍倒的斜靠，都得在列里 ---
	var bam2: Control = load("res://scripts/mini_games/MiniGameBamboo.gd").new()
	var b2stub := StubWorld.new()
	stubs.append(b2stub)
	bam2._world_ref = b2stub
	bam2.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bam2)
	await process_frame
	var bh2: float = bam2.size.y * 0.52
	var bbase := Vector2(0.0, bam2.size.y * 0.82)
	var standing: PackedVector2Array = bam2.stalk_poly(bbase, bh2, bam2.STALK_W_BASE,
			bam2.STALK_W_TIP, 0.0)
	var w_bot: float = standing[0].distance_to(standing[3])
	var w_top: float = standing[1].distance_to(standing[2])
	_check(w_bot > w_top * 1.5,
			"竹：竹身是收分的（底 %.0fpx / 顶 %.0fpx），不是一条等宽竖条" % [w_bot, w_top])
	_check(w_bot >= 20.0, "竹：竹身有 %.0fpx 宽，12px 的条上画不出竹节" % w_bot)
	var fracs: PackedFloat32Array = bam2.node_fracs(bam2.NODE_COUNT)
	var nodes_ok: bool = fracs.size() == int(bam2.NODE_COUNT)
	for i in range(fracs.size()):
		if fracs[i] <= 0.0 or fracs[i] >= 1.0:
			nodes_ok = false
		if i > 0 and fracs[i] <= fracs[i - 1]:
			nodes_ok = false
	_check(nodes_ok, "竹：%d 个竹节都落在 (0,1) 里且从下往上排 %s"
			% [fracs.size(), str(fracs)])
	# 砍倒的那截必须老老实实待在自己那一列：横向伸出去的最远点
	# 越过桩的半宽也不许碰到邻居。原来的"倒下去"是把整根往下平移 0.9 倍高，
	# 五根一起平移就成了一片压在底边上的绿条，谁也数不清砍了几根。
	var top2: Vector2 = bbase + Vector2(0.0, -bh2 * bam2.STUMP_FRAC)
	var reach := 0.0
	for s in [-1.0, 1.0]:
		var fell: PackedVector2Array = bam2.stalk_poly(top2, bam2.fall_len(bam2.SPACING),
				bam2.STALK_W_BASE * 0.86, bam2.STALK_W_TIP, bam2.FALL_DEG * s)
		for q in fell:
			reach = maxf(reach, absf(q.x) - bam2.STALK_W_BASE * 0.5)
	_check(reach < bam2.SPACING,
			"竹：砍倒的那截横向伸出 %.0fpx，还在列距 %.0fpx 之内（不压到邻居）"
			% [reach, bam2.SPACING])
	_check(bam2.SPACING > bam2.STALK_W_BASE * 3.0,
			"竹：列距 %.0fpx 撑得开 %.0fpx 的竹身，五根之间留得出缝"
			% [bam2.SPACING, bam2.STALK_W_BASE])
	# 往左往右交替：都往同一边倒的话，靠着的那截会压在右边还立着的那根上
	_check(bam2.fall_dir(0) != bam2.fall_dir(1), "竹：相邻两根往相反方向倒")
	# 还没冒头的那根也得读得出"这里还有一根"。原来只画到 0.10 倍高，
	# 于是一屏是"一根竹子 + 四个几乎看不见的点"，另外四座等于空着。
	var sprout: PackedVector2Array = bam2.stalk_poly(bbase, bh2 * bam2.SPROUT_FRAC,
			bam2.STALK_W_BASE * 0.62, bam2.STALK_W_TIP * 0.7, 0.0)
	var sprout_h: float = sprout[0].y - sprout[1].y
	var sprout_w: float = sprout[0].distance_to(sprout[3])
	_check(sprout_h >= 40.0 and sprout_h > bh2 * 0.12,
			"竹：没冒头的笋有 %.0fpx 高（立着的那根 %.0fpx 的 1/%.1f），不是一粒点"
			% [sprout_h, bh2, bh2 / maxf(sprout_h, 0.01)])
	_check(sprout_w > (sprout[1].distance_to(sprout[2])) * 1.5,
			"竹：笋是收分的（底 %.0fpx / 顶 %.0fpx）" % [sprout_w,
			sprout[1].distance_to(sprout[2])])
	# 顶上的叶必须是**窄条**。原来那片叶横向 116px、垂 52px，比 30px 的竹身
	# 还大，两片一左一右读成一对翅膀。量的是三角形自己的最大垂直宽度
	# （= 2×面积 ÷ 最长边）而不是 `LEAVES` 里那个宽度字段——参数写对了
	# 而画笔没照着画，这一节就该红。
	# 遍历 `LEAVES` 全表而不是挑一片：画笔是整张表循环画的。
	var leaf_ok := true
	var leaf_worst := 0.0
	var leaf_ratio := INF
	var leaf_longest := 0.0
	for L in bam2.LEAVES:
		var row: Array = L
		var leaf: PackedVector2Array = bam2.leaf_poly(
				bbase + Vector2(0.0, bh2 * row[0]), 1.0,
				bh2 * row[1], bh2 * row[2], bh2 * row[3])
		var lv1: Vector2 = leaf[1] - leaf[0]
		var lv2: Vector2 = leaf[2] - leaf[1]
		var lcross: float = absf(lv1.x * lv2.y - lv1.y * lv2.x)
		var llong: float = maxf(leaf[0].distance_to(leaf[2]),
				maxf(leaf[0].distance_to(leaf[1]), leaf[1].distance_to(leaf[2])))
		var lw: float = lcross / maxf(llong, 0.01)
		leaf_worst = maxf(leaf_worst, lw)
		leaf_ratio = minf(leaf_ratio, llong / maxf(lw, 0.01))
		leaf_longest = maxf(leaf_longest, llong)
		if lw > bh2 * 0.06 or llong / maxf(lw, 0.01) < 6.0 or llong > bh2 * 0.35:
			leaf_ok = false
	_check(leaf_ok,
			"竹：%d 片叶全是窄条（最宽 %.0fpx = 竹身 %.0fpx 的 1/%.1f，长宽比 1/%.1f，最长 %.0fpx）"
			% [bam2.LEAVES.size(), leaf_worst, bam2.STALK_W_BASE,
			bam2.STALK_W_BASE / maxf(leaf_worst, 0.01), leaf_ratio, leaf_longest])
	_check(bam2.LEAVES.size() >= 2,
			"竹：顶上画了 %d 层叶（少的那个数一读成一根绿棍子）" % bam2.LEAVES.size())
	# 6h 要用这两个常量，而 6h 排在各段 queue_free() 之后——先存成局部量，
	# 别在后面那一节再去戳一个已经释放的实例
	var bamboo_count: int = bam2.BAMBOO_COUNT
	if is_instance_valid(bam2):
		bam2.queue_free()
	await process_frame

	# --- 琴：徽位 / 岳山 / 雁足 / 标题点了名 ---
	var zit2: Control = load("res://scripts/mini_games/MiniGameZither.gd").new()
	var z2stub := StubWorld.new()
	stubs.append(z2stub)
	zit2._world_ref = z2stub
	zit2.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(zit2)
	await process_frame
	var hui: PackedFloat32Array = zit2.hui_positions(zit2.HUI_FROM, zit2.HUI_TO, zit2.HUI_COUNT)
	var hui_ok: bool = hui.size() == int(zit2.HUI_COUNT) and int(zit2.HUI_COUNT) == 13
	for i in hui.size():
		if hui[i] <= 0.0 or hui[i] >= 1.0:
			hui_ok = false
		if i > 0 and hui[i] <= hui[i - 1]:
			hui_ok = false
	_check(hui_ok, "琴：%d 个徽位从琴额排到雁足、全在 (0,1) 里" % hui.size())
	# 徽排在岳山与雁足**之间**，不是从琴头一路铺到琴尾 —— 铺满全长的话
	# 第一颗就压在岳山上、最后一颗压在雁足上，看着像琴面上多了一条虚线。
	_check(float(zit2.HUI_FROM) > 0.05 and float(zit2.HUI_TO) < 0.95,
			"琴：徽不铺满全长（%.2f ~ %.2f，两头都留了余量）"
			% [zit2.HUI_FROM, zit2.HUI_TO])
	# 徽嵌在琴面正中——那正好是四根弦里中间两根之间的空档。
	# 量的是**弦线**（命中区的中线）而不是命中区的边：命中区是四条首尾相接
	# 铺满琴面的横带，两条边的公共边上什么都没有，弦画在各自那条带的中线上。
	# 压到弦上就看不见了，而看不见的徽等于没有徽。
	var srects: Array[Rect2] = zit2._string_rects()
	var bcy: float = zit2._board_rect().get_center().y
	var s1y: float = srects[1].get_center().y
	var s2y: float = srects[2].get_center().y
	_check(srects.size() == 4 and s1y < bcy and s2y > bcy,
			"琴：正中线落在中间两根弦之间（弦在 %.0f / %.0f，正中线 %.0f）"
			% [s1y, s2y, bcy])
	_check(s2y - s1y > 4.0 * zit2.HUI_R,
			"琴：中间两根弦之间空出 %.0fpx，够摆下 %.0fpx 的徽（%.0fpx 直径）"
			% [s2y - s1y, zit2.HUI_R, zit2.HUI_R * 2.0])
	# 屏上得有一处字点出这把乐器。原来的标题「记住音符顺序并重复」通篇不提琴，
	# 而这一屏上除了标题没有第二个地方说它是什么。
	var zit_title: String = _loc.t("mg_zither_title")
	_check(zit_title.contains("古琴") or zit_title.to_lower().contains("guqin"),
			"琴：标题点了名这把乐器，实际「%s」" % zit_title)
	# 岳山是**压在琴面里**的一道棱，不是一块戳在琴头旁边的牌子。
	# 判据量的是画笔真的摆的那一处（`head_anchor` 和 `_draw` 同源）：
	# 四边都还在琴身的矩形之内。
	var zboard: Rect2 = zit2._board_rect()
	var zhead_h: float = zboard.size.y * 0.5
	var hg: PackedVector2Array = zit2.headgear_poly(zit2.head_anchor(zboard), zhead_h)
	var hg_in := true
	for q in hg:
		var v: Vector2 = q
		if v.x < zboard.position.x or v.x > zboard.end.x \
				or v.y < zboard.position.y or v.y > zboard.end.y:
			hg_in = false
	_check(hg_in, "琴：岳山整道都落在琴面之内（琴面 %.0f..%.0f × %.0f..%.0f）"
			% [zboard.position.x, zboard.end.x, zboard.position.y, zboard.end.y])
	# 雁足两只都撑在**琴腹以下**。原来一支朝上一支朝下，朝上的那支从琴面里钻出来、
	# 顶出琴身，两片脚读成两片鱼鳍。
	var zcy: float = zboard.get_center().y
	var zbody2: PackedVector2Array = zit2.body_poly(zboard)
	var feet_below := true
	for fp2 in zit2.foot_polys(zit2.foot_anchor(zboard, zbody2), zboard.size.y * 0.16):
		for q in (fp2 as PackedVector2Array):
			if (q as Vector2).y <= zcy:
				feet_below = false
	_check(feet_below, "琴：雁足两只都在琴腹中线以下（%.0f），没有一支朝上顶出琴面"
			% zcy)
	if is_instance_valid(zit2):
		zit2.queue_free()
	await process_frame

	# 6h. 进度条：门槛写在了字里，条上却什么都没有。
	#
	# 云那一屏写「到 75% 算过」而条是一条填到头就赢的槽；茶写「3 秒后完成」
	# 而条上只有一条边框；竹连条都没有，只有一行「进度 0/5」。三处都是
	# **把门槛说给玩家听、却不给它一个位置**——玩家盯着一个从 0 爬到 100 的
	# 数，看不出离赢还差多远，而那个差距正是这一屏的全部张力。
	var bar: Object = load("res://scripts/mini_games/MiniGameBar.gd")
	var view := Vector2(1280.0, 720.0)

	# 上面那十几条量的是 `MiniGameBar` 这几个纯函数，**量不到画笔有没有
	# 真的去调它们**——`--headless` 不调 `_draw`，而把画笔那一行的门槛换成
	# 一个字面量的话，几何照样全绿。所以这三条读源码文本（和第 6 节核
	# `MiniGameBackdrop.<THEME>` 同一个办法）：门槛**画在条上**这件事本身，
	# 只能这么钉。
	var csrc: String = FileAccess.get_file_as_string(GAMES[7])
	var tsrc: String = FileAccess.get_file_as_string(GAMES[10])
	var bsrc: String = FileAccess.get_file_as_string(GAMES[14])
	_check(csrc.contains("MiniGameBar.draw_bar(self, bar, _drawn_ratio, SUCCESS_THRESHOLD"),
			"云：画笔把 SUCCESS_THRESHOLD 这个门槛交给进度条（不是自己填个数）")
	_check(tsrc.contains("MiniGameBar.draw_bar(self, bar, held, 1.0"),
			"茶：画笔把门槛（按满即成）交给进度条")
	_check(bsrc.contains("MiniGameBar.draw_pips(self, pbar, BAMBOO_COUNT, _current_bamboo"),
			"竹：画笔把 BAMBOO_COUNT 格交给进度条（原来只有一行「进度 0/5」）")

	# --- 云：75% 那道刻痕 ---
	# 量的是 `threshold_x()` / `tick_span()` 这两个画笔真的调的那一处。
	var cbar: Rect2 = bar.rect(view, 0.88, 0.5, 16.0)
	var ct: float = cloud_thresh
	var cspan: PackedVector2Array = bar.tick_span(cbar, ct)
	var ctx: float = cspan[0].x
	_check(ctx > cbar.position.x + 1.0 and ctx < cbar.end.x - 1.0,
			"云：门槛刻痕落在条**里面**（条 %.0f..%.0f，刻痕在 %.0f）"
			% [cbar.position.x, cbar.end.x, ctx])
	# 刻痕要跨在条外。画在条里面时它就是"条上的一道纹"，和边框、分隔线
	# 长得一样，扫一眼分辨不出它是门槛。
	_check(cspan[0].y < cbar.position.y and cspan[1].y > cbar.end.y,
			"云：刻痕比条高 %.0fpx（上下各露出 %.0fpx）"
			% [cspan[1].y - cspan[0].y, float(bar.TICK_OVERHANG)])
	# 刻痕的位置必须正好是字里报的那个数。两处写的是同一个常量，所以差一步
	# 就是"刻痕在 75%、字里写 70%"——而那正是玩家拿去做决定的那个数。
	var cline: String = _loc.t("mg_complete") % [62, int(ct * 100)]
	_check(cline.contains("%d%%" % int(ct * 100)),
			"云：字里报的门槛和条上的刻痕是同一个数，实际「%s」" % cline)
	# 门槛不能贴着两端：贴 0 是"一开始就赢了"，贴 1 就是"和没画一样"。
	_check(ct > 0.05 and ct < 0.95, "云的门槛在 %.0f%%（不是贴边的装饰）" % (ct * 100.0))

	# 刻痕下面那个「75%」。
	#
	# `draw_string` 的宽度参数是**裁切宽度**。第一版写死 `(-14, 宽度 28)`，
	# 而 16px 的「75%」要 36px 宽——多出来的半个百分号被切掉，定妆照上只剩
	# 「75」。**没有任何量控件尺寸的断言能看见这个**，因为标签的框一直是
	# 28px，它只是把字切了。所以判据量的是那条真正会漏的量：
	# 框宽 vs 字体给这串字量出来的宽度。
	var clab: Rect2 = bar.tick_label_rect(cbar, ct)
	var ctxt: String = "%d%%" % int(ct * 100)
	var cneed: Vector2 = ThemeDB.fallback_font.get_string_size(
			ctxt, HORIZONTAL_ALIGNMENT_LEFT, -1, bar.TICK_LABEL_FONT)
	_check(clab.size.x >= cneed.x,
			"云：刻痕那个「%s」放得下（框 %.0fpx，字要 %.0fpx）"
			% [ctxt, clab.size.x, cneed.x])
	# 而且不许掉出条外：掉出去就成了条底下悬着的一个数，不知道说的是哪根刻痕。
	_check(clab.position.x >= cbar.position.x - 0.01
			and clab.end.x <= cbar.end.x + 0.01,
			"云：那个数落在条的水平范围内（%.0f..%.0f / 条 %.0f..%.0f）"
			% [clab.position.x, clab.end.x, cbar.position.x, cbar.end.x])
	# 门槛贴住条的一头时标签要被夹回来，夹了之后仍得完整。
	var cedge: Rect2 = bar.rect(view, 0.88, 0.5, 16.0)
	var elab: Rect2 = bar.tick_label_rect(cedge, 1.0)
	_check(elab.end.x <= cedge.end.x + 0.01,
			"云：门槛贴到 100%% 时标签被夹回条内（右沿 %.0f / 条尾 %.0f）"
			% [elab.end.x, cedge.end.x])

	# --- 茶：门槛在条的右端，剩下多少秒 ---
	var tbar: Rect2 = bar.rect(view, 0.72, 0.55, 22.0)
	var tspan: PackedVector2Array = bar.tick_span(tbar, 1.0)
	_check(absf(tspan[0].x - tbar.end.x) < 0.01,
			"茶：门槛就是条的右端（刻痕 %.0f / 条尾 %.0f），按满即成"
			% [tspan[0].x, tbar.end.x])
	# 只报百分比的话，玩家得自己乘一个他不知道是多少的 HOLD_DURATION。
	var tleft: String = _loc.t("mg_tea_left") % 1.4
	_check(tleft.contains("1.4") and tleft != "mg_tea_left",
			"茶：另报一句还差几秒，实际「%s」" % tleft)
	# 条不许铺满屏宽。铺满的话右端那条刻痕就是条自己的边框，等于没画。
	_check(tbar.size.x < view.x * 0.9,
			"茶的条只占屏宽 %.0f%%，右端那道刻痕不会和边框重合"
			% (tbar.size.x / view.x * 100.0))

	# --- 竹：五格 ---
	# 分格而不是一根连续条：竹子的进度是**五件互相独立的事**。一根填到 60%
	# 的条读成"有一根被砍掉了 60%"，实际是三根倒了、两根还立着。
	var pbar: Rect2 = bar.rect(view, 0.88, 0.42, 14.0)
	var nb: int = bamboo_count
	var pip_ok := nb == 5
	var pw: float = bar.pip_width(pbar, nb)
	for i in nb:
		var pr: Rect2 = bar.pip_rect(pbar, nb, i)
		if i > 0 and pr.position.x < bar.pip_rect(pbar, nb, i - 1).end.x - 0.01:
			pip_ok = false
		if pr.position.x < pbar.position.x - 0.01 or pr.end.x > pbar.end.x + 0.01:
			pip_ok = false
		if pr.size.x <= 1.0:
			pip_ok = false
	_check(pip_ok, "竹：%d 格不叠、都在条内（每格 %.0fpx，缝 %.1fpx）"
			% [nb, pw, bar.pip_gap(pbar, nb)])
	# 头一格贴着条首、末一格贴着条尾：整排要占满那条，不能缩在里面。
	_check(absf(bar.pip_rect(pbar, nb, 0).position.x - pbar.position.x) < 0.01
			and absf(bar.pip_rect(pbar, nb, nb - 1).end.x - pbar.end.x) < 0.01,
			"竹：五格占满整条（%.0f..%.0f / 条 %.0f..%.0f）"
			% [bar.pip_rect(pbar, nb, 0).position.x,
			bar.pip_rect(pbar, nb, nb - 1).end.x, pbar.position.x, pbar.end.x])
	# 格缝按宽度取：固定 6px 的缝在一条 700px 的条上是 0.9%、在 300px 的
	# 条上是 2%，窄屏上就糊成一片。
	var wide_frac: float = bar.pip_gap(pbar, nb) / pbar.size.x
	var narrow: Rect2 = bar.rect(Vector2(640.0, 720.0), 0.88, 0.42, 14.0)
	_check(absf(bar.pip_gap(narrow, nb) / narrow.size.x - wide_frac) < 0.0001,
			"竹：格缝占条宽 %.2f%%，换半屏宽还是 %.2f%%" % [wide_frac * 100.0,
			bar.pip_gap(narrow, nb) / narrow.size.x * 100.0])

	# 6h-2. 云：操作提示行不许压在要描的那朵云上。
	#
	# 「方向键 / WASD 挪光标 · 按住空格落笔 · ESC 取消」原来落在 `h * 0.8`，
	# 而 720p 上要描的云下缘在 563px、那行字的基线在 576px——**玩家的字就横穿
	# 在要描的那条轮廓的下缘上**，描线全程压着图形。定妆照上看得见，尺寸断言
	# 全绿（框一直在屏内），所以判据量的是**两个 y 区间相交**，不是绝对位置。
	#
	# 轨迹走 `path_for()`：画笔和回归读同一个函数（下面那条读源码文本就是钉它），
	# 否则这里量的是一条和屏上那条不一样的路径。
	var cloud3: Object = load(GAMES[7])
	var hint_txt: String = _loc.t("mg_cloud_hint")
	var hint_need: Vector2 = ThemeDB.fallback_font.get_string_size(
			hint_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, cloud3.HINT_FONT)
	var views: Array = [
		Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0), Vector2(1280.0, 1280.0),
		Vector2(900.0, 1600.0), Vector2(1600.0, 900.0),
	]
	var hint_clear := 0
	var hint_below := 0
	var hint_inside := 0
	var hint_offbar := 0
	var last_hint: Rect2 = Rect2()
	for vp3 in views:
		var v3: Vector2 = vp3
		var p3: PackedVector2Array = cloud3.path_for(v3)
		var pb3: Rect2 = cloud3.path_bounds(p3)
		var hr3: Rect2 = cloud3.hint_rect(v3.x, v3.y, p3, hint_need.x)
		last_hint = hr3
		var vb3: Rect2 = bar.rect(v3, cloud3.BAR_Y_FRAC, cloud3.BAR_W_FRAC, cloud3.BAR_H)
		var y_lo3: float = maxf(pb3.position.y, hr3.position.y)
		var y_hi3: float = minf(pb3.end.y, hr3.end.y)
		var hit: bool = y_hi3 > y_lo3
		if not hit:
			hint_clear += 1
		_check(not hit,
			"云：%dx%d 提示行不压在要描的云上（云 %.0f..%.0f，提示 %.0f..%.0f）"
			% [int(v3.x), int(v3.y), pb3.position.y, pb3.end.y,
			hr3.position.y, hr3.end.y])
		if hr3.position.y >= pb3.end.y:
			hint_below += 1
		if hr3.position.x >= 8.0 and hr3.position.y >= 8.0 \
				and v3.x - hr3.end.x >= 8.0 and v3.y - hr3.end.y >= 8.0:
			hint_inside += 1
		var b_lo3: float = maxf(vb3.position.y, hr3.position.y)
		var b_hi3: float = minf(vb3.end.y, hr3.end.y)
		if b_hi3 <= b_lo3:
			hint_offbar += 1
	# 上面那五条是逐档视口的；这四条是整体结论，不该靠人加总。
	_check(hint_below == views.size(),
		"云：提示行在云的**下方**，不是躲到图形上面去（%d/%d 档）"
		% [hint_below, views.size()])
	_check(hint_inside == views.size(),
		"云：提示行五档视口都在屏内且离边 ≥8px（%d/%d 档）"
		% [hint_inside, views.size()])
	_check(hint_offbar == views.size(),
		"云：提示行也不压在进度条上（%d/%d 档）" % [hint_offbar, views.size()])
	# `draw_string` 的宽度参数是**裁切宽度**（同族的坑在 6h 门槛标签上犯过一次），
	# 而这行字改成了左对齐 + 量出来的宽度：框不够宽就把最后一个字切掉。
	_check(last_hint.size.x >= hint_need.x,
		"云：提示那行字放得下（框 %.0fpx，字要 %.0fpx）" % [last_hint.size.x, hint_need.x])
	# 字形盒整个在行盒里。`draw_string` 的 position.y 是**基线**不是行盒顶——
	# 量行盒量不出字形有没有探出去（同族第 6i 节那条）。
	var hint_font: Font = ThemeDB.fallback_font
	var glyph_h: float = hint_font.get_ascent(cloud3.HINT_FONT) \
			+ hint_font.get_descent(cloud3.HINT_FONT)
	_check(glyph_h <= cloud3.HINT_LINE_H,
		"云：提示行的字形盒 %.0fpx 装得进行盒 %.0fpx" % [glyph_h, cloud3.HINT_LINE_H])
	# 又是读源码文本那两条：上面量的是 `hint_rect()` 这个纯函数，量不到画笔
	# 有没有去调它——把它调成 `h * 0.8` 的话几何全绿而图上那行字又压回云上。
	_check(csrc.contains("var hint: Rect2 = hint_rect(w, h, PackedVector2Array(_path_world),"),
		"云：画笔的落位走 hint_rect()（不是又写死一个 h*0.8）")
	_check(not csrc.contains("Localization.t(\"mg_cloud_hint\"), HORIZONTAL_ALIGNMENT_CENTER, w, 20,"),
		"云：提示行没有退回那个压在图形上的居中写死落位")
	# 落笔位置也要取自那一行盒。上面那条量的是"整行调用在不在"，这一条量的是
	# **位置从哪来**：把 `Vector2(0.0, h * 0.8)` 写回画笔，提示行就又压在云上了，
	# 而两条文本断言都必须红——它们守的是同一件毛病的两半。
	_check(csrc.contains("Vector2(hint.position.x, hint.position.y + ThemeDB.fallback_font.get_ascent(HINT_FONT)),"),
		"云：提示行的落笔位置取自 hint_rect 给的那行盒（不是又写死一个 h*0.8）")
	# 轨迹也只有一份：画笔和回归读同一个 path_for()
	_check(csrc.contains("for p in path_for(size):"),
		"云：画笔的轨迹走 path_for()（回归量的是同一个函数）")

	# 6i. 取消按钮：它是最不费事的一个动作，却穿了一件警报红的衣服。
	#
	# 原来的颜色是 fill (0.4, 0.3, 0.3) + border (0.8, 0.3, 0.3)。全工程真正
	# 在报警的红是 `HUD3D.set_boundary_intensity()` 那圈边界警告
	# (0.75, 0.12, 0.12) 和竹子那根砍伐窗口倒计时 —— 玩家学会
	# 「红 = 出事了」之后，再在角落里看见一块红，读出来的是「取消要付代价」。
	# 而它不要付：ESC 也能按，驿站还能再来一次。
	#
	# 判据量的不是"不是那个红"（那是拿自己测自己），而是**读作警报的那两个量**：
	# 饱和度，以及红通道比另两路高出多少。写成单边的 `<=`，不是"等于某个值"。
	var chrome: Object = load("res://scripts/mini_games/MiniGameChrome.gd")

	# 真警报的基线：拿产品里那圈边界警告红当尺子。取消按钮必须**明显比它弱**，
	# 否则它仍然和"出事了"共用一种语言。
	var alarm: Color = Color(0.75, 0.12, 0.12)
	var alarm_sat: float = (alarm.r - alarm.b) / maxf(alarm.r, 0.001)
	_check(alarm_sat > 0.5, "先确认这把尺子真的是红的（饱和度 %.2f）" % alarm_sat)

	var chrome_ok := true
	var worst_sat := 0.0
	var worst_excess := 0.0
	for c in [chrome.FILL, chrome.BORDER, chrome.LABEL]:
		var col: Color = c
		var mx: float = maxf(col.r, maxf(col.g, col.b))
		var mn: float = minf(col.r, minf(col.g, col.b))
		var sat: float = (mx - mn) / maxf(mx, 0.001)
		# 红通道高出另两路多少。0.63 的旧边框这一项是 0.50。
		var excess: float = col.r - maxf(col.g, col.b)
		worst_sat = maxf(worst_sat, sat)
		worst_excess = maxf(worst_excess, excess)
		if sat > 0.25 or excess > 0.10:
			chrome_ok = false
	_check(chrome_ok,
			"取消按钮三档色都读作中性（最高饱和度 %.2f、红通道最多高出 %.2f，"
			% [worst_sat, worst_excess]
			+ "而警报红是 %.2f / %.2f）"
			% [alarm_sat, 0.5])

	# 底板不透明：五个小游戏的背景亮度差得远，半透明底板的对比度随背景漂，
	# 而"这个字在五屏上都读得出来"只有底板自己说了算才立得住。
	_check(chrome.FILL.a >= 0.999,
			"取消按钮的底板不透明（alpha %.2f），对比度不随背景漂" % chrome.FILL.a)

	# 字在**它自己的底板**上要 ≥4.5:1。这条量的是玩家读的那一层，
	# 而不是"按钮在整屏上亮不亮"。
	var lab_lum: float = _wcag_lum(chrome.LABEL)
	var fill_lum: float = _wcag_lum(chrome.FILL)
	var ratio: float = (maxf(lab_lum, fill_lum) + 0.05) / (minf(lab_lum, fill_lum) + 0.05)
	_check(ratio >= 4.5, "「取消」在自己那块底板上 %.1f:1（≥4.5）" % ratio)

	# 边要能把板子的轮廓勾出来：糊进底色里的话，玩家看不见这是一块可点的东西。
	var bord_lum: float = _wcag_lum(chrome.BORDER)
	var edge: float = (bord_lum + 0.05) / (fill_lum + 0.05)
	_check(edge >= 3.0, "边框对底板 %.1f:1（≥3.0，那块板子的轮廓勾得出来）" % edge)

	# 字放得下。`draw_string` 的宽度是**裁切宽度**，给窄了半个字被切掉
	# （同一个坑在进度条的门槛标签上犯过一次，见 6h）。
	var lrect: Rect2 = chrome.label_rect(chrome.cancel_rect(view))
	var ctext: String = _loc.t("mg_cancel")
	var cneed2: Vector2 = ThemeDB.fallback_font.get_string_size(
			ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, chrome.LABEL_FONT)
	_check(lrect.size.x >= cneed2.x,
			"「%s」放得下（框 %.0fpx，字要 %.0fpx）" % [ctext, lrect.size.x, cneed2.x])
	# 框要整个落在按钮里，且按钮整个落在屏里。量的是**字形盒**
	# （用字体真实 ascent/descent 算出来的那个），不是任意一个行盒——
	# 框在按钮里而字形探出边沿，正是量行盒量不出来的那种坏。
	_check(lrect.position.y >= chrome.cancel_rect(view).position.y
			and lrect.end.y <= chrome.cancel_rect(view).end.y,
			"字形整个在按钮之内（%.0f..%.0f / 按钮 %.0f..%.0f）"
			% [lrect.position.y, lrect.end.y,
			chrome.cancel_rect(view).position.y, chrome.cancel_rect(view).end.y])
	var cr: Rect2 = chrome.cancel_rect(view)
	_check(cr.position.x >= 0.0 and cr.position.y >= 0.0
			and cr.end.x <= view.x and cr.end.y <= view.y,
			"取消按钮整个在屏内（%.0f,%.0f %.0f×%.0f / 屏 %.0f×%.0f）"
			% [cr.position.x, cr.position.y, cr.size.x, cr.size.y, view.x, view.y])
	# 贴边会被读成系统按钮。离屏边至少 8px。
	_check(cr.position.x >= 8.0 and cr.position.y >= 8.0
			and view.x - cr.end.x >= 8.0 and view.y - cr.end.y >= 8.0,
			"取消按钮没贴着屏边（左 %.0f / 上 %.0f / 右 %.0f / 下 %.0f）"
			% [cr.position.x, cr.position.y, view.x - cr.end.x, view.y - cr.end.y])
	# 换个分辨率仍然贴右下角——不能写成绝对坐标。
	var cr2: Rect2 = chrome.cancel_rect(Vector2(1920.0, 1080.0))
	_check(absf(cr2.end.x - 1920.0) - 20.0 < 0.01
			and absf(cr2.end.y - 1080.0) - 16.0 < 0.01,
			"1080p 上仍贴在右下（右边 %.0f / 下边 %.0f）"
			% [1920.0 - cr2.end.x, 1080.0 - cr2.end.y])

	# 五个小游戏都得**调那个共用函数**。又是读源码文本那几条：几何量的是
	# `MiniGameChrome` 自己那一个函数，量不到五个画笔有没有去调它——
	# 禽原来连画都没画，竹原来也只在 `_gui_input` 留了 ESC。
	var zsrc: String = FileAccess.get_file_as_string(GAMES[13])
	var bsrc2: String = FileAccess.get_file_as_string(GAMES[4])
	var basrc: String = FileAccess.get_file_as_string(GAMES[14])
	for pair in [[GAMES[7], csrc], [GAMES[10], tsrc], [GAMES[13], zsrc],
			[GAMES[4], bsrc2], [GAMES[14], basrc]]:
		var pr: Array = pair
		_check((pr[1] as String).contains("MiniGameChrome.draw_cancel(self,"),
				"%s：画笔调共用的取消按钮（不是各画一份）"
				% (pr[0] as String).get_file())
	# 热区不许再抄一份 `Rect2(w - 160, ...)`：画和点各一份的话，挪一次按钮
	# 就得改两处，而漏掉的那一处症状是「看得见点不着」。
	for pair in [[GAMES[7], csrc], [GAMES[10], tsrc], [GAMES[13], zsrc],
			[GAMES[4], bsrc2], [GAMES[14], basrc]]:
		var pr2: Array = pair
		var body: String = pr2[1]
		_check(not body.contains("w - 160, h - 60") and not body.contains("size.x - 160, size.y - 60"),
				"%s：热区也走 cancel_rect()，没抄第二份矩形"
				% (pr2[0] as String).get_file())
	# 竹那一屏的左键是"砍"，所以**取消的热区必须判在砍之前**。
	# 判在后面的话，点了取消反而挨一刀——而这一屏 ESC 是隐藏的，
	# 鼠标玩家发现不了还能走。
	_check(basrc.find("cancel_rect(size).has_point(event.position)")
			< basrc.find("_cut_current_bamboo()\n"),
			"竹：取消热区判在当成砍之前（判在后面的话，点取消反而挨一刀）")

	# 6d. 「第十八驿」是世界里的第 18 座驿站吗？不是 —— 那是旅店的名字。
	# 顶栏写的是「已过 n 驿」，明信片背面写「第十八驿在我这儿」，
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

	_section_backdrops()
	_section_rotation()
	for s in stubs:
		s.free()
	print("[verify_mini_game] ", "PASS" if _failures == 0 else "FAIL", " failures=", _failures)
	quit(0 if _failures == 0 else 1)
