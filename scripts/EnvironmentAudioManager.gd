extends Node3D
## EnvironmentAudioManager — 环境音层 (PRD F-26 山风/鸟鸣/水声 + F-23 客家山歌)
##
## 每驿站 3 个 AudioStreamPlayer3D（wind/birds/water）常驻播放，
## 靠 Godot 内置 3D 距离衰减做淡入淡出（max_distance=120，30m 内可听）。
## 水景只在水边的两个碎片驿站（idx=3 竹雨庭 / idx=4 禽语湖湾）播放。
## 客家山歌每驿站触发一次：dist<30 且未打卡且未播过 → 播一次即标记。
## _on_all_collected 时 stop_all 淡出，避免与 synthesis SFX 冲突。

var _stations: Array = []
var _player = null
var _wind_players: Array = []
var _bird_players: Array = []
var _water_players: Array = []
var _song_player: AudioStreamPlayer3D
var _song_played_once: Array = []
var _check_timer: float = 0.0
var _stopped = false

const WATER_STATIONS: Array = [3, 4]
const AMBIENT_MAX_DIST: float = 120.0
const SONG_MAX_DIST: float = 50.0
const SONG_TRIGGER_DIST: float = 30.0
const AMBIENT_VOL: float = -6.0
const SONG_VOL: float = -4.0


func setup(stations: Array) -> void:
	_stations = stations
	for i in range(stations.size()):
		var pos = stations[i]
		_wind_players.append(_make_player(pos, "wind", AMBIENT_MAX_DIST, AMBIENT_VOL))
		_bird_players.append(_make_player(pos + Vector3(0, 5, 0), "birds", AMBIENT_MAX_DIST, AMBIENT_VOL))
		if WATER_STATIONS.has(i):
			_water_players.append(_make_player(pos, "water", AMBIENT_MAX_DIST, AMBIENT_VOL))
		else:
			_water_players.append(null)
		_song_played_once.append(false)
	_create_song_player()


func set_player(p) -> void:
	_player = p
	if _song_player:
		_song_player.max_distance = SONG_MAX_DIST


func _make_player(pos: Vector3, stream_name: String, max_d: float, vol: float) -> AudioStreamPlayer3D:
	var p = AudioStreamPlayer3D.new()
	p.position = pos
	p.max_distance = max_d
	p.volume_db = vol
	var s = _load_stream(stream_name)
	if s != null:
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		p.stream = s
		p.autoplay = true
	add_child(p)
	return p


func _create_song_player() -> void:
	_song_player = AudioStreamPlayer3D.new()
	_song_player.max_distance = SONG_MAX_DIST
	_song_player.volume_db = SONG_VOL
	var s = _load_stream("song")
	if s != null:
		_song_player.stream = s
	add_child(_song_player)


func _process(delta: float) -> void:
	if _stopped or _player == null:
		return
	_check_timer += delta
	if _check_timer < 0.1:
		return
	_check_timer = 0.0
	var pp: Vector3 = _player.global_position
	for i in range(_stations.size()):
		var dist: float = pp.distance_to(_stations[i])
		if dist < SONG_TRIGGER_DIST \
				and not _song_played_once[i] \
				and not GameManager.is_collected(i) \
				and _song_player.stream != null \
				and not _song_player.playing:
			_song_player.global_position = _stations[i] + Vector3(0, 5, 0)
			_song_played_once[i] = true
			_song_player.play()


func stop_all() -> void:
	if _stopped:
		return
	_stopped = true
	for arr in [_wind_players, _bird_players, _water_players]:
		for p in arr:
			if p == null:
				continue
			if p.playing:
				var tw = create_tween()
				tw.tween_property(p, "volume_db", -60.0, 0.5)
				tw.tween_callback(p.stop)
	if _song_player != null and _song_player.playing:
		var tw2 = create_tween()
		tw2.tween_property(_song_player, "volume_db", -60.0, 0.5)
		tw2.tween_callback(_song_player.stop)


func has_song_played(idx: int) -> bool:
	if idx < 0 or idx >= _song_played_once.size():
		return true
	return _song_played_once[idx]


func _load_stream(name: String) -> AudioStream:
	var path = "res://assets/audio/ambient/" + name + ".ogg"
	if FileAccess.file_exists(path):
		return load(path)
	return null
