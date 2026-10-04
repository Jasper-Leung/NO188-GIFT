extends Node
# 188号礼物 - 全局管理器 (Autoload Singleton)
# 东坡赏心十六乐事（公版诗词）：雨后登楼看山/客至汲泉烹茶/乞得名花盛开/开瓮勿逢陶谢
# 月下东邻吹箫/隔江山寺闻钟/晨兴半炷茗香/接客不着衣冠/清溪浅水行舟/柳阴堤畔闲行
# 气爽褰衣散步/抚琴听者知音/微雨竹窗夜话/暑至临溪濯足/花坞樽前微笑/飞来佳禽自语
# 游戏选用第1,2,12,13,16件 -> 碎片：云/茶/琴/竹/禽

const JIA_QIN = "佳禽"
const SAVE_PATH := "user://gift188.cfg"
## 存档是**原子写**的：先落到临时文件，再换名盖掉正本，最后把换名之前
## 上一份好的复制成 `.bak`。三步的顺序不能挪 —— 换名在 Windows 上会直接
## 擦掉目标，所以备份必须抢在它前面；而临时文件写完之前正本一个字都不动。
## 原来直接 `cfg.save(SAVE_PATH)`，崩溃/断电/Web 上关标签页会把它截断成
## 半份，而 ConfigFile 对**截断、纯垃圾、空文件一律返回 OK**（实测，
## 见 tools/verify_save_robustness.gd 第 1 节）—— 于是读档"成功"、版本号
## 取到 0、走 `_clear_save()` 把玩家整趟行程删掉。
const SAVE_TMP := "user://gift188.cfg.tmp"
const SAVE_BAK := "user://gift188.cfg.bak"
const SAVE_VERSION := 3
## 目标里程（虚构的环形路线长度,用于 HUD 进度显示;纯创意数值,不指涉任何现实道路）
const TOTAL_ROUTE_KM := 188.0
## 每个驿站最大可打卡次数（影响proximity提示和小游戏）
const MAX_VISITS_PER_STATION := 3

## ---- 旅币（lvbi）经济 ----
## 预算口径见 tools/verify_economy.gd 按公式重算：
##   全清 799 旅币（376 里程 + 48 路过 + 75 首次打卡 + 50 重复打卡 + 100 小游戏 + 150 碎片）
##   合理全购 1010 旅币，缺口 211 —— 必须在视野和纸面之间做减法。
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
const MOOD_MASK_MAX := 0.34      # 心神 1 时遮罩不透明度上限（绝不盖满，不做失败态）
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

## ---- 演示模式（给评审的 90 秒路径）----
##
## **不存档**：`enter_demo()` 每次都从 `reset()` 起，任何一次普通游玩读档
## 都读不到它。它唯一的作用是让 World3D 跳过操作说明和序章、并挂上
## DemoDirector；那张明信片本身仍是玩家走出来的存档现算的。
var demo_mode: bool = false

## 演示总长，和标题页按钮上写的「90 秒」是同一个数
const DEMO_BUDGET_SEC := 90.0
## 演示在这里收工跳去结算页，剩下的时间留给明信片和终局二选一
const DEMO_END_AT_SEC := 62.0


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


## 玩家真正要记的那几个键 —— **注册**与**屏上那份键位表**的同一个出处。
##
## 原来两边各写一份，而且屏上那份存在过**四份**不同的实现：这里逐行注册、
## `OnboardingGuide` 的结构化 Label、`HUD3D/HelpOverlay` 场景里写死的中文、
## `Localization.help_overlay` 一整段带换行的文本。四份互相对拍的话格式先对不上
## （后一份根本没有结构），于是"新增一个键位忘了改屏上那份"这种漏改没有任何
## 回归会红 —— 而 `verify_mood_mask` 里那条"区分用的字符必须是字"就是同一族的教训。
##
## `keys` 是真的绑定（`_setup_input_map` 拿它注册 InputMap），`keys_label` 只是
## 屏上怎么写这两个键（箭头写 ↑ 还是 Up Arrow 是排版决定，不是绑定），
## 而**键与字面量是否对得上由回归去比**，不许靠这里自觉一致。
const PLAYER_ACTIONS := [
	{"action": "move_up", "keys": [KEY_W, KEY_UP], "keys_label": "W / ↑", "desc_key": "key_forward"},
	{"action": "move_down", "keys": [KEY_S, KEY_DOWN], "keys_label": "S / ↓", "desc_key": "key_back"},
	{"action": "move_left", "keys": [KEY_A, KEY_LEFT], "keys_label": "A / ←", "desc_key": "key_left"},
	{"action": "move_right", "keys": [KEY_D, KEY_RIGHT], "keys_label": "D / →", "desc_key": "key_right"},
	{"action": "interact", "keys": [KEY_SPACE, KEY_ENTER], "keys_label": "Space / Enter", "desc_key": "key_check_in"},
	{"action": "pause", "keys": [KEY_ESCAPE], "keys_label": "ESC", "desc_key": "key_pause"},
	{"action": "mute", "keys": [KEY_M], "keys_label": "M", "desc_key": "key_mute"},
]


## 屏上那一行怎么写。**冷启动的操作说明与设置面板都调这一个出处**——
## 键位表以前是冷启动唯一的一次性面板（`onboarding_shown` 一置就不再出现），
## 而玩家中途想再看一眼时 HUD 上那个「?」按钮压根没接线（`show_help()` 零调用者）。
func player_control_rows() -> Array:
	var rows := []
	for entry in PLAYER_ACTIONS:
		rows.append([str(entry["keys_label"]), Localization.t(str(entry["desc_key"]))])
	return rows


## 触屏那三行。走 `Localization` 的 key 而不是写死中文 —— 原来 HUD 场景里那份
## 触屏表是三行写死的中文，英文界面下那三行仍然是中文。
func touch_control_rows() -> Array:
	return [
		[Localization.t("touch_joystick_key"), Localization.t("touch_joystick_desc")],
		[Localization.t("touch_checkin_key"), Localization.t("touch_checkin_desc")],
		[Localization.t("touch_buttons_key"), Localization.t("touch_buttons_desc")],
	]


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
	# 玩家要记的键位从 PLAYER_ACTIONS 走一遍，别再在这里逐行动手抄一遍——
	# 注册处与"屏上那份键位表"曾经是两份独立的手抄，四份实现格式各不相同
	# （这里逐行 / OnboardingGuide 的结构化 Label / HUD3D 场景里写死的中文
	# / Localization 里一整段带换行的文本），漂了没有任何一条回归会红。
	for entry in PLAYER_ACTIONS:
		_add_action(str(entry["action"]), entry["keys"])
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


## 心神的上行口。原来满工程只有 `cost_mood()` 一个写点、**零个**恢复点，
## 于是它是一条单向的下水道：收满五块碎片正好把 4 打到 1，而 1 正是遮罩最浓
## 那一档——玩家最需要看清世界的那一刻（集齐二选一那面面板）恰恰最暗。
## 灯笼/香囊只对冲视野半径、把雾留着，所以它们没有、也不该堵这条下水道；
## 这就是那个出口。返回实际涨了几格，满的时候返回 0（买东西不能白花旅币）。
func restore_mood(amount: int = 1) -> int:
	var before := mood
	mood = mini(MOOD_CEIL, mood + amount)
	var delta := mood - before
	if delta != 0:
		mood_changed.emit(mood)
		_save_game()
	return delta


## 心神 → 视野遮罩不透明度。0 = 完全看得清，0.34 = 雾最浓。
## 只有心神进这条：灯笼/香囊走 get_visibility_factor()，不把雾买散。
## 0.52 → 0.34：原来那一档正好落在**集齐二选一那面面板**上（五块碎片收完
## 心神 4→1，遮罩最浓），于是全场信息量最大的那一刻是最暗的。降下来之后
## 心神 1 是 0.34、心神 2 是 0.17——梯度还在，屏幕不再糊掉。
## 降它的前提是心神有一条上行口（`restore_mood()` + 茶铺的清心茶），
## 否则玩家只剩一条单向的下水道。
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
	if str(g.get("grant", "")) == "mood_up":
		# 满心神时买它等于白花旅币，所以这条要**真的挡在 can_buy 里**，
		# 不能只让 ShopPanel 把按钮画灰 —— 灰按钮玩家看得见，但绕过
		# disabled 的程序化触发照样会把钱花掉。
		if mood >= MOOD_CEIL:
			return false
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
		if str(g.get("grant", "")) == "mood_up":
			restore_mood(int(g.get("mood_up", 1)))
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
	demo_mode = false
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
	# 1) 新的内容先落到临时文件。这一步失败的话正本一个字都不动。
	if cfg.save(SAVE_TMP) != OK:
		push_warning("存档写入失败: %s" % SAVE_TMP)
		return
	# 2) 换名会擦掉目标，所以先把正本（上一份已知是好的）复制成 .bak。
	#    没有这一步，"正本被截断"就等于"整趟行程没了"，因为没有第二份可退。
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(SAVE_PATH, SAVE_BAK)
	# 3) 换名盖掉正本。同盘换名在 NTFS / ext4 上是原子的，崩在中间也只会
	#    停在"旧的"或"新的"这一边，不会停在半份上。
	if DirAccess.rename_absolute(SAVE_TMP, SAVE_PATH) != OK:
		push_warning("存档换名失败: %s" % SAVE_PATH)
		if not FileAccess.file_exists(SAVE_PATH):
			# 正本被搬走又没搬回来 —— 宁可退回临时那份，也别留一个空的正本
			DirAccess.copy_absolute(SAVE_TMP, SAVE_PATH)
		DirAccess.remove_absolute(SAVE_TMP)


## 读一份存档。**返回 false = 这份文件不能信**，调用方据此退回备份或重来。
##
## 注意这里**不看 `ConfigFile.load()` 的返回值**：实测它对截断、纯垃圾、
## 空文件一律返回 OK（tools/verify_save_robustness.gd 第 1 节钉着这三条），
## 所以"没报错"什么都不能证明。判据只能是"版本号对得上、而且 economy
## 那一段真的解得出字典" —— 自己写出来的存档必定两样都满足。
func _try_load_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var cfg := ConfigFile.new()
	cfg.load(path)
	if int(cfg.get_value("game", "version", 0)) != SAVE_VERSION:
		return false   # v1/v2 旧存档：照旧从头开始，但让调用方先试备份
	var blob = JSON.parse_string(str(cfg.get_value("game", "economy", "")))
	if not (blob is Dictionary):
		return false
	collected = _sanitise_collected(str(cfg.get_value("game", "collected", "")))
	progress_km = clampf(float(cfg.get_value("game", "progress_km", 0.0)), 0.0, TOTAL_ROUTE_KM)
	onboarding_shown = int(cfg.get_value("game", "onboarding_shown", 0)) != 0
	lvbi = maxi(0, int(blob.get("lvbi", 0)))
	inv = _sanitise_inv(blob.get("inv", {}))
	spent_km = clampf(float(blob.get("spent_km", 0.0)), 0.0, TOTAL_ROUTE_KM)
	# 幂等账本的键是拼出来的（checkin_7_1 / frag_7 / pass_3），没法列白名单，
	# 但值必须是 true —— earn() 只看键在不在，值坏了不会多发钱。
	earned_tags = _sanitise_flags(blob.get("earned_tags", {}))
	seen_stations = _sanitise_seen(blob.get("seen_stations", {}))
	mood = clampi(int(blob.get("mood", MOOD_INITIAL)), MOOD_FLOOR, MOOD_CEIL)
	seen_villain = clampi(int(blob.get("seen_villain", 0)), 0, VILLAIN_SCENE_COUNT)
	prologue_done = blob.get("prologue_done", false) == true
	ending_id = str(blob.get("ending_id", ""))
	# 必须在 collected 载入**之后**再对齐：这两个事件是在存档写下的那一刻
	# 就已经发过了，读档回来它们不该再发一遍 —— 否则一个五站全收的存档，
	# 第一次回访打卡就会重放合成动画、把玩家弹去结算页。
	_collected_fired = _all_collected()
	_maxed_fired = all_fragments_maxed()
	return true


## 读档：正本 → 备份 → 当作没有存档。
##
## 原来只有"正本"这一条路，而正本被截断时 `load()` 还返回 OK，于是版本号
## 取到 0 走 `_clear_save()`，**把玩家这一趟直接删掉**。现在中间那一档是
## 玩家真正想要的：从上一份好的接着玩，而不是从头开始。
func _load_save() -> void:
	if _try_load_from(SAVE_PATH):
		return
	if _try_load_from(SAVE_BAK):
		push_warning("存档损坏，已从上一份备份恢复: %s" % SAVE_BAK)
		return
	_clear_save()   # v1 旧存档直接清除；新版本从头开始


## 一份坏存档不许把玩家推进「赢不了」或者「白赢」的状态。
## 每一条都是**从玩家的下一帧真的读出来的那几个量**倒推的：
## · collected 落到 [0, MAX_VISITS_PER_STATION]：超了的话
##   `is_station_exhausted()` 恒真，这一座碎片站**永久打不了卡**，
##   而顶栏"下一处"还指着它 —— 玩家卡死在一个永远减不到 0 的数字上。
##   不在 FRAGMENT_SLOT_STATION_IDX 里的键整个丢掉，`_all_collected()`
##   遍历的是那五座，多出来的键只是让存档看着像有进度。
## · inv 里的 `postcard_tier` 直接被 `get_postcard_tier()` 读出来当档位，
##   夹到商品表里真正存在的最高档；未知商品 id 丢掉，免得白嫖出没花钱的东西。
## · seen_stations.size() 就是顶栏那句「已过 n 驿」，也是灯铺与郑铎三场的门槛，
##   所以只认真站号、且把值统一成 true。
func _sanitise_collected(data: String) -> Dictionary:
	var raw := {}
	for entry in data.split(",", false):
		var kv := str(entry).split(":")
		if kv.size() == 2:
			raw[kv[0].strip_edges().to_int()] = kv[1].strip_edges().to_int()
	var d := {}
	for st_idx in RoadData.FRAGMENT_SLOT_STATION_IDX:
		d[st_idx] = clampi(int(raw.get(st_idx, 0)), 0, MAX_VISITS_PER_STATION)
	return d


func _sanitise_inv(src: Variant) -> Dictionary:
	if not (src is Dictionary):
		return {}
	var out := {}
	for g in ShopData.GOODS:
		var gid := str(g["id"])
		if src.has(gid):
			out[gid] = clampi(int(src[gid]), 0, maxi(0, int(g.get("max_own", 1))))
	# 档位不是商品，走单独一支：表里 tier_rank 的最大值就是天花板。
	var max_tier := 0
	for g in ShopData.GOODS:
		if str(g.get("grant", "")) == "postcard_tier":
			max_tier = maxi(max_tier, int(g.get("tier_rank", 0)))
	if src.has("postcard_tier"):
		out["postcard_tier"] = clampi(int(src["postcard_tier"]), 0, max_tier)
	return out


## 幂等账本 / 到过驿站的旗标：键留着，值一律 true。
func _sanitise_flags(src: Variant) -> Dictionary:
	var out := {}
	if src is Dictionary:
		for k in src.keys():
			out[str(k)] = true
	return out


func _sanitise_seen(src: Variant) -> Dictionary:
	# stations 是 RoadData 的实例字段而不是静态表，而 RoadData 唯一的
	# 静态副本 FRAGMENT_SLOT_STATION_IDX 只有五座 —— 拿它当上界会把
	# 13 座普通驿站到过的记录全丢掉，顶栏「已过 n 驿」于是永远 ≤5。
	var rd: RefCounted = load("res://scripts/road_data.gd").new()
	var n: int = rd.stations.size()
	var out := {}
	if src is Dictionary:
		for k in src.keys():
			var idx := int(k)
			if idx >= 0 and idx < n:
				out[idx] = true
	return out


func _clear_save() -> void:
	for p in [SAVE_PATH, SAVE_TMP, SAVE_BAK]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## 从标题页进演示模式。一律从 `reset()` 起，所以点了演示之后退出重进，
## 磁盘上也不会留下任何演示痕迹。
func enter_demo() -> void:
	reset()
	demo_mode = true
	# 演示一开始就是"会玩的人"：操作说明和序章都在 World3D 里被 demo_mode 跳过，
	# 这里只需要保证那两个标记是真的，免得它们各自再判一遍。
	onboarding_shown = true
	prologue_done = true


## 把这一趟补齐成**完满**评级：五座碎片驿站各刷满三次、十六驿全路过、
## 珍藏笺 + 四件散件全上身。演示快结束时调一次，好让评审看到的是那张
## 带金印的满配明信片，而不是一张走了两站的中途卡。
##
## 关键：**直接写字段，不走 `check_in()`**。`check_in()` 会把
## `all_fragments_maxed_reached` 那个闩锁翻过来，于是 World3D 的
## `_on_all_maxed()` 当场锁死操纵权、2.5 秒后自己跳去结算页——而那时候
## 演示还在半路。演示要自己掌握什么时候收工，所以这里绕开信号。
func fill_finished_run() -> void:
	var rd: RefCounted = load("res://scripts/road_data.gd").new()
	for i in rd.stations.size():
		seen_stations[i] = true
	for si in rd.FRAGMENT_SLOT_STATION_IDX:
		collected[si] = MAX_VISITS_PER_STATION
	inv["postcard_tier"] = 3
	for id in ["paper", "ink", "seal", "env"]:
		inv[id] = 1
	seen_villain = VILLAIN_SCENE_COUNT
	mood = MOOD_INITIAL


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
