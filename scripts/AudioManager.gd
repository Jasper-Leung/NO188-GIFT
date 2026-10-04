extends Node
## AudioManager — BGM / SFX 主控 + 三档静音
## signal mute_changed 通知 HUD3D / PausePanel 同步按钮文案
## 消费 GameManager 注册的 mute action (KEY_M)

signal mute_changed


const SFX_VOICES := 6

## BGM 相对满音量的固定偏移。不是装饰：满音量下 BGM 会盖过音效，
## 而这三个数是当初配好的混音平衡（原来是 `_bgm_normal_db = -6.0` 写死）。
## 音量滑杆量的 0~1 乘上去，所以滑杆停在 100% 时听感和今天一模一样。
const BGM_BASE_DB := -6.0
const SFX_BASE_DB := 0.0

## 暂停时压低 BGM 的量，**相对**当前音量减这么多分贝。
##
## 原来写死 -18.0 dB（绝对值），在只有开关的时候碰巧没问题（正常就是 -6，
## 减深一点更安静）。有了音量滑杆之后那是**反的**：玩家把 BGM 拉到 20%
## （约 -20 dB），暂停时写回 -18 就比他还响一档 —— 暂停反而变吵。
const PAUSE_DUCK_DB := 12.0

## 0 线性音量落在这个分贝上而不是 -inf：`linear_to_db(0)` 是负无穷，
## 而负无穷的 `volume_db` 在混音里会算出 NaN。-80 已经听不见，且是有限数。
const SILENT_DB := -80.0

## 开局的默认音量。不是 100%：满音量对一片轻音乐太吵，而这是默认值不是上限。
const DEFAULT_VOLUME := 0.8

const SAVE_PATH_CFG := "user://settings.cfg"

var _bgm_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _muted = false
var _bgm_volume := DEFAULT_VOLUME
var _sfx_volume := DEFAULT_VOLUME
## 静音前玩家自己选的那一档。取消静音要回到那个数而不是回到 100%——
## 顶栏/HUD 上那个「♪」按钮是玩家在骑行途中最常按的一个。
var _bgm_last_nonzero := DEFAULT_VOLUME
var _sfx_last_nonzero := DEFAULT_VOLUME
var _bus_idx = 0
var _ducked := false


func _ready() -> void:
	_bus_idx = AudioServer.get_bus_index("Master")
	_load_volumes()

	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Master"
	_bgm_player.process_mode = AudioStreamPlayer.PROCESS_MODE_ALWAYS
	add_child(_bgm_player)
	_bgm_player.finished.connect(_on_bgm_finished)

	# 池子而不是单个 player：琴小游戏要连着敲 4 个音，单 player 下一个音会把
	# 上一个从中间掐断，听感是"卡带"。轮转取，播完的槽自然被复用。
	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.process_mode = AudioStreamPlayer.PROCESS_MODE_ALWAYS
		add_child(p)
		_sfx_players.append(p)

	_apply_volumes()
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
	if _muted or _bgm_volume <= 0.0:
		return
	if _bgm_player.stream != null and not _bgm_player.playing:
		_bgm_player.play()


func _on_bgm_finished() -> void:
	if not _muted and _bgm_volume > 0.0 and _bgm_player.stream != null:
		_bgm_player.play()


func stop_bgm() -> void:
	_bgm_player.stop()


func play_sfx(name: String) -> void:
	if _muted or _sfx_volume <= 0.0:
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


# ---- 音量：0~1 线性，滑杆与静音开关共用这一个状态 ----
#
# 静音**不是**另一个布尔，它就是滑杆拉到 0。原来的 `_bgm_muted` 是个独立标志，
# 于是"静音开着而滑杆显示 80%"这种自相矛盾是允许出现的——而顶栏那个「♪ 开」
# 读的就是那个布尔，玩家能同时看见两个互相打架的真相。合成一处之后两边
# 不可能对不上（`is_bgm_muted()` 现算 `_bgm_volume <= 0`）。


func bgm_volume() -> float:
	return _bgm_volume


func sfx_volume() -> float:
	return _sfx_volume


func set_bgm_volume(v: float, persist: bool = true) -> void:
	_bgm_volume = clampf(v, 0.0, 1.0)
	if _bgm_volume > 0.0:
		_bgm_last_nonzero = _bgm_volume
	_bgm_player.playing = not _muted and _bgm_volume > 0.0
	_apply_volumes()
	if persist:
		_save_volume("bgm", _bgm_volume)
	mute_changed.emit()


func set_sfx_volume(v: float, persist: bool = true) -> void:
	_sfx_volume = clampf(v, 0.0, 1.0)
	if _sfx_volume > 0.0:
		_sfx_last_nonzero = _sfx_volume
	_apply_volumes()
	if persist:
		_save_volume("sfx", _sfx_volume)
	mute_changed.emit()


## 静音 = 音量 0。取消静音回到静音前那一档，不是回到 100%——
## 玩家在骑行途中按 HUD 上那个「♪」时，100% 常常比他自己选的那一档响得多。
func set_bgm_muted(val: bool) -> void:
	if val:
		set_bgm_volume(0.0)
	else:
		set_bgm_volume(_bgm_last_nonzero)


func is_bgm_muted() -> bool:
	return _bgm_volume <= 0.0


func toggle_bgm_mute() -> bool:
	set_bgm_muted(_bgm_volume > 0.0)
	return is_bgm_muted()


func set_sfx_muted(val: bool) -> void:
	if val:
		set_sfx_volume(0.0)
	else:
		set_sfx_volume(_sfx_last_nonzero)


func is_sfx_muted() -> bool:
	return _sfx_volume <= 0.0


func toggle_sfx_mute() -> bool:
	set_sfx_muted(_sfx_volume > 0.0)
	return is_sfx_muted()


func set_paused_bgm(v: bool) -> void:
	_ducked = v
	_apply_volumes()


## 线性 0~1 落到 dB。静音那一端落 `SILENT_DB` 而不是负无穷。
static func _to_db(linear: float, base_db: float) -> float:
	if linear <= 0.0001:
		return SILENT_DB
	return base_db + linear_to_db(linear)


func _bgm_db() -> float:
	var db := _to_db(_bgm_volume, BGM_BASE_DB)
	return db - PAUSE_DUCK_DB if _ducked else db


func _sfx_db() -> float:
	return _to_db(_sfx_volume, SFX_BASE_DB)


func _apply_volumes() -> void:
	if _bgm_player == null:
		return
	_bgm_player.volume_db = _bgm_db()
	for p in _sfx_players:
		p.volume_db = _sfx_db()


func _load_volumes() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH_CFG) != OK:
		return
	var b := float(cfg.get_value("audio", "bgm", -1.0))
	var s := float(cfg.get_value("audio", "sfx", -1.0))
	if b >= 0.0:
		_bgm_volume = clampf(b, 0.0, 1.0)
		_bgm_last_nonzero = maxf(_bgm_volume, 0.01)
	if s >= 0.0:
		_sfx_volume = clampf(s, 0.0, 1.0)
		_sfx_last_nonzero = maxf(_sfx_volume, 0.01)


## 读-改-写而不是 `ConfigFile.save()` 覆盖：`QualitySettings` 的画质档位
## 存在**同一份文件**的另一节（"video"），直接覆盖会把玩家挑的档位抹成默认值。
func _save_volume(which: String, value: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH_CFG)
	cfg.set_value("audio", which, value)
	cfg.save(SAVE_PATH_CFG)
