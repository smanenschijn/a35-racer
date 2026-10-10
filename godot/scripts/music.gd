class_name MusicPlayer
extends Node
## Title loop + race playlist from assets/music/. Missing files are skipped silently.
## Port of src/core/Music.ts.

signal track_started(title: String)

const TITLE_TRACK := {"file": "plaatsnaambord.mp3", "title": "Plaatsnaambord"}
const RACE_TRACKS := [
	{"file": "a35.mp3", "title": "A35"},
	{"file": "beuk-m-de-vangrail-in.mp3", "title": "Beuk 'm de vangrail in"},
]
const SETTINGS := "user://settings.cfg"

var volume := 0.7
var _player: AudioStreamPlayer
var _lp: AudioEffectLowPassFilter
var _mode := "off"
var _race_index := randi() % RACE_TRACKS.size()
var _current := {}
var _muffled := false


func _ready() -> void:
	var bus := GameAudio.make_bus("Music", 0.0)
	_lp = AudioEffectLowPassFilter.new()
	_lp.cutoff_hz = 20000
	AudioServer.add_bus_effect(bus, _lp)
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	add_child(_player)
	_player.finished.connect(func(): if _mode == "race": next())
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		volume = cfg.get_value("music", "volume", volume)
	_apply_volume()


func _has(t: Dictionary) -> bool:
	return ResourceLoader.exists("res://assets/music/" + t.file)


func _play(t: Dictionary, loop: bool) -> void:
	if not _has(t):
		_current = {}
		_player.stop()
		return
	if _current != t:
		var s: AudioStreamMP3 = load("res://assets/music/" + t.file).duplicate()
		s.loop = loop
		_player.stream = s
		_current = t
		track_started.emit(t.title)
	_player.play()


func play_title() -> void:
	if _mode == "title":
		return
	_mode = "title"
	_play(TITLE_TRACK, true)


func play_race() -> void:
	if _mode == "race":
		return
	_mode = "race"
	var t := _next_available_race(0)
	if t.is_empty():
		_player.stop()
	else:
		_play(t, false)


func next() -> void:
	if _mode != "race":
		return
	var t := _next_available_race(1)
	if not t.is_empty():
		_current = {} # force reload even if it's the same file
		_play(t, false)


func _next_available_race(step: int) -> Dictionary:
	for i in RACE_TRACKS.size():
		_race_index = (_race_index + (step if i == 0 else 1)) % RACE_TRACKS.size()
		var t: Dictionary = RACE_TRACKS[_race_index]
		if _has(t):
			return t
	return {}


## Muffled = heard "through a wall": pause menu and slow-motion moments.
func set_muffled(m: bool) -> void:
	if m == _muffled:
		return
	_muffled = m
	_apply_volume()


## Bullet time: the track slows down like a tape (pitch drops with it).
func set_slow(on: bool) -> void:
	_player.pitch_scale = 0.8 if on else 1.0


func change_volume(delta: float) -> float:
	volume = clampf(roundf((volume + delta) * 10) / 10.0, 0.0, 1.0)
	_apply_volume()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("music", "volume", volume)
	cfg.save(SETTINGS)
	return volume


func _process(delta: float) -> void:
	var target := 650.0 if _muffled else 20000.0
	_lp.cutoff_hz = lerpf(_lp.cutoff_hz, target, 1.0 - exp(-delta / 0.08))


func _apply_volume() -> void:
	_player.volume_db = linear_to_db(maxf(0.0001, volume * (0.6 if _muffled else 1.0)))
