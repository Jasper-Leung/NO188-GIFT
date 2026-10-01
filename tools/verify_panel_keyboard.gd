extends SceneTree
## verify_panel_keyboard.gd — 纯键盘能不能从冷启动走到第一次踩上踏板。
##
## 修的是两处，它们是同一个漏洞的两端：
##  1. `OnboardingGuide` 上唯一的出口是一个 Button，而全工程只有它没调
##     `grab_focus()`（GiftBox 抓 `_start_btn`、EndCard 抓 `_export_btn`）。
##     于是 `gui_get_focus_owner()` 一直是 <null>，空格/回车没有接收者——
##     而 `World3D._play_prologue()` 是 `await _onboarding.dismissed`，
##     键盘玩家卡死在**第一屏**，连序章都没开始。
##  2. Button 的 `ui_accept` 是引擎内建动作、按 `keycode` 匹配，而 Web 导出下
##     `keycode` 可能填不上（本项目 InputMap 当年就是因为这个才全用
##     physical_keycode）。于是只带物理键的事件在按钮那头不算命中——
##     补 `grab_focus()` 只能救桌面端，Web 上这一屏仍然出不去。
##     `OnboardingGuide._unhandled_input()` 是第二半：不走 GUI 路由，
##     只认物理键。（写 `_gui_input` 不行，见那处的注释。）
##
## 两半各测一遍：第 1 节用**只带 physical_keycode** 的事件（Web 的形状），
## 第 2 节用完整事件（桌面的形状）。只测一种的话，另一半坏了照样全绿。
##
## 断言不止"面板不见了"：`dismissed` 的下游是序章对白，所以这里一路推到
## `prologue_done` 且玩家真的能移动。面板单独消失但游戏没启动，也算红。
##
## 必须带窗口跑：headless 的 dummy display server 不做焦点路由，
## 没有焦点这一整节就量不到，跑出来的 PASS 是假的。
## `--quit-after` 是帧数不是秒，这台机器窗口下 280+ FPS，要给足。
## 用法： godot --path . --script tools/verify_panel_keyboard.gd --quit-after 60000

const WAIT_MS := 8000

var _failures := 0
var _gm: Node = null
var _loc: Node = null
var _world: Node = null


func _check(cond: bool, label: String) -> void:
	if cond:
		print("[OK]   ", label)
	else:
		_failures += 1
		print("[FAIL] ", label)


## 只填 physical_keycode，keycode 留 0 —— 复刻 Web 导出下的键盘事件
func _push_physical_only(key: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		ev.pressed = pressed
		Input.parse_input_event(ev)


## 完整事件。桌面键盘两个码都填得上，也是内建 ui_accept 唯一认的那种
func _push_full(key: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = key
		ev.physical_keycode = key
		ev.pressed = pressed
		Input.parse_input_event(ev)


## 等到 cond 为真或超时。**按墙钟等，不是按帧数**——窗口模式下这台机器
## 280+ FPS，拿帧数当秒数会把"没等到"直接判成"等到了"。
func _until(cond: Callable, what: String) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < WAIT_MS:
		if cond.call():
			return true
		await process_frame
	print("[FAIL] 等不到：%s（%d ms）" % [what, Time.get_ticks_msec() - t0])
	_failures += 1
	return false


func _focus_desc() -> String:
	var f: Control = root.gui_get_focus_owner()
	if f == null:
		return "<null>"
	return "%s(%s)" % [f.name, f.get_class()]


func _initialize() -> void:
	for n in {
		"GameManager": "res://scripts/GameManager.gd",
		"AudioManager": "res://scripts/AudioManager.gd",
		"Localization": "res://scripts/Localization.gd",
	}:
		if root.get_node_or_null(n) == null:
			var node: Node = load(n).new()
			node.name = n
			root.add_child(node)
	_gm = root.get_node("GameManager")
	_loc = root.get_node("Localization")

	# —— 第 1 节：只带 physical_keycode 的空格（Web 的形状）——
	await _section("只带 physical_keycode", true)
	# —— 第 2 节：完整空格（桌面的形状），并一路推到玩家解禁 ——
	await _section("完整 keycode + physical_keycode", false)
	# —— 第 3 节：铺子买得到吗 ——
	await _shop_section()

	_report()


## 铺子那一屏。原来 `_button()` 一律 `focus_mode = FOCUS_NONE`，于是键盘玩家
## 能用 ESC 关掉铺子，却一件也买不了——面板上每一行都写着价钱和「买」，
## 一块看得见（鼠标）摸不着（键盘）的经济系统。
##
## 判据不看"焦点在某个按钮上"，看**按下去真的买到了**：驿铺第一件
## （素笺，price 0）永远买得起，于是空格一按 `postcard_tier` 就该变成 1。
func _shop_section() -> void:
	print("\n---- 铺子：键盘能不能买到东西 ----")
	var w: Node = _world
	_gm.reset()
	_gm.headless_mode = false
	_gm.onboarding_shown = true     # 别让操作说明面板挡在前面
	_gm.prologue_done = true
	_gm.check_in(0)                 # 走真实入口拿旅币，不手写存档

	var panel: Node = w._shop_panel
	# 得真的站在铺子跟前：`World3D._physics_process` 里"面板开着却骑出了
	# 铺子范围就自动收摊"，而 `_nearby_shop_idx` 是每帧按距离算的。
	# 第一版直接 `_open_shop(0)`，于是买完的下一帧铺子自己收了，
	# 断言读到的 visible=false 是测试自己造出来的，不是被测代码的问题。
	w._player.position = w._stations[0].position + Vector3(0, 1.0, 3)
	if not await _until(func(): return w._nearby_shop_idx == 0, "站到驿铺跟前（_nearby_shop_idx=%d）"
			% w._nearby_shop_idx):
		return
	w._open_shop(0)                 # 驿铺（seen_unlock = 0，开局就开着）
	if not await _until(func(): return panel != null and panel.visible, "驿铺打开"):
		return

	var f: Control = root.gui_get_focus_owner()
	_check(f is Button, "铺子一开就有按钮拿着焦点（焦点 = %s）" % _focus_desc())
	_check(f is Button and not (f as Button).disabled,
			"焦点落在一个买得起的按钮上（焦点 = %s）" % _focus_desc())

	var before: int = _gm.get_postcard_tier()
	_push_physical_only(KEY_SPACE)
	await _until(func(): return _gm.get_postcard_tier() != before,
			"按一次空格就买到东西（postcard_tier %d → %d）"
			% [before, _gm.get_postcard_tier()])
	_check(_gm.get_postcard_tier() == 1,
			"空格买到了第一件（素笺），postcard_tier=%d" % _gm.get_postcard_tier())
	_check(panel.visible, "买完东西铺子还开着（visible=%s）" % str(panel.visible))

	# 买完之后焦点得落在**还买得了**的那一件上。停在刚刚买下的那件（已经 disabled）
	# 上是最坏的一种：按钮只是变灰了，而变灰正是"买到了"该有的反馈，
	# 于是玩家按第二下空格什么都不会发生，还以为是自己没按对。
	var fo: Control = root.gui_get_focus_owner()
	_check(fo is Button, "买完之后焦点仍在某个按钮上（焦点 = %s）" % _focus_desc())
	_check(fo is Button and not (fo as Button).disabled,
			"焦点不在一个已经买不了的按钮上（焦点 = %s）" % _focus_desc())

	# ESC 关铺子（这条本来就通，顺带钉住它没被上面几处改坏）
	_push_physical_only(KEY_ESCAPE)
	await _until(func(): return not panel.visible, "ESC 关掉铺子")


## 装一份全新的 World3D 当新玩家，跑完一整条"操作说明 → 序章 → 能骑"。
## with_prologue = true 时把序章也推完，顺带钉住 dismissed 的下游。
func _section(title: String, physical_only: bool) -> void:
	print("\n---- %s ----" % title)
	_gm.reset()
	# reset() 把 prologue_done / seen_villain 归零，正是"新玩家"该有的状态。
	# headless_mode 必须 false：序章对白要真的弹出来，await 才有下游。
	_gm.headless_mode = false
	_gm.onboarding_shown = false

	var w: Node = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(w)
	_world = w

	# `_onboarding` 是 `_ready()` 里挂的，add_child 返回时还不在。上一版直接
	# 解引用，于是抛 "Invalid access to property 'visible' on Nil" 把协程掐断，
	# `quit()` 永远走不到，进程被 --quit-after 收掉时**退出码是 0**——
	# 一条一行断言都没打过的回归，看着像跑通了。
	if not await _until(func(): return w._onboarding != null, "操作说明面板挂上视口"):
		return
	var ob: Control = w._onboarding
	var dlg: Node = w._dialogue_popup

	# 面板淡入 0.4s，等它淡完再按
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 700:
		await process_frame
	_check(ob.visible, "操作说明面板自动弹出")

	# 第一道门：面板上得有焦点，而且那个焦点就是出口按钮。
	# 这一条是修 grab_focus 的判据——原来这里是 <null>，后面每一条都必然红。
	var f: Control = root.gui_get_focus_owner()
	_check(f != null, "面板可见时视口里有焦点（焦点 = %s）" % _focus_desc())
	_check(f is Button and (f as Button).text == _loc.t("start_ride"),
			"焦点落在出口按钮「%s」上（焦点 = %s）" % [_loc.t("start_ride"), _focus_desc()])
	_check(not dlg.visible, "收面板之前序章对白还没开始")

	var push := _push_physical_only if physical_only else _push_full
	push.call(KEY_SPACE)
	await _until(func(): return not ob.visible, "一次空格收掉操作说明面板")
	if ob.visible:
		return

	# 面板淡出 0.3s，dismissed 在末尾才发。序章对白紧接着弹出来。
	await _until(func(): return dlg.visible, "面板一收，序章对白就弹出来（dismissed 的下游真的走了）")
	_check(not _gm.prologue_done, "面板一收不等于序章完成（序章还在播）")
	_check(int(w._check_in_in_progress) == 0,
			"收面板那一下空格没漏成驿站打卡（_check_in_in_progress=%s）"
			% str(w._check_in_in_progress))

	# 一路推到玩家真的能骑
	var guard := Time.get_ticks_msec()
	while dlg.visible and Time.get_ticks_msec() - guard < WAIT_MS:
		_push_full(KEY_SPACE)
		await process_frame
		await process_frame
	_check(not dlg.visible, "序章对白能一路用空格推完")
	_check(_gm.prologue_done, "序章标记完成（prologue_done=%s）" % str(_gm.prologue_done))
	await _until(func(): return w._player._can_move, "序章收尾之后玩家解禁")

	# 同一次空格不许收起两遍面板：多发一次 `dismissed` 会顶掉序章那一轮对白，
	# 那一条 await 就永远等不到（见 CLAUDE.md「一个 await 挂死了不会自己报错」）。
	# 所以这里要求序章对白**只弹过一次**——第二遍世界是干净的，不该有残留。
	_check(int(w._check_in_in_progress) == 0, "全程没有误触发驿站打卡")


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


func _report() -> void:
	print("\n==== verify_panel_keyboard ====")
	var bad := _failures
	print("[verify_panel_keyboard] %s  (失败 %d)" % ["PASS" if bad == 0 else "FAIL", bad])
	# 序章会写 user://gift188.cfg。跑完必须清掉，否则下次进游戏面板直接不弹，
	# 这条回归自己就测不到东西了。
	if _gm != null and _gm.has_method("_clear_save"):
		_gm._clear_save()
	quit(0 if bad == 0 else 1)