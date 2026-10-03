extends Control
## EndCard — 结局 / 礼物合成 (PRD §5.5)
## 集齐5块碎片后合成动态明信片，可一键导出PNG
##
## 明信片是三层拼的（整合方案 §5.3），只有一层是买的：
##   纸面 = Postcard.gd 按 GameManager 的档位与散件画
##   正面 = 五块碎片，商店里明列「无价」
##   背面 = 本文件的终局落笔 —— 选【留门】还是【放手】
## 二选一要压在明信片揭示之前：背面那句话就是结局本身，
## 选之前就让它露出来等于剧透了一半（§7.3）。
## keep/break 唯一的后果就是背面预填哪一句（_seed_back_text），所以卡片上
## 摆的就是那一句本身，不另编一段"选了会怎样"——见 _show_ending_choice。

@onready var _export_btn: Button = $VBox/ExportBtn
@onready var _restart_btn: Button = $VBox/RestartBtn
@onready var _share_btn: Button = $VBox/ShareBtn
@onready var _postcard: Control = $Postcard
@onready var _export_viewport: SubViewport = $ExportViewport
@onready var _postcard_export: Control = $ExportViewport/PostcardExport
@onready var _write_back_btn: Button = $VBox/WriteBackBtn

var _toast_label: Label = null
var _back_text: String = ""
var _back_editor: Control = null       # 背面写字覆盖层
var _back_title: Label = null          # 覆盖层里的可翻译控件，切语言时按引用刷新
var _back_text_edit: TextEdit = null
var _back_confirm_btn: Button = null
var _back_skip_btn: Button = null
var _back_viewport: SubViewport = null  # 背面导出视口
var _back_postcard: Control = null      # 背面 PostcardBack 实例
var _back_preview: Control = null       # 背面预览
var _back_thumb: TextureRect = null     # 写字时的小预览
var _back_thumb_caption: Label = null
var _back_thumb_dirty: bool = false
var _back_thumb_wait: float = 0.0
var _back_to_front_btn: Button = null
var _ending_overlay: Control = null     # 终局二选一覆盖层
var _variant_hint: Label = null          # 「正面第 5 格为什么是问号」的说明行
var _choice_title: Label = null
var _choice_hint: Label = null
var _choice_keep_title: Label = null
var _choice_keep_desc: Label = null
var _choice_break_title: Label = null
var _choice_break_desc: Label = null
var _recap_overlay: Control = null      # 「重新开始」前的这一趟回执
var _recap_title: Label = null
var _recap_body: Label = null
var _recap_again_btn: Button = null
var _recap_stay_btn: Button = null


func _ready() -> void:
	_export_btn.pressed.connect(_on_export_pressed)
	_restart_btn.pressed.connect(_on_restart_pressed)
	_share_btn.pressed.connect(_on_share_pressed)
	_write_back_btn.pressed.connect(_show_back_editor)
	Localization.language_changed.connect(_apply_language)
	_apply_language()

	_postcard_export.size = Vector2(1920, 1080)

	# 背面导出 SubViewport
	_back_viewport = SubViewport.new()
	_back_viewport.transparent_bg = true
	_back_viewport.size = Vector2(1920, 1080)
	_back_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_back_viewport)
	_back_postcard = preload("res://scenes/PostcardBack.tscn").instantiate()
	# SubViewport 不是 Control，anchor_* 对它不生效，背面卡片会停在 0×0：
	# 底色/边框/文字框全是退化矩形，导出的背面几乎是空白。必须显式给尺寸
	# （正面的 _postcard_export 同理，见上面那行）。
	_back_postcard.position = Vector2.ZERO
	_back_postcard.size = _back_viewport.size
	_back_viewport.add_child(_back_postcard)

	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.z_index = 200
	_toast_label.set_anchors_preset(Control.PRESET_CENTER)
	_toast_label.size = Vector2(500, 50)
	_toast_label.text = ""
	_toast_label.modulate.a = 0.0
	add_child(_toast_label)

	# 「集齐五件却看到灰问号」的说明行。默认不显示，见 _reveal_postcard()。
	_variant_hint = Label.new()
	_variant_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_variant_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_variant_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_variant_hint.add_theme_font_size_override("font_size", 14)
	_variant_hint.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	var patch := StyleBoxFlat.new()
	patch.bg_color = Color(0.33, 0.33, 0.33)
	_variant_hint.add_theme_stylebox_override("normal", patch)
	_variant_hint.z_index = 60
	_variant_hint.visible = false
	add_child(_variant_hint)

	# 明信片先藏起来等二选一：选完才揭示。
	_postcard.visible = false
	_postcard.scale = Vector2(0.5, 0.5)
	_postcard.modulate.a = 0.0
	$VBox.visible = false

	_seed_back_text()
	if _needs_choice():
		_show_ending_choice()
	else:
		_reveal_postcard()


func _apply_language() -> void:
	_export_btn.text = Localization.t("export")
	_restart_btn.text = Localization.t("restart_end")
	_share_btn.text = Localization.t("share")
	_write_back_btn.text = Localization.t("write_back")
	if _back_title:
		_back_title.text = Localization.t("back_editor_title")
	if _back_text_edit:
		_back_text_edit.placeholder_text = Localization.t("back_placeholder")
	if _back_confirm_btn:
		_back_confirm_btn.text = Localization.t("back_confirm")
	if _back_skip_btn:
		_back_skip_btn.text = Localization.t("back_skip")
	if _back_thumb_caption:
		_back_thumb_caption.text = Localization.t("back_preview_caption")
	if _back_to_front_btn:
		_back_to_front_btn.text = Localization.t("back_to_front")
	if _choice_title:
		_choice_title.text = Localization.t("ending_title")
	if _choice_hint:
		_choice_hint.text = Localization.t("ending_hint")
	if _choice_keep_title:
		_choice_keep_title.text = Localization.t("ending_keep")
	if _choice_keep_desc:
		_choice_keep_desc.text = Localization.t("back_keep")
	if _choice_break_title:
		_choice_break_title.text = Localization.t("ending_break")
	if _choice_break_desc:
		_choice_break_desc.text = Localization.t("back_break_blank")
	if _variant_hint and _variant_hint.visible:
		_variant_hint.text = Localization.t("postcard_variant_hint")
	if _recap_overlay != null:
		_refresh_recap_text()
	if _back_postcard and _back_postcard.has_method("refresh_text"):
		_back_postcard.refresh_text()


## ===================== 终局二选一（§7.3） =====================

## 还需要玩家做抉择：没选过，且五个碎片齐了。
## 未齐（§7.3 的「未竟」）直接出明信片：正面缺格、背面空白，礼物照样成立。
func _needs_choice() -> bool:
	return GameManager.ending_id == "" \
			and GameManager.get_collected_count() >= RoadData.FRAGMENT_SLOT_STATION_IDX.size()


## 背面那句话由终局抉择给，不是买来的、也不是默认的。
##
## 留门：游戏把那句写上去（玩家仍可改）。放手：背面**留白**，那句话退成
## 写字界面里的灰色占位提示——摆在那儿，要不要拿由玩家。留白 + 掰开的蜡封
## 是这个抉择真正落在产物上的东西；只改一句预填文案的话，玩家的收获和
## 手抄一遍没区别，那不叫选择。未竟（ending_id 为空）同样留白：只有纸纹。
func _seed_back_text() -> void:
	var key := ""
	match GameManager.ending_id:
		"keep":
			key = "back_keep"
	if key == "":
		_back_text = ""
		if _back_postcard != null:
			_back_postcard.set_back_text("")
		return
	_back_text = Localization.t(key)
	if _back_postcard != null:
		_back_postcard.set_back_text(_back_text)


## 二选一覆盖层。标题 + 提示 + 两张可点卡片，卡片本身没有 Button，
## 所以命中范围要自己接 gui_input，否则只有那一行标题能点。
func _show_ending_choice() -> void:
	if _ending_overlay != null:
		return
	_ending_overlay = Control.new()
	_stretch_full(_ending_overlay)
	_ending_overlay.z_index = 90
	add_child(_ending_overlay)

	var shade := ColorRect.new()
	# 和背面编辑器同一层的不透明度：薄一点的话明信片与按钮会透出来，两处叠着不好读
	shade.color = Color(0.05, 0.04, 0.04, 0.97)
	_stretch_full(shade)
	_ending_overlay.add_child(shade)

	# 遮罩刚入树，同一帧还没排版完成，所以拿视口尺寸算位置
	var vp := get_viewport_rect().size
	var vw := vp.x
	var h := vp.y

	_choice_title = Label.new()
	_choice_title.text = Localization.t("ending_title")
	_choice_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice_title.add_theme_font_size_override("font_size", 40)
	_place_top_wide(vw, _choice_title, h * 0.12, 52.0)
	_ending_overlay.add_child(_choice_title)

	_choice_hint = Label.new()
	_choice_hint.text = Localization.t("ending_hint")
	_choice_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice_hint.add_theme_font_size_override("font_size", 22)
	_choice_hint.add_theme_color_override("font_color", Color(0.78, 0.73, 0.64))
	_place_top_wide(vw, _choice_hint, h * 0.24, 36.0)
	_ending_overlay.add_child(_choice_hint)

	var card_w := minf(vw * 0.42, 480.0)
	var gap := 44.0
	var left := maxf((vw - card_w * 2.0 - gap) * 0.5, 0.0)
	var card_h := minf(h * 0.24, 170.0)
	# 卡片正文写的就是选完之后真正会发生的事，不另编一段"选了会怎样"的形容。
	# 留门：背面就多这一句（所以正文直接是那一句本身）。
	# 放手：背面留白、封口的蜡掰开，那句话只作为写字界面的占位提示——所以
	# 正文说的是"留白"，不是把那句拿过来当承诺。旧版两条正文都只是"守住归途 /
	# 打破循环"这类形容，keep/break 在整条代码路径上只决定背面预填哪一句，
	# 玩家选完去找差别只找到一句话。
	_ending_overlay.add_child(_make_choice_card(
		"ending_keep", "back_keep", "keep", card_w, left, h * 0.38, card_h))
	_ending_overlay.add_child(_make_choice_card(
		"ending_break", "back_break_blank", "break", card_w, left + card_w + gap, h * 0.38, card_h))


func _make_choice_card(title_key: String, desc_key: String, ending: String,
		width: float, x: float, y: float, height: float) -> Control:
	var card := PanelContainer.new()
	# 必须显式命名：回归脚本按名字取卡片来 emit gui_input 验证两条分支，
	# 不命名的话自动名是 @PanelContainer@N，keep 和 break 没法区分。
	card.name = "Choice_" + ending
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.11, 0.10, 0.94)
	sb.border_color = Color(0.66, 0.52, 0.32, 0.95)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(20)
	card.add_theme_stylebox_override("panel", sb)
	_place_fixed(card, x, y, width, height)

	var box := VBoxContainer.new()
	# 对齐枚举挂在 BoxContainer 上，不在 Control 上；写 Control.ALIGNMENT_CENTER
	# 会直接 Parse Error，EndCard.tscn 整场加载不出来。
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	var tl := Label.new()
	tl.text = Localization.t(title_key)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_font_size_override("font_size", 28)
	var dl := Label.new()
	dl.text = Localization.t(desc_key)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.add_theme_font_size_override("font_size", 16)
	dl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.66))
	box.add_child(tl)
	box.add_child(dl)
	card.add_child(box)

	if ending == "keep":
		_choice_keep_title = tl
		_choice_keep_desc = dl
	else:
		_choice_break_title = tl
		_choice_break_desc = dl

	card.gui_input.connect(_on_choice_card_input.bind(ending))
	return card


func _on_choice_card_input(event: InputEvent, ending: String) -> void:
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_choose_ending(ending)


func _choose_ending(ending: String) -> void:
	if ending != "keep" and ending != "break":
		return
	GameManager.set_ending(ending)
	_seed_back_text()
	AudioManager.play_sfx("open")
	# 先隐藏再 free：queue_free 是延迟的，同一帧里它还盖着揭示动画
	_ending_overlay.visible = false
	_ending_overlay.queue_free()
	_ending_overlay = null
	_choice_title = null
	_choice_hint = null
	_choice_keep_title = null
	_choice_keep_desc = null
	_choice_break_title = null
	_choice_break_desc = null
	_reveal_postcard()


## 二选一完成（或从存档恢复时本来就选过了）之后揭示明信片。
func _reveal_postcard() -> void:
	$VBox.visible = true
	_postcard.visible = true
	_export_btn.grab_focus()
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_postcard, "scale", Vector2(1, 1), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_postcard, "modulate:a", 1.0, 0.4)
	# 摆放必须等补间把 scale 放回 1.0 之后再算：动画期间 get_global_rect()
	# 拿到的是缩到 0.5 的那一份，照那个摆会正好压在明信片正中间。
	tw.chain().tween_callback(_show_variant_hint)


## 集齐五块碎片、但没有一座驿站到过 3 次时，评级是「大师」而不是「完满」，
## 正面第 5 格画的是灰色问号而不是真禽（见 Postcard.VARIANT_LAYOUTS）。
## HUD 写着「碎片 5/5」、明信片却带一个问号，玩家只会当成 bug。
##
## 说明写在灰格里面，而不是卡片底下：720p 下明信片底边紧贴着 VBox 的四个
## 按钮（导出/分享/写背面/重新开始），底下根本放不下第五行；而问号在哪，
## 玩家的眼睛就在哪，正好把答案写在问号原来的位置。
func _show_variant_hint() -> void:
	if _variant_hint == null or PostcardVariant.compute_variant() != 3:
		return
	_variant_hint.text = Localization.t("postcard_variant_hint")
	# 灰格占正面的 0.8w~1.0w × 0.3h~0.85h（见 Postcard._draw 的分区算法）。
	# 铺满整格而不是只盖住文字那一小块：卡片自己画的「?」在格子正中，
	# 文字压在它上面会从底下露出半个问号，看着像渲染错了。
	# 底色取 Color.GRAY.darkened(0.3) 再压掉 Postcard._draw 的 shimmer，
	# 和旁边四格看不出差别。
	var pw := _postcard.size.x
	var ph := _postcard.size.y
	_place_fixed(_variant_hint,
			_postcard.position.x + pw * 0.8,
			_postcard.position.y + ph * 0.30,
			pw * 0.2, ph * 0.55)
	_variant_hint.visible = true


## ===================== 重新开始前的「这一趟」回执 =====================
##
## 通关一次要 10 分钟，而一次通关本身不给出任何再玩的理由：明信片已经导出，
## 五块碎片都在身上，玩家手里没有「下次换个玩法」的具体东西可抓。这里在
## 玩家按下【重新开始】、进度**还没被 reset 清掉**的那一帧，把这一趟真实
## 没碰过的东西列出来 —— 快照不是另存一份，reset 之后就没得查了。
##
## 三条纪律：
##   1. 全部由存档里已有的字段推出来（seen_stations / collected /
##      earned_tags / lvbi / ending_id），不新增任何进度写入。
##   2. 玩家没做过的事不列。编一条出来骗他再骑一趟，第二趟发现根本没有，
##      比不弹更伤 —— 所以「全走到了」是真的会显示的。
##   3. 这是回执不是评分：没有扣分、没有红字、没有倒计时。

## 把名字数组接成一句。分隔符跟着界面语言走。
func _join_names(names: Array) -> String:
	return (", " if Localization.is_english() else "、").join(names)


## 这一趟还剩下什么。纯函数：只读 GameManager，不写。
func _recap_lines() -> Array:
	var rd = RoadData.new()
	var lines: Array = []

	# 1. 没拿到的碎片。未竟时这是最要紧的一句，也是下一次最该去的地方。
	var missing: Array = []
	for st_idx in RoadData.FRAGMENT_SLOT_STATION_IDX:
		if not GameManager.is_collected(st_idx):
			missing.append(rd.station_display_fragment(st_idx))
	if missing.size() > 0:
		lines.append(Localization.t(
				"recap_frag_one" if missing.size() == 1 else "recap_frag_missing",
				[_join_names(missing)]))

	# 2. 没到过的驿站。11 座风景站每座都有一句只在这里说的话（World3D 的
	#    路过话），骑过就算读到，没骑过就永远读不到 —— 点名比报个数字有用。
	var seen: int = GameManager.get_seen_station_count()
	var total: int = rd.stations.size()
	if seen < total:
		var unread: Array = []
		for i in total:
			if GameManager.seen_stations.has(i):
				continue
			unread.append(rd.station_display_name(i))
			if unread.size() >= 3:
				break
		lines.append(Localization.t("recap_seen", [seen]))
		if unread.size() > 0:
			lines.append(Localization.t("recap_unread", [_join_names(unread)]))

	# 3. 没赢过的小乐事。on_mini_game() 写的 mini_%d_win / mini_%d_lose
	#    是逐站的，两个 tag 都没有 = 压根没玩成（失败或中途放弃）。
	var wins: int = 0
	var lost: Array = []
	for st_idx in RoadData.FRAGMENT_SLOT_STATION_IDX:
		if GameManager.earned_tags.has("mini_%d_win" % st_idx):
			wins += 1
		else:
			lost.append(rd.station_display_fragment(st_idx))
	if wins > 0 or lost.size() > 0:
		# 全赢了就只报「没赢过的那些」。写「五件都赢过了」不是漏项，
		# 是一句在回执里没有对象的客套。
		if lost.size() > 0:
			lines.append(Localization.t("recap_mini", [wins]))
			lines.append(Localization.t("recap_mini_lost", [_join_names(lost)]))

	# 4. 没到过的另一边。keep / break 只有一次，走了这边那边就空着。
	if GameManager.ending_id != "":
		lines.append(Localization.t("recap_ending",
				[Localization.t("ending_keep" if GameManager.ending_id == "keep"
						else "ending_break")]))

	# 5. 没到过的完满：正面第 5 格是问号。跟卡片上那行说明是同一句话。
	if PostcardVariant.compute_variant() == 3:
		lines.append(Localization.t("postcard_variant_hint"))

	# 6. 没花完的旅币
	if GameManager.lvbi > 0:
		lines.append(Localization.t("recap_lvbi", [GameManager.lvbi]))

	return lines


## 该不该弹。只要这一趟真的骑过就弹。
##
## 想过「全都走到了就免弹」，但那一条永远不成立：keep / break 一次只能选
## 一个，存档又随重开清零，所以**另一边的结局必然空着**，每趟至少剩一样。
## 与其编一句「你都走到了」来糊住这个空，不如就把它摆出来 —— 那正是
## 下一趟唯一还没试过的东西。
func _recap_worth_showing() -> bool:
	return GameManager.ending_id != "" or GameManager.get_collected_count() > 0


func _refresh_recap_text() -> void:
	if _recap_title == null or _recap_body == null:
		return
	_recap_title.text = Localization.t("recap_title")
	_recap_body.text = "\n".join(_recap_lines())
	if _recap_again_btn:
		_recap_again_btn.text = Localization.t("recap_again")
	if _recap_stay_btn:
		_recap_stay_btn.text = Localization.t("recap_stay")


## 回执覆盖层。挡在「重新开始」和真正的 reset 之间：玩家已经决定再玩，
## 但还没决定值不值得再玩，所以先把这趟剩的东西摆出来。
func _show_run_recap() -> void:
	if _recap_overlay != null:
		return
	_recap_overlay = Control.new()
	_stretch_full(_recap_overlay)
	_recap_overlay.z_index = 110
	add_child(_recap_overlay)

	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.04, 1.0)
	_stretch_full(shade)
	_recap_overlay.add_child(shade)

	# 遮罩刚入树，同一帧还没排版完成，所以拿视口尺寸算位置
	var vp := get_viewport_rect().size
	var vw := vp.x
	var h := vp.y

	_recap_title = Label.new()
	_recap_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recap_title.add_theme_font_size_override("font_size", 36)
	_place_top_wide(vw, _recap_title, h * 0.12, 50.0)
	_recap_overlay.add_child(_recap_title)

	_recap_body = Label.new()
	_recap_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 必须开自动换行：正文是按中文长度定的 720px 宽，英文那句「没读到它们
	# 的话：…」连着三个驿站名能拉到 900px+，不换行就是直接被裁掉右半截，
	# 而窗口模式下没人会注意到少了半句。
	_recap_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_recap_body.add_theme_font_size_override("font_size", 20)
	_recap_body.add_theme_constant_override("line_spacing", 8)
	_recap_body.add_theme_color_override("font_color", Color(0.84, 0.79, 0.70))
	_place_top_wide(vw, _recap_body, h * 0.26, h * 0.40, minf(vw - 160.0, 720.0))
	_recap_overlay.add_child(_recap_body)

	# 「再骑一趟」在左：它才是这一屏想让人按的那个，焦点环也在它身上。
	_recap_again_btn = _make_recap_button("recap_again", vw, h * 0.70, true)
	_recap_stay_btn = _make_recap_button("recap_stay", vw, h * 0.70, false)
	_recap_overlay.add_child(_recap_again_btn)
	_recap_overlay.add_child(_recap_stay_btn)
	_refresh_recap_text()
	_recap_again_btn.grab_focus()


func _make_recap_button(key: String, vw: float, y: float, is_left: bool) -> Button:
	var b := Button.new()
	b.text = Localization.t(key)
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = Vector2(200, 58)
	_place_fixed(b, vw * 0.5 + (-212.0 if is_left else 12.0), y, 200, 58)
	b.pressed.connect(_on_recap_again_pressed if is_left else _on_recap_stay_pressed)
	return b


func _on_recap_again_pressed() -> void:
	GameManager.go_to_gift_box()


func _on_recap_stay_pressed() -> void:
	AudioManager.play_sfx("open")
	if _recap_overlay == null:
		return
	_recap_overlay.queue_free()
	_recap_overlay = null
	_recap_title = null
	_recap_body = null
	_recap_again_btn = null
	_recap_stay_btn = null
	_export_btn.grab_focus()


## ===================== 背面写字编辑器 =====================

## 打开背面写字编辑器
func _show_back_editor() -> void:
	if _back_editor != null:
		return
	_back_editor = Control.new()
	# 只调 set_anchors_preset 不会真正写进 anchor_*：节点保持 0 锚点、0 偏移，
	# 尺寸退化成最小值。下面的 h = _back_editor.size.y 于是读到 0，
	# 所有子控件被摆到 y=0 且宽度算成 max(0-700,0)=0 —— 屏幕上只剩一层
	# 黑色遮罩，按钮既看不见也点不到。锚点和偏移必须显式写。
	_stretch_full(_back_editor)
	_back_editor.z_index = 100
	add_child(_back_editor)

	# 打开编辑器时就把正面收掉。只靠 shade 的 alpha 压不住：正面的明信片和
	# VBox 四个按钮会从遮罩里透出来（截图实拍能看到「导出明信片 / 写背面」
	# 一行行浮在编辑器按钮底下），而「跳过，直接导出」正好落在那一行上面。
	# 遮罩只在 _show_back_editor_preview() 里才把正面藏掉，那是确认之后的事。
	$VBox.visible = false
	_postcard.visible = false
	_variant_hint.visible = false

	var shade := ColorRect.new()
	# 纯不透明。已经是全屏模态了，没有任何理由让上一层透过来；
	# 之前留 0.03 的缝就是透出鬼影的那 3%。
	shade.color = Color(0.05, 0.04, 0.04, 1.0)
	_stretch_full(shade)
	_back_editor.add_child(shade)

	# 用视口尺寸而不是 _back_editor.size：遮罩刚入树，同一帧内还没排版完成。
	var vp := get_viewport_rect().size
	var h := vp.y
	var vw := vp.x

	# 标题
	_back_title = Label.new()
	_back_title.text = Localization.t("back_editor_title")
	_back_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_back_title.add_theme_font_size_override("font_size", 32)
	_place_top_wide(vw, _back_title, h * 0.14, 48.0)
	_back_editor.add_child(_back_title)

	# TextEdit
	_back_text_edit = TextEdit.new()
	# 必须显式命名：_on_back_text_changed 是按名字 "TextEdit" 取节点的，
	# 不命名的话自动名是 "@TextEdit@N"，取不到 -> 玩家写的字永远进不了 _back_text
	_back_text_edit.name = "TextEdit"
	# 不要写 max_length：TextEdit 没有这个属性（那是 LineEdit 的），
	# 赋值会抛错并中断本函数。200 字上限由 _on_back_text_changed 里的 substr 兜住。
	# 选了【放手】的话，占位提示换成那句没写上去的话：它摆在那儿，灰色的，
	# 拿不拿随玩家。留门 / 未竟用通用提示。
	_back_text_edit.placeholder_text = Localization.t("back_break") \
			if GameManager.ending_id == "break" else Localization.t("back_placeholder")
	_back_text_edit.add_theme_font_size_override("font_size", 20)
	_back_text_edit.add_theme_color_override("background_color", Color(0.16, 0.15, 0.14, 1.0))
	_back_text_edit.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	# 输入框原来占 h*0.32（720p 上 230px，约十一行）。200 字的上限用不满这个高度，
	# 而多出来的每一行都是从底下那张预览的份额里扣的 —— 见 `_add_back_thumb`。
	_place_top_wide(vw, _back_text_edit, h * 0.22, h * 0.24, minf(vw * 0.7, 700.0))
	# 先塞默认文案再接信号：玩家拿到的是「可以改的定稿」，
	# 而不是空框加一句占位提示。顺序反过来会先触发一次 text_changed，
	# 把刚赋进去的值原样读回 _back_text（无害，但没必要）。
	_back_text_edit.text = _back_text
	_back_text_edit.text_changed.connect(_on_back_text_changed)
	_back_editor.add_child(_back_text_edit)

	# 两个按钮**并排**摆，不是叠着摆。
	# 叠着的时候每个按钮各吃 56/44 的行高，两行就是 100px 上下，全从底下那张
	# 预览的份额里扣：720p 上预览只剩一百五十几像素、宽 200 —— 一张 200px 宽的
	# 卡上写满字之后每行只剩七来个像素，根本读不出自己写了什么，"所见即导出"
	# 就成了一句空话。并排放省下的那一行才是给预览的。
	var bw := minf(vw * 0.22, 280.0)
	var bgap := 24.0
	var bx := (vw - bw * 2.0 - bgap) * 0.5
	var by := h * THUMB_BTN_Y_FRAC

	# 确认按钮
	_back_confirm_btn = Button.new()
	_back_confirm_btn.text = Localization.t("back_confirm")
	_place_fixed(_back_confirm_btn, bx, by, bw, THUMB_BTN_H)
	_back_confirm_btn.pressed.connect(_on_back_confirmed)
	_back_editor.add_child(_back_confirm_btn)

	# 跳过按钮
	_back_skip_btn = Button.new()
	_back_skip_btn.text = Localization.t("back_skip")
	_place_fixed(_back_skip_btn, bx + bw + bgap, by, bw, THUMB_BTN_H)
	_back_skip_btn.pressed.connect(_on_back_confirmed)
	_back_editor.add_child(_back_skip_btn)

	_add_back_thumb(vw, h)


## 写字时的卡片缩略图。
##
## 原来这一屏是「一个空框 + 两个按钮」：玩家在 200 字的框里打字，底下什么都没有，
## 不知道自己写的东西印在卡上是什么样。缩略图用的是导出同一个 SubViewport 的纹理，
## 所以它不是示意图——所见即导出的那张背面。
##
## 尺寸是**从"按钮下沿到屏底"那段空当反推的**，不是拍一个常数。
## 这一屏的元素全是 h 的分数，屏越矮留给预览的就越少；而预览的价值全在字大不
## 大（"所见即导出"这句话的意思是玩家认得出自己写的字），一旦为了塞下去把它
## 缩回 200px 宽，它就退化成一张分不出内容的色块，那不如没有。按宽度算一遍、
## 按高度算一遍，取小的那个，两头都不越界。
##
## 常量放在 `_show_back_editor()` 摆按钮的地方也要用，所以是文件级的：
## 预览的高度就是从按钮的下沿量上去的，两边各写一份必然会漂。
const THUMB_BTN_Y_FRAC := 0.50
const THUMB_BTN_H := 56.0

func _add_back_thumb(vw: float, h: float) -> void:
	var pad := 14.0
	var cap_h := 20.0
	var gap := 5.0
	var breath := 10.0
	# 高度这一侧是硬的：预览 + 说明行必须整块落在按钮下沿以下
	var avail := h - (h * THUMB_BTN_Y_FRAC + THUMB_BTN_H) - breath - pad - gap - cap_h
	# 宽度这一侧只是别在超宽屏上糊成一片
	var by_w := minf(vw * 0.36, 460.0)
	var th := minf(by_w * 9.0 / 16.0, maxf(avail, 60.0))
	var tw := th * 16.0 / 9.0
	var thumb_y := h - pad - th
	var side := maxf((vw - tw) * 0.5, 0.0)

	var cap := Label.new()
	cap.text = Localization.t("back_preview_caption")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 14)
	cap.add_theme_color_override("font_color", Color(0.72, 0.68, 0.60))
	_place_fixed(cap, side, thumb_y - gap - cap_h, tw, cap_h)
	_back_editor.add_child(cap)
	_back_thumb_caption = cap

	_back_thumb = TextureRect.new()
	_back_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_back_thumb.stretch_mode = TextureRect.STRETCH_SCALE
	# 只是看，不接受点击 —— 否则它会盖在按钮的命中区上
	_back_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_fixed(_back_thumb, side, thumb_y, tw, th)
	_back_editor.add_child(_back_thumb)
	_refresh_back_thumb()
	# 刚入树的这一帧 SubViewport 还没渲染出这一屏的字，_process 会再抓一次
	_back_thumb_dirty = true


## 抓一帧背面纹理。SubViewport 渲染完要到下一帧才看得到新字，所以每次改字只置
## dirty，由 _process 按 THUMB_REFRESH_SEC 的节奏去抓（get_image 是 GPU 回读，
## 每个键击都抓会掉帧）。
const THUMB_REFRESH_SEC := 0.12

func _refresh_back_thumb() -> void:
	if _back_thumb == null or not is_instance_valid(_back_thumb) or _back_viewport == null:
		return
	# 判 texture 是不是 null，不能直接 get_texture().get_image()：dummy renderer
	# 下 get_texture() 返回 null，链上去 get_image() 会抛 "Parameter t is null"
	# 把这个函数从中间掐断，下面的 dirty 清不掉。
	var tex := _back_viewport.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	_back_thumb.texture = ImageTexture.create_from_image(img)


## 抓帧前必须先等两帧。
##
## set_back_text() 只发 queue_redraw，SubViewport 要到下一帧才真的把新字画出来。
## 在 _process 里当场回读，拿到的是改字之前那张——缩略图会一直停在没字的卡上，
## 而且因为那一次已经"刷新过"了，dirty 被清掉后再没人去补。_on_back_confirmed()
## 末尾等两帧是同一个道理。
func _grab_back_thumb() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_back_thumb_dirty = false
	_refresh_back_thumb()


func _process(delta: float) -> void:
	if not _back_thumb_dirty or _back_thumb == null or not is_instance_valid(_back_thumb):
		return
	_back_thumb_wait -= delta
	if _back_thumb_wait <= 0.0:
		_back_thumb_wait = THUMB_REFRESH_SEC
		_grab_back_thumb()


## 铺满父节点。必须显式写 anchor_* / offset_*，只赋 anchors_preset 不会改锚点。
func _stretch_full(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0


## 把一个控件排成「整行铺满、顶部锚定」的一行：纵向从 y 起、高 height；
## width > 0 时在整行内水平居中到该宽度（否则真正铺满整行）。
## 只写 offset_*，不写 size —— size 的 setter 会去改 offset，
## 而 offset_top 是在 size 之后赋值的，两步一起用会互相覆盖，算出负高度。
func _place_top_wide(parent_w: float, c: Control, y: float, height: float, width: float = -1.0) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 0.0
	c.offset_top = y
	c.offset_bottom = y + height
	if width > 0.0:
		var side := maxf((parent_w - width) * 0.5, 0.0)
		c.offset_left = side
		c.offset_right = -side


## 按绝对坐标放一个固定尺寸控件。锚点必须显式写全：
## set_anchors_preset 不改锚点，而 size 和 offset 会互相覆盖（见 _place_top_wide）。
func _place_fixed(c: Control, x: float, y: float, width: float, height: float) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = x
	c.offset_right = x + width
	c.offset_top = y
	c.offset_bottom = y + height


func _on_back_text_changed() -> void:
	if _back_text_edit == null:
		return
	_back_text = _back_text_edit.text.substr(0, 200)
	# 同步给背面卡片，缩略图才有东西可看。原来只在确认时才 set_back_text()，
	# 于是写字的整个过程里 SubViewport 一直是选完那一句的旧字。
	if _back_postcard != null:
		_back_postcard.set_back_text(_back_text)
	_back_thumb_dirty = true


func _on_back_confirmed() -> void:
	# 直接从 TextEdit 取，不要只靠 text_changed 信号：程序化赋值 .text 不会发信号，
	# 那样 _back_text 会停在空串，导出的背面是空白框。
	if _back_text_edit != null:
		_on_back_text_changed()
	if _back_postcard != null:
		_back_postcard.set_back_text(_back_text)
	if _back_editor != null:
		_back_editor.queue_free()
		_back_editor = null
	_back_title = null
	_back_text_edit = null
	_back_confirm_btn = null
	_back_skip_btn = null
	_back_thumb = null
	_back_thumb_caption = null
	_back_thumb_dirty = false
	# set_back_text() 只发 queue_redraw，SubViewport 的纹理要到下一帧才更新。
	# 同一帧里立刻截图拿到的是改字之前的画面：预览是空的框，导出也丢字。
	await get_tree().process_frame
	await get_tree().process_frame
	_show_back_editor_preview()


func _show_back_editor_preview() -> void:
	# 重复调用时先清掉上一份，避免预览和返回按钮越叠越多
	_clear_back_preview()

	# 隐藏正面按钮，切到预览背面
	$VBox.visible = false
	_postcard.visible = false
	_variant_hint.visible = false

	var vp := get_viewport_rect().size
	var pw := minf(vp.x * 0.72, 900.0)
	var ph := pw * 9.0 / 16.0

	var preview := Control.new()
	preview.z_index = 50
	preview.anchor_left = 0.5
	preview.anchor_top = 0.5
	preview.anchor_right = 0.5
	preview.anchor_bottom = 0.5
	preview.offset_left = -pw * 0.5
	preview.offset_top = -ph * 0.5
	preview.offset_right = pw * 0.5
	preview.offset_bottom = ph * 0.5
	add_child(preview)
	_back_preview = preview

	var img := _back_viewport.get_texture().get_image()
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(img)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.anchor_left = 0.0
	rect.anchor_top = 0.0
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.offset_left = 0.0
	rect.offset_top = 0.0
	rect.offset_right = 0.0
	rect.offset_bottom = 0.0
	preview.add_child(rect)

	# 返回编辑按钮。锚点偏移要显式写全，set_anchors_preset 不会改锚点。
	_back_to_front_btn = Button.new()
	_back_to_front_btn.text = Localization.t("back_to_front")
	_back_to_front_btn.anchor_left = 1.0
	_back_to_front_btn.anchor_top = 1.0
	_back_to_front_btn.anchor_right = 1.0
	_back_to_front_btn.anchor_bottom = 1.0
	_back_to_front_btn.offset_left = -220.0
	_back_to_front_btn.offset_right = -20.0
	_back_to_front_btn.offset_top = -80.0
	_back_to_front_btn.offset_bottom = -20.0
	_back_to_front_btn.pressed.connect(_on_back_to_front)
	add_child(_back_to_front_btn)


func _clear_back_preview() -> void:
	if _back_preview != null and is_instance_valid(_back_preview):
		_back_preview.queue_free()
	_back_preview = null
	if _back_to_front_btn != null and is_instance_valid(_back_to_front_btn):
		_back_to_front_btn.queue_free()
	_back_to_front_btn = null
	# 缩略图挂在 _back_editor 上，随它一起走；这里只是把引用摘干净，
	# 免得 _process 拿着一个已 free 的 TextureRect 继续 get_image()。
	_back_thumb = null
	_back_thumb_dirty = false


func _on_back_to_front() -> void:
	$VBox.visible = true
	_postcard.visible = true
	_clear_back_preview()


func _on_export_pressed() -> void:
	AudioManager.play_sfx("export")

	# 先导正面
	var img_front = _export_viewport.get_texture().get_image()
	var img_back = _back_viewport.get_texture().get_image()

	if OS.has_feature("web"):
		# Web: 先下正面，再下背面（两次 Blob 下载）
		_export_two_images_web(img_front, img_back)
		_show_toast(Localization.t("exported"))
	else:
		# 桌面: 保存到 gift_188_postcard/ 文件夹
		var base_dir := "user://gift_188_postcard"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_dir))
		var path_front = base_dir + "/gift_188_front.png"
		var path_back = base_dir + "/gift_188_back.png"
		var err_front = img_front.save_png(path_front)
		var err_back = img_back.save_png(path_back)
		if err_front == OK and err_back == OK:
			var gpath = ProjectSettings.globalize_path(base_dir)
			_show_toast(Localization.t("saved_to") + gpath)
			OS.shell_open(gpath)
		else:
			_show_toast(Localization.t("export_failed"))


func _export_two_images_web(img_front: Image, img_back: Image) -> void:
	var png_front = img_front.save_png_to_buffer()
	var png_back = img_back.save_png_to_buffer()
	var b64_front = Marshalls.raw_to_base64(png_front)
	var b64_back = Marshalls.raw_to_base64(png_back)

	var js_front = (
		"fetch('data:image/png;base64," + b64_front + "')" +
		".then(function(r){return r.blob();})" +
		".then(function(b){var u=URL.createObjectURL(b);" +
		"var a=document.createElement('a');a.href=u;a.download='gift_188_front.png';" +
		"document.body.appendChild(a);a.click();" +
		"setTimeout(function(){URL.revokeObjectURL(u);document.body.removeChild(a);},1500);});"
	)
	var js_back = (
		"fetch('data:image/png;base64," + b64_back + "')" +
		".then(function(r){return r.blob();})" +
		".then(function(b){var u=URL.createObjectURL(b);" +
		"var a=document.createElement('a');a.href=u;a.download='gift_188_back.png';" +
		"document.body.appendChild(a);a.click();" +
		"setTimeout(function(){URL.revokeObjectURL(u);document.body.removeChild(a);},1500);});"
	)
	JavaScriptBridge.eval(js_front)
	await get_tree().create_timer(0.3, false).timeout
	JavaScriptBridge.eval(js_back)


func _on_share_pressed() -> void:
	# 复制分享文案到剪贴板
	# 一个 key，中英各存一份。写成 `share_text_zh` / `share_text_en` 两个 key 的做法
	# 看着更直白，实际是在表里埋一个陷阱：两份表各存各的，于是中文表里没有
	# `share_text_en`、英文表里躺着一份没人读的 `share_text_zh`，两边的 key 集合
	# 永远对不上（`verify_story.gd` 第 1 节量的就是这个）。而 `t()` 查不到 key 时
	# 返回 key 自己，不报错——真有人把这里"简化"成 t("share_text") 之外的写法时，
	# 屏幕上出现的就是 "share_text_en" 这五个字母。
	var share_text = Localization.t("share_text")
	DisplayServer.clipboard_set(share_text)
	_share_btn.text = Localization.t("copied")
	await get_tree().create_timer(1.5, false).timeout
	_share_btn.text = Localization.t("share")


func _on_restart_pressed() -> void:
	# 回执必须赶在 reset 之前：go_to_gift_box() 会把 seen_stations / collected /
	# earned_tags / ending_id 一起清掉，清完之后就没有任何东西能回答
	# 「这一趟我漏了什么」了。
	if _recap_worth_showing():
		_show_run_recap()
		return
	GameManager.go_to_gift_box()


func _show_toast(msg: String) -> void:
	_toast_label.text = msg
	_toast_label.modulate.a = 0.0
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_toast_label, "modulate:a", 1.0, 0.3)
	tw.tween_property(_toast_label, "scale", Vector2(1.05, 1.05), 0.2).set_trans(Tween.TRANS_BACK)
	await get_tree().create_timer(2.5, false).timeout
	tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_toast_label, "modulate:a", 0.0, 0.3)
	tw.tween_property(_toast_label, "scale", Vector2(0.95, 0.95), 0.25)
	await tw.finished
	_toast_label.scale = Vector2.ONE
