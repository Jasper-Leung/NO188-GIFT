extends Control
## HUD3D — 3D 场景顶部栏 + 右上角多按钮 + 帮助面板 (PRD F-29/F-31/F-32)
## 显示：碎片 n/5、已过 n/16 驿、旅币、心神
## 按钮：暂停 / 全局静音 / BGM 静音 / SFX 静音 / 帮助
## 挂载：World3D/HUD3D，全屏锚点
##
## 顶栏**不挂里程**。世界只有 1228.8m 的一圈，而进度条写的是「已行 km / 188km」，
## 换算下来 2km/s：玩家骑三十秒就能心算出 7200km/h，然后「188」这个题眼连同
## 它承载的解锁门一起变成噪音。碎片是通关条件、驿是可数的真实进度，两个都摆在
## 明面上。里程仍然在内部记（GameManager.progress_km），只作旅币经济口径。
##
## 心神遮罩：全屏雾，alpha = GameManager.get_mood_mask_alpha() —— 心神越差越浓，
## 买灯笼/香囊把它淡回去。插在 HUD3D 子节点 index 0（最底层），TopBar / 按钮 /
## 帮助面板压在它上面；mouse_filter = IGNORE，永不拦输入、永不构成失败态。
##
## 但"浓"只该发生在叙事时刻，不该是玩家整个后半程的背景色。原来的做法是常驻：
## 心神初始 4、每收一块碎片 −1，于是从第 3 块碎片起（也就是 5 块里最长的
## 一半流程）屏幕永久挂着 0.52 的雾、视野砍到 0.65 —— 玩家在最需要看清路去找
## 剩下几块碎片的时候看得最差。奖励变成了惩罚。
## 现在拆成两档：骑行时压到 MOOD_REST_SCALE，只有对白/结果面板亮着的时候
## 才冲上 GameManager 那一档。雾负责讲故事，不负责挡路。

@onready var _progress_label: Label = $TopBar/HBox/ProgressLabel
@onready var _station_label: Label = $TopBar/HBox/StationLabel
@onready var _mute_btn: Button = $TopRightHBox/MuteBtn
@onready var _bgm_btn: Button = $TopRightHBox/BgmBtn
@onready var _sfx_btn: Button = $TopRightHBox/SfxBtn
@onready var _help_panel: Control = $HelpOverlay
@onready var _help_title: Label = $HelpOverlay/Panel/VBox/HelpTitle
@onready var _desktop_header: Label = $HelpOverlay/Panel/VBox/DesktopSection/DesktopHeader
@onready var _key_w: Label = $HelpOverlay/Panel/VBox/DesktopSection/KeyW
@onready var _key_s: Label = $HelpOverlay/Panel/VBox/DesktopSection/KeyS
@onready var _key_a: Label = $HelpOverlay/Panel/VBox/DesktopSection/KeyA
@onready var _key_d: Label = $HelpOverlay/Panel/VBox/DesktopSection/KeyD
@onready var _key_space: Label = $HelpOverlay/Panel/VBox/DesktopSection/KeySpace
@onready var _key_esc: Label = $HelpOverlay/Panel/VBox/DesktopSection/KeyEsc
@onready var _key_m: Label = $HelpOverlay/Panel/VBox/DesktopSection/KeyM
@onready var _mobile_header: Label = $HelpOverlay/Panel/VBox/MobileSection/MobileHeader
@onready var _touch_joy: Label = $HelpOverlay/Panel/VBox/MobileSection/TouchJoy
@onready var _touch_checkin: Label = $HelpOverlay/Panel/VBox/MobileSection/TouchCheckin
@onready var _touch_buttons: Label = $HelpOverlay/Panel/VBox/MobileSection/TouchBtns
@onready var _help_mute_hint: Label = $HelpOverlay/Panel/VBox/HelpMuteHint

const MASK_TINT := Color(0.11, 0.14, 0.19)   # 冷灰蓝，读作「雾」；浓淡全靠 alpha
const MASK_TEX_SIZE := 128
const MASK_FADE_SPEED := 3.0                 # 每帧逼近系数，约 1 秒到位
## 骑行时的雾相对叙事档的折扣。0.30 × 0.52 ≈ 0.16 —— 足够读出"眼前起了雾"，
## 又不至于挡住路。买灯笼/香囊依然只影响 get_visibility_factor()（视野半径），
## 这一点不变：雾是叙事，视野才是可以花钱解的。
const MOOD_REST_SCALE := 0.30

## 每座碎片驿站最多打卡几次 —— 满格是明信片的完满评级。
## 从 GameManager 抄一份常量不如直接问它，静态 const 也拿不到 autoload，
## 所以这里显式对齐：verify_minimap.gd 会断言这两个数一致。
const MAX_VISITS_PER_STATION := 3
## 进场比退场快：叙事档冲上去要跟手（对白一开就该浓），退场要慢（人物情绪
## 慢慢散开），一快一慢用同一个系数做的话两头都不对。
const MASK_PULSE_IN := 6.0
const MASK_PULSE_OUT := 2.0
const LVBI_GAIN_SHOW_SEC := 1.4              # 「+N 旅币」提示停留时间
## 8 向箭头，索引 0 = 正前方，顺时针递增。字体 LXGW 覆盖这几个码位。
const ARROWS := ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]

var _boundary_warning: Control = null
var _boundary_rects: Array = []
var _mood_mask: TextureRect = null
var _mood_alpha: float = 0.0
var _mood_pulse: bool = false
var _lvbi_label: Label = null
var _lvbi_toast: Label = null
var _mood_label: Label = null
var _lvbi_gain_text := ""       # 入账提示，非空时压过余额显示
var _lvbi_gain_left := 0.0
var _next_label: Label = null
var _next_gap: Control = null   # 顶栏左半（状态）右半（导航）之间那个撑开的弹簧
var _hint_label: Label = null   # 「为什么按了没反应」那行
var _hint_left := 0.0
var _pass_label: Label = null   # 路过非碎片驿时那一句风景话
var _pass_holder: Control = null
var _pass_left := 0.0
var _cue_label: Label = null
var _cue_name_label: Label = null
var _cue_holder: Control = null
var _cue_left := 0.0
var _road_data: RoadData = null
var _player: CharacterBody3D = null

## 顶栏衬底的高度与不透明度。
##
## 顶栏的字是米金 (0.96, 0.78, 0.49)，而它经常压在浅蓝天空上——实测对比度约
## 1.6:1，远低于正文可读线，逆光方向更糟。衬底不是"好看"，是这条信息在
## 天空那一档背景上根本读不出来。加一层往下淡出的暗条即可，不必做整块面板。
const SCRIM_H := 62.0

## 顶栏实底段的不透明度，和它往下淡出之前的实底宽度比例。
##
## 这两个数不是调出来的，是算出来的。18px 正文要过 AA 的 4.5:1，而**顶栏背后最亮的
## 背景是正午的天**（实测 `12b_day_正午.png` 衬底外的天空 ≈ sRGB(198,210,237)，
## 相对亮度 0.642）——比顶栏那行金字（≈(245,200,126)，0.621）还亮。
## 也就是说单靠调暗衬底色没用（衬底本来就接近黑），只有 alpha 能救：
## 合成亮度 = a·0.0069 + (1-a)·0.642 ≤ 0.099 才够 4.5:1，解出来 **a ≥ 0.855**。
## 0.46 那版实测只有 1.36:1（`04_ride` 1.22:1），字在天上等于没写。
##
## 宽度必须够盖住**整条文字行盒**，不只是字形：18px 的字在 `SCRIM_H`(62px)
## 里占到 t≈0.23~0.61（行盒比字形高，下面那一截是降部留白）。纯 pow 渐变在
## 那一段只剩 0.16~0.31 的 alpha，挡不住任何东西——所以是"先实底一段，
## 再往下淡出"，不是一路渐变。留到 0.68 是给字号和 TopBar 内边距留余量：
## `verify_mood_mask.gd` 第 9 节直接拿真实 Label 的 rect 来卡这条线。
const SCRIM_TOP_ALPHA := 0.90
const SCRIM_SOLID_FRAC := 0.68

## 顶栏右半那排按钮占掉的宽度，以及状态栏和它之间要留的缝。
##
## `TopBar/HBox` 在 .tscn 里写死 `offset_right = 480`，也就是它**声称**自己只有
## 468px 宽，而它五个标签的最小宽度加起来约 663px——于是最后那 195px 是**溢出**
## 出去的，容器自己的 rect 一直是个谎。溢出本身不报错（`clip_contents` 默认关），
## 真正的后果是排版权交给了"字有多长"：顶栏右端那 345px 的空档不是设计，
## 是"没排满的余量"，而整条衬底一直铺到 1280，于是空档读成一条什么都没有的
## 黑带——`z13_top.png` 里那块约 600px 的死区（那一帧"下一处"恰好是空的，
## 于是空档整整翻倍）。
##
## 修法是让容器**真的**占满「左边缘 → 按钮排左边」这一段，中间塞一个撑开的
## 弹簧，于是顶栏读成「状态（左）… 导航（右）… 按钮（最右）」三段，
## 剩下的空档落在该落的地方，而不是全堆在导航后面。
const TOP_RIGHT_W := 260.0     # 与 .tscn 里 TopRightHBox 的 offset_left 同一个数
const TOP_RIGHT_GAP := 16.0


## 下一处目标提示。8 字环两个方向都能到全部 5 座碎片驿站，路又是自闭合的，
## 顶栏原来只有「已行 Nkm」和「碎片 n/5」——新玩家上路后第一件事就是想
## 「往哪骑」，而这件事在界面上没有任何答案。挂进 _process 跟着每帧刷，
## 不另开信号：驿站收没收到看的是 GameManager.is_collected()。
func setup(rd: RoadData, p: CharacterBody3D) -> void:
	_road_data = rd
	_player = p


func _next_fragment_target() -> Dictionary:
	## 最近的、还欠一次到访的碎片驿站。返回 {} 表示五座都刷满了。
	## 判据在 GameManager.fragment_station_needs_visit()，和小地图、脚下提示圈共用
	## 同一个函数 —— 第一次拿到碎片之后这一站还剩两次，所以"已收"不等于"不用再去"。
	if _road_data == null or _player == null:
		return {}
	var best := {}
	var best_d := INF
	for i in range(_road_data.stations.size()):
		if not GameManager.fragment_station_needs_visit(i):
			continue
		var d: float = _player.global_position.distance_to(
				_road_data.get_station_world_pos(i))
		if d < best_d:
			best_d = d
			best = {"idx": i, "dist": d}
	return best


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_mute_btn.pressed.connect(_on_mute_btn_pressed)
	_bgm_btn.pressed.connect(_on_bgm_btn_pressed)
	_sfx_btn.pressed.connect(_on_sfx_btn_pressed)
	AudioManager.mute_changed.connect(_update_buttons)
	Localization.language_changed.connect(_apply_language)
	_update_buttons()
	_apply_language()
	_setup_help_sections()
	_setup_economy_labels()
	_setup_scrim()
	_setup_blocked_hint()
	_setup_pass_line()
	_setup_cue_line()
	_setup_mood_mask()
	_boundary_warning = _create_boundary_warning()
	add_child(_boundary_warning)
	_boundary_warning.visible = false


func _setup_help_sections() -> void:
	var desktop = $HelpOverlay/Panel/VBox/DesktopSection
	var mobile = $HelpOverlay/Panel/VBox/MobileSection
	var is_touch = DisplayServer.is_touchscreen_available()
	desktop.visible = not is_touch
	mobile.visible = is_touch
	_help_panel.gui_input.connect(_on_help_overlay_input)


func _on_help_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var panel = $HelpOverlay/Panel
			if not panel.get_global_rect().has_point(mb.position):
				close_help()
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		if event.pressed:
			var panel = $HelpOverlay/Panel
			if not panel.get_global_rect().has_point(event.position):
				close_help()
				get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# 驿数要跟着 seen_stations 走，而它只在 on_station_pass() 里变动（没有信号），
	# 所以只能每帧重算。16 站的字典 size() 是常数级，开销可以忽略。
	if _road_data != null:
		_progress_label.text = Localization.t("stations_seen",
				[GameManager.get_seen_station_count(), _road_data.stations.size()])
	_station_label.text = Localization.t("fragments", [GameManager.get_collected_count()])
	# 余额只显示余额，永不被入账提示顶掉。提示走独立的一条 toast（见 _setup_lvbi_toast），
	# 因为把「旅币 120」换成「+20 旅币」会让这个 Label 的宽度一变，顶栏 HBox 里
	# 后面的心神、"下一处"整排横向跳一下——玩家正在读距离的时候被推走，很难受。
	_lvbi_label.text = Localization.t("lvbi_label", [GameManager.lvbi])
	if _lvbi_gain_left > 0.0:
		_lvbi_gain_left -= delta
		if _lvbi_toast != null:
			# 留最后 0.4s 淡出
			_lvbi_toast.modulate.a = clampf(_lvbi_gain_left / 0.4, 0.0, 1.0)
		if _lvbi_gain_left <= 0.0:
			_lvbi_gain_text = ""
			if _lvbi_toast != null:
				_lvbi_toast.text = ""
	_mood_label.text = Localization.t("mood_label", [GameManager.mood])
	if _hint_left > 0.0:
		_hint_left -= delta
		# 留最后 0.35s 淡出，不要"啪"地一下消失
		if _hint_left < 0.35 and _hint_label != null:
			_hint_label.modulate.a = maxf(_hint_left / 0.35, 0.0)
		if _hint_left <= 0.0:
			_hint_label.text = ""
	if _pass_left > 0.0:
		_pass_left -= delta
		if _pass_left < 0.5 and _pass_holder != null:
			_pass_holder.modulate.a = maxf(_pass_left / 0.5, 0.0)
		if _pass_left <= 0.0 and _pass_label != null:
			_pass_label.text = ""
	if _cue_left > 0.0:
		_cue_left -= delta
		if _cue_left < 0.5 and _cue_holder != null:
			_cue_holder.modulate.a = maxf(_cue_left / 0.5, 0.0)
		if _cue_left <= 0.0 and _cue_label != null:
			_cue_label.text = ""
	_update_next_label()
	_update_mood_mask(delta)


## 叙事脉冲的开关。由 World3D 每帧按对白弹窗的真实可见性推过来，
## 不在这里自己去找那个弹窗：HUD3D 和 DialoguePopup 分属不同 CanvasLayer，
## 跨层查询既脆又没好处。单一来源是"弹窗此刻可见不可见"，不会有计数泄漏。
func set_mood_pulse(on: bool) -> void:
	_mood_pulse = on


func _update_mood_mask(delta: float) -> void:
	var target: float = GameManager.get_mood_mask_alpha()
	if not _mood_pulse:
		target *= MOOD_REST_SCALE
	if absf(_mood_alpha - target) < 0.002:
		_mood_alpha = target
	else:
		var speed: float = MASK_PULSE_IN if _mood_pulse else MASK_PULSE_OUT
		_mood_alpha = lerpf(_mood_alpha, target, clampf(delta * speed, 0.0, 1.0))
	_mood_mask.modulate.a = _mood_alpha


func _update_next_label() -> void:
	if _next_label == null:
		return
	var t := _next_fragment_target()
	if t.is_empty():
		# 五座都刷满了，这一趟没有"下一处"可指。**这里原来写的是空串**，
		# 于是顶栏右端那条标签整条消失，只剩衬底——而这正是玩家最该看着
		# 那一栏的两秒：`_on_all_maxed()` 刚把「五座驿站都走满了」放到屏幕中央，
		# 2.5 秒后就要跳去结算页。信息量最大的一刻，导航栏先哑了。
		_next_label.text = Localization.t("hud_all_done")
		return
	var idx: int = t["idx"]
	# 站名走 road_data.station_display_name()，和 World3D._station_name() 同一套口径
	var arrow := _arrow_glyph(_player.global_position, _player_forward(),
			_road_data.get_station_world_pos(idx))
	# 五件都收齐之后，"下一处"指的是回访而不是新碎片，文案必须跟着换 ——
	# 还写"下一处 · 站名 · 距离"的话，玩家会以为这一站里还压着一块没捡的碎片。
	if GameManager.is_collected(idx):
		_next_label.text = Localization.t("hud_revisit_target",
				[_road_data.station_display_name(idx), arrow,
				Localization.t("visits_left_n", [
					MAX_VISITS_PER_STATION - GameManager.get_station_count(idx)])])
	else:
		_next_label.text = Localization.t("hud_next_target",
				[_road_data.station_display_name(idx), arrow, int(t["dist"])])


## 车身朝向。Godot 里 -Z 是正前方。
func _player_forward() -> Vector3:
	return -_player.global_transform.basis.z


## 从 from 出发、面朝 fwd 时，target 落在哪个方向 —— 给 8 向箭头。
##
## 只有距离没有方向是这一行最大的坑：8 字环自闭合，骑反了"下一处 · 84m"会一直是
## 84m，玩家在交叉点上完全看不出自己骑反了。8 字也意味着两个方向都能到，所以
## 箭头必须是相对**车头**而不是罗盘北。
static func _arrow_glyph(from: Vector3, fwd: Vector3, target: Vector3) -> String:
	var d := target - from
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return ARROWS[0]
	var f := fwd
	f.y = 0.0
	if f.length_squared() < 0.0001:
		return ARROWS[0]
	# 约定一个 2D 方位角：a(v) = atan2(x, -z)，于是正前方（-Z）是 0、
	# 正右方（+X）是 +π/2。相减取负向即"目标相对车头偏了几度"，向右为正。
	var rel := wrapf(atan2(d.x, -d.z) - atan2(f.x, -f.z), -PI, PI)
	var i := posmod(int(round(rel / (PI / 4.0))), ARROWS.size())
	return ARROWS[i]


func _on_mute_btn_pressed() -> void:
	AudioManager.toggle_mute()
	_update_buttons()


func _on_bgm_btn_pressed() -> void:
	AudioManager.toggle_bgm_mute()
	_update_buttons()


func _on_sfx_btn_pressed() -> void:
	AudioManager.toggle_sfx_mute()
	_update_buttons()


## 三个音频开关的按钮文案。
##
## 这一族**不用符号来区分**，用的是字（`bgm_short` / `sfx_short`）。原来的
## 版本给 BGM 和音效分了两个音乐符号（♫ / ♪）——它们在字体里是真的不一样
## （单独放大渲染过，U+266B 那个横杠画得出来，`Font.has_char` 也报 true），
## 而在顶栏那个字号上**那根横杠是亚像素的**：两个按钮读起来就是同一个东西。
## 放大 5 倍的定妆照 `04_ride` 右上角能量出那一两根像素的差别，
## 而玩家不会放大 5 倍去看一个 18px 的按钮。
##
## 教训可推广：**「两个字符在字体里长得不一样」不等于「玩家分得出来」**。
## 靠字符长相传达区别时，判据是**在实际字号上**还剩多少差别，而那只有图能量；
## 顺带一条同族的：`Font.has_char()` 只查 cmap，缺字形会静默回退，
## 所以它绿着也不代表屏幕上画的是那个字——但**这一族连回退都没有**，
## 两个码位都画得出来，差的只是那一笔。凡是拿细笔画当区分度的 UI，
## 直接换成词。tooltip 那一条留着：「点开之前」玩家得先看得懂那是什么。
const GLYPH_MUTE_ALL_ON := "🔊"
const GLYPH_MUTE_ALL_OFF := "🔇"


func _update_buttons() -> void:
	var on = Localization.t("on")
	var off = Localization.t("off")
	var bgm_off := AudioManager.is_bgm_muted()
	var sfx_off := AudioManager.is_sfx_muted()
	_mute_btn.text = GLYPH_MUTE_ALL_OFF if AudioManager.is_muted() else GLYPH_MUTE_ALL_ON
	_mute_btn.tooltip_text = Localization.t("mute")
	_bgm_btn.text = "%s %s" % [Localization.t("bgm_short"), off if bgm_off else on]
	_bgm_btn.tooltip_text = Localization.t("bgm_mute")
	_sfx_btn.text = "%s %s" % [Localization.t("sfx_short"), off if sfx_off else on]
	_sfx_btn.tooltip_text = Localization.t("sfx_mute")


func _apply_language() -> void:
	_help_title.text = Localization.t("controls_title")
	_help_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_title.add_theme_font_size_override("font_size", 22 if Localization.is_english() else 24)
	_desktop_header.text = Localization.t("desktop_controls")
	_desktop_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desktop_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desktop_header.add_theme_font_size_override("font_size", 16 if Localization.is_english() else 18)
	_key_w.text = "  W / ↑       " + Localization.t("key_forward")
	_key_s.text = "  S / ↓       " + Localization.t("key_back")
	_key_a.text = "  A / ←       " + Localization.t("key_left")
	_key_d.text = "  D / →       " + Localization.t("key_right")
	_key_space.text = "  Space     " + Localization.t("key_check_in")
	_key_esc.text = "  ESC         " + Localization.t("key_pause")
	_key_m.text = "  M           " + Localization.t("key_mute")
	for lbl in [_key_w, _key_s, _key_a, _key_d, _key_space, _key_esc, _key_m]:
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", 14 if Localization.is_english() else 15)
	_mobile_header.text = Localization.t("touch_buttons_key")
	_mobile_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mobile_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mobile_header.add_theme_font_size_override("font_size", 16 if Localization.is_english() else 18)
	_touch_joy.text = "  " + Localization.t("touch_joystick_key") + "     " + Localization.t("touch_joystick_desc")
	_touch_checkin.text = "  " + Localization.t("touch_checkin_key") + "     " + Localization.t("touch_checkin_desc")
	_touch_buttons.text = "  " + Localization.t("touch_buttons_key") + "     " + Localization.t("touch_buttons_desc")
	for lbl in [_touch_joy, _touch_checkin, _touch_buttons]:
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", 14 if Localization.is_english() else 15)
	_help_mute_hint.text = Localization.t("help_close")
	_help_mute_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_mute_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_mute_hint.add_theme_font_size_override("font_size", 13 if Localization.is_english() else 14)


func _setup_economy_labels() -> void:
	var box := $TopBar/HBox
	# 容器得先说实话：它要占满「12px → 按钮排左边」这一整段。
	# 不改这一条，弹簧没地方撑，`_next_label` 仍然是从 12px 起顺排出来的，
	# 空档还是全堆在它后面 —— 而溢出那一段没有任何回归能量得到。
	box.anchor_right = 1.0
	box.offset_right = -(TOP_RIGHT_W + TOP_RIGHT_GAP)
	_lvbi_label = _make_hud_label()
	_mood_label = _make_hud_label()
	_next_label = _make_hud_label()
	# 和旅币/心神一个字号同一个色，别做成第二行——顶栏只有一条，
	# 加行会把 1280 宽的屏挤爆。
	_next_label.add_theme_font_size_override("font_size", 16)
	box.add_child(_lvbi_label)
	box.add_child(_mood_label)
	# 弹簧在心神和「下一处」之间，所以**变长变短的是弹簧**：站名再长、
	# 「还差 N 次」再长，往左推的都是它，旅币和心神一个像素都不会动
	#（那正是 CLAUDE.md 里"顶栏 HBox 里任何一个 Label 改字都会把整排标签横向推走"
	# 那条陷阱要的形状）。`custom_minimum_size.x = 0` 是留给窄屏的：
	# 1280 撑不开的时候它收到 0，行为和旧版一样（宁可溢出也不压字）。
	_next_gap = Control.new()
	_next_gap.name = "NextGap"
	_next_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_next_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_gap.custom_minimum_size = Vector2(0.0, 0.0)
	box.add_child(_next_gap)
	box.add_child(_next_label)
	_setup_lvbi_toast()
	GameManager.lvbi_changed.connect(_on_lvbi_changed)


## 「+N 旅币」的那条 toast。挂在 HUD3D 上、绝对定位，**不进 TopBar 的 HBox**。
##
## 之前是直接改余额标签的 text，Label 宽度一变 HBox 就重排，心神和"下一处"
## 整排横着跳一下。现在余额纹丝不动，toast 单独浮在顶栏下面一行。
## 位置避开右上角小地图（top 56~246），压在顶栏正下方左侧，和它指的那份余额挨着。
func _setup_lvbi_toast() -> void:
	_lvbi_toast = Label.new()
	_lvbi_toast.name = "LvbiToast"
	_lvbi_toast.add_theme_font_size_override("font_size", 18)
	_lvbi_toast.add_theme_color_override("font_color", Color(1.0, 1.45, 0.95, 1.0))
	_lvbi_toast.anchor_left = 0.0
	_lvbi_toast.anchor_right = 0.0
	_lvbi_toast.offset_left = 14.0
	_lvbi_toast.offset_top = SCRIM_H + 24.0
	_lvbi_toast.offset_right = 400.0
	_lvbi_toast.offset_bottom = SCRIM_H + 50.0
	_lvbi_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lvbi_toast.text = ""
	_lvbi_toast.modulate.a = 0.0
	add_child(_lvbi_toast)


func _make_hud_label() -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.961, 0.784, 0.494, 1.0))
	return lbl


func _on_lvbi_changed(amount: int, _total: int) -> void:
	if amount <= 0 or _lvbi_label == null:
		return
	# 入账不只闪一下：把「+N 旅币」写成一条独立 toast，1.4 秒后 _process 收回。
	# earn() 只在入账时发信号（负数不发），所以这里不用区分赚和花。
	# 余额标签一个字都不动——它一动整排顶栏就跟着重排。
	_lvbi_gain_text = Localization.t("collecting_lvbi", [amount])
	_lvbi_gain_left = LVBI_GAIN_SHOW_SEC
	if _lvbi_toast != null:
		_lvbi_toast.text = _lvbi_gain_text
		_lvbi_toast.modulate = Color(1.0, 1.45, 0.95, 1.0)


## 顶栏衬底。插在 index 0（比心神遮罩还靠下一层），往下淡出到全透明。
## 用一张一次性生成的 1×N 渐变图拉伸，不引 .png —— 零纹理资产是本项目的硬约束。
func _setup_scrim() -> void:
	var tex := ImageTexture.create_from_image(_make_scrim_image())
	var scrim := TextureRect.new()
	scrim.name = "TopScrim"
	scrim.texture = tex
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 只贴顶边那一条，别糊成整块面板——下半段越接近 0 越不挡视线
	scrim.offset_left = 0.0
	scrim.offset_top = 0.0
	scrim.offset_right = 0.0
	scrim.offset_bottom = SCRIM_H
	scrim.anchor_right = 1.0
	add_child(scrim)
	move_child(scrim, 0)


static func _make_scrim_image() -> Image:
	var n := 32
	var img := Image.create_empty(1, n, false, Image.FORMAT_RGBA8)
	for y in n:
		var t := float(y) / float(n - 1)
		var a := SCRIM_TOP_ALPHA
		if t > SCRIM_SOLID_FRAC:
			# 实底段之后才淡出，pow 1.4 让它尽快给下方画面让路
			var k := (t - SCRIM_SOLID_FRAC) / (1.0 - SCRIM_SOLID_FRAC)
			a = SCRIM_TOP_ALPHA * pow(1.0 - k, 1.4)
		img.set_pixel(0, y, Color(0.07, 0.08, 0.12, a))
	return img


## 「为什么按了没反应」那行。挂在顶栏下面一点，不占顶栏的 HBox。
func _setup_blocked_hint() -> void:
	_hint_label = _make_hud_label()
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", Color(0.86, 0.87, 0.90, 1.0))
	_hint_label.anchor_left = 0.0
	_hint_label.anchor_right = 0.0
	_hint_label.offset_left = 14.0
	_hint_label.offset_top = SCRIM_H - 6.0
	_hint_label.offset_right = 640.0
	_hint_label.offset_bottom = SCRIM_H + 22.0
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.text = ""
	add_child(_hint_label)


## 空格/触屏按钮被门控挡掉时顶栏给一行原因。
## 和 CheckInPrompt.flash_blocked() 用同一个 key，两处说同一句话。
const HINT_HOLD_SEC := 1.6

func show_blocked_hint(key: String) -> void:
	if _hint_label == null or key == "":
		return
	_hint_label.text = Localization.t(key)
	_hint_label.modulate.a = 0.0
	_hint_left = HINT_HOLD_SEC
	var tw := create_tween()
	tw.tween_property(_hint_label, "modulate:a", 1.0, 0.12)


## 路过非碎片驿时浮出的那一句。
##
## 16 座驿里只有 5 座给碎片，剩下 11 座以前路过时除了顶栏「已过 n/16 驿」
## 之外什么都没有——而它们其实早就各写好了一句风景话（road_data 的 text/text_en），
## 只是永远没人读得到：_nearby_station_idx 只会收碎片驿，而那条 text 唯一的
## 调用点在打卡之后。这一行就是把那份已经存在的数据接上。
##
## 绝不能做成可点的：交互一旦归它，就和新手引导/对白/小游戏抢同一个空格，
## 那正是"提示圈照画、按键全死、只能重开"那一族。纯展示，mouse_filter = IGNORE。
const PASS_HOLD_SEC := 3.2
## 入场提示停留。它得盖住 `World3D` 那一下镜头收束（`VILLAIN_CAM_PULL_SEC`
## 的移动 + 定格），所以比 `PASS_HOLD_SEC` 短不了——提示先收、字后走。
const CUE_HOLD_SEC := 2.6

func _setup_pass_line() -> void:
	# 底板挂在 CenterContainer 上而不是 Label 身上：Label 拉满屏宽时 stylebox 会
	# 跟着铺满，出来是一条横贯全屏的暗带，看着像顶栏多了一行。套一层
	# CenterContainer 让底板只包住文字，实际宽度随句子长短变。
	var holder := CenterContainer.new()
	holder.name = "PassLine"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.anchor_left = 0.0
	holder.anchor_right = 1.0
	holder.offset_top = SCRIM_H + 30.0
	holder.offset_bottom = SCRIM_H + 62.0
	holder.modulate.a = 0.0
	add_child(holder)

	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", _pass_box())
	holder.add_child(plate)

	_pass_label = Label.new()
	# 米金顶栏压在浅蓝天空上只有 1.6:1 对比度，这行同理，自己带一块底。
	# 居中放在衬底下面：左边的被挡提示、左下的旅币 toast 都不占这一带。
	_pass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pass_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pass_label.add_theme_font_size_override("font_size", 17)
	_pass_label.add_theme_color_override("font_color", Color(0.90, 0.89, 0.85))
	_pass_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pass_label.text = ""
	plate.add_child(_pass_label)
	_pass_holder = holder


## 「有人找你」的那一句，郑铎三场之前浮一次。
##
## 单独一套 holder，不复用 `PassLine`：两者都是"居中 + 底板 + 淡出"，复用的话
## 一次打断正好撞上一句还没淡完的风景话，两条字挤在同一带里、还共用一个
## `_pass_left` —— 谁后浮谁把谁掐掉。CLAUDE.md 那条"淡入淡出要挂在 holder 上、
## 两处都 modulate 会相乘成 0"在这里同理：两条通道各自归各自。
func _setup_cue_line() -> void:
	var holder := CenterContainer.new()
	holder.name = "CueLine"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.anchor_left = 0.0
	holder.anchor_right = 1.0
	# 比风景话高、也更靠中间：这是一次**事件**，不是路边的 scenery，
	# 摆低了会被读成又一句路过的风景话 —— 而玩家要的正是一眼分得开。
	holder.offset_top = SCRIM_H + 96.0
	holder.offset_bottom = SCRIM_H + 152.0
	holder.modulate.a = 0.0
	add_child(holder)

	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", _cue_box())
	holder.add_child(plate)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	plate.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.name = "CueName"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 20)
	# 冷白偏蓝，和顶栏米金分开：这是"外面来的人"，不是这趟旅程自己在说话。
	name_lbl.add_theme_color_override("font_color", Color(0.80, 0.86, 0.96))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.text = ""
	vbox.add_child(name_lbl)

	_cue_label = Label.new()
	_cue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cue_label.add_theme_font_size_override("font_size", 17)
	_cue_label.add_theme_color_override("font_color", Color(0.93, 0.93, 0.90))
	_cue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cue_label.text = ""
	vbox.add_child(_cue_label)

	_cue_name_label = name_lbl
	_cue_holder = holder


func _cue_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	# 比 `_pass_box` 更实：这一屏背后可能是正午的天，而它要在那上面立住。
	sb.bg_color = Color(0.04, 0.05, 0.09, 0.86)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 30.0
	sb.content_margin_right = 30.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	return sb


## 浮一句"有人找你"。`who` 是说话人，`what` 是那句入场的短句。
func show_cue_line(who: String, what: String) -> void:
	if _cue_label == null or what.strip_edges() == "":
		return
	if _cue_name_label != null:
		_cue_name_label.text = who
	_cue_label.text = what
	_cue_holder.modulate.a = 1.0
	_cue_left = CUE_HOLD_SEC


## 立刻收掉入场提示。
##
## 单独一个方法而不是等 `_cue_left` 走完：对白一弹起来，那句提示就该让位，
## 而它自己那条淡出还要 0.5s——两层底板叠着，字压在字上。
func clear_cue_line() -> void:
	_cue_left = 0.0
	if _cue_holder != null:
		_cue_holder.modulate.a = 0.0
	if _cue_label != null:
		_cue_label.text = ""
	if _cue_name_label != null:
		_cue_name_label.text = ""


func _pass_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.08, 0.62)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb


func show_pass_line(text: String) -> void:
	if _pass_label == null or text.strip_edges() == "":
		return
	_pass_label.text = text
	_pass_holder.modulate.a = 1.0
	_pass_left = PASS_HOLD_SEC


## 遮罩本体。插到 index 0，让 TopBar / TopRightHBox / HelpOverlay 都压在上面。
func _setup_mood_mask() -> void:
	_mood_mask = TextureRect.new()
	_mood_mask.name = "MoodMask"
	_mood_mask.texture = ImageTexture.create_from_image(_make_mask_image())
	_mood_mask.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mood_mask.stretch_mode = TextureRect.STRETCH_SCALE
	_mood_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mood_mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_mood_mask)
	move_child(_mood_mask, 0)
	# 开局就按骑行档起手。写成叙事档的话，进游戏第一帧是一屏 0.52 的雾，
	# 要等 _process 慢慢退下去——玩家会先看到"这游戏一开局就糊"。
	_mood_alpha = GameManager.get_mood_mask_alpha() * MOOD_REST_SCALE
	_mood_mask.modulate.a = _mood_alpha


## 径向渐变：中心全清、越靠边角越浓。pow 1.6 让「看得见的路」留出一块中央安全区。
static func _make_mask_image() -> Image:
	var n := MASK_TEX_SIZE
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var c := float(n) * 0.5
	var max_d := Vector2(c, c).length()
	for y in n:
		for x in n:
			var d := clampf(Vector2(float(x) - c, float(y) - c).length() / max_d, 0.0, 1.0)
			img.set_pixel(x, y, Color(MASK_TINT, pow(d, 1.6)))
	return img


func _create_boundary_warning() -> Control:
	var overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	var edges = [
		[0.0, 0.0, 1.0, 0.07],
		[0.0, 0.93, 1.0, 1.0],
		[0.0, 0.0, 0.07, 1.0],
		[0.93, 0.0, 1.0, 1.0],
	]
	for e in edges:
		var rect = ColorRect.new()
		rect.color = Color(0.75, 0.12, 0.12, 0.0)
		rect.anchor_left = e[0]
		rect.anchor_top = e[1]
		rect.anchor_right = e[2]
		rect.anchor_bottom = e[3]
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(rect)
		_boundary_rects.append(rect)
	return overlay


func set_boundary_intensity(v: float) -> void:
	if v > 0.001:
		_boundary_warning.visible = true
		var alpha = clampf(v * 0.45, 0.0, 0.38)
		for r in _boundary_rects:
			r.color = Color(0.75, 0.12, 0.12, alpha)
	else:
		if _boundary_warning.visible:
			_boundary_warning.visible = false


func show_help() -> void:
	_help_panel.visible = true
	_help_panel.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(_help_panel, "modulate:a", 1.0, 0.2)


func close_help() -> void:
	var tw = create_tween()
	tw.tween_property(_help_panel, "modulate:a", 0.0, 0.2)
	await tw.finished
	_help_panel.visible = false
	_help_panel.modulate.a = 1.0
