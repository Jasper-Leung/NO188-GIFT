extends SceneTree
## verify_shop_world.gd — World3D 里的经济 / 铺子 / 叙事接线回归。
##
## 用真实 World3D 场景验「里程→旅币、路过→旅币、靠近→开店→购买→入账」这条链，
## 以及序章与郑铎三场的触发门。数值口径由 verify_economy.gd 负责，本文件只测接线：
## 期望值一律走 GameManager / ShopPanel 自己给的数，不硬编码价格。
##
## 覆盖：
##   1. headless 下 World3D 能起来，序章走 headless 逃逸路径并落盘
##   2. 里程 → earn_km 只发差额；骑不动就不发
##   3. 路过驿站 → on_station_pass 发一次，重复路过不再发
##   4. 靠近铺子站 → _nearby_shop_idx 正确，且与碎片站的提示互斥
##   5. _open_shop / _close_shop：面板显隐、玩家被钉住、关店恢复
##   6. 骑出铺子范围自动收摊
##   7. 面板内购买 → 入账、purchased 信号、HUD 旅币标签同步
##   8. 灯铺未到解锁里程：面板照开但整铺禁用，钱花不出去
##   9. 郑铎三场按里程触发、严格顺序、seen_villain 落盘
##
## 用法： godot --headless --path . --script tools/verify_shop_world.gd --quit-after 30000
## 注意 --quit-after 单位是帧不是秒（本机 280+FPS，90 帧只有 0.3 秒，
## 会把脚本掐死在场景加载处，只剩一串 warning 看着像通过）。

## 铺子驿站索引，取自 shop_data.gd 的 SHOP_AT_STATION。
## 不在 --script 里引用 ShopData class_name：编译期拉依赖会撞到 autoload 解析陷阱。
const SHOP_STATION_EYI := 0      # 驿铺
const SHOP_STATION_CHA := 2      # 茶铺
const SHOP_STATION_DENG := 8     # 灯铺
const FRAGMENT_STATION := 4      # 第一个碎片驿站
const ROUTE_KM := 188.0          # = GameManager.TOTAL_ROUTE_KM
const DENG_GATE := 6              # = shop_data.gd 灯铺的 seen_unlock


var _fails: Array = []
var _oks := 0
var _gm: Node = null
var _loc: Node = null
var _world: Node = null

var _purchased: Array = []


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_oks += 1
		print("[OK]   ", label)
	else:
		var msg := label + ("（" + detail + "）" if detail != "" else "")
		_fails.append(msg)
		print("[FAIL] ", msg)


func _eq(label: String, got: Variant, want: Variant) -> void:
	_ck(label, got == want, "got=%s want=%s" % [str(got), str(want)])


func _on_purchased(id: String) -> void:
	_purchased.append(id)


## 走几帧让 _physics_process 结算完（邻近判定、里程入账都发生在里面）。
func _frames(n: int = 40) -> void:
	for i in n:
		await process_frame


## 等 HUD 的「+N 旅币」入账提示自然退场。按帧数等不可靠：_frames() 默认 40 帧
## 只有零点几秒，而入账提示要 1.4 秒才回到余额显示。
func _wait_gain_expired(hud: Node, cap_msec: int = 4000) -> void:
	# 判据是 HUD 自己把提示文字清空，不是计时器归零：计时器归零那一帧
	# 走的是「还有提示」分支（先把 gain_left 减成负的），要再等一帧
	# _process 才换回余额。等 gain_text 清空才等价于「余额已经显示出来了」。
	var t0 := Time.get_ticks_msec()
	while String(hud._lvbi_gain_text) != "" and Time.get_ticks_msec() - t0 < cap_msec:
		await process_frame


## 里程计按比例写死，绕过玩家位移。必须和传送配对用：
## 传送后不同步 _last_global_pos 的话，下一帧 move_vec 会是一个巨无霸，
## 里程和旅币都会跟着虚高。
func _set_km(km: float) -> void:
	_world._odometer_units = _world._total_arclen * (km / ROUTE_KM)


## 顶栏进度、解锁门、郑铎三场现在全挂在"路过多少座驿"上。驿数是
## GameManager.seen_stations 的字典大小，直接写前 n 个站的标记。
func _set_seen(n: int) -> void:
	_gm.seen_stations = {}
	for i in mini(n, _world._stations.size()):
		_gm.seen_stations[i] = true


func _teleport(station_idx: int) -> void:
	_world._close_shop()
	_world._player.position = _world._stations[station_idx].position + Vector3(0, 1.0, 3.0)
	_world._last_global_pos = _world._player.global_position
	_world._has_last_pos = true
	_world._odometer_units = 0.0
	_world._interact_cooldown = 0.0
	_world._recheck_armed = true
	_world._nearby_station_idx = -1
	_world._nearby_shop_idx = -1
	_world._nearby_station_dist = 999.0
	_world._nearby_shop_dist = 999.0


func _reset_world_state() -> void:
	_gm.reset()
	_gm.prologue_done = true          # reset() 会归零
	_world._all_done = false
	_world._check_in_in_progress = false
	_world._villain_armed = [true, true, true]
	_world._villain_playing = false


## 铺子面板内的第 id 个商品行；找不到返回 -1。
func _find_row(id: String) -> int:
	var rows = _world._shop_panel._rows
	for i in rows.size():
		if str(rows[i][0].get("id", "")) == id:
			return i
	return -1


func _row_price(id: String) -> int:
	var rows = _world._shop_panel._rows
	for r in rows:
		if str(r[0].get("id", "")) == id:
			return int(r[0].get("price", 0))
	return -1


func _row_btn(id: String) -> Button:
	var rows = _world._shop_panel._rows
	for i in rows.size():
		if str(rows[i][0].get("id", "")) == id:
			return rows[i][4]
	return null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== World3D 经济 / 铺子 / 叙事接线回归 ===")

	_gm = root.get_node_or_null("GameManager")
	# 不能直接写 Localization.t(...)：--script 模式下 analyzer 解析不到 autoload
	# 全局名，直接 Identifier not found 编译失败。一律走 root.get_node()。
	_loc = root.get_node_or_null("Localization")
	if _gm == null or _loc == null:
		print("[ABORT] 拿不到 autoload")
		quit(1)
		return

	# 存档与语言备份：脚本会 reset() 和写档，跑完还原
	var backup := ""
	if FileAccess.file_exists(str(_gm.SAVE_PATH)):
		var rf = FileAccess.open(str(_gm.SAVE_PATH), FileAccess.READ)
		if rf != null:
			backup = rf.get_as_text()
			rf.close()
	var lang_before: String = _loc.get_current_language()

	_gm.reset()
	_gm.onboarding_shown = true
	_gm.headless_mode = true
	_loc.set_language("zh")

	# 序章故意留成未完成：headless 下要走逃逸路径（落盘但不弹框）。
	_world = load("res://scenes/World3D.tscn").instantiate()
	root.add_child(_world)
	await create_timer(2.5).timeout
	_world._shop_panel.purchased.connect(_on_purchased)
	var hud: Node = _world.get_node("HUD3D")

	# ---- 1. 序章 headless 逃逸路径 ----
	_eq("序章已落盘（headless 不弹框）", _gm.prologue_done, true)
	_ck("序章没把对白框留在屏幕上", not _world._dialogue_popup.visible)
	_ck("序章没卡住玩家移动", _world._player._can_move)

	# ---- 2. 里程 → 旅币 ----
	_reset_world_state()
	# 路过 +3 会和里程旅币叠在一起，这一节只测里程那一笔：
	# 把 16 个驿站全部预登记，on_station_pass 一律返回 0。
	for i in _world._stations.size():
		_gm.seen_stations[i] = true
	_world._last_global_pos = _world._player.global_position
	_world._has_last_pos = true
	_set_km(0.0)
	await _frames()
	_eq("开局里程 0", int(_gm.get_progress_km()), 0)
	_eq("开局旅币 0", int(_gm.lvbi), 0)
	_set_km(56.4)
	await _frames()
	_eq("里程只进到整公里", int(_gm.get_progress_km()), 56)
	_eq("里程按整公里发旅币", int(_gm.lvbi), 56 * int(_gm.LVBI_PER_KM))
	_set_km(56.4)          # 原地不动
	await _frames()
	_eq("不骑就不增发", int(_gm.lvbi), 56 * int(_gm.LVBI_PER_KM))
	_set_km(65.0)
	await _frames()
	_eq("骑到 65km 只补差额", int(_gm.lvbi), 65 * int(_gm.LVBI_PER_KM))
	_set_km(ROUTE_KM + 50.0)
	await _frames()
	_eq("里程封顶在总路线长", int(_gm.get_progress_km()), int(ROUTE_KM))
	_eq("封顶后不再发旅币", int(_gm.lvbi), int(ROUTE_KM) * int(_gm.LVBI_PER_KM))

	# ---- 3. 路过驿站 → 旅币（幂等） ----
	_reset_world_state()
	_teleport(SHOP_STATION_EYI)
	await _frames()
	_eq("路过驿铺发了旅币", int(_gm.lvbi), int(_gm.LVBI_PER_PASS))
	var pass_once: int = int(_gm.lvbi)
	await _frames()
	_eq("同站不重复发", int(_gm.lvbi), pass_once)
	_eq("路过记录进了 seen_stations", _gm.seen_stations.has(SHOP_STATION_EYI), true)

	# ---- 4. 邻近判定：铺子 vs 碎片驿站互斥 ----
	_reset_world_state()
	_teleport(SHOP_STATION_EYI)
	await _frames()
	_eq("驿铺附近 _nearby_shop_idx", int(_world._nearby_shop_idx), SHOP_STATION_EYI)
	_ck("驿铺附近铺子距离在半径内", float(_world._nearby_shop_dist) < float(_world.STATION_PASS_RADIUS))
	_eq("驿铺不是碎片站，_nearby_station_idx 为空", int(_world._nearby_station_idx), -1)

	_teleport(FRAGMENT_STATION)
	await _frames()
	_eq("碎片驿站 _nearby_station_idx", int(_world._nearby_station_idx), FRAGMENT_STATION)
	_eq("碎片驿站旁 _nearby_shop_idx 为空", int(_world._nearby_shop_idx), -1)

	# ---- 5. 开店 / 关店 ----
	_reset_world_state()
	_teleport(SHOP_STATION_EYI)
	await _frames()
	_eq("近处铺子可开门", _world._can_open_shop(int(_world._nearby_shop_idx)), true)
	_world._open_shop(int(_world._nearby_shop_idx))
	_eq("开店后 _shop_open", _world._shop_open, true)
	_eq("面板可见", _world._shop_panel.visible, true)
	_ck("开店后玩家被钉住", not _world._player._can_move)
	_eq("开店后地面提示让位", int(_world._check_in_prompt._prompt_target().size()), 0)
	_world._close_shop()
	_eq("关店后 _shop_open 清掉", _world._shop_open, false)
	_eq("关店后面板隐藏", _world._shop_panel.visible, false)
	_ck("关店后玩家能骑", _world._player._can_move)
	_world._close_shop()
	_ck("重复关店是空操作", not _world._shop_open)

	# ---- 6. 骑出铺子范围自动收摊 ----
	_reset_world_state()
	_teleport(SHOP_STATION_EYI)
	await _frames()
	_world._open_shop(int(_world._nearby_shop_idx))
	_ck("开店状态", _world._shop_open)
	_teleport(SHOP_STATION_DENG)
	await _frames()
	_eq("骑出驿铺范围后自动收摊", _world._shop_open, false)
	_eq("新位置自动认到灯铺", int(_world._nearby_shop_idx), SHOP_STATION_DENG)

	# ---- 7. 面板内购买入账 ----
	_reset_world_state()
	_teleport(SHOP_STATION_EYI)
	await _frames()
	_world._open_shop(SHOP_STATION_EYI)
	var i_plain := _find_row("kit_plain")
	_eq("找到素笺行", i_plain >= 0, true)
	var lvbi_before: int = int(_gm.lvbi)
	_row_btn("kit_plain").pressed.emit()
	_eq("素笺 0 元购买入账", int(_gm.get_postcard_tier()), 1)
	_eq("0 元不扣账", int(_gm.lvbi), lvbi_before)
	_eq("purchased 载荷是素笺", str(_purchased.back()), "kit_plain")
	# 传送踩到驿铺会路过发旅币，HUD 先闪「+N 旅币」再回到余额。这里等提示
	# 退场再比余额——不等的话断言读到的永远是入账提示那一帧。
	await _wait_gain_expired(hud)
	_eq("HUD 旅币标签同步", hud._lvbi_label.text, _loc.t("lvbi_label", [int(_gm.lvbi)]))
	_gm.earn(1000)
	await _frames()
	_eq("找到上笺行", _find_row("kit_fine") >= 0, true)
	_ck("1000 旅币买得上上笺", not _row_btn("kit_fine").disabled)
	var fine_price: int = _row_price("kit_fine")
	var lvbi_before_fine: int = int(_gm.lvbi)
	_row_btn("kit_fine").pressed.emit()
	_eq("上笺覆盖素笺档位", int(_gm.get_postcard_tier()), 2)
	_eq("按行价格扣账", int(_gm.lvbi), lvbi_before_fine - fine_price)
	_eq("purchased 载荷是上笺", str(_purchased.back()), "kit_fine")
	# 碎片门槛：珍藏笺要 5 块碎片，钱再多也买不了
	_eq("找到珍藏笺行", _find_row("kit_rare") >= 0, true)
	_ck("钱够也买不了缺碎片的珍藏笺", _row_btn("kit_rare").disabled)
	var lvbi_before_rare: int = int(_gm.lvbi)
	_row_btn("kit_rare").pressed.emit()
	_eq("买失败不扣账", int(_gm.lvbi), lvbi_before_rare)
	_world._close_shop()

	# ---- 8. 灯铺未到解锁驿数 ----
	_reset_world_state()
	_teleport(SHOP_STATION_DENG)
	await _frames()
	_eq("灯铺在 0 驿处可开门（锁判断在面板里）", _world._can_open_shop(SHOP_STATION_DENG), true)
	_world._open_shop(SHOP_STATION_DENG)
	_ck("未到驿数面板照开", _world._shop_panel.visible)
	_ck("未到驿数锁文案非空", str(_world._shop_panel._locked_msg) != "")
	var locked_rows = _world._shop_panel._rows
	var all_disabled := true
	for r in locked_rows:
		if not r[4].disabled:
			all_disabled = false
	_ck("锁定状态整铺禁用", all_disabled)
	var inv_before_lock: Dictionary = _gm.inv.duplicate(true)
	var lvbi_before_lock: int = int(_gm.lvbi)
	_row_btn("lamp").pressed.emit()          # 直接 emit，绕过 disabled 检查
	_eq("锁定时点了也不扣账", int(_gm.lvbi), lvbi_before_lock)
	_eq("锁定时点了也不改背包", _gm.inv, inv_before_lock)
	_world._close_shop()
	# 门必须真的挡得住：把驿数顶到门槛前一格，仍然该锁着。
	_set_seen(DENG_GATE - 1)
	_world._open_shop(SHOP_STATION_DENG)
	_ck("差一驿时仍然锁着", str(_world._shop_panel._locked_msg) != "")
	_world._close_shop()
	_set_seen(DENG_GATE)
	await _frames()
	_world._open_shop(SHOP_STATION_DENG)
	_eq("过够驿数后锁文案清空", str(_world._shop_panel._locked_msg), "")
	_gm.earn(500)
	await _frames()
	_ck("解锁后灯笼恢复可买", not _row_btn("lamp").disabled)
	_world._close_shop()

	# ---- 9. 郑铎三场 ----
	_reset_world_state()
	_gm.seen_villain = 0
	_world._villain_armed = [true, true, true]
	_set_seen(0)
	_world._player.position = _world._stations[SHOP_STATION_EYI].position + Vector3(0, 1.0, 3.0)
	_world._last_global_pos = _world._player.global_position
	_world._has_last_pos = true
	await _frames()
	_eq("未到 4 驿不触发", int(_gm.seen_villain), 0)
	# 差一驿时仍然不触发：门不能是"到过就算"。
	_set_seen(3)
	await _frames()
	_eq("3 驿仍不触发", int(_gm.seen_villain), 0)
	_set_seen(4)
	await _frames()
	_eq("4 驿触发第 1 场", int(_gm.seen_villain), 1)
	_eq("第 1 场武装位被消费", bool(_world._villain_armed[0]), false)
	_eq("第 2 场还武装着", bool(_world._villain_armed[1]), true)
	# 一次跨过 8 与 12：三场排着队全播完，且 _villain_playing 不会把它们堵死。
	# （严格顺序由 GameManager.claim_villain_scene 保证，verify_economy.gd 已覆盖。）
	_set_seen(16)
	await _frames()
	_eq("跨两档三场全部触发", int(_gm.seen_villain), 3)
	_eq("第 3 场武装位也消费掉", bool(_world._villain_armed[2]), false)
	_eq("三场播完没人还在播", _world._villain_playing, false)
	_ck("对白框已收", not _world._dialogue_popup.visible)
	await _frames()
	_eq("三场播完不再重播", int(_gm.seen_villain), 3)

	_world.queue_free()
	await process_frame
	_finish(backup, lang_before)


func _finish(backup: String, lang_before: String) -> void:
	_loc.set_language(lang_before)
	if backup != "":
		# 三份一起收：存档改成原子写之后，跑一遍会多出 .bak / .tmp，只写回正本会把它们留在盘上
		_gm._clear_save()
		var wf = FileAccess.open(str(_gm.SAVE_PATH), FileAccess.WRITE)
		if wf != null:
			wf.store_string(backup)
			wf.close()
	else:
		_gm._clear_save()

	print("\n=== 结果：OK %d / FAIL %d ===" % [_oks, _fails.size()])
	for f in _fails:
		print("  [FAIL] ", f)
	quit(0 if _fails.is_empty() else 1)
