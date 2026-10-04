extends Control
## PausePanel — 暂停菜单 (PRD F-32)
## 全屏黑底 + 中央 Panel：继续 / 结束这一趟 / 重新开始 / 设置 / 语言 / 画质
## 挂载：World3D/PausePanel，初始 visible=false，由 World3D.toggle_pause() 控制
##
## **三档静音按钮原来在这儿，现在在设置面板里**（音量滑杆拉到 0 就是静音，
## 两件事是同一个状态，见 `AudioManager`）。收掉这五行不只是为了清爽：
## 量过 720p 下这一列 中文 need=432 / 可用 464、英文 need=451 / 可用 464，
## **英文只剩 13px**，而这一列现在每一行都是 30px 上下——留着它们的话
## 任何一行新内容都会静默溢出（VBox 装不下时不报错，只把最下面那几行
## 顶出面板下沿，而那几行正好是新加的）。
## 行数与高度的回归在 `verify_quality_settings.gd` 第 5 节。

@onready var _continue_btn: Button = $Overlay/Panel/VBox/ContinueBtn
@onready var _restart_btn: Button = $Overlay/Panel/VBox/RestartBtn
@onready var _settings_btn: Button = $Overlay/Panel/VBox/HelpBtn
@onready var _language_btn: Button = $Overlay/Panel/VBox/LanguageBtn
@onready var _quality_btn: Button = $Overlay/Panel/VBox/QualityBtn
@onready var _quality_hint: Label = $Overlay/Panel/VBox/QualityHintLabel
@onready var _title_label: Label = $Overlay/Panel/VBox/TitleLabel

var _finish_btn: Button = null
var _tier_label: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_finish_btn = _make_finish_btn()
	_tier_label = _make_tier_label()
	_continue_btn.pressed.connect(_on_continue_pressed)
	_restart_btn.pressed.connect(_on_restart_pressed)
	_settings_btn.pressed.connect(_on_settings_pressed)
	_language_btn.pressed.connect(_on_language_pressed)
	_quality_btn.pressed.connect(_on_quality_pressed)
	Localization.language_changed.connect(_apply_language)
	# 必须在这里连：World3D.tscn 里 PausePanel 那个节点没有 [connection] 段，
	# 而 _on_visibility_changed 是靠信号才会在"面板被打开"那一刻跑到。
	# 没连的话这个函数从头到尾没人调用——按钮的开场状态也就永远不刷新。
	visibility_changed.connect(_on_visibility_changed)
	_apply_language()
	_update_quality_button()


## 「结束这一趟」——这一趟现在**只能**由刷满五座碎片驿站结束（那是重玩钩子，
## 不该被玩家的耐心决定），所以总得留一个玩家自己喊停的出口。否则低档明信片
## （初旅/探索者/朝圣者/大师）就成了永远走不到的死代码，PostcardVariant 的前四档
## 全部作废，而且玩家只剩"重新开始"——把这一趟从头再来一遍。
##
## 代码里建而不是摆进 .tscn：这个按钮的可见性依赖存档（收过几块），场景文件里
## 存不下这个条件。
func _make_finish_btn() -> Button:
	var btn = Button.new()
	btn.name = "FinishBtn"
	btn.custom_minimum_size = Vector2(0, 44)
	btn.pressed.connect(_on_finish_pressed)
	var vbox := _continue_btn.get_parent()
	vbox.add_child(btn)
	vbox.move_child(btn, _continue_btn.get_index() + 1)
	return btn


## 一块碎片都还没拿到时不许收工：那时候做出来的是一张空卡，
## 而"空卡"这个状态在 EndCard 上没有任何说法，只会让玩家以为按错了。
func _refresh_finish_btn() -> void:
	var have := int(GameManager.get_collected_count()) > 0
	_finish_btn.visible = have
	_finish_btn.text = Localization.t("finish_run")
	_finish_btn.tooltip_text = Localization.t("finish_run_hint")
	_refresh_tier_label()


## 「此刻这一趟会做出哪一档明信片，还差几步到完满」——**收工这个决定发生在这一屏上，
## 而这个数以前只在集齐面板的一句话里出现过**（还是另一个时刻、另一块板子）。
## 玩家在这里决定"现在停还是再骑一趟"，屏上却只有一个按钮：按下去会收工，
## 按之前他知道收工能得到什么吗？不知道——五档的名字 `Localization` 里一个字都没有，
## README 还把它写成"分四档"，把唯一有玩法含义的完满整个漏在外面。
##
## 跟 FinishBtn 一样代码里建：它跟着按钮一起显隐，而那个条件在存档里。
##
## **`custom_minimum_size.x` 是必须的，不是排版洁癖**：带 `autowrap_mode` 的 Label
## 不给这个数，最小宽度是 1px，自动折行会**逐字**断成十几行（见文件头那条）。
func _make_tier_label() -> Label:
	var lbl := Label.new()
	lbl.name = "TierLabel"
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var vbox := _continue_btn.get_parent()
	var want: float = vbox.get_combined_minimum_size().x
	lbl.custom_minimum_size = Vector2(maxf(want, 440.0), 0)
	vbox.add_child(lbl)
	vbox.move_child(lbl, _finish_btn.get_index() + 1)
	return lbl


func _refresh_tier_label() -> void:
	if _tier_label == null:
		return
	_tier_label.visible = _finish_btn.visible
	var v := PostcardVariant.compute_variant()
	var left := PostcardVariant.visits_to_full()
	if left <= 0:
		_tier_label.text = Localization.t("tier_full")
	else:
		_tier_label.text = Localization.t("tier_now") % [
			Localization.t(PostcardVariant.tier_name_key(v)),
			v + 1, PostcardVariant.tier_count(), left,
		]


func _on_finish_pressed() -> void:
	AudioManager.set_paused_bgm(false)
	GameManager.go_to_end_card()


func _apply_language() -> void:
	_title_label.text = Localization.t("pause_title")
	_continue_btn.text = Localization.t("continue")
	_restart_btn.text = Localization.t("restart")
	_settings_btn.text = Localization.t("settings")
	_language_btn.text = "%s  %s" % [Localization.t("language"), Localization.t("language_current")]
	if _quality_hint != null:
		_quality_hint.text = Localization.t("quality_hint")
	# 切语言时这一行必须跟着重算：档名是玩家看得见的五个词，
	# 停在中文那一侧等于英文界面里这一行还是半个中文。
	_refresh_tier_label()


func _on_language_pressed() -> void:
	Localization.set_language("zh" if Localization.is_english() else "en")


func _on_visibility_changed() -> void:
	if visible:
		_update_quality_button()
		_refresh_finish_btn()


func _on_continue_pressed() -> void:
	get_parent().toggle_pause()


func _on_restart_pressed() -> void:
	GameManager.go_to_gift_box()


## 打开的是**共享**的那一块设置面板，和顶栏右上角那个「?」进的是同一块。
## 两块面板各写一份的话，键位表立刻又多一份——而它已经有四次前科。
func _on_settings_pressed() -> void:
	_settings_panel().open()


func _settings_panel() -> Control:
	return get_parent().get_node_or_null("SettingsPanel")


func _on_quality_pressed() -> void:
	# 落盘（persist=true）：玩家自己挑的档位要留下来。而阴影是**当场**生效的，
	# 所以要再推一遍给已经建好的世界——植被半径写回 radius_override，
	# 下一趟 setup() 才读它（面板上那一行提示就是在说这件事）。
	QualitySettings.set_tier((QualitySettings.tier + 1) % QualitySettings.TIER_COUNT, true)
	QualitySettings.apply_to_world(get_parent())
	_update_quality_button()


func _update_quality_button() -> void:
	if _quality_btn == null:
		return
	_quality_btn.text = "%s  %s" % [Localization.t("quality"),
			Localization.t(str(QualitySettings.tier_name_key()))]
	if _quality_hint != null:
		_quality_hint.text = Localization.t("quality_hint")
