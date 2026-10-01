extends Control
## ShopPanel — 三铺（驿铺 / 茶铺 / 灯铺）采购面板
##
## 骑到铺子驿站按空格打开。价格、解锁里程、明信片档位互斥全在 shop_data.gd，
## 本文件零硬编码价格与名字；换语言走 Localization.language_changed。
## 「无价」栏把云茶琴竹禽渲染出来但不可点击 —— 买得到纸，买不到云。
##
## 层级：World3D 直接子节点（不塞进 HUD3D，避免压到 MoodMask 的层级约定），
## 全屏锚点 + mouse_filter = PASS；dim 遮罩在最下、CenterContainer 压在上面。
## 点遮罩或按 ESC / 点「离开小铺」关闭。
##
## 铺子未到解锁驿数时（灯铺 seen_unlock = 6）面板照开，但所有行禁用并标原因 ——
## 判断收在本文件里，World3D 只管「近不近」，不用知道锁不锁。

signal purchased(item_id: String)
signal closed

const PANEL_W := 960.0
const PANEL_H := 720.0
const PANEL_MARGIN := 44.0
const ROW_MIN_H := 58.0

const COL_DIM := Color(0.02, 0.02, 0.03, 0.72)
const COL_BG := Color(0.09, 0.075, 0.065)
const COL_TEXT := Color(0.92, 0.9, 0.86)
const COL_MUTED := Color(0.62, 0.59, 0.55)
const COL_GOLD := Color(0.961, 0.784, 0.494)
const COL_LINE := Color(0.961, 0.784, 0.494, 0.28)
const COL_BTN_BG := Color(0.17, 0.135, 0.11)
const COL_BTN_HOVER := Color(0.25, 0.195, 0.145)
const COL_BTN_PRESSED := Color(0.32, 0.25, 0.18)
const COL_BTN_DISABLED := Color(0.115, 0.1, 0.095)


var _shop_name := ""
var _locked_msg := ""

var _panel: PanelContainer = null
var _body: VBoxContainer = null
var _title_lbl: Label = null
var _balance_lbl: Label = null
var _nfs_title_lbl: Label = null
var _nfs_hint_lbl: Label = null
# [good, name_lbl, desc_lbl, state_lbl, buy_btn]
var _rows: Array = []
var _nfs_labels: Array = []


func _ready() -> void:
	# World3D 用 add_child() 直接挂上来，没有场景树里的锚点预设 —— 不自己铺满的话，
	# 子节点那两把 PRESET_FULL_RECT 会锚到一个 0×0 的父矩形，整个面板塌成一点。
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	var dim := ColorRect.new()
	dim.color = COL_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "ShopPanel"   # .new() 默认命名 @Panel@n，显式命名才好定位
	_panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	_panel.add_theme_stylebox_override("panel", _style(COL_BG, 2.0, Vector2(PANEL_MARGIN, PANEL_MARGIN)))
	center.add_child(_panel)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_panel.add_child(_body)

	visible = false
	Localization.language_changed.connect(_on_language_changed)
	GameManager.lvbi_changed.connect(_on_lvbi_changed)


func setup(shop_name: String) -> void:
	_shop_name = shop_name
	_refresh_lock()
	_rebuild_body()
	visible = true
	_grab_first_focus()


## 铺子一开就得有一件东西拿着焦点，否则 ui_up / ui_down / 回车全都没有起点
## （`Viewport` 只把按键投给 key focus 的控件，视口里一个焦点都没有时它们
## 谁也到不了——新手引导那一屏原来就是这么把键盘玩家卡在第一屏的）。
## 停在第一件买得起的而不是关闭按钮：玩家推完序章进来，多半是来看能买什么；
## 一件都买不起时自然落到关闭按钮上，键盘玩家至少有出路。
func _grab_first_focus() -> void:
	for c in _body.get_children():
		var b := _focusable_in(c)
		if b != null:
			b.grab_focus()
			return


func _focusable_in(n: Node) -> Button:
	if n is Button:
		var btn := n as Button
		# 买不了的不给焦点：对 disabled 控件 grab_focus() 是空操作，
		# 停在这里等于又变成"视口里一个焦点都没有"
		return null if btn.disabled else btn
	for c in n.get_children():
		var b := _focusable_in(c)
		if b != null:
			return b
	return null


## 解锁门只看"路过多少座驿"，不再看里程。_km 只留在内部作旅币经济口径。
func _refresh_lock() -> void:
	_locked_msg = ""
	var need := ShopData.shop_unlock_seen(_shop_name)
	if need > 0 and GameManager.get_seen_station_count() < need:
		_locked_msg = Localization.t("shop_locked", [need])


func _rebuild_body() -> void:
	# 立即 free 而不是 queue_free：setup() 之后同一帧就 _refresh()，
	# 延迟释放会让旧行和新行在同一帧同时占位、面板闪一下。
	for c in _body.get_children():
		_body.remove_child(c)
		c.free()
	_rows.clear()
	_nfs_labels.clear()

	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(0, 50)
	_title_lbl = _label(COL_TEXT, 25)
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_balance_lbl = _label(COL_GOLD, 20)
	_balance_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_balance_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_balance_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_title_lbl)
	head.add_child(_balance_lbl)
	_body.add_child(head)
	_body.add_child(_make_sep())

	for g in ShopData.goods_for_shop(_shop_name):
		_body.add_child(_make_row(g))

	_body.add_child(_make_sep())

	_nfs_title_lbl = _label(COL_GOLD, 17)
	_nfs_title_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_nfs_title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_nfs_hint_lbl = _label(COL_MUTED, 14)
	_nfs_hint_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_nfs_hint_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var nfs := VBoxContainer.new()
	nfs.add_theme_constant_override("separation", 6)
	nfs.add_child(_nfs_title_lbl)
	nfs.add_child(_nfs_hint_lbl)
	var nfs_row := HBoxContainer.new()
	nfs_row.add_theme_constant_override("separation", 18)
	nfs_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for f in ShopData.not_for_sale_display():
		var lbl := _label(COL_MUTED, 15)
		lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_nfs_labels.append(lbl)
		nfs_row.add_child(lbl)
	nfs.add_child(nfs_row)
	_body.add_child(nfs)

	var close_btn := _button()
	close_btn.custom_minimum_size = Vector2(0, 44)
	close_btn.pressed.connect(_close)
	_body.add_child(close_btn)

	_apply_text()


## 每行：名称 + 描述（可撑开）| 状态说明 | 购买按钮
func _make_row(g: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(0, ROW_MIN_H)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var name_lbl := _label(COL_TEXT, 18)
	var desc_lbl := _label(COL_MUTED, 13)
	info.add_child(name_lbl)
	info.add_child(desc_lbl)

	var state_lbl := _label(COL_MUTED, 14)
	state_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	state_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var btn := _button()
	btn.custom_minimum_size = Vector2(152, 42)
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_buy_pressed.bind(g))

	box.add_child(info)
	box.add_child(state_lbl)
	box.add_child(btn)
	_rows.append([g, name_lbl, desc_lbl, state_lbl, btn])
	return box


func _make_sep() -> Control:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_LINE
	sb.content_margin_top = 1.0
	sb.content_margin_bottom = 1.0
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", sb)
	sep.custom_minimum_size = Vector2(0, 1)
	return sep


func _label(color: Color, size: int) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _button() -> Button:
	var btn := Button.new()
	# 原来这里是 FOCUS_NONE，于是**全铺没有一个控件能被键盘选中**：键盘玩家
	# 能用 ESC 关掉铺子，却一件也买不了，而面板上每一行都写着价钱和"买"——
	# 一块看得见摸不着（键盘）的经济系统。整个核心循环对键盘玩家是断的，
	# 而界面上没有任何一处提示这一点。
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", COL_GOLD)
	btn.add_theme_color_override("font_hover_color", COL_TEXT)
	btn.add_theme_color_override("font_pressed_color", COL_TEXT)
	btn.add_theme_color_override("font_disabled_color", COL_MUTED)
	var m := Vector2(18.0, 10.0)
	btn.add_theme_stylebox_override("normal", _style(COL_BTN_BG, 4.0, m))
	btn.add_theme_stylebox_override("hover", _style(COL_BTN_HOVER, 4.0, m))
	btn.add_theme_stylebox_override("pressed", _style(COL_BTN_PRESSED, 4.0, m))
	btn.add_theme_stylebox_override("disabled", _style(COL_BTN_DISABLED, 4.0, m))
	# 焦点框要看得见——引擎默认那圈描边在深色铺子里几乎看不见，
	# 于是即使能选中，玩家也不知道自己现在停在第几件上
	btn.add_theme_stylebox_override("focus", _style(COL_BTN_HOVER, 4.0, m))
	return btn


func _style(bg: Color, corner: float, m: Vector2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(corner))
	sb.content_margin_left = m.x
	sb.content_margin_top = m.y
	sb.content_margin_right = m.x
	sb.content_margin_bottom = m.y
	return sb


func _apply_text() -> void:
	_title_lbl.text = ShopData.shop_display_name(_shop_name)
	_nfs_title_lbl.text = Localization.t("shop_nfs_title")
	_nfs_hint_lbl.text = Localization.t("shop_nfs_hint")
	var frags: Array = ShopData.not_for_sale_display()
	# 只写名字。原来这里拼的是 section 的标题，于是渲染成
	# 「云·无价 茶·无价 琴·无价 竹·无价 禽·无价」——上面已经有一行"无价"、
	# 下面已经有一句"买不到"，再重复五遍就成了五个看不懂的价格，
	# 第一眼看着像面板坏了。名字单独列出来反而更像"这五件是去找的"。
	for i in _nfs_labels.size():
		_nfs_labels[i].text = str(frags[i])
	for row in _rows:
		var g: Dictionary = row[0]
		row[1].text = ShopData.good_display_name(g)
		row[2].text = ShopData.good_display_desc(g)
		_refresh_btn_text(row)
	# 必须在这里定按钮状态：_rebuild_body() 建出来的按钮默认是 enabled、状态栏空着，
	# 不等 lvbi_changed / item_purchased 信号就不会刷新 —— 0 旅币时整铺会看着都能买。
	_refresh()


## 按钮上的文字。买满/已买/买不好时照样显示价格 —— 状态说明另走 state_lbl，
## 别让 disabled_text 把价格盖掉。
func _refresh_btn_text(row: Array) -> void:
	var g: Dictionary = row[0]
	row[4].text = Localization.t("shop_buy", [int(g.get("price", 0))])


func _refresh_balance() -> void:
	_balance_lbl.text = Localization.t("shop_balance", [int(GameManager.lvbi)])


## 逐行判定并落状态。reason 的优先级：碎片门槛 > 旅币 > 明信片档位 > 数量上限。
func _refresh() -> void:
	_refresh_balance()
	for row in _rows:
		var g: Dictionary = row[0]
		var btn: Button = row[4]
		var state_lbl: Label = row[3]
		if _locked_msg != "":
			btn.disabled = true
			state_lbl.text = _locked_msg
			continue
		if GameManager.can_buy(g):
			btn.disabled = false
			state_lbl.text = ""
			continue
		btn.disabled = true
		state_lbl.text = _buy_block_reason(g)
	# 买完之后焦点还留在**刚刚买下的那件**上，而它已经 disabled 了：引擎不会
	# 因为 disabled 就把焦点踢走，于是玩家按第二下空格什么都不会发生，
	# 界面上也看不出区别（那件只是变灰了，而变灰正是"买到了"该有的反馈）。
	# 所以焦点落在 <null> 或一个已经买不了的按钮上时都要挪走。只在这两种情况下
	# 动：鼠标玩家点了哪儿都不该被拽。
	if visible:
		var fo: Control = get_viewport().gui_get_focus_owner()
		if fo == null or (fo is Button and (fo as Button).disabled):
			_grab_first_focus()


## 为什么买不了。不直接翻译 can_buy() 的布尔值，玩家得知道缺什么。
func _buy_block_reason(g: Dictionary) -> String:
	var g_fragments := int(g.get("requires_fragments", 0))
	if g_fragments > int(GameManager.get_collected_count()):
		return Localization.t("shop_need_frags", [g_fragments])
	if int(g.get("price", 0)) > int(GameManager.lvbi):
		return Localization.t("shop_need_lvbi")
	if str(g.get("grant", "")) == "postcard_tier":
		var rank := int(g.get("tier_rank", 1))
		var tier := int(GameManager.get_postcard_tier())
		if tier > rank:
			return Localization.t("shop_lower_tier")
		return Localization.t("shop_bought")
	if int(GameManager.get_item_count(str(g["id"]))) >= int(g.get("max_own", 1)):
		return Localization.t("shop_maxed")
	return ""


func _on_buy_pressed(g: Dictionary) -> void:
	# 锁定是铺子级的门，can_buy() 不知道 —— 这里必须先挡，否则绕过 disabled 的
	# 程序化触发（pressed.emit()）照样能把钱花掉。
	if _locked_msg != "":
		return
	if not GameManager.buy(g):
		_refresh()
		return
	AudioManager.play_sfx("collect")
	purchased.emit(str(g["id"]))
	_refresh()


func _on_lvbi_changed(_amount: int, _total: int) -> void:
	if _balance_lbl == null:
		return
	_refresh_balance()
	_refresh()


func _on_language_changed() -> void:
	if _shop_name == "":
		return
	_refresh_lock()
	_apply_text()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_close()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_close()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()
