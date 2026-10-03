extends Node
## DemoDirector — 给评审的 90 秒演示路径。
##
## 为什么要有这个：一条完整的一趟是「五座驿站各刷满三次 = 15 次打卡」，
## 每次一段对白加一个小游戏，而环路一圈 1228.8m、满速 15m/s 要 82 秒。
## 评审手上只有几分钟，按正常流程他大概率**看不到这张明信片**——而明信片
## 才是这个作品真正的产物，前面的世界只是为它存在的。
##
## 所以演示模式不是"跳过游戏"，而是**把这条路径压缩**：程序骑一段真的环路
## （真的路面、真的行道树、真的打卡圈与对白、真的把车骑到亭子跟前去），
## 62 秒时把这一趟补齐成完满评级，然后跳去结算页，把剩下 28 秒留给那张卡
## 和终局二选一。**不替评审做选择**——二选一停在屏上，让他自己按。
##
## 演示**不替评审打小游戏**：每个小游戏放 `MINIGAME_LINGER_SEC` 秒就 ESC 走人。
##
## 这不是省事，是**试过了**：五个小游戏的通关键各不相同（茶长按空格三秒、
## 竹要卡五个时机、云要描一条路径、琴要复述十三徽、禽要认出刚才那只是第几只，
## 而答错立刻判失败），没有一条通用按键序列能通吃。中间试过"至少让演示按住
## 空格把茶赢下来"——`HOLD_WIN_SCRIPT` 那条路写完了，量出来是**一次都没走到**：
## 62 秒只够停两站，而起点最近的那座碎片站是禽（槽位 4，驿站 4），茶在更远的
## 环上。`GameManager.check_in()` 是小游戏做完之后才调的，于是这一趟演示骑行
## 确实一块碎片也拿不到。
##
## 于是**交出去那张卡上的数全是补的**（`fill_finished_run()`），而这正是必须
## **说出口**的话：评审亲眼看了 62 秒，看到的是 2 座驿站和一个小游戏弹出来又
## 消失，卡上却写着十六驿全到过、五件乐事各三次。所以收工时先在屏上打一行
## `demo_card_notice` 停一拍再换场。**补齐不是谎，闷声补齐才是。**
## 想让卡上那些数是真的，只有两条路：把演示做到真能通关（一趟 20~30 分钟，
## 评审不会等），或者干脆别补——而空卡教会评审的东西比满卡少得多。
##
## 全程只用 `Input.parse_input_event()` / `Input.action_press()`，
## 也就是玩家真按的那些键走的那条管线：不直接挪玩家、不直接调 `check_in()`。
## 理由和 `tools/play_newcomer.gd` 一样——直接挪过去量的是"瞬移要多久"，
## 而这条演示要证明的是"这条路真的通"。
##
## 计时一律墙钟（`Time.get_ticks_msec()`）。`t += delta` 在这里不行：
## 演示是要给别人看的，时长必须真的等于墙上的秒表。

## 演示总长。标题页上写着「90 秒」，这里就是那 90 秒。
const BUDGET_SEC := 90.0
## 什么时候收工去结算页。剩下的 `BUDGET_SEC - END_AT_SEC` 秒留给明信片和二选一。
const END_AT_SEC := 62.0

## 沿中心线骑：目标点提前 24 个采样（约 31m）。
##
## 第一版是 6 个（约 7.7m），量出来是骑了 896m 只路过 1 座驿站：车在 15m/s
## 上按 TURN_SPEED=1.8 rad/s 拧把根本来不及，8 字的两个弯一律切过去，
## 于是它大半程在草地上跑。提前量就是"提前多久开始拧"。
const RAIL_LEAD := 24
## 指针吸到多近算"已经过了这一点"
const RAIL_CATCH := 14.0
## 前方多远开始往站点拐（沿中心线的弧长）
const APPROACH_ARC := 55.0
## 拐进站里时按空格的距离。世界自己的 `STATION_PASS_RADIUS` 是 15m，这里留 2m 余量。
const PRESS_DIST := 13.0
## 靠站到这个距离以内就收油——15m/s 直冲过去会直接从亭子旁边掠过
const APPROACH_SLOW_DIST := 30.0
## 停在站前这么久还没打上卡，就当这座不去了
const PARK_GIVEUP_SEC := 8.0
## 有东西挡路时（对白在播 / 打卡在跑）按空格的节奏
const PRESS_INTERVAL_SEC := 1.2
## 小游戏弹出来之后放它跑这么久，然后 ESC 走掉。
##
## 别调长：一次停站（对白 + 小游戏 + 失败面板 + 静默期 + 骑开重新武装）
## 要吃掉 13 秒左右，而 62 秒里只塞得下两站。放太久的话演示走到第二个亭子
## 就得收工，评审看到的是一整趟里只有一次到站。
const MINIGAME_LINGER_SEC := 4.0
## 收工到跳结算页之间留的一拍，用来把 `demo_card_notice` 那句交代打在屏上。
## 必须留：换场之后那一行就没了，而"卡上那些数是补的"这件事就只剩下没人说。
const HANDOFF_NOTICE_SEC := 2.6

var _world: Node = null
var _player: Node3D = null
var _rd: RefCounted = null
var _rail: Array = []
var _frag_stations: Array = []
var _frag_rail_idx: Array = []
var _spacing := 1.28
var _i := 0
var _t0 := 0
var _next_press := 0
var _minigame_started_ms := 0
var _handed_off := false
var _handoff_done := false
var _handoff_at_ms := 0
var _phase := 0
var _space_down := false
var _space_up_at := 0
var _park_k := -1
var _park_since_ms := 0
var _park_ms := 0
var _give_up_k := -1


func setup(world: Node, rd: RefCounted) -> void:
	_world = world
	_player = world._player
	_rd = rd
	_rail = rd.points
	_frag_stations = rd.FRAGMENT_SLOT_STATION_IDX.duplicate()
	if _rail.size() > 1:
		_spacing = _xz(_rail[1], _rail[0])
	_frag_rail_idx = []
	for k in _frag_stations.size():
		_frag_rail_idx.append(
				_nearest_rail_index(_rd.get_station_world_pos(_frag_stations[k])))
	_i = _nearest_rail_index(_player.global_position)
	_t0 = Time.get_ticks_msec()
	# 演示从"这一趟刚开始"起算，操作说明和序章都在 World3D 那边跳过了。
	world._hud3d.show_pass_line(Localization.t("demo_hint"))


func _sec() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0


func _process(_delta: float) -> void:
	if _world == null or _player == null or not is_instance_valid(_player):
		return
	if _world._paused:
		return

	# 收工分两拍：**先在屏上交代一句**，停 HANDOFF_NOTICE_SEC，再补齐 + 换场。
	# 必须在**换场之前**改存档——`go_to_end_card()` 之后明信片是现算的，
	# 而 go_to_gift_box() 才 reset。
	if _sec() >= END_AT_SEC and not _handed_off:
		_handed_off = true
		_release()
		_world._hud3d.show_pass_line(Localization.t("demo_card_notice"))
		_handoff_at_ms = Time.get_ticks_msec()
		return
	if _handed_off and not _handoff_done:
		if Time.get_ticks_msec() - _handoff_at_ms < int(HANDOFF_NOTICE_SEC * 1000.0):
			return
		_handoff_done = true
		_release_interact()
		GameManager.fill_finished_run()
		GameManager.go_to_end_card()
		return

	_steer()
	_drive_dialogue()
	_pump_space()


func _release() -> void:
	for a in ["move_up", "move_left", "move_right"]:
		Input.action_release(a)


## 朝前视点拧把。约定 a(v) = atan2(v.x, -v.z)（正前 -Z 是 0）。
##
## 前视点有两种：默认是中心线上提前 RAIL_LEAD 个采样那点；前方有还没去过的
## 碎片站时换成**站本身**。这一条不是优化而是前提——16 座站全都摆在离中心线
## 18m 处，而 `World3D.STATION_PASS_RADIUS` 是 15m：贴着中心线骑，一座站既
## 路过不了（`on_station_pass` 也在同一个半径里）也靠不近。实测 62 秒骑了
## 836m，到过的驿是 1 座、拿到的碎片 0 块，全程离最近一座碎片站的最近距离
## 是 21.9m。打卡是要拐下路把车骑到亭子跟前去的，那正是玩家做的事。
func _steer() -> void:
	if not bool(_player._can_move):
		_release()
		return
	while _i < _rail.size() and _xz(_rail[_i], _player.global_position) < RAIL_CATCH:
		_i += 1
	if _i >= _rail.size():
		# 骑完一圈：绕回去继续，别停在终点
		_i = 0

	var pk := _pending_station()
	var tgt: Vector3 = _rd.get_station_world_pos(_frag_stations[pk]) if pk >= 0 \
			else _rail[mini(_i + RAIL_LEAD, _rail.size() - 1)]
	var to := tgt - _player.global_position
	to.y = 0.0
	var diff := wrapf(_bearing(to) - _bearing(-_player.global_basis.z), -PI, PI)

	# 到站了就松油刹住，等 `_drive_dialogue()` 把空格按出去。
	# 别再往前顶：目标点还在 PRESS_DIST 之外时车会绕着亭子打转，而占空比一降到
	# 1/4 车速就掉到 0.2m/s——实测它在 12.0m 上磨了 14 秒，一块碎片也没拿到。
	if pk >= 0 and to.length() < PRESS_DIST:
		_release()
		if _park_k == pk:
			_park_ms = Time.get_ticks_msec() - _park_since_ms
			if _park_ms > PARK_GIVEUP_SEC * 1000.0:
				# 演示绝不能卡死在这儿。62 秒里耗在一条走不通的路上，比少停一站更糟；
				# 存档最后由 `fill_finished_run()` 补齐，这一趟少停一站看不出来。
				_give_up_k = pk
				_park_k = -1
		else:
			_park_k = pk
			_park_since_ms = Time.get_ticks_msec()
			_park_ms = 0
		return

	# 降速用占空比，而且**下限是 1/2，绝不能一直松着**。
	# `Player3D` 的转向速率按速度缩放（turn_factor = clamp(|speed|/3, 0, 1)），
	# 车一停下就拧不动，于是"误差大 → 松油 → 停住 → 更拧不动"是个死锁：
	# 第一版就是这么骑了 0 米的。所以每 duty 帧才松一次，车永远在动、转向一直有效。
	#
	# 拧不动的时候**只能**停在 1/2：试过"误差大就用 1/4"，结果开局车头是歪的
	# （出发点上 rail[42] 在侧后方 152°），25% 的油门攒不起速度、速度不够就拧不动，
	# 于是 62 秒只骑了 8m。对准了就是满油——占空比是用来拧把的，不是用来巡航的。
	var duty := 1
	if absf(diff) > 0.45:
		duty = 2
	elif pk >= 0 and to.length() < APPROACH_SLOW_DIST:
		duty = 4
	if _phase % duty == 0:
		Input.action_press("move_up")
	else:
		Input.action_release("move_up")
	_phase += 1
	Input.action_press("move_left", diff < -0.12)
	Input.action_press("move_right", diff > 0.12)


## 打卡与推进对白。有东西挡路就按空格——和真人一样，不去调 check_in()。
func _drive_dialogue() -> void:
	var now := Time.get_ticks_msec()

	# 小游戏弹出来之后放它跑 MINIGAME_LINGER_SEC 再 ESC 走掉。
	# 不这么做的话一次演示会在第一个小游戏上耗掉 30 秒超时。
	if _world._mini_game_state == _world.MG_RUNNING:
		if _minigame_started_ms == 0:
			_minigame_started_ms = now
			_release()
		elif now - _minigame_started_ms > int(MINIGAME_LINGER_SEC * 1000.0):
			_minigame_started_ms = 0
			_send_escape()
		return

	var near := _nearest_checkin_station()
	# 一旦看见世界真的进了打卡序列，就算这座"去过"了。
	#
	# 判据**不能**用 `GameManager.get_station_count(si)`：`check_in()` 要等小游戏
	# 做完才调（World3D 里那句在碎片弹窗之后），而演示是每个小游戏放几秒就 ESC
	# 走掉的——次数永远停在 0，于是 `_pending_station()` 一次次把车领回同一座站，
	# 实测 62 秒里有 21 秒耗在同一个亭子前。
	if _world._check_in_in_progress and _park_k >= 0:
		_give_up_k = _park_k
	if near < 0 and not _world._dialogue_popup.visible:
		return
	if now < _next_press:
		return
	_next_press = now + int(PRESS_INTERVAL_SEC * 1000.0)
	_send_space()


## 前方不远处、这一趟还没打过卡的碎片站（`_frag_stations` 的下标）；没有就 -1。
##
## "还没打过"读的是 `GameManager.get_station_count()` —— 那是世界自己写的那一份，
## 这里**不另记一份副本**。第一版存过一个 `_checked` 数组、而且在**按下空格之前**
## 就把它置真，于是车一进范围就被标记成"处理过"，之后 `_nearest_checkin_station()`
## 永远返回 -1，空格一次都没发出去，实测骑了 896m 拿了 0 块碎片。
##
## `fragment_station_needs_visit()` 只管"还欠不欠一次到访"（刷满三次才算还清），
## 所以打完一次之后它仍然为真——演示要的是每座站停一次，不是把它刷满三遍。
func _pending_station() -> int:
	var n := _rail.size()
	for k in _frag_stations.size():
		if k == _give_up_k:
			continue
		var si: int = _frag_stations[k]
		if not GameManager.fragment_station_needs_visit(si):
			continue
		if GameManager.get_station_count(si) > 0:
			continue
		var fwd: int = (int(_frag_rail_idx[k]) - _i + n) % n
		if fwd * _spacing > APPROACH_ARC:
			continue
		return k
	return -1


## 已经骑到打卡距离内、可以按空格的那座碎片站；不在半径内或没有就返回 -1。
func _nearest_checkin_station() -> int:
	var best := -1
	var best_d := PRESS_DIST
	for k in _frag_stations.size():
		if k == _give_up_k:
			continue
		var si: int = _frag_stations[k]
		if not GameManager.fragment_station_needs_visit(si):
			continue
		if GameManager.get_station_count(si) > 0:
			continue
		var d := _xz(_rd.get_station_world_pos(si), _player.global_position)
		if d < best_d:
			best_d = d
			best = k
	return best


func _send_space() -> void:
	if _space_down:
		return
	_space_down = true
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	_space_up_at = Time.get_ticks_msec() + 80


## 松掉空格，并把本脚本的节流闩一起清掉。收工时调：`go_to_end_card()` 之后
## 这份演示脚本就没人管了，而一个一路按着的空格键会跟着进结算页。
func _release_interact() -> void:
	if _space_down:
		var up := InputEventKey.new()
		up.keycode = KEY_SPACE
		up.physical_keycode = KEY_SPACE
		up.pressed = false
		Input.parse_input_event(up)
	_space_down = false
	_space_up_at = 0


## 松开空格。**必须和按下分在两帧里**：挤在同一帧的话，`World3D` 那条
## `Input.is_action_just_pressed("interact")` 判定时这一帧已经松手了，
## 打卡分支一次都进不去——车停在站前，空格按了十几下，什么也没发生。
func _pump_space() -> void:
	if not _space_down or Time.get_ticks_msec() < _space_up_at:
		return
	_space_down = false
	var up := InputEventKey.new()
	up.keycode = KEY_SPACE
	up.physical_keycode = KEY_SPACE
	up.pressed = false
	Input.parse_input_event(up)


func _send_escape() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)


func _nearest_rail_index(p: Vector3) -> int:
	var best := 0
	var best_d := INF
	for k in _rail.size():
		var d := _xz(_rail[k], p)
		if d < best_d:
			best_d = d
			best = k
	return best


func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _bearing(v: Vector3) -> float:
	return atan2(v.x, -v.z)