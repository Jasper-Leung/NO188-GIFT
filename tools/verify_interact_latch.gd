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
## 5/6 两条后来补的，都是同一个键在两处说话：
##   5  贴脸时提示文字不许掉出屏外（63 点网格扫）
##   6  **反派戏期间脚下的圈不许还在推销打卡** —— 打卡被 ① 挡掉了，
##      可 `CheckInPrompt._prompt_target()` 只读 `_nearby_station_idx`、
##      不知道 `_villain_playing`，于是圈一边写着「空格 · 完成乐事」，
##      一边在同一次按键里变灰成「这里现在进不去」，而那一次按键正在推进对白。
##      7  铺子最终可达（这条回归的终点：不再需要重开游戏）
##      8  驿站占地不许骑进去：半径必须小于打卡半径（否则被墙挡住打不了卡）、
##         从站心放开要真被摆出去、满速撞 3 秒钻不进去
##      9  **郑铎打断的落点**：贴着碎片站时不起播、骑开了才起播、
##         一次只排一场（阈值被一口气冲掉也只放一场）、入场提示浮得出来、
##         收尾时相机锁与 look_at 都还回去
##
## 第 6 节要注入真空格，但**加不加 --headless 都跑得过**（两种都实测过）：
## `DialoguePopup` 推进对白走的是 `Node._input()`，不走焦点路由，注入的空格照样到得了。
## 与「headless 收不到按键」那条结论不冲突——那边卡住的是 `Button` 的 `ui_accept`，
## 那才是 GUI 焦点路由的范围。

const SHOT_DIR := "user://lookdev_journey"
## 轮换表。第 4 节要认"回访该玩哪一件"，判据只能取产品自己的那张表——
## 这里重抄一份的话，产品把轮换改坏了这条也会照样绿。
const MiniGamePicker = preload("res://scripts/mini_games/MiniGamePicker.gd")
const RevisitNote = preload("res://scripts/RevisitNote.gd")

var _fails := 0
var _gm: Node = null
var _world: Node = null

## 第 10 节的收尾旗 + 断言条数下限。
##
## 加这条是因为真的踩了一次：`_section10` 里写了个不存在的
## `Player3D.get_can_move()`，抛异常把**整节**掐断，而 `await` 一个抛异常的
## 协程不会把异常往上抛——`_run()` 接着走完、照样打出
## `PASS (失败 0)`。**一整节断言一行没跑，报告却全绿**，
## 跟 CLAUDE.md 里记的「一条回归自己抛异常时退出码是 0」是同一族。
## 旗子必须由这一节**自己**在末尾置位，中途抛异常就永远置不上。
var _s10_done := false
var _ck_total := 0
var _s10_ck_at_start := 0
const _S10_MIN_CK := 20


func _ck(label: String, cond: bool, detail: String = "") -> void:
	_ck_total += 1
	if cond:
		print("[OK]   ", label)
	else:
		_fails += 1
		print("[FAIL] ", label + ("（" + detail + "）" if detail != "" else ""))


## 剔掉行注释（GDScript 只有 `#` 行注释），保留字符串字面量里的 `#`。
## 文本判据读源码之前必须先过这一道——本工程栽过两次同一个坑：
## `edge_line_color` 声明了整整一个项目从没被读过、`HUD3D` 那块注释里
## 描述的帮助面板从来没被打开过。**注释里写着的那句话和代码真的那么干，
## 是三件事**，而 `contains()` 分不出来。
func _strip_comments(src: String) -> String:
	var out: Array = []
	for line in src.split("\n"):
		var res := ""
		var quote := ""
		for i in line.length():
			var ch := line[i]
			if quote != "":
				res += ch
				if ch == quote:
					quote = ""
			elif ch == "\"" or ch == "'":
				quote = ch
				res += ch
			elif ch == "#":
				break
			else:
				res += ch
		out.append(res)
	return "\n".join(out)


## 读一个 .gd 文件、剔掉注释、再切出**某一个函数**的正文。
##
## 两个动作各自都有它自己的理由，缺一个就量错东西：
## · 剔注释——见 `_strip_comments()`，不剔的话下面那段解释本身的散文里
##   就写着要找的那个 key，把真调用删掉照样全绿。
## · 限死函数体——不限的话量的是"这个文件里有这句话"，而这一族要的
##   是"**这一处**有没有调它"。同一个字符串在文件别处也合法出现。
## 限的时候要认 `static func`：只找 `"\nfunc "` 的话，一个 static 函数
## 后面若跟的是另一个 static 函数，正文会一路取到文件末尾。
func _func_body(path: String, fn: String) -> String:
	var src := _strip_comments(FileAccess.get_file_as_string(path))
	var start := src.find("func %s(" % fn)
	if start < 0:
		return ""
	var lines := src.substr(start).split("\n")
	var body: Array = []
	for i in lines.size():
		if i > 0:
			var t := lines[i].strip_edges()
			if t.begins_with("func ") or t.begins_with("static func "):
				break
		body.append(lines[i])
	return "\n".join(body)


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


## 站到这座站**最近能站的地方**（`STATION_KEEPOUT_PAD` 之外 0.6m）。
##
## 不能随手写死 3m/1.2m：`World3D._apply_station_keepout()` 会把钻进占地的车
## 摆回墙外，于是回归"瞬移到站中心"量到的其实是墙外那个位置——
## 而且是隔了几帧才摆过去的，中间态连断言的时序都不对。要贴脸就得贴着墙站。
func _teleport_close(station_idx: int) -> Vector3:
	var r: float = _world.station_keepout_radius(station_idx)
	if r <= 0.0:
		# 模型还没流进来（这条回归开跑时 GLB 是异步加载的），先按最小的一座估
		r = 5.0
	var pos: Vector3 = _world._stations[station_idx].position + Vector3(0, 1.0, r + 0.6)
	_world._player.position = pos
	_world._last_global_pos = _world._player.global_position
	_world._has_last_pos = true
	_world._interact_cooldown = 0.0
	_world._recheck_armed = true
	_world._check_in_in_progress = false
	_world._mini_game_state = -1
	return pos


func _teleport(station_idx: int) -> void:
	_world._close_shop()
	_teleport_close(station_idx)


## 把车摆到**离所有待到访碎片驿站都远**的路面上。
##
## 第 6 节原来 `_teleport(4)`，而 4 正是五座碎片站之一（`[7,10,13,14,4]`）。
## 第 9 节那道落点闸（`VILLAIN_MIN_TARGET_DIST`）会据此判定"玩家正贴着目标"
## 而一直不起播，于是第 6 节等的是一个**永远不会到达的状态**、`_until` 走满
## 超时后把后面所有断言一起染红——而报上来的现象是"被测代码坏了"。
## 回归自己站到了一个游戏已经不触发的地方，就得把它挪到游戏真的会触发的地方去。
##
## "远"按游戏自己的判据算（离**还要去**的碎片站最远），不写死一个距离：
## 写死的话，哪天碎片站的顺序变了、或者这一轮已经收齐了，这个位置就不再远，
## 而第 6 节又会开始等一个等不到的东西。
func _teleport_open_road() -> Vector3:
	var rd = _world._road_builder.get_road_data()
	var best := Vector3.ZERO
	var best_d := -1.0
	for line in _world._road_builder.get_all_centerlines():
		for p in line:
			var d := 1e9
			for i in rd.stations.size():
				if not _gm.fragment_station_needs_visit(i):
					continue
				var sp: Vector3 = _world._stations[i].position
				d = minf(d, Vector2(p.x - sp.x, p.z - sp.z).length())
			if d > best_d:
				best_d = d
				best = p
	var pos := Vector3(best.x, _world._get_terrain_height(best.x, best.z), best.z)
	_world._player.position = pos
	_world._last_global_pos = _world._player.global_position
	_world._has_last_pos = true
	_world._interact_cooldown = 0.0
	_world._recheck_armed = true
	return pos


## 带窗口跑这一节才对：`CheckInPrompt` 靠真实按键事件驱动，而 headless 用的是
## dummy display server，不做真焦点路由，注入进去的空格到不了 `_input`。
## 完整事件（keycode + physical_keycode），桌面键盘两个码都填得上。
func _push_space() -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_SPACE
		ev.physical_keycode = KEY_SPACE
		ev.pressed = pressed
		Input.parse_input_event(ev)


## 按墙钟等，不是按帧数——窗口模式下这台机器 280+ FPS，
## 拿帧数当秒数会把"没等到"直接判成"等到了"。
func _until(cond: Callable, what: String) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		if cond.call():
			return true
		await process_frame
	_ck("等不到：%s" % what, false)
	return false


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
	# 现在对白前面有一段入场（提示 + 镜头收束，`VILLAIN_CAM_PULL_SEC` +
	# `VILLAIN_CAM_HOLD_SEC`，合计 1.8s），所以这里必须**等它真的弹出来**，
	# 不能再用"两帧之后应该在"——那一版量到的是入场中间态，
	# 报上来的现象是"对白没起来"，而真相是"还没到"。
	await _until(func(): return _world._dialogue_popup.visible,
			"郑铎第一段对白弹出来")
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
	# ---------- 4b 首访那一屏有没有把「规则」说出口 ----------
	#
	# 「还差 2 次」顶栏一直在写，所以"这一站要来三次"玩家知道；
	# **"每次换一件乐事"这一半从头到尾没有任何一个像素告诉过玩家**——
	# 于是他把两次回访读成"再玩一遍刚才那件"，而三次到访是完满评级
	# 唯一的门槛、也是全游戏最强的重玩钩子。补的那一句写在**首访**，
	# 因为那是唯一一次他还来得及决定要不要为这件事再跑两趟的时刻。
	#
	# 量的是 `_popup_foot_text()` 这个**纯函数**（不碰画笔），所以要在
	# `check_in()` **之前**问：那一刻 `is_collected(4)` 还是假，问到的才是首访那一支。
	var foot_first: String = _world._popup_foot_text(4)
	_ck("首访底行说出了「三次到访，三件乐事」这条规则",
			foot_first.contains(_root_loc().t("checkin_three_joys")),
			"底行写着：%s" % foot_first)
	# 正对照：原来那半句还在。把「获得碎片」换成规则句的话这一条会红。
	_ck("正对照：首访底行仍然报「获得碎片」（不是被规则句顶掉了）",
			foot_first.contains(_root_loc().t("fragment_obtained")),
			"底行写着：%s" % foot_first)
	# **这一行必须放得下**。量的是 `get_string_size()` 而不是那个框的宽度——
	# `FragmentLabel` 开着 `AUTOWRAP_WORD_SMART`，字比框宽就折行，
	# 而框在 VBox 里是固定高的一格，折出来的那一截画到面板外面去。
	#
	# **框宽必须先把弹窗显示出来量**：那一瞬弹窗还是 `visible = false`，
	# 容器没排过版，而带 `autowrap_mode` 的 Label 在排版之前 `size.x` 是
	# **1px**——于是"字比框宽"恒真，量到的是一个还没存在过的框
	# （第一版就栽在这里：框宽读到 1px、两条一起红，读起来像产品坏了）。
	# 顺便把弹窗放出来还顺带量到了"这一屏真的排得下"之外的那一半：
	# 面板是 `.tscn` 里写死的 600×360、VBox 两侧各 inset 30，
	# 而**那个 540 是产品自己的排版结果，不许在测试里手抄**。
	var lbl: Label = _world._popup_fragment
	var popup: Control = _world._check_in_popup
	var was_popup_visible: bool = popup.visible
	var popup_was_collecting: bool = _world._collecting_label.visible
	popup.visible = true
	_world._collecting_label.visible = false
	await process_frame
	await process_frame
	var frame_w: float = lbl.size.x
	_ck("正对照：弹窗排过版之后那一行的框宽是个真宽度（不是 1px）",
			frame_w > 200.0, "框宽 %.1fpx——弹窗多半还没排版" % frame_w)
	# 取不到字体的话 `fnt` 是 null，下面两条会直接报错，
	# 所以先钉一条"字体真的取到了"。
	var fnt: Font = lbl.get_theme_font("font")
	var fsz: int = lbl.get_theme_font_size("font_size")
	_ck("正对照：那一行真的量到了字宽（两语都 > 0，字体不是 null）",
			fnt != null and fsz > 0, "font=%s size=%d" % [str(fnt), fsz])

	var loc: Node = _root_loc()
	var saved_lang: String = str(loc.get("current_language"))
	# **必须走 `set_language()`，不许 `set("lang", …)`**：那个属性名是
	# `current_language`，而 `Object.set()` 对不存在的属性是**静默空操作**——
	# 于是"切到英文"那一步没发生，量到的还是中文，而两条断言一模一样地绿着
	# （第一版正是这样：英文那条 detail 里印出来的写着「获得碎片：禽」）。
	# 这和 CLAUDE.md 里「量状态切换的断言必须自己先把起点摆出来」是同一条，
	# 只是这次连切都没切成功。
	loc.call("set_language", "zh")
	var t_zh: String = _world._popup_foot_text(4)
	var zh_w: float = 0.0 if fnt == null \
			else fnt.get_string_size(t_zh, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	_ck("首访那一行中文放得下（不折行、不画到面板外）", zh_w <= frame_w,
			"字宽 %.0fpx，框宽 %.0fpx，字号 %d" % [zh_w, frame_w, fsz])
	loc.call("set_language", "en")
	# 正对照：这一遍真的切过去了。`set_language()` 只在 key 不存在时静默
	# 返回，而 key 写错的话上面那条量到的仍然是中文。
	_ck("正对照：这一遍真的切到了英文（不然下面那条量的是同一串字）",
			str(loc.get("current_language")) == "en"
			and _world._popup_foot_text(4) != t_zh,
			"current_language=%s，底行写着：%s"
			% [str(loc.get("current_language")), _world._popup_foot_text(4)])
	var t_en: String = _world._popup_foot_text(4)
	var w_en: float = 0.0 if fnt == null \
			else fnt.get_string_size(t_en, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	_ck("首访那一行英文也放得下（英文长一截，只量中文等于没量）",
			w_en <= frame_w,
			"字宽 %.0fpx，框宽 %.0fpx，字号 %d；写着：%s"
			% [w_en, frame_w, fsz, t_en])
	loc.call("set_language", saved_lang)
	# 摆出来的现场要原样收回去：后面紧跟着的就是真的 `check_in(4)`，
	# 而那一趟自己会把弹窗弹出来、被玩家按掉。留一个可见的弹窗在那儿，
	# 后面量到的就不是这一趟的世界了。
	popup.visible = was_popup_visible
	_world._collecting_label.visible = popup_was_collecting
	# 读源码文本：几何函数对不对、和画笔有没有去调它是两件事，而**这一族
	# 连"函数被调过"都不量得到**（首访那一屏在这一次里根本没弹出来）。
	# 剥掉注释再限死函数体——不剥注释的话，这句解释本身的散文里就写着
	# `checkin_three_joys`，把真调用删掉照样全绿。
	var w3src: String = _func_body(
			"res://scripts/World3D.gd", "_popup_foot_text")
	_ck("画笔真的调了那条规则（读源码文本，剥注释 + 限函数体）",
			not w3src.is_empty() and w3src.contains('t("checkin_three_joys")'),
			"函数体 %d 字，里面没有那个 key" % w3src.length())

	_gm.check_in(4)                   # 第 1 次：拿到碎片
	_teleport(4)
	await process_frame
	# 旧口径在这里会把这一站从"下一处"里摘掉。可完满评级要求每座碎片驿站
	# 去过 3 次，第一次拿到碎片之后还剩两次 —— 摘掉它等于把最强的重玩钩子
	# 从顶栏上抹了，而脚下的圈还照亮 2 次。
	_ck("首次到访后：顶栏仍指这一站（还欠 2 次到访）",
			_world._hud3d._next_fragment_target().get("idx", -1) == 4,
			"顶栏指的是 %s" % str(_world._hud3d._next_fragment_target().get("idx", -1)))
	_ck("首次到访后：顶栏说的是「再访」不是「下一处」",
			_world._hud3d._next_label.text != ""
			and not _world._hud3d._next_label.text.contains(
					_root_loc().t("hud_next_target").split("%s")[0]),
			"顶栏写着：%s" % _world._hud3d._next_label.text)
	_ck("首次到访后：顶栏写出了还差几次",
			_world._hud3d._next_label.text.contains(
					(_root_loc().t("visits_left_n") % 2)),
			"顶栏写着：%s" % _world._hud3d._next_label.text)
	_ck("回访站仍可打卡（还差两次到访，不是死路）", _world._can_start_check_in(4),
			"环数上限 3 次，回访是设计内的")
	# 回访只给旅币不给碎片，所以不能说"完成乐事"；但也不能一直说"歇一脚"——
	# 第三次到访是完满评级的最后一格，对着它劝退就等于把钩子自己掐了。
	_ck("回访时提示圈写的是还差几次，不是「完成乐事」也不是「歇一脚」",
			_visit_prompt_label().contains(
					(_root_loc().t("desktop_revisit_prompt") % 2)),
			"圈上写着：%s" % _visit_prompt_label())
	# 跑一遍完整回访序列。回访现在**也会有一件乐事**——原来只有首次到访才进
	# `_run_mini_game()`，于是完满评级要的三次里后两次是空的。所以序列变成
	# 1.0s 运镜 + 1.5s 定格 + 小游戏 + 面板 1.0s 飞行 + 0.4s 收尾，
	# 4.0s 之内小游戏根本不会结束，得先把它交掉再等面板。
	#
	# 里程先推到**第二圈**：回访那句话按"第几次 × 绕没绕完一圈"选，
	# 不把里程推上去的话"绕没绕圈"那半边在这一次里恒等于 0，
	# 于是**把圈数那一路整个删掉，这些断言照样全绿**。里程是真的骑出来的，
	# 推 `_odometer_units` 就是玩家真骑了一整圈。
	_world._odometer_units = _world._total_arclen
	var lvbi_before: int = _gm.lvbi
	_world._do_check_in(4)
	var waited := 0.0
	while _world._mini_game_state != _world.MG_RUNNING and waited < 10.0:
		await create_timer(0.1).timeout
		waited += 0.1
	_ck("回访也有一件乐事（原来后两次到访是空的）",
			_world._mini_game_state == _world.MG_RUNNING,
			"等了 %.1fs，状态还是 %d" % [waited, _world._mini_game_state])
	# 而且必须是**换过的那件**。驿站4 是槽位 4：第一次玩禽，第二次该轮到云。
	# 这里只认 MiniGamePicker 算出来的那一个——把轮换退化成"每次都玩自己
	# 那件"的话，这一条是唯一会红的地方。
	if _world._mini_game_node != null and is_instance_valid(_world._mini_game_node):
		var got: String = str(_world._mini_game_node.get_script().resource_path)
		var want: String = MiniGamePicker.script_for(4, 1)
		_ck("回访玩的是轮到的那一件，不是原样重播", got == want,
				"实际 %s，该是 %s" % [got.get_file(), want.get_file()])
		# 这一节量的是"回访这一趟的账"，不是怎么描完一朵云。直接交成功，
		# 免得把云的描边逻辑在这里重演一遍（它有自己的一节，见 verify_mini_game）。
		if _world._mini_game_state == _world.MG_RUNNING:
			_world._on_mini_game_done(0)
	await create_timer(4.0).timeout
	_ck("回访序列跑完了", not _world._check_in_in_progress)
	_ck("回访跑完没有留下小游戏", _world._mini_game_node == null
			and _world._mini_game_state != _world.MG_RUNNING,
			"node=%s state=%d" % [str(_world._mini_game_node), _world._mini_game_state])
	# _popup_text 在面板收掉之后仍然留着最后写的字，所以断字比断可见性稳。
	# 断的是"选句函数返回的那一个 key"，不是某句写死的文案——
	# 原来这里写的是 `_root_loc().t("revisit_note")`，而那句话对第 2 次和
	# 第 3 次到访都成立，**一个恒真的判据看起来像在守着这件事**。
	_ck("回访面板写的是「第 2 次 + 已绕完一圈」那一句",
			_world._popup_text.text == _root_loc().t(
					RevisitNote.key(1, 1)),
			"面板上写着：%s" % _world._popup_text.text)
	# 正对照：这次**真的**推过了一整圈，所以"没绕圈"那一句必须不是它。
	# 这一条是圈数那一路的**承重**判据——把 `_lap_index()` 换成 `return 1`
	# 或者干脆不调它，这里才会红。
	_ck("里程推了一整圈，写出来的不再是「没绕圈」那一句",
			_world._popup_text.text != _root_loc().t(RevisitNote.key(1, 0)),
			"两档撞成同一句了：%s" % _world._popup_text.text)
	# 「这一趟玩的是哪一件」必须**说出口**。原来这块 Label 在回访时整个
	# 被藏掉，于是 MiniGamePicker 那张轮换表从头到尾没有任何一个像素
	# 告诉过玩家——他每次都以为重玩的是同一件。
	var want_joy: int = MiniGamePicker.game_for(4, 1)   # 驿站4=槽位4，第2次
	_ck("回访面板说出了这一趟轮到的乐事",
			_world._popup_fragment.visible
			and _world._popup_fragment.text == _root_loc().t("mg_played")
					+ _root_loc().t(RevisitNote.joy_key(want_joy)),
			"面板上写着：%s（该是第 %d 件）"
			% [_world._popup_fragment.text, want_joy])
	_ck("回访不再谎报「获得碎片」",
			not _world._popup_fragment.text.contains(
					_root_loc().t("fragment_obtained")),
			"面板上写着：%s" % _world._popup_fragment.text)
	_ck("回访照样发旅币", _gm.lvbi > lvbi_before,
			"%d → %d" % [lvbi_before, _gm.lvbi])
	_ck("回访打卡次数累到 2", _gm.get_station_count(4) == 2,
			"实际 %d" % _gm.get_station_count(4))

	# ---------- 5 提示文字不许掉出屏外 ----------
	# 玩家越骑越近，站点的投影就越往画面下方跑，贴着站停下时圈已经压在 720 上，
	# 那行"空格 · 完成乐事"整个在屏外——恰恰是最该读到它的一刻。
	# 真相机走贴脸那一档 + 全屏 63 点网格扫：只测真相机碰上的那一个点，
	# 镜头一改就又漏了。
	var cp = _world._check_in_prompt
	_ck("提示圈铺满视口", cp.size.x > 1000.0 and cp.size.y > 500.0,
			"size=%s" % str(cp.size))
	var st_pos: Vector3 = _world._stations[4].position
	_teleport_close(4)   # 贴到墙外最近的那一点，投影落进画面下半
	await process_frame
	await process_frame
	var cam: Camera3D = _world._player_cam
	var sp: Vector2 = cam.unproject_position(st_pos)
	var fs := 16 if _root_loc().is_english() else 18
	var tw: float = ThemeDB.fallback_font.get_string_size(
			_cp_label(), HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	var lp: Vector2 = cp._label_pos(sp, 46.0, tw, fs)
	_ck("贴脸时提示文字在屏内",
			lp.y >= float(fs) and lp.y + float(fs) <= cp.size.y
			and lp.x >= 0.0 and lp.x + tw <= cp.size.x,
			"站投影 y=%.0f → 文字 y=%.0f，屏高 %.0f" % [sp.y, lp.y, cp.size.y])
	var off := []
	for gx in 9:
		for gy in 7:
			var probe := Vector2(float(gx) * cp.size.x / 8.0, float(gy) * cp.size.y / 6.0)
			var p: Vector2 = cp._label_pos(probe, 46.0, tw, fs)
			if p.y < float(fs) or p.y + float(fs) > cp.size.y \
					or p.x < 0.0 or p.x + tw > cp.size.x:
				off.append(str(probe))
	_ck("全屏 63 个取样点上文字都在屏内", off.is_empty(), "越界于 %s" % str(off))

	# ---------- 6 反派戏期间脚下不许还在推销打卡 ----------
	# 第 1 节量的是"郑铎在播时**打卡**进不去"，这一节量的是同一次按键的**另一半**：
	# 圈还在推销。按键把打卡挡掉了，可 `_on_interact_blocked()` 照跑，而
	# `CheckInPrompt._prompt_target()` 只读 `_nearby_station_idx`、不知道
	# `_villain_playing`，于是圈一边画着「空格 · 完成乐事」，一边在同一次按键里
	# 变灰成「这里现在进不去」。玩家看着对白在推进、脚下的圈在同时说他按错了。
	# 这一节只测"那一圈和那句话该不该存在"，不测对白推进本身（第 3 节测了）。
	_gm._clear_save()
	_gm.headless_mode = false
	_world._headless_mode = false
	# 前面的第 3 节在 headless 下碰过一次 `_play_villain_scene`，那一次已经把
	# 第 0 场 consume 掉了（armed 清空 + claim 成功 + 立即 return）。这里复位，
	# 否则这一节等的是一个已经放过的场，测的是空气。
	_gm.seen_villain = 0
	# 先按住不放，等基线量完再上膛。`_try_villain_scene()` 每帧轮询，
	# 一起播就晚了——上一版把基线断言写在 `_teleport` 后面两帧，那两帧里
	# 反派戏已经起来，`_can_start_check_in` 自然 false，量到的不是"戏前"，
	# 而且这条断言会一直红，看起来像被测代码坏了。
	var cp6 = _world._check_in_prompt
	_world._villain_armed = [false, false, false]
	_teleport(4)
	await process_frame
	await process_frame
	_ck("起始：反派戏之前圈是亮的（这一节不是在测一个本来就不亮的圈）",
			not cp6._prompt_target().is_empty()
			and _world._can_start_check_in(4),
			"圈目标=%s can_start=%s" % [str(cp6._prompt_target()),
					str(_world._can_start_check_in(4))])
	# 基线量完就挪到空路上：4 号站本身是碎片站，第 9 节的落点闸会一直按住
	# 反派戏不放（这正是它该做的），而第 6 节要量的是"戏一起播那半边"。
	var open_p: Vector3 = _teleport_open_road()
	_ck("挪到了离所有待到访碎片站都远的地方（否则第 6 节会等一个不触发的状态）",
			not _world._too_close_to_target(),
			"最近 %s，距站 4 %.1fm" % [str(_world._too_close_to_target()),
					Vector2(open_p.x - _world._stations[4].position.x,
					open_p.z - _world._stations[4].position.z).length()])

	# 上膛。触发条件是"路过 4 座驿"（VILLAIN_SCENES[0].seen = 4）；回归是瞬移的，
	# 前面几节路过几座全看瞬移顺序，所以这里显式补足，不靠巧合。
	# 前面第 3 节在 headless 下碰过一次 `_play_villain_scene`，那一次已经把第 0 场
	# consume 掉了（armed 清空 + claim 成功 + 立即 return），所以 seen_villain 也要复位。
	for i in [0, 1, 2, 3]:
		_gm.on_station_pass(i)
	_world._villain_armed = [true, true, true]

	if await _until(func(): return _world._villain_playing, "郑铎第 0 场起播"):
		# 必须再等两个物理帧：`_try_villain_scene()` 是在 `_physics_process` 的
		# **末尾**把 `_villain_playing` 置上的，而清 `_nearby_*` 的那张早退单子在
		# **开头**——所以起播那一帧过后还差一帧才清完。立刻断言就量到了那一帧的
		# 中间态（带窗口跑时碰巧赶上了，带 headless 跑时就赶上不到了，
		# 同一份代码两种模式结论相反）。
		await process_frame
		await process_frame
		_ck("反派戏起播后脚下不再有可交互目标",
				cp6._prompt_target().is_empty(),
				"圈还指着 %s —— 它在推销一个这一趟按不出来的交互" % str(cp6._prompt_target()))
		_ck("反派戏期间按空格不给「进不去」那句",
				_world._interact_blocked_reason() == "",
				"报的是 %s" % _world._interact_blocked_reason())
		var dp6 = _world._dialogue_popup
		# `_villain_playing` 现在比对白弹起来早 1.8 秒（入场那一下），
		# 所以必须等弹窗真的可见再往下量。少了这一句，`_typewriter_done`
		# 读的是上一轮留下的 true，于是空格打在**入场那一段**上——
		# 那一段没有对白在接，于是"空格推进了一行"永远量到 0 → 0，
		# 报上来的现象是"按键被吃掉了"，而真相是"对白还没开始"。
		await _until(func(): return dp6.visible, "反派戏的对白真的弹出来")
		# 打字机没走完时按空格只是把这一行补全（`_on_next_pressed` 的第一个分支），
		# 不换行。所以这里等它走完再量"空格推进了一行"，否则量的是补字。
		await _until(func(): return dp6._typewriter_done, "第一行打字机走完")
		var line_before: int = dp6._line_idx
		_push_space()
		await process_frame
		await process_frame
		await process_frame
		_ck("这一次空格仍然是在推进对白（不是被吃掉了）",
				dp6._line_idx > line_before,
				"对白行 %d → %d" % [line_before, dp6._line_idx])
		_ck("推进对白的这一次空格没有顺手开打卡",
				not _world._check_in_in_progress)
		_ck("推进对白的这一次空格没有把圈变灰",
				cp6._blocked_key == "",
				"圈上写着 %s" % cp6._blocked_key)
		# 推到整场结束：验它自己收尾，也验它没有把这一趟永久锁死
		var guard := Time.get_ticks_msec()
		while _world._villain_playing and Time.get_ticks_msec() - guard < 15000:
			_push_space()
			await process_frame
			await process_frame
		_ck("整场推完后 _villain_playing 归位",
				not _world._villain_playing,
				"漏了这一句，铺子从此再也开不了")
		_ck("反派戏记进了进度",
				_gm.seen_villain == 1, "seen_villain=%d" % _gm.seen_villain)
	_teleport(4)
	await process_frame
	await process_frame
	_ck("反派戏散场后圈重新亮起（不是被永久收走了）",
			not cp6._prompt_target().is_empty(),
			"圈目标=%s" % str(cp6._prompt_target()))
	_ck("反派戏散场后这一站还能打卡",
			_world._can_start_check_in(4))
	_world._headless_mode = true
	_gm.headless_mode = true

	# ---------- 6b 暂停时脚下的圈要收掉 ----------
	# 和第 6 节同一个家族（"这些状态下提示不许还在推销一个按不出来的交互"），
	# 但成因不同，所以收的地方也不同：`_physics_process` 那张早退单子管的是
	# **状态还在跑**的情形，而暂停是**树停了**——`_process` 不再跑，
	# `queue_redraw()` 再也不来，圈会**冻在最后一帧**上继续显示。
	# 暂停面板的遮罩是 0.8 alpha（3D 透出来是故意的），于是那圈和它那行
	# 「空格 · 进入小镇」会从面板底下透上来，正好落在「语言」那一行上，
	# 读起来就是「语言：空格 · 进入小镇」。定妆照 `lookdev_journey` 的
	# `04a_pause_暂停面板` 就是这么发现的。
	_teleport(4)
	await process_frame
	await process_frame
	_ck("挪到碎片站 4 旁边时圈是亮的（这一节的前提，不成立的话后面恒绿）",
			not cp6._prompt_target().is_empty(),
			"圈目标=%s" % str(cp6._prompt_target()))
	_world.toggle_pause()
	await process_frame
	_ck("暂停面板弹出来了", _world._pause_panel.visible)
	_ck("暂停时脚下的圈收掉了（不许冻在最后一帧上透过面板继续显示）",
			not _world._check_in_prompt.visible,
			"visible=%s" % str(_world._check_in_prompt.visible))
	_world.toggle_pause()
	await process_frame
	_ck("继续之后圈又回来了（不是被永久收走）",
			_world._check_in_prompt.visible)

	# ---------- 7 铺子最终可达 ----------
	_teleport(shop_idx)
	await process_frame
	await process_frame
	_ck("铺子能开（回归的终点：不再需要重开游戏）",
			_world._can_open_shop(_world._nearby_shop_idx))

	# ---------- 8 驿站占地不许骑进去 ----------
	# `Player3D` 是直接 `position += forward * speed * delta` 的，没有碰撞求解器，
	# 而 16 座站的亭子最大一座占地近 16m 宽。车能直接开进亭子里，相机跟着穿进
	# 模型内壁，贴脸那一屏的下半屏全是内壁。修法是一圈硬推出（不是软力：
	# 15m/s 一帧 0.25m，力推拦不住）。
	#
	# 这三条各自盯一件会悄悄坏掉的事：
	#   · 半径全部 < STATION_PASS_RADIUS —— 否则玩家被挡在打卡圈外面，
	#     顶栏「下一处 … Nm」永远减不到 0、圈永远不亮；
	#   · 从站心放开会被摆到墙外 —— 推出真的在跑；
	#   · 满速冲 3 秒穿不过去 —— 半径不是只在慢速下才拦得住。
	await _until(func(): return _world.station_keepout_radius(4) > 0.0,
			"站 4 的模型流进来（半径量出来了）")
	var worst_r := 0.0
	for i in _world._stations.size():
		worst_r = maxf(worst_r, _world.station_keepout_radius(i))
	_ck("16 座站都量出了占地（没有一座半径是 0）",
			worst_r > 0.0, "最大 %.2fm" % worst_r)
	_ck("挡车半径全部小于打卡半径（玩家被墙挡住就打不了卡了）",
			worst_r < float(_world.STATION_PASS_RADIUS),
			"最大 %.2fm vs STATION_PASS_RADIUS %.1fm"
			% [worst_r, _world.STATION_PASS_RADIUS])
	var r4: float = _world.station_keepout_radius(4)
	var c4: Vector3 = _world._stations[4].position
	_world._player.position = c4
	_world._last_global_pos = _world._player.global_position
	await create_timer(0.5).timeout
	var d4 := Vector2(_world._player.position.x - c4.x, _world._player.position.z - c4.z).length()
	_ck("从站心放开会被摆到墙外（不是留在亭子里）", d4 >= r4 - 0.05,
			"停在 %.2fm，半径 %.2fm" % [d4, r4])
	_ck("摆到墙外之后仍然打得到卡（这一屏还是到站那一屏）",
			_world._can_start_check_in(4) and d4 <= _world.STATION_PASS_RADIUS,
			"距站 %.2fm" % d4)
	# 满速撞墙：位置每帧被摆回边界，速度每帧被 damp_speed 掉一点，测的是有没有哪一帧钻了进去。
	# 先把操纵权要回来——第 4/6 节走完真打卡之后 `_can_move` 可能还锁着，
	# 而 `Player3D._physics_process` 开头就 return，车根本不动，那样测的是空气。
	_world._player.set_can_move(true)
	_world._player.position = c4 + Vector3(r4 + 4.0, 0, 0)
	_world._player.rotation.y = atan2(-(c4.x - _world._player.position.x),
			-(c4.z - _world._player.position.z))
	_world._player._speed = 15.0
	var thru := 0
	var t_end := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < t_end:
		await process_frame
		if Vector2(_world._player.position.x - c4.x,
				_world._player.position.z - c4.z).length() < r4 - 0.5:
			thru += 1
	_ck("满速 15m/s 撞 3 秒钻不进亭子", thru == 0,
			"有 %d 帧人在墙里（末速度 %.1f）" % [thru, _world._player.get_speed()])
	_ck("撞墙之后车真的慢下来了（不是贴着墙蹭着走）",
			_world._player.get_speed() < 15.0,
			"末速度 %.1f" % _world._player.get_speed())

	await _section9_villain_placement()
	await _section10_synthesis_choice()
	_verify_section10_completed()

	_gm._clear_save()
	print("\n[verify_interact_latch] %s  (失败 %d)" % [
			"PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)


func _root_loc() -> Node:
	return root.get_node("Localization")


## 郑铎打断的**落点**：什么时候才该把他叫出来。
##
## 实测（`.review/play_newcomer2.txt` ~146s）：玩家离目标还有 15m、正全速冲刺，
## 车突然停住，一个不认识的人开始讲 9 行台词——第一次读到这一屏的人，
## 报上来的现象是"游戏卡了"。所以这里钉三件事：
##   1  贴着碎片站时**不起播**，而且是"不消费"（armed 还在，等骑开了再放）
##   2  阈值被一口气冲掉时**一次只放一场**（不是三场连着灌）
##   3  入场真的有一个可归因的边界：一行提示 + 一次镜头收束，然后才是对白；
##      散场时相机锁和 look_at 都还回去
##
## 第 3 条的收尾是这里最容易漏的一处：`_play_villain_scene()` 现在
## `set_camera_locked(true)` 并置 `_cam_look_at_active`，而漏掉其中任何一个
## 的话，相机就再也不跟车了——车照跑、镜头定死在原地，而且**没有任何断言会红**。
func _section9_villain_placement() -> void:
	print("\n---- 9. 郑铎打断的落点 ----")
	var hud = _world._hud3d
	var loc = _root_loc()
	_gm._clear_save()
	_gm.headless_mode = false
	_world._headless_mode = false
	_gm.seen_villain = 0
	_world._villain_playing = false
	_world._villain_last_play_seen = -999
	_world._villain_armed = [true, true, true]
	_world._player.set_camera_locked(false)
	_world._player.set_can_move(true)

	# -- 1. 站在碎片站边上：不该起播，且这一场不能被消费掉 --
	_teleport(4)
	await process_frame
	await process_frame
	for i in range(0, 4):
		if i != 4:
			_gm.on_station_pass(i)
	await process_frame
	await process_frame
	_ck("贴着碎片站时反派戏不起播（正冲刺的人被冻住读成'卡了'）",
			not _world._villain_playing,
			"_villain_playing=%s" % str(_world._villain_playing))
	_ck("贴着目标时这一场**没有被消费掉**（是延后，不是取消）",
			bool(_world._villain_armed[0]) and _gm.seen_villain == 0,
			"armed=%s seen_villain=%d" % [str(_world._villain_armed), _gm.seen_villain])
	_ck("这一条闸确实判的是距离（站到站里就是'太近'）",
			_world._too_close_to_target(), "")

	# -- 2. 骑到空路上：这一场该放了 --
	var open: Vector3 = _teleport_open_road()
	await process_frame
	if not await _until(func(): return _world._villain_playing,
			"骑离目标之后第 0 场起播（位置 %s）" % str(open)):
		return

	# 入场：提示 + 镜头收束。这一段在第 9 条改动之前根本不存在。
	await process_frame
	var cue: Label = hud._cue_label
	var cue_name: Label = hud._cue_name_label
	_ck("起播后浮出了入场提示（让'刚才那一下'有出处）",
			cue != null and str(cue.text) == loc.t("villain_cue_1"),
			"写着「%s」" % ("" if cue == null else str(cue.text)))
	_ck("入场提示带着角色名", cue_name != null
			and str(cue_name.text) == loc.t("villain_speaker"),
			"写着「%s」" % ("" if cue_name == null else str(cue_name.text)))

	# 镜头真的被收束了：相机被冻住，且注视目标被接管。
	var moved := false
	var t_cue := Time.get_ticks_msec() + 1200
	while Time.get_ticks_msec() < t_cue:
		await process_frame
		if _world._cam_look_at_active:
			moved = true
	var cam_locked: bool = _world._player.is_camera_locked()
	_ck("入场时相机被锁住并接管了注视目标",
			cam_locked and moved and _world._cam_look_at_active,
			"locked=%s look_at=%s" % [str(cam_locked), str(_world._cam_look_at_active)])

	# 对白弹起来之前，入场提示必须先收掉：两层底板叠着是字压在字上。
	if await _until(func(): return _world._dialogue_popup.visible, "入场之后对白弹出来"):
		_ck("对白弹起时入场提示已经让位",
				str(cue.text) == "" and float(hud._cue_holder.modulate.a) <= 0.001,
				"text=「%s」a=%.2f" % [str(cue.text),
				float(hud._cue_holder.modulate.a)])

	# -- 3. 把整场推完，验收尾把相机还回去了 --
	var guard := Time.get_ticks_msec()
	while _world._villain_playing and Time.get_ticks_msec() - guard < 20000:
		_push_space()
		await process_frame
		await process_frame
	_ck("整场推完后 _villain_playing 归位", not _world._villain_playing, "")
	_ck("整场推完后相机锁还回去了（漏了它车还在跑、镜头定死）",
			not _world._player.is_camera_locked(), "locked=%s" % str(_world._player.is_camera_locked()))
	_ck("整场推完后 look_at 也还回去了（漏了它镜头再也回不到车后面）",
			not _world._cam_look_at_active, "active=%s" % str(_world._cam_look_at_active))
	_ck("本场确实播的是第 0 场", _gm.seen_villain == 1,
			"seen_villain=%d" % _gm.seen_villain)

	# -- 4. 一次只排一场：阈值一口气冲到 12，也只该再放一场 --
	# 场景就是玩家从 4 驿一路骑到 12 驿：三场同时武装、同时够阈值。
	# 没有场次间隔闸的话，第 1 场刚结束第 2 场立刻顶上来，一口气灌完。
	#
	# 必须真的把 seen 顶到 **12 以上**，不然第 3 场自己的阈值就没到、
	# 它压根不武装 —— 于是"第 3 场没排上"这条断言在闸被删掉之后照样绿。
	# 这一版第一遍只过了 11 座（0~10），第 3 场从来没到过阈值，量的是空气。
	_teleport_open_road()
	_world._villain_armed = [true, true, true]
	for i in [5, 6, 7, 8, 9, 10, 11, 12]:
		_gm.on_station_pass(i)
	await process_frame
	await process_frame
	# 这里只钉前提的"数量"那一半。`armed` 那一半**不能**在这里断言：
	# 上面已经让了两帧物理时间，第 3 场要么被闸挡住（armed 仍为 true）、
	# 要么已经起播（armed 已翻 false）——两种都是对的行为，
	# 写进前提里只会在闸被删掉时误报一条与被测无关的红。
	_ck("驿数真的顶到第 3 场的阈值了（否则下面几条量的是空气）",
			_gm.get_seen_station_count() >= int(_world.VILLAIN_SCENES[2]["seen"]),
			"seen=%d 阈值=%d" % [_gm.get_seen_station_count(),
			int(_world.VILLAIN_SCENES[2]["seen"])])
	_ck("阈值一口气冲过之后立刻又放了一场",
			_world._villain_playing and _gm.seen_villain == 2,
			"playing=%s seen_villain=%d" % [str(_world._villain_playing), _gm.seen_villain])
	# 就在这场开着的时候，第 3 场不许也排上队
	_ck("第 3 场没有同时排上（一次只排一场）",
			bool(_world._villain_armed[2]),
			"armed=%s" % str(_world._villain_armed))

	guard = Time.get_ticks_msec()
	while _world._villain_playing and Time.get_ticks_msec() - guard < 20000:
		_push_space()
		await process_frame
		await process_frame
	# 必须再等几个物理帧再断言：`while` 是在 `_villain_playing` 变 false 的**那一帧**
	# 退出的，而第 3 场要等下一个 `_physics_process` 才起播。不等的话量到的
	# 是"还没轮到它"，而不是"它被闸挡住了"——这一版回归在闸被删掉之后照样全绿。
	await create_timer(0.5).timeout
	_ck("第 2 场收尾后第 3 场仍未排上（场次间隔闸在起作用）",
			bool(_world._villain_armed[2]) and _gm.seen_villain == 2
			and not _world._villain_playing,
			"armed=%s seen_villain=%d playing=%s" % [str(_world._villain_armed),
			_gm.seen_villain, str(_world._villain_playing)])
	# 闸的值是从上一场开演时的驿数算的，所以再过两驿它就该放了。
	var need: int = _world._villain_last_play_seen + int(_world.VILLAIN_MIN_STATION_GAP)
	_ck("闸的下限确实是「上一场开演时的驿数 + 间隔」",
			_gm.get_seen_station_count() < need,
			"seen=%d < %d + %d" % [_gm.get_seen_station_count(),
			_world._villain_last_play_seen, int(_world.VILLAIN_MIN_STATION_GAP)])
	_ck("上一场开演时的驿数被记下来了",
			_world._villain_last_play_seen >= 0,
			"=%d" % _world._villain_last_play_seen)


## 问提示圈自己现在打算写哪句话（走的是它自己的 _label()，不是重演一遍逻辑）
func _visit_prompt_label() -> String:
	var cp = _world._check_in_prompt
	var t: Array = cp._prompt_target()
	return "" if t.is_empty() else str(cp._label(t))


## 只为量字宽：拿到一条真实的提示句，走的仍然是提示圈自己的 _label()
func _cp_label() -> String:
	var cp = _world._check_in_prompt
	var t: Array = cp._prompt_target()
	return _root_loc().t("desktop_checkin_prompt") if t.is_empty() else str(cp._label(t))


## ===================== 10 集齐二选一面板 =====================
## 第一次集齐五块碎片时弹的那块面板。它是**这一趟的落点**：
## 以前这里只浮一句「顶栏的圆点还是空的」就把操纵权还回去了，而唯一的出口
## 「收下明信片」藏在暂停面板深处、没有任何一句话告诉玩家它在那儿。
## 一趟 20~30 分钟，评委玩不到终点就已经还回去了。
##
## 这节量的三件事，和第 6 节是同一个家族：
##   1  面板是个真模态：世界冻住、空格漏不进来、脚下的圈跟着收
##   2  「再骑一圈」真的把一切还回去，**而且 `_all_done` 仍然是 false**
##      （拿 `_all_done` 当这个闸门会让 `verify_minimap.gd` 第 9 节变红，
##        而那条是对的：面板期间这一趟并没有走完）
##   3  只弹一次
##
## 全部走真实 `check_in()` 驱动，不直接写 `collected` —— 直接写不发信号，
## 那一节量的是一个不存在的世界（CLAUDE.md「测试里的存档摆弄必须走真实入口」）。
func _section10_synthesis_choice() -> void:
	print("\n---- 10. 集齐二选一面板 ----")
	_s10_ck_at_start = _ck_total
	var loc = _root_loc()
	var panel = _world._synthesis_panel
	_gm._clear_save()
	_gm.headless_mode = false
	_world._headless_mode = false
	_world._villain_playing = false
	_world._synthesis_choice_open = false
	panel.visible = false

	var rd = _world._road_builder.get_road_data()
	var frag: Array = rd.FRAGMENT_SLOT_STATION_IDX
	for i in frag.size() - 1:
		_teleport(int(frag[i]))
		await process_frame
		_gm.check_in(int(frag[i]))
		# `all_fragments_collected` 是状态翻转信号，第 5 次才发；
		# 前四次之后确认面板没被提前弹出来（弹早了玩家还没集齐就被问
		# 「要不要收下明信片」，而他手上还差一个站）。
		if i < frag.size() - 1:
			await create_timer(0.15).timeout
			_ck("集齐 %d/%d 时面板没有提前弹出" % [i + 1, frag.size()],
					not panel.visible and not _world._synthesis_choice_open)
	# 合成动画 2.5s + 一点余量。判据只能等墙钟：`--quit-after` 的单位是帧。
	var waited := 0.0
	while not _world._synthesis_choice_open and waited < 8.0:
		await create_timer(0.1).timeout
		waited += 0.1
	_ck("五块碎片集齐后面板弹出来了", _world._synthesis_choice_open and panel.visible,
			"等了 %.1fs，open=%s visible=%s" % [waited,
			str(_world._synthesis_choice_open), str(panel.visible)])
	if not panel.visible:
		# 面板没起来就别往下量了：后面每一条都在量"面板开着的时候…"，
		# 继续跑只会把"面板根本没弹"报成四五条不相干的失败。
		return

	# -- 1 它是个真模态 --
	_ck("面板开着时操纵权没还回来", not bool(_world._player._can_move),
			"能骑 = %s" % str(bool(_world._player._can_move)))
	_ck("面板开着时相机还锁着", _world._player.is_camera_locked())

	# 空格在这个面板上是**按钮的 ui_accept**，可同一个键又是全局 interact
	#（`Input.is_action_just_pressed` 拦不住）。少了 `_can_start_check_in`
	# 里那一格，玩家按「收下明信片」的那一下会顺手再走一遍 interact 分支。
	_teleport(int(frag[0]))
	await process_frame
	await process_frame
	_ck("面板开着时打卡闸是关着的（空格漏不进来）",
			not _world._can_start_check_in(int(frag[0])),
			"按「收下明信片」的那一下空格会顺手再开一轮打卡")
	# 圈必须跟着收：`_physics_process` 那张早退单子把 `_nearby_*` 清成 -1，
	# `CheckInPrompt._prompt_target()` 只读 `_nearby_*`、不知道有这个状态。
	# 漏了的话圈上写着「空格 · 再办一次」，而空格正在按钮上。
	_ck("面板开着时脚下的圈不画了", _world._nearby_station_idx == -1
			and _visit_prompt_label() == "",
			"nearby=%d，圈上写着「%s」" % [_world._nearby_station_idx,
			_visit_prompt_label()])
	_ck("面板开着时不冒「这里进不去」那句话",
			_world._interact_blocked_reason() == "",
			"说的是「%s」" % _world._interact_blocked_reason())

	# -- 2 键盘可达性 --
	# 只钉 focus_mode：headless 的 dummy display server 不做焦点路由，
	# `has_focus()` 在这里恒为 false —— 那是量不出来的，不是坏的。
	# 真按键走通那一条是 `verify_panel_keyboard.gd`（带窗口）的活。
	var take_btn = panel.get_node_or_null("Panel/Margin/VBox/TakePostcardBtn")
	var keep_btn = panel.get_node_or_null("Panel/Margin/VBox/KeepRidingBtn")
	_ck("两个按钮都建出来了", take_btn != null and keep_btn != null)
	if take_btn != null and keep_btn != null:
		_ck("两个按钮都能被键盘走到（focus_mode 不是 NONE）",
				take_btn.focus_mode != Control.FOCUS_NONE
				and keep_btn.focus_mode != Control.FOCUS_NONE)
		# 尺寸：都在屏内、且不叠。"不叠"比"不越界"更容易被忽略——
		# 两个都铺满屏的按钮在屏内，可玩家怎么按都只有下面那个能按。
		var tr: Rect2 = take_btn.get_global_rect()
		var kr: Rect2 = keep_btn.get_global_rect()
		var vp: Vector2 = _world.get_viewport().get_visible_rect().size
		_ck("两个按钮都在屏内", tr.intersects(Rect2(Vector2.ZERO, vp))
				and kr.intersects(Rect2(Vector2.ZERO, vp)),
				"take=%s keep=%s 屏=%s" % [str(tr), str(kr), str(vp)])
		_ck("两个按钮不叠", not tr.intersects(kr),
				"两块都铺满屏的话，玩家按上面那个永远没反应")
		_ck("按钮上写的是人话，不是 key 名",
				take_btn.text == loc.t("synthesis_take_postcard")
				and keep_btn.text == loc.t("synthesis_keep_riding"),
				"写着「%s」/「%s」" % [take_btn.text, keep_btn.text])
	_ck("面板上写清了这一趟已经跑通了",
			panel.get_node_or_null("Panel/Margin/VBox/Hint").text
				== loc.t("synthesis_choice_hint"),
			"这句是「让玩家深刻了解这游戏是做什么的」那句话本身")

	# -- 3 选「再骑一圈」：什么都得还回去，而且这一趟**没有**走完 --
	keep_btn.emit_signal("pressed")
	await create_timer(0.2).timeout
	_ck("「再骑一圈」后面板关掉了", not panel.visible
			and not _world._synthesis_choice_open)
	_ck("「再骑一圈」把操纵权还回去了", bool(_world._player._can_move))
	_ck("「再骑一圈」把相机还回去了", not _world._player.is_camera_locked())
	_ck("「再骑一圈」没有把这一趟判成走完（`_all_done` 仍是 false）",
			not _world._all_done,
			"拿 `_all_done` 当这个闸门的话，顶栏「再访 · 还差 2 次」当场变成谎言")
	_ck("「再骑一圈」没有把评级顶到完满", not _gm.all_fragments_maxed())
	_ck("「再骑一圈」给了一段空格静默期", _world._interact_cooldown > 0.0,
			"玩家手上多半还按着空格")
	_teleport(int(frag[0]))
	await process_frame
	await process_frame
	_ck("「再骑一圈」之后回到站边还能继续打卡", _world._can_start_check_in(int(frag[0])))

	# -- 3b 收面板的责任在 World3D 侧，不只在按钮侧 --
	# 上面那条是**点按钮**走出来的，面板自己收自己。而 `synthesis_choice` 是个
	# 公开信号：定妆照脚本、以后的自动导览、任何 `emit()` 都走不到按钮那一行。
	# 面板原先只在 `_emit()` 里收，于是这些路子里 `_synthesis_choice_open` 已经
	# 归零（操纵权还回去了）而模态还亮着——`lookdev_journey.gd` 的 `13c` 就是这么
	# 拍出一张"还骑一圈之后"却和上一张一模一样的图的：断言量的是操纵权，图上量
	# 的是屏幕，而那一条当时两边都在说谎。
	panel.open()
	await process_frame
	_ck("信号这条路也能把面板打开（前提：面板此刻可见）", panel.visible)
	panel.synthesis_choice.emit(false)
	await create_timer(0.2).timeout
	_ck("直接发信号收工时面板也被收掉了（不点按钮也收）", not panel.visible)
	_ck("直接发信号收工时闩锁也放下了", not _world._synthesis_choice_open)

	# -- 4 只弹一次 --
	# `all_fragments_collected` 是带 `_collected_fired` 闩锁的状态翻转信号。
	# 不需要额外闩锁，但要有断言证明它：回访一轮之后如果又弹一次，
	# 玩家每去一站就被问一遍"要不要收下明信片"。
	_gm.check_in(int(frag[0]))
	await create_timer(0.6).timeout
	_ck("回访之后面板没有第二次弹出来", not panel.visible
			and not _world._synthesis_choice_open)
	_ck("回访之后操纵权是玩家的", bool(_world._player._can_move))

	# -- 5 另一条：选「收下明信片」要去结算页 --
	# 真的按下去会 `go_to_end_card()` 换场景，把整条回归的 _world 抽掉，
	# 所以这里只量**信号契约**：面板发什么，由 World3D 去落地。
	# `_synthesis_choice_open` 是 World3D 的闩锁、`open()` 是面板自己的方法，
	# 两者刻意不耦合——所以这里不能拿 `panel.open()` 之后闩锁有没有按上来当判据，
	# 那是拿测试的捷径去量产品。
	_gm._clear_save()
	await create_timer(0.3).timeout
	var got_choice: Array = []
	panel.synthesis_choice.connect(func(take: bool): got_choice.append(take),
			CONNECT_ONE_SHOT)
	panel.open()
	await process_frame
	_ck("面板可以再打开（第二条路不是死路）", panel.visible)
	take_btn.emit_signal("pressed")
	await create_timer(0.3).timeout
	_ck("「收下明信片」发的是 take_postcard=true",
			got_choice.size() == 1 and bool(got_choice[0]), str(got_choice))
	_ck("发了选择之后面板自己收掉了", not panel.visible)
	_ck("「收下明信片」这条路没有把 `_all_done` 提前翻过来（落地在 World3D 侧）",
			not _world._all_done)
	_s10_done = true


## 第 10 节跑完之后在调用点验一次。
##
## 旗子由这一节**自己**在末尾置位，所以它测的是"这一节的函数体真的跑到了
## 最后一行"，而不是"我写了一个 await"。第 10 节头一版就栽在这里：
## 一个不存在的 `get_can_move()` 抛异常掐断了整节，而 `await` 一个抛异常的
## 协程不会把异常往上抛，`_run()` 接着走完、照样打出 `PASS (失败 0)`。
func _verify_section10_completed() -> void:
	var got := _ck_total - _s10_ck_at_start
	_ck("第 10 节跑到了最后一行（不是抛异常掐在半路）", _s10_done)
	_ck("第 10 节打出的断言一条不少（实测 %d 条）" % got, got >= _S10_MIN_CK,
			"少于 %d 条说明中间被掐了，而上面的旗子已经报过" % _S10_MIN_CK)
