extends Control
## PausePanel — 暂停菜单 (PRD F-32)
## 全屏黑底 + 中央 Panel：继续 / 重新开始 / 操作说明 / 全局静音 / BGM 静音 / SFX 静音
## 挂载：World3D/PausePanel，初始 visible=false，由 World3D.toggle_pause() 控制

@onready var _continue_btn: Button = $Overlay/Panel/VBox/ContinueBtn
@onready var _restart_btn: Button = $Overlay/Panel/VBox/RestartBtn
@onready var _help_btn: Button = $Overlay/Panel/VBox/HelpBtn
@onready var _mute_btn: Button = $Overlay/Panel/VBox/MuteBtn
@onready var _bgm_btn: Button = $Overlay/Panel/VBox/BgmBtn
@onready var _sfx_btn: Button = $Overlay/Panel/VBox/SfxBtn
@onready var _language_btn: Button = $Overlay/Panel/VBox/LanguageBtn
@onready var _title_label: Label = $Overlay/Panel/VBox/TitleLabel

var _help_overlay: Control = null
var _help_overlay_label: Label = null
var _finish_btn: Button = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_finish_btn = _make_finish_btn()
	_continue_btn.pressed.connect(_on_continue_pressed)
	_restart_btn.pressed.connect(_on_restart_pressed)
	_help_btn.pressed.connect(_on_help_pressed)
	_mute_btn.pressed.connect(_on_mute_pressed)
	_bgm_btn.pressed.connect(_on_bgm_pressed)
	_sfx_btn.pressed.connect(_on_sfx_pressed)
	_language_btn.pressed.connect(_on_language_pressed)
	AudioManager.mute_changed.connect(_update_mute_buttons)
	Localization.language_changed.connect(_apply_language)
	# 必须在这里连：World3D.tscn 里 PausePanel 那个节点没有 [connection] 段，
	# 而 _on_visibility_changed 是靠信号才会在"面板被打开"那一刻跑到。
	# 没连的话这个函数从头到尾没人调用——静音按钮的开场状态也就永远不刷新。
	visibility_changed.connect(_on_visibility_changed)
	_apply_language()
	_help_overlay = _make_help_overlay()
	add_child(_help_overlay)
	_help_overlay_label = _help_overlay.get_node("HelpPanel/HelpLabel")
	_help_overlay.visible = false
	_update_mute_buttons()


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


func _on_finish_pressed() -> void:
	AudioManager.set_paused_bgm(false)
	GameManager.go_to_end_card()


func _make_help_overlay() -> Control:
	var overlay = Control.new()
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_help_overlay_input)

	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_help_overlay_input)
	overlay.add_child(bg)

	var panel = Panel.new()
	# 名字必须显式给出:_apply_language 靠 get_node("HelpPanel/HelpLabel") 取回这个 Label,
	# 用 .new() 建出来的匿名节点名字是 @Panel@2 之类的,路径永远取不到。
	panel.name = "HelpPanel"
	panel.anchor_left = 0.25
	panel.anchor_top = 0.2
	panel.anchor_right = 0.75
	panel.anchor_bottom = 0.8
	panel.z_index = 10
	overlay.add_child(panel)

	var lbl = Label.new()
	lbl.name = "HelpLabel"
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.offset_left = 16.0
	lbl.offset_top = 12.0
	lbl.offset_right = -16.0
	lbl.offset_bottom = -12.0
	lbl.text = Localization.t("help_overlay")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 15 if Localization.is_english() else 16)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	panel.add_child(lbl)
	return overlay


func _apply_language() -> void:
	_title_label.text = Localization.t("pause_title")
	_continue_btn.text = Localization.t("continue")
	_restart_btn.text = Localization.t("restart")
	_help_btn.text = Localization.t("help")
	_language_btn.text = "%s  %s" % [Localization.t("language"), Localization.t("language_current")]
	_update_mute_buttons()
	if _help_overlay_label != null:
		_help_overlay_label.text = Localization.t("help_overlay")


func _on_language_pressed() -> void:
	Localization.set_language("zh" if Localization.is_english() else "en")


func _on_help_overlay_input(_event: InputEvent) -> void:
	if _help_overlay.visible:
		_help_overlay.visible = false


func _on_visibility_changed() -> void:
	if visible:
		_update_mute_buttons()
		_refresh_finish_btn()


func _on_continue_pressed() -> void:
	get_parent().toggle_pause()


func _on_restart_pressed() -> void:
	GameManager.go_to_gift_box()


func _on_help_pressed() -> void:
	_help_overlay.visible = not _help_overlay.visible


func _on_mute_pressed() -> void:
	AudioManager.toggle_mute()
	_update_mute_buttons()


func _on_bgm_pressed() -> void:
	AudioManager.toggle_bgm_mute()
	_update_mute_buttons()


func _on_sfx_pressed() -> void:
	AudioManager.toggle_sfx_mute()
	_update_mute_buttons()


func _update_mute_buttons() -> void:
	var on = Localization.t("on")
	var off = Localization.t("off")
	_mute_btn.text = "%s [%s]" % [Localization.t("mute"), on if AudioManager.is_muted() else off]
	_bgm_btn.text = "%s [%s]" % [Localization.t("bgm_mute"), on if AudioManager.is_bgm_muted() else off]
	_sfx_btn.text = "%s [%s]" % [Localization.t("sfx_mute"), on if AudioManager.is_sfx_muted() else off]
