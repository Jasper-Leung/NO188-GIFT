extends Node
# 188号礼物 - 全局管理器 (Autoload Singleton)
# 东坡赏心十六乐事（公版诗词）：雨后登楼看山/客至汲泉烹茶/乞得名花盛开/开瓮勿逢陶谢
# 月下东邻吹箫/隔江山寺闻钟/晨兴半炷茗香/接客不着衣冠/清溪浅水行舟/柳阴堤畔闲行
# 气爽褰衣散步/抚琴听者知音/微雨竹窗夜话/暑至临溪濯足/花坞樽前微笑/飞来佳禽自语
# 游戏选用第1,2,12,13,16件 -> 碎片：云/茶/琴/竹/禽

const JIA_QIN = "佳禽"
const SAVE_PATH := "user://gift188.cfg"
const SAVE_VERSION := 3
## 目标里程（虚构的环形路线长度,用于 HUD 进度显示;纯创意数值,不指涉任何现实道路）
const TOTAL_ROUTE_KM := 188.0
## 每个驿站最大可打卡次数（影响proximity提示和小游戏）
const MAX_VISITS_PER_STATION := 3

## ---- 旅币（lvbi）经济 ----
## 预算口径见 tools/verify_economy.gd 按公式重算：
##   全清 799 旅币（376 里程 + 48 路过 + 75 首次打卡 + 50 重复打卡 + 100 小游戏 + 150 碎片）
##   合理全购 890 旅币，缺口 91 ≈ 一盏灯笼 —— 必须在视野和纸面之间做减法。
const LVBI_PER_KM := 2            # 每骑过 1 整公里
const LVBI_PER_PASS := 3         # 首次路过任意驿站（16 站每一座都有）
const LVBI_FIRST_CHECKIN := 15   # 碎片站首次打卡
const LVBI_REPEAT_CHECKIN := 5   # 碎片站重复打卡（每站最多 2 次）
const LVBI_MINI_WIN := 20        # 小游戏成功
const LVBI_MINI_LOSE := 5        # 失败也留一点，别让玩家觉得白挨一趟
const LVBI_PER_FRAGMENT := 30    # 首次拾取碎片

## 反派场次总数（K50 / K100 / K150），终局摊牌不算在内
const VILLAIN_SCENE_COUNT := 3

## ---- 心神（mood）----
## 沿用《归途》冻结版的形状：初始 4、下限 1、永不归零、绝不锁操作。
## 代价分两路走，都只作用于「看见多少」，不作用于收入：
##   遮罩浓淡 get_mood_mask_alpha() —— 只有心神进这条
##   视野半径 get_visibility_factor() —— 心神 + 灯笼 + 香囊
## 灯笼/香囊只对冲后者：买灯笼是把「看得见的范围」撑回来，不是把雾买散。
const MOOD_CEIL := 5
const MOOD_FLOOR := 1
const MOOD_INITIAL := 4
const MOOD_MASK_MAX := 0.52      # 心神 1 时遮罩不透明度上限（绝不盖满，不做失败态）
## 视野系数：心神 5 → 1.00 全开，心神 1 → 0.65
const MOOD_VIS_MAX := 1.00
const MOOD_VIS_MIN := 0.65
const LAMP_VIS_STEP := 0.25      # 一盏灯笼把视野半径放大 25%
const LAMP_VIS_MAX_OWN := 2      # 可叠两件
const LAMP_VIS_CAP := 1.50       # 两件封顶 +50%
const SACHET_PENALTY_SCALE := 0.5   # 香囊：心神的视野惩罚减半
const VIS_FLOOR := 0.50          # 再差也不能看不见路
const VIS_CEIL := 1.00           # 买不到比初始更远的视野，也不越流式驻留半径

enum State { GIFT_BOX, ROAMING, CHECK_IN, SYNTHESIZING, END_CARD }

## Headless 验证脚本设置此标志，跳过需人工交互的对话弹窗
var headless_mode := false

signal fragment_collected(index)
## 五座碎片驿站**各**至少到访过一次（第一次集齐）。不是结束条件 ——
## 之后每座还欠 MAX_VISITS_PER_STATION-1 次回访，那才是全游戏的重玩钩子。
signal all_fragments_collected()
## 五座碎片驿站各刷满 MAX_VISITS_PER_STATION 次。**这才是"这一趟走完了"。**
##
## 原来没有这个信号，World3D 直接拿 all_fragments_collected 当结束条件 ——
## 于是顶栏一路写着「再访 · 还差 N 次」而游戏在第一次集齐时就把玩家锁死
## 2.5 秒弹去结算页。那个承诺从第一屏起就兑现不了。all_fragments_maxed()
## 这个判据一直写在那里，却没有任何地方调用过。
signal all_fragments_maxed_reached()
signal state_changed(new_state)
signal lvbi_changed(amount: int, total: int)
signal mood_changed(value: int)
signal item_purchased(item_id: String)

## station_idx (int) -> 累计打卡次数 (int，0=从未到访)
var collected: Dictionary = _new_collected()
## 两个"翻转已发过"的闩锁，只活在本次会话里，不落盘。
## 读档之后要按存档现状补齐 —— 否则一个已经五站全收的存档，
## 下一次回访打卡会重发一次 all_fragments_collected，把合成动画重放一遍。
var _collected_fired := false
var _maxed_fired := false
var current_state = State.GIFT_BOX
## 里程**只作经济口径**，不再出现在任何玩家可见的界面上（顶栏改挂驿数）。
## 铺子解锁和郑铎三场原来都挂在这上面，见 shop_data.gd / World3D.VILLAIN_SCENES。
var progress_km: float = 0.0
var onboarding_shown: bool = false

## ---- v3 新增状态 ----
var lvbi: int = 0                  # 当前旅币余额
var inv: Dictionary = {}           # 商品 id -> 数量；明信片档位存 inv["postcard_tier"]
var spent_km: float = 0.0          # 已计费的里程，防止读档后重复发钱
var earned_tags: Dictionary = {}   # tag -> true，earn() 的幂等账本
var seen_stations: Dictionary = {} # station_idx -> true，首次路过 +3 只发一次
var mood: int = MOOD_INITIAL       # 心神 1..5
var seen_villain: int = 0          # 已播到的反派场次（1-based）
var prologue_done: bool = false
var ending_id: String = ""


func _ready():
	_setup_input_map()
	if ResourceLoader.exists("res://assets/fonts/LXGWWenKai-Regular.ttf"):
		ThemeDB.fallback_font = load("res://assets/fonts/LXGWWenKai-Regular.ttf")
	# 启动时先尝试读档：上次打卡的碎片、里程、首启提示会沿用
	# 没有存档时 _load_save() 是 no-op,保留上面的默认值。
	# 显式"重新开始"由 go_to_gift_box() 走 reset() 路径,不影响这里。
	_load_save()


func _new_collected() -> Dictionary:
	var d := {}
	for st_idx in RoadData.FRAGMENT_SLOT_STATION_IDX:
		d[st_idx] = 0
	return d


func _add_action(action_name, keys):
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for key in keys:
		var ev = InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action_name, ev)


func _add_action_with_modifier(action_name, keycode, ctrl: bool = false, shift: bool = false, alt: bool = false) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var ev = InputEventKey.new()
	ev.physical_keycode = keycode
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	ev.alt_pressed = alt
	InputMap.action_add_event(action_name, ev)


func _setup_input_map():
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("interact", [KEY_SPACE, KEY_ENTER])
	_add_action("pause", [KEY_ESCAPE])
	_add_action("mute", [KEY_M])
	# 编辑模式动作(无副作用,普通运行也注册,只在编辑器里消费)
	# 注意:不能用 --editor,会与 Godot 内置的 --editor 标志冲突
	# 方向键只用于选中对象移动;选中对象时相机不响应方向键
	_add_action("editor_move_fwd", [KEY_UP])
	_add_action("editor_move_back", [KEY_DOWN])
	_add_action("editor_move_left", [KEY_LEFT])
	_add_action("editor_move_right", [KEY_RIGHT])
	# Q/E 只用于旋转,不绑相机升降(避免视角乱飞)
	_add_action("editor_rotate_cw", [KEY_E])
	_add_action("editor_rotate_ccw", [KEY_Q])
	# 相机升降改用 R / F
	_add_action("editor_camera_up", [KEY_R])
	_add_action("editor_camera_down", [KEY_F])
	_add_action("editor_scale_up", [KEY_BRACKETRIGHT])
	_add_action("editor_scale_down", [KEY_BRACKETLEFT])
	# 重置改到 Backspace(原 R 已被相机上升占用)
	_add_action("editor_reset", [KEY_BACKSPACE])
	# 取消选中(在编辑器里选中对象后,任何时候按 X 退出选择,把 WASD 还给相机)
	_add_action("editor_deselect", [KEY_X])
	# 保存:绑定 Ctrl+S(用带修饰键的注册,避免按 S 时误触发)
	_add_action_with_modifier("editor_save", KEY_S, true, false, false)
	_add_action("editor_exit", [KEY_ESCAPE])
	_bind_ui_accept_to_physical()


## 给引擎内建的 `ui_accept` / `ui_select` 补一份 **physical_keycode** 绑定。
##
## 为什么要补：全工程每一个按钮——操作说明的「开始骑行」、驿铺的每一件、
## 标题页的「开始」、结算页的「导出」——都靠 `ui_accept` 触发，而内建动作
## 是按 `keycode` 匹配的。本项目 InputMap 当年全用 physical_keycode，
## 正因为 Web 导出下 `keycode` 可能填不上（见 CLAUDE.md 已知陷阱）——
## 于是同一个陷阱搬了个家：桌面端好好的，Web 上**一个按钮都按不动**，
## 而键盘玩家除了按鼠标没有别的出路（实测：`verify_panel_keyboard.gd` 第 3 节，
## 焦点确实落在「买」上，按空格 8 秒纹丝不动）。
##
## 补在这里而不是给每个面板加兜底：一个键位表漏一处就是一处新的死路，
## 而这里是唯一的出处。内建的 keycode 绑定保留，所以桌面端行为不变。
func _bind_ui_accept_to_physical() -> void:
	for action in ["ui_accept", "ui_select"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


## 编辑模式触发条件(任一满足):
##   1. 命令行含 --gift-editor (不能用 --editor,会被 Godot 内置标志劫持)
##   2. 环境变量 GIFT188_EDITOR=1
##   3. 项目根目录存在 .editor_mode 文件 (已加入 .gitignore)
static func is_editor_mode() -> bool:
	if OS.get_cmdline_args().has("--gift-editor"):
		return true
	if OS.get_environment("GIFT188_EDITOR") == "1":
		return true
	return FileAccess.file_exists("res://.editor_mode")


func check_in(station_index):
	if station_index < 0:
		return
	# 非碎片驿站不记录
	if not RoadData.FRAGMENT_SLOT_STATION_IDX.has(station_index):
		return
	var prev: int = int(collected.get(station_index, 0))
	var next_count: int = mini(prev + 1, MAX_VISITS_PER_STATION)
	if next_count <= prev:
		return  # 已达上限
	collected[station_index] = next_count
	# 旅币：首次打卡 15，重复打卡 5。tag 幂等，读档重玩不会重复发钱。
	if prev == 0:
		earn(LVBI_FIRST_CHECKIN, "checkin_%d_1" % station_index)
	else:
		earn(LVBI_REPEAT_CHECKIN, "checkin_%d_%d" % [station_index, next_count])
	# 仅在第一次到访时触发碎片动画signal
	if prev == 0:
		earn(LVBI_PER_FRAGMENT, "frag_%d" % station_index)
		cost_mood(1)   # 深度余响的代价：心神 -1
		fragment_collected.emit(station_index)
	_save_game()
	# 这两个都是**状态翻转**事件，不是"当前状态"。原来只有 all_fragments_collected
	# 且没有翻转检测：五站各收过第一次之后，每一次回访打卡都会再发一遍。
	# 那时无害 —— 第一轮就把整趟锁死、弹去结算页了，不会有第二次。
	# 现在结束条件改成 all_fragments_maxed()，回访变成正常玩法，
	# 缺了这道检测就变成"每回访一次重放合成动画并把玩家弹去结算页"。
	if _all_collected() and not _collected_fired:
		_collected_fired = true
		all_fragments_collected.emit()
	if all_fragments_maxed() and not _maxed_fired:
		_maxed_fired = true
		all_fragments_maxed_reached.emit()


func is_collected(station_idx: int) -> bool:
	return collected.get(station_idx, 0) > 0


func _all_collected():
	# 5 个碎片驿站分散在 16 站 idx 中(4/7/10/13/14),不能直接 range(5)
	for st_idx in RoadData.FRAGMENT_SLOT_STATION_IDX:
		if collected.get(st_idx, 0) <= 0:
			return false
	return true


func get_collected_count() -> int:
	var n = 0
	for st_idx in RoadData.FRAGMENT_SLOT_STATION_IDX:
		if collected.get(st_idx, 0) > 0:
			n += 1
	return n


## 已经过的驿站数（不含碎片逻辑，全 16 站一起数）。
##
## 这是唯一还留在玩家面前的"进度单位"。原来顶栏挂的是 km，但世界只有 1228.8m，
## km 与 188 一换算就是 2km/s —— 玩家骑三十秒就能算出 7200km/h，然后整个数字
## 连同它承载的解锁门一起失去可信度。驿是可数的、真的、和结局条件同源。
func get_seen_station_count() -> int:
	return seen_stations.size()


## 给定 slot idx (0..4),查询对应碎片是否已收集（slot有否被激活过）
func is_fragment_collected(slot_idx: int) -> bool:
	if slot_idx < 0 or slot_idx >= RoadData.FRAGMENT_SLOT_STATION_IDX.size():
		return false
	return collected.get(RoadData.FRAGMENT_SLOT_STATION_IDX[slot_idx], 0) > 0


## 某个驿站已达最大打卡次数
func is_station_exhausted(station_idx: int) -> bool:
	return collected.get(station_idx, 0) >= MAX_VISITS_PER_STATION


## 这座碎片驿站还欠一次到访吗？
##
## 完满评级要求五座碎片驿站各去过 MAX_VISITS_PER_STATION 次，所以"还没收"从来
## 不是目标的全集：第一次到访之后这一站还剩两次。可这三处 UI 原来一律按
## `not station_has_fragment(i) or is_collected(i)` 跳过它，于是最强的重玩钩子
## 在玩法里既不主动说、也不给导航 —— 而回访提示还写着"歇一脚"，等于在劝退。
##
## 顶栏 / 小地图 / 脚下提示圈三处都调这一个函数。它们是本项目里唯三会告诉
## 玩家"下一处在哪"的地方，任何一处自己抄一遍判据都会让玩家看到三块互相
## 打架的指示牌（见 CLAUDE.md 的已知陷阱）。
func fragment_station_needs_visit(station_idx: int) -> bool:
	if not RoadData.FRAGMENT_SLOT_STATION_IDX.has(station_idx):
		return false
	return collected.get(station_idx, 0) < MAX_VISITS_PER_STATION


## 五座碎片驿站是不是都刷满了。全满之后"下一处"才真的没有目标。
func all_fragments_maxed() -> bool:
	for st_idx in RoadData.FRAGMENT_SLOT_STATION_IDX:
		if collected.get(st_idx, 0) < MAX_VISITS_PER_STATION:
			return false
	return true


## 某个 slot（0..4）还差几次到访才满格。已满返回 0。
func fragment_slot_visits_left(slot_idx: int) -> int:
	if slot_idx < 0 or slot_idx >= RoadData.FRAGMENT_SLOT_STATION_IDX.size():
		return 0
	var cnt: int = collected.get(RoadData.FRAGMENT_SLOT_STATION_IDX[slot_idx], 0)
	return maxi(MAX_VISITS_PER_STATION - cnt, 0)


## 获取某驿站当前打卡次数
func get_station_count(station_idx: int) -> int:
	return collected.get(station_idx, 0)


## ================= 旅币与背包 =================

## 每骑过 1 整公里 +2。只在跨过整数公里时发钱并写盘；
## 帧间只记进度，所以 set_progress_km() 每帧调用也不会每帧写文件。
func earn_km(new_km: float) -> int:
	var clamped := clampf(new_km, 0.0, TOTAL_ROUTE_KM)
	var whole := int(floorf(clamped))
	if whole > int(spent_km):
		var gained := (whole - int(spent_km)) * LVBI_PER_KM
		spent_km = float(whole)
		lvbi += gained
		lvbi_changed.emit(gained, lvbi)
		_save_game()
		return gained
	if clamped > spent_km:
		spent_km = clamped
	return 0


## tag 幂等：同一个 tag 只发一次。空 tag 每次都发（仅测试用）。
## 本函数不写盘，由调用方在离散事件末尾统一 _save_game()。
func earn(amount: int, tag: String = "") -> int:
	if amount <= 0:
		return 0
	if tag != "":
		if earned_tags.has(tag):
			return 0
		earned_tags[tag] = true
	lvbi += amount
	lvbi_changed.emit(amount, lvbi)
	return amount


## 首次路过任意驿站 +3。16 站里 11 座没有碎片，这条让它们都有存在理由。
func on_station_pass(station_idx: int) -> int:
	if seen_stations.has(station_idx):
		return 0
	seen_stations[station_idx] = true
	var gained := earn(LVBI_PER_PASS, "pass_%d" % station_idx)
	_save_game()
	return gained


## 小游戏结算：成功 +20，失败 +5，同一站各只发一次。
func on_mini_game(station_idx: int, win: bool) -> int:
	var amount := LVBI_MINI_WIN if win else LVBI_MINI_LOSE
	var tag := ("mini_%d_win" if win else "mini_%d_lose") % station_idx
	var gained := earn(amount, tag)
	_save_game()
	return gained


## ================= 心神 =================

## 只扣不锁：下限 1，永不归零。不把它做成失败条件（冻结版 §7 的红线）。
func cost_mood(amount: int = 1) -> int:
	var before := mood
	mood = maxi(MOOD_FLOOR, mood - amount)
	var delta := mood - before
	if delta != 0:
		mood_changed.emit(mood)
	return delta


## 心神 → 视野遮罩不透明度。0 = 完全看得清，0.52 = 雾最浓。
## 只有心神进这条：灯笼/香囊走 get_visibility_factor()，不把雾买散。
## 「你听见过去越多，眼前的世界越看不见；要不要花钱让眼睛重新看见，是你自己的事。」
func get_mood_mask_alpha() -> float:
	return clampf(MOOD_MASK_MAX * float(MOOD_CEIL - mood) / float(MOOD_CEIL - MOOD_FLOOR),
			0.0, MOOD_MASK_MAX)


## 心神 → 草皮与树的可见半径系数。心神越差越收，灯笼把它撑回来，香囊把惩罚砍一半。
## 方案 §7.1 的算例：心神 1 + 两件灯笼 = 0.65 × 1.50 = 0.975。
## 上限夹在 1.0：花钱买不到比初始更远的视野，也不越过流式的驻留半径。
func get_visibility_factor() -> float:
	var t := float(MOOD_CEIL - mood) / float(MOOD_CEIL - MOOD_FLOOR)
	var penalty := 1.0 - lerpf(MOOD_VIS_MAX, MOOD_VIS_MIN, t)
	if has_item("sachet"):
		penalty *= SACHET_PENALTY_SCALE
	var base := 1.0 - penalty
	var lamps := minf(float(get_item_count("lamp")), float(LAMP_VIS_MAX_OWN))
	base *= minf(1.0 + LAMP_VIS_STEP * lamps, LAMP_VIS_CAP)
	return clampf(base, VIS_FLOOR, VIS_CEIL)


## ================= 背包与购物 =================

func get_item_count(item_id: String) -> int:
	return int(inv.get(item_id, 0))


func has_item(item_id: String) -> bool:
	return get_item_count(item_id) > 0


## 明信片档位：0 = 没买套餐（明信片照样产出，只是最素的一档）
func get_postcard_tier() -> int:
	return int(inv.get("postcard_tier", 0))


func can_buy(g: Dictionary) -> bool:
	if int(g.get("price", 0)) > lvbi:
		return false
	if int(g.get("requires_fragments", 0)) > get_collected_count():
		return false
	if str(g.get("grant", "")) == "postcard_tier":
		return get_postcard_tier() < int(g.get("tier_rank", 1))
	return get_item_count(str(g["id"])) < int(g.get("max_own", 1))


func buy(g: Dictionary) -> bool:
	if not can_buy(g):
		return false
	var gid := str(g["id"])
	var price := int(g.get("price", 0))
	lvbi -= price
	if str(g.get("grant", "")) == "postcard_tier":
		inv["postcard_tier"] = int(g.get("tier_rank", 1))
	else:
		inv[gid] = get_item_count(gid) + 1
	lvbi_changed.emit(-price, lvbi)
	item_purchased.emit(gid)
	_save_game()
	return true


## ================= 剧情进度 =================

func mark_prologue_done() -> void:
	prologue_done = true
	_save_game()


## 反派场次（1-based）。返回 true 表示这一场该播。
## 严格顺序：必须 i == seen_villain + 1。编辑器里把玩家传送到 K150
## 也不能跳过前两场——跳场会把漏掉的对白永久吞掉。
func claim_villain_scene(i: int) -> bool:
	if i < 1 or i > VILLAIN_SCENE_COUNT or seen_villain != i - 1:
		return false
	seen_villain = i
	_save_game()
	return true


func set_ending(ending: String) -> void:
	ending_id = ending
	_save_game()


func get_progress_km():
	return int(round(progress_km))


func set_progress_km(km: float) -> void:
	progress_km = clampf(km, 0.0, TOTAL_ROUTE_KM)


func set_state(new_state):
	current_state = new_state
	state_changed.emit(new_state)


func reset():
	collected = _new_collected()
	_collected_fired = false
	_maxed_fired = false
	current_state = State.GIFT_BOX
	progress_km = 0.0
	onboarding_shown = false
	lvbi = 0
	inv = {}
	spent_km = 0.0
	earned_tags = {}
	seen_stations = {}
	mood = MOOD_INITIAL
	seen_villain = 0
	prologue_done = false
	ending_id = ""
	_clear_save()


func _save_game() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("game", "version", SAVE_VERSION)
	# v2: Dictionary 格式 "station_idx:count,..." 仅存5个碎片驿站
	var parts := []
	for st_idx in RoadData.FRAGMENT_SLOT_STATION_IDX:
		parts.append("%d:%d" % [st_idx, collected.get(st_idx, 0)])
	cfg.set_value("game", "collected", ",".join(parts))
	cfg.set_value("game", "progress_km", progress_km)
	cfg.set_value("game", "onboarding_shown", 1 if onboarding_shown else 0)
	# v3: 经济/心神/剧情进度打包成一个 JSON 块，加字段不用再改序列化逻辑
	cfg.set_value("game", "economy", JSON.stringify({
		"lvbi": lvbi, "inv": inv, "spent_km": spent_km, "earned_tags": earned_tags,
		"seen_stations": seen_stations, "mood": mood, "seen_villain": seen_villain,
		"prologue_done": prologue_done, "ending_id": ending_id,
	}))
	if cfg.save(SAVE_PATH) != OK:
		push_warning("存档写入失败: %s" % SAVE_PATH)


func _load_save() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var ver := int(cfg.get_value("game", "version", 0))
	if ver != SAVE_VERSION:
		_clear_save()   # v1 旧存档直接清除；新版本从头开始
		return
	var data: String = str(cfg.get_value("game", "collected", ""))
	if data != "":
		for entry in data.split(","):
			var kv := entry.split(":")
			if kv.size() == 2:
				var st_idx := kv[0].to_int()
				var cnt := kv[1].to_int()
				collected[st_idx] = cnt
	progress_km = clampf(float(cfg.get_value("game", "progress_km", 0.0)), 0.0, TOTAL_ROUTE_KM)
	onboarding_shown = int(cfg.get_value("game", "onboarding_shown", 0)) != 0
	# v3: economy 块缺失（老存档已按版本号清掉）或损坏时保留默认值，绝不抛错
	var blob = JSON.parse_string(str(cfg.get_value("game", "economy", "")))
	if blob is Dictionary:
		lvbi = maxi(0, int(blob.get("lvbi", 0)))
		if blob.get("inv") is Dictionary:
			inv = blob["inv"]
		spent_km = clampf(float(blob.get("spent_km", 0.0)), 0.0, TOTAL_ROUTE_KM)
		if blob.get("earned_tags") is Dictionary:
			earned_tags = blob["earned_tags"]
		if blob.get("seen_stations") is Dictionary:
			seen_stations = blob["seen_stations"]
		mood = clampi(int(blob.get("mood", MOOD_INITIAL)), MOOD_FLOOR, MOOD_CEIL)
		seen_villain = maxi(0, int(blob.get("seen_villain", 0)))
		prologue_done = blob.get("prologue_done", false) == true
		ending_id = str(blob.get("ending_id", ""))
	# 必须在 collected 载入**之后**再对齐：这两个事件是在存档写下的那一刻
	# 就已经发过了，读档回来它们不该再发一遍 —— 否则一个五站全收的存档，
	# 第一次回访打卡就会重放合成动画、把玩家弹去结算页。
	_collected_fired = _all_collected()
	_maxed_fired = all_fragments_maxed()


func _clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func go_to_roaming(scene: PackedScene = null):
	set_state(State.ROAMING)
	if scene != null:
		get_tree().change_scene_to_packed(scene)
	else:
		get_tree().change_scene_to_file("res://scenes/World3D.tscn")


func go_to_end_card():
	set_state(State.END_CARD)
	get_tree().change_scene_to_file("res://scenes/EndCard.tscn")


func go_to_gift_box():
	reset()
	get_tree().change_scene_to_file("res://scenes/GiftBox.tscn")
