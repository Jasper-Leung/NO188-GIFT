extends SceneTree
## ShopPanel 回归 —— 三铺采购面板的接线与状态机。
##
## 面板是纯 UI + GameManager，不需要 World3D，所以这里直接把脚本挂到 root 上测；
## World3D 那一侧的开店触发由集成回归负责。
##
## 覆盖：
##   1. setup() 按铺子行数展开（驿铺 6 / 灯铺 2 / 茶铺 1），标题与余额对得上
##   2. 素笺 0 旅币 = 「明信片永远拿得到」：没钱也能买
##   3. 旅币不足 / 碎片不足 / 明信片档位互斥 / 数量封顶 —— 四种阻塞原因各走各的文字
##   4. purchased 信号只在该买时发；买失败不发、不改账
##   5. 灯铺未到解锁驿数：整铺禁用并标原因，点按钮也不入账，过够驿数后自动放开
##   6. 「无价」栏渲染出来但一个购买按钮都没有
##   7. 换语言全量重刷（标题 / 行名 / 无价 / 余额）
##   8. 关闭路径：关闭后不可见、重复关闭幂等、点遮罩关闭
##
## 期望值一律走 GameManager / Localization 自己给的数，不硬编码价格与预算。
## 用法： godot --headless --path . --script tools/verify_shop_panel.gd --quit-after 30000
## 注意 --quit-after 单位是帧不是秒（本机 280+FPS，90 帧只有 0.3 秒）。

# 碎片站索引，源自 road_data.gd 的 FRAGMENT_SLOT_STATION_IDX。
# 不在 --script 里引用 RoadData class_name：编译期拉依赖会撞到 autoload 解析陷阱。
const FRAGMENT_STATION_IDX := [4, 7, 10, 13, 14]


var _fails: Array = []
var _oks := 0
var _gm: Node = null
var _loc: Node = null
var _panel = null          # 故意不加类型：自定义脚本走 Variant 取成员最省事
var _sd = null             # shop_data 运行时实例，见 _run() 里的 autoload 陷阱说明

var _purchased: Array = []
var _closed_count := 0


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


func _on_closed() -> void:
	_closed_count += 1


func _row(n: int) -> Array:
	return _panel._rows[n]


func _find(id: String) -> int:
	for i in _panel._rows.size():
		if str(_panel._rows[i][0].get("id", "")) == id:
			return i
	return -1


func _btn(n: int) -> Button:
	return _panel._rows[n][4]


func _state(n: int) -> String:
	return _panel._rows[n][3].text


## 直接写 collected 而不是走 check_in()：后者会连带发旅币、扣心神，
## 把经济账算乱。写完立刻校验计数，索引漂移会让这里当场炸出来。
func _give_fragments(n: int) -> void:
	_gm.collected = _gm._new_collected()
	for i in mini(n, FRAGMENT_STATION_IDX.size()):
		_gm.collected[FRAGMENT_STATION_IDX[i]] = 1
	_eq("碎片计数是 %d" % n, int(_gm.get_collected_count()), n)


func _clear_inv() -> void:
	_gm.inv = {}
	_gm.lvbi = 0
	_gm.spent_km = 0.0
	_gm.earned_tags = {}
	_gm.seen_stations = {}
	_gm.collected = _gm._new_collected()


func _count_buttons(node: Node) -> int:
	var n := 0
	if node is Button:
		n += 1
	for c in node.get_children():
		n += _count_buttons(c)
	return n


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== ShopPanel 回归 ===")

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

	# 固定从中文起步：user://language.cfg 可能残留上一次的偏好，
	# 不重置的话下面的中文期望全是假的（跑一遍英文界面就整体翻车）。
	_loc.set_language("zh")

	# ShopPanel.gd 走运行时 load() 而不写类型注解：--script 模式下 class_name /
	# 类型注解会编译期拉依赖，autoload 引用在那里解析不到，脚本会静默挂死。
	# shop_data.gd 同样有 Localization 引用，所以这里也必须走运行时实例。
	_sd = load("res://scripts/shop_data.gd").new()
	var sp = load("res://scripts/ShopPanel.gd")
	_panel = sp.new()
	_panel.purchased.connect(_on_purchased)
	_panel.closed.connect(_on_closed)
	root.add_child(_panel)
	_ck("初始不可见", not _panel.visible)

	# ---- 1. 三铺行数 + 标题 ----
	for pair in [["驿铺", 6], ["灯铺", 2], ["茶铺", 1]]:
		_panel.setup(str(pair[0]))
		_eq("%s 行数" % pair[0], _panel._rows.size(), int(pair[1]))
		_eq("%s 标题" % pair[0], _panel._title_lbl.text, str(pair[0]))

	_panel.setup("驿铺")
	_ck("setup 后可见", _panel.visible)
	_eq("余额标签跟 GameManager 同步", _panel._balance_lbl.text, _loc.t("shop_balance", [int(_gm.lvbi)]))
	_eq("无价栏 5 件", _panel._nfs_labels.size(), 5)
	# 五件只列名字。「云·无价」那种拼法是把 section 标题重复了五遍：上面已经有
	# 一行"无价"、下面已经有一句"买不到"，第一眼看着像五个看不懂的价格。
	var nfs_plain := true
	for l in _panel._nfs_labels:
		if String(l.text).find("·") >= 0 or String(l.text).strip_edges() == "":
			nfs_plain = false
	_ck("无价条目只写名字、不重复标题", nfs_plain)
	_eq("无价首条就是碎片名", String(_panel._nfs_labels[0].text), "云")
	_ck("无价栏自己说清楚买不到", String(_panel._nfs_hint_lbl.text) != "")

	# ---- 2. 素笺 0 旅币 ----
	var i_plain := _find("kit_plain")
	_eq("素笺价格是 0", int(_panel._rows[i_plain][0].get("price", 0)), 0)
	_ck("没旅币也能买素笺", not _btn(i_plain).disabled)
	_eq("可买时状态栏为空", _state(i_plain), "")
	_btn(i_plain).pressed.emit()
	_eq("purchased 发了一次", _purchased.size(), 1)
	_eq("purchased 载荷是 good id", _purchased[0], "kit_plain")
	_eq("档位写入 inv", int(_gm.get_postcard_tier()), 1)
	_eq("0 元购买不扣账", int(_gm.lvbi), 0)

	# ---- 3a. 买失败 / 旅币不足 ----
	_gm.inv = {}
	var i_fine := _find("kit_fine")
	var before_fail := _purchased.size()
	_btn(i_fine).pressed.emit()      # 0 旅币去买上笺
	_eq("买失败不发 purchased", _purchased.size(), before_fail)
	_eq("买失败档位不变", int(_gm.get_postcard_tier()), 0)
	_gm.earn(50)                     # earn() 顺带走 lvbi_changed → 面板自动刷
	_eq("旅币 50 买不上 180 的上笺", _btn(i_fine).disabled, true)
	_eq("原因文案是旅币不够", _state(i_fine), _loc.t("shop_need_lvbi"))
	_eq("余额跟着 earn 变了", _panel._balance_lbl.text, _loc.t("shop_balance", [50]))

	# ---- 3b. 碎片门槛 ----
	var i_rare := _find("kit_rare")
	_gm.earn(1000)
	_panel._refresh()
	_ck("旅币够也买不了缺碎片的珍藏笺", _btn(i_rare).disabled)
	_eq("原因文案是碎片不够", _state(i_rare), _loc.t("shop_need_frags", [5]))
	_give_fragments(5)
	_panel._refresh()
	_ck("碎片齐了珍藏笺放开", not _btn(i_rare).disabled)
	_btn(i_rare).pressed.emit()
	_eq("珍藏笺是最高档", int(_gm.get_postcard_tier()), 3)

	# ---- 3c. 明信片档位互斥 ----
	_panel._refresh()
	_eq("已有珍藏后上笺提示已有更好的一档", _state(i_fine), _loc.t("shop_lower_tier"))
	_eq("已有珍藏后素笺也提示已有更好的一档", _state(i_plain), _loc.t("shop_lower_tier"))

	# ---- 3d. 数量封顶 ----
	var i_paper := _find("paper")
	_btn(i_paper).pressed.emit()
	_eq("宣纸买到 1", int(_gm.get_item_count("paper")), 1)
	_panel._refresh()
	_ck("宣纸买满后禁用", _btn(i_paper).disabled)
	_eq("原因文案是买满了", _state(i_paper), _loc.t("shop_maxed"))

	# ---- 4. 灯铺：灯笼两件封顶 + 蜡封 ----
	# 这一节要先过掉解锁门（门本身在第 5 节单独测）
	_gm.seen_stations = {0: true, 1: true, 2: true, 3: true, 4: true, 5: true}
	_panel.setup("灯铺")
	_eq("灯铺行数", _panel._rows.size(), 2)
	var i_lamp := _find("lamp")
	_gm.earn(500)
	_panel._refresh()
	_ck("灯笼可买", not _btn(i_lamp).disabled)
	_btn(i_lamp).pressed.emit()
	_btn(i_lamp).pressed.emit()
	_eq("灯笼两件封顶", int(_gm.get_item_count("lamp")), 2)
	_panel._refresh()
	_ck("第三件灯笼买不到", _btn(i_lamp).disabled)
	_eq("灯笼封顶原因文案", _state(i_lamp), _loc.t("shop_maxed"))
	var i_seal := _find("seal")
	_btn(i_seal).pressed.emit()
	_eq("蜡封买到了", int(_gm.get_item_count("seal")), 1)

	# ---- 5. 灯铺未到解锁驿数 ----
	_gm.seen_stations = {}
	_panel.setup("灯铺")
	var gate: int = _sd.shop_unlock_seen("灯铺")
	_eq("未到驿数的锁定文案", _panel._locked_msg, _loc.t("shop_locked", [gate]))
	for i in _panel._rows.size():
		var b: Button = _btn(i)
		_ck("锁定第 %d 行禁用" % (i + 1), b.disabled,
			"disabled=%s" % str(b.disabled))
		_eq("锁定第 %d 行原因" % (i + 1), _state(i), _panel._locked_msg)
	var before_lock := _purchased.size()
	var inv_before_lock: Dictionary = _gm.inv.duplicate(true)
	_btn(0).pressed.emit()          # 直接 emit，绕过 disabled 检查
	_eq("锁定时点了也不入账", _purchased.size(), before_lock)
	_eq("锁定时点了也不改背包", _gm.inv, inv_before_lock)
	# 差一驿时仍然锁着。
	for i in range(gate - 1):
		_gm.seen_stations[i] = true
	_panel.setup("灯铺")
	_eq("差一驿仍然锁着", _panel._locked_msg, _loc.t("shop_locked", [gate]))
	# 过够驿数后放开：清掉之前买过的灯笼，否则「买不上」是撞 max_own 而不是解锁门，
	# 测不出「解锁」这件事本身。驿数必须放在 _clear_inv() 之后重设 ——
	# 它顺手把 seen_stations 也清了。
	_clear_inv()
	_gm.earn(500)
	for i in range(gate):
		_gm.seen_stations[i] = true
	_eq("过够驿数后 seen 计数 = 门槛", _gm.get_seen_station_count(), gate)
	_panel.setup("灯铺")
	_eq("过够驿数后锁定文案清空", _panel._locked_msg, "")
	_panel._refresh()
	_ck("解锁后灯笼恢复可买", not _btn(_find("lamp")).disabled)
	_eq("解锁后状态栏清空", _state(_find("lamp")), "")
	_gm.seen_stations = {}

	# ---- 6. 无价栏没有按钮 ----
	_panel.setup("茶铺")
	_eq("全树按钮数 = 商品行数 + 1 个关闭按钮", _count_buttons(_panel), _panel._rows.size() + 1)
	var i_sachet := _find("sachet")
	_btn(i_sachet).pressed.emit()
	_eq("香囊买到了", int(_gm.get_item_count("sachet")), 1)
	_panel._refresh()
	_eq("香囊买满后提示买满了", _state(i_sachet), _loc.t("shop_maxed"))

	# ---- 7. 换语言全量重刷 ----
	_clear_inv()
	_gm.progress_km = 0.0
	_panel.setup("驿铺")
	_loc.set_language("en")
	_eq("英文标题", _panel._title_lbl.text, "Station Shop")
	_eq("英文无价标题", _panel._nfs_title_lbl.text, "Priceless")
	_eq("英文无价首条", String(_panel._nfs_labels[0].text), "Cloud")
	_eq("英文余额", _panel._balance_lbl.text, "Lvbi 0")
	var en_names := ""
	var all_renamed := true
	for r in _panel._rows:
		en_names += String(r[1].text) + "|"
		if String(r[1].text) == str(r[0].get("name", "")):
			all_renamed = false
	_ck("英文行名都换过了", all_renamed)
	_eq("英文行名表", en_names, "Plain Sheet|Fine Sheet|Rare Sheet|Rice Paper|Pine Ink|Envelope|")
	_loc.set_language("zh")
	_eq("切回中文标题", _panel._title_lbl.text, "驿铺")
	_eq("切回中文首行名", String(_panel._rows[0][1].text), "素笺")
	_eq("切回中文无价首条", String(_panel._nfs_labels[0].text), "云")

	# ---- 8. 关闭 ----
	_panel._close()
	_eq("关闭后不可见", _panel.visible, false)
	_eq("closed 发了一次", _closed_count, 1)
	_panel._close()
	_eq("重复关闭不重复发", _closed_count, 1)
	_panel.setup("驿铺")
	_panel.visible = false
	_panel._close()
	_eq("不可见时关闭是空操作", _closed_count, 1)
	_panel.setup("驿铺")
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	_panel._on_dim_input(ev)
	_eq("点遮罩关闭面板", _panel.visible, false)
	_eq("点遮罩发 closed", _closed_count, 2)

	_panel.queue_free()
	await process_frame    # 让 queue_free 真正释放，否则 exit 时报 RID 泄漏
	_finish(backup, lang_before)


func _finish(backup: String, lang_before: String) -> void:
	_loc.set_language(lang_before)
	if backup != "":
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
