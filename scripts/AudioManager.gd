extends Node
## AudioManager — BGM / SFX 主控 + 三档静音
## signal mute_changed 通知 HUD3D / PausePanel 同步按钮文案
## 消费 GameManager 注册的 mute action (KEY_M)

signal mute_changed


const SFX_VOICES := 6

var _bgm_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _muted = false
var _bgm_muted = false
var _sfx_muted = false
var _bgm_normal_db = -6.0
var _bus_idx = 0


func _ready() -> void:
	_bus_idx = AudioServer.get_bus_index("Master")

	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Master"
	_bgm_player.volume_db = _bgm_normal_db
	_bgm_player.process_mode = AudioStreamPlayer.PROCESS_MODE_ALWAYS
	add_child(_bgm_player)
	_bgm_player.finished.connect(_on_bgm_finished)

	# 池子而不是单个 player：琴小游戏要连着敲 4 个音，单 player 下一个音会把
	# 上一个从中间掐断，听感是"卡带"。轮转取，播完的槽自然被复用。
	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = 0.0
		p.process_mode = AudioStreamPlayer.PROCESS_MODE_ALWAYS
		add_child(p)
		_sfx_players.append(p)

	_load_bgm()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_M:
		toggle_mute()
		get_viewport().set_input_as_handled()


func _load_bgm() -> void:
	var stream = _load_stream("res://assets/audio/bgm.ogg")
	if stream != null:
		_bgm_player.stream = stream


func play_bgm() -> void:
	if _muted or _bgm_muted:
		return
	if _bgm_player.stream != null and not _bgm_player.playing:
		_bgm_player.play()


func _on_bgm_finished() -> void:
	if not _muted and not _bgm_muted and _bgm_player.stream != null:
		_bgm_player.play()


func stop_bgm() -> void:
	_bgm_player.stop()


func play_sfx(name: String) -> void:
	if _muted or _sfx_muted:
		return
	var stream = _load_stream("res://assets/audio/sfx/" + name + ".ogg")
	if stream == null:
		stream = _load_stream("res://assets/audio/sfx/" + name + ".mp3")
	if stream != null:
		var p := _sfx_players[_sfx_next]
		_sfx_next = (_sfx_next + 1) % _sfx_players.size()
		p.stream = stream
		p.play()


func _load_stream(path: String) -> AudioStream:
	if FileAccess.file_exists(path):
		return load(path)
	return null


func set_muted(val: bool) -> void:
	_muted = val
	AudioServer.set_bus_mute(_bus_idx, val)
	_bgm_player.playing = not val


func is_muted() -> bool:
	return _muted


func toggle_mute() -> void:
	set_muted(not _muted)
	mute_changed.emit()


func set_bgm_muted(val: bool) -> void:
	_bgm_muted = val
	_bgm_player.playing = not _muted and not val


func is_bgm_muted() -> bool:
	return _bgm_muted


func toggle_bgm_mute() -> bool:
	set_bgm_muted(not _bgm_muted)
	mute_changed.emit()
	return _bgm_muted


func set_sfx_muted(val: bool) -> void:
	_sfx_muted = val


func is_sfx_muted() -> bool:
	return _sfx_muted


func toggle_sfx_mute() -> bool:
	set_sfx_muted(not _sfx_muted)
	mute_changed.emit()
	return _sfx_muted


func set_paused_bgm(v: bool) -> void:
	if v:
		_bgm_player.volume_db = -18.0
	else:
		_bgm_player.volume_db = _bgm_normal_db


func set_bgm_volume_db(db: float) -> void:
	_bgm_normal_db = db
	_bgm_player.volume_db = db
