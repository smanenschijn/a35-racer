class_name GameAudio
extends Node
## Sound effects: pre-rendered synth one-shots (scripts/gen_sfx.py) and live-filtered loops for the
## engine, rail scrape, tyre squeal and siren. Port of src/core/Audio.ts.

const ONE_SHOTS := ["crash", "whoosh", "beep_lo", "beep_hi", "chime", "horn_car", "horn_truck", "flash"]

var muted := false
var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _engine: AudioStreamPlayer
var _scrape: AudioStreamPlayer
var _squeal: AudioStreamPlayer
var _siren: AudioStreamPlayer
var _engine_lp: AudioEffectLowPassFilter
var _scrape_bp: AudioEffectBandPassFilter
var _squeal_bp: AudioEffectBandPassFilter
var _master := 0
# Smoothed values, like setTargetAtTime in Web Audio.
var _eng_freq := 60.0
var _eng_cut := 900.0
var _eng_gain := 0.0
var _scrape_gain := 0.0
var _scrape_cut := 2500.0
var _squeal_gain := 0.0
var _squeal_cut := 1100.0
var _siren_gain := 0.0
var _targets := {}


static func make_bus(bus_name: String, volume_db: float, send := "Master") -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_volume_db(idx, volume_db)
	AudioServer.set_bus_send(idx, send)
	return idx


func _ready() -> void:
	_master = AudioServer.get_bus_index("Master")
	var sfx := make_bus("SFX", linear_to_db(0.6))
	var comp := AudioEffectCompressor.new()
	comp.threshold = -18
	comp.ratio = 4
	AudioServer.add_bus_effect(sfx, comp)
	var eng := make_bus("Engine", 0.0, "SFX")
	_engine_lp = AudioEffectLowPassFilter.new()
	_engine_lp.cutoff_hz = 900
	_engine_lp.resonance = 0.75
	AudioServer.add_bus_effect(eng, _engine_lp)
	var scr := make_bus("Scrape", 0.0, "SFX")
	_scrape_bp = AudioEffectBandPassFilter.new()
	_scrape_bp.cutoff_hz = 2500
	_scrape_bp.resonance = 0.75
	AudioServer.add_bus_effect(scr, _scrape_bp)
	var sq := make_bus("Squeal", 0.0, "SFX")
	_squeal_bp = AudioEffectBandPassFilter.new()
	_squeal_bp.cutoff_hz = 1100
	_squeal_bp.resonance = 0.95
	AudioServer.add_bus_effect(sq, _squeal_bp)

	for n in ONE_SHOTS:
		var path := "res://assets/sfx/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_engine = _loop("engine", "Engine")
	_scrape = _loop("noise", "Scrape")
	_squeal = _loop("noise", "Squeal")
	_siren = _loop("siren", "SFX")


func _loop(file: String, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	var path := "res://assets/sfx/%s.wav" % file
	if ResourceLoader.exists(path):
		var s: AudioStreamWAV = load(path).duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
		p.stream = s
	p.volume_db = -80
	add_child(p)
	p.play()
	return p


func _play(n: String, gain: float, pitch := 1.0) -> void:
	if not _streams.has(n) or gain <= 0.001:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[n]
	p.volume_db = linear_to_db(gain)
	p.pitch_scale = pitch
	p.play()


func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(_master, m)


## 0..1 loudness of the nearest police siren.
func siren(level: float) -> void:
	_targets.siren = level * 0.07 / 0.12


## Checkpoint: rising arpeggio.
func chime() -> void:
	_play("chime", 0.8)


## Car horn (two detuned squares); trucks honk lower and longer.
func horn(truck: bool, level: float) -> void:
	if level > 0.05:
		_play("horn_truck" if truck else "horn_car", 0.45 * level)


## Speed camera: a bright ping.
func flash() -> void:
	_play("flash", 0.9)


## speed in m/s, throttle 0..1
func engine(spd: float, throttle: float, nitro: bool, act: bool) -> void:
	# Fake 5-speed gearbox: rpm saws up through each gear.
	var gear_top := [14.0, 26.0, 38.0, 52.0, 80.0]
	var gear := 0
	while gear < gear_top.size() - 1 and spd > gear_top[gear]:
		gear += 1
	var lo: float = 0.0 if gear == 0 else gear_top[gear - 1]
	var ratio := minf(1.0, (spd - lo) / (gear_top[gear] - lo))
	var rpm := 0.25 + ratio * 0.75
	_targets.eng_freq = 45 + rpm * 110 + gear * 6
	_targets.eng_cut = 500 + throttle * 1400 + (1200.0 if nitro else 0.0)
	_targets.eng_gain = 0.13 + throttle * 0.1 if act else 0.05


## Tyre squeal while drifting or braking hard (0..1).
func squeal(level: float) -> void:
	_targets.squeal = level * 0.3
	_targets.squeal_cut = 900 + level * 500 + randf() * 80


func scrape(intensity: float) -> void:
	_targets.scrape = intensity * 0.35
	_targets.scrape_cut = 1800 + intensity * 2500


func crash(strength: float) -> void:
	var vol := minf(1.0, strength / 18.0)
	_play("crash", vol, 0.85 + randf() * 0.3)


func whoosh() -> void:
	_play("whoosh", 0.9, 0.9 + randf() * 0.2)


func beep(high: bool) -> void:
	_play("beep_hi" if high else "beep_lo", 0.7)


func _process(delta: float) -> void:
	var k := func(tc: float) -> float: return 1.0 - exp(-delta / tc)
	_eng_freq = lerpf(_eng_freq, _targets.get("eng_freq", 60.0), k.call(0.04))
	_eng_cut = lerpf(_eng_cut, _targets.get("eng_cut", 900.0), k.call(0.05))
	_eng_gain = lerpf(_eng_gain, _targets.get("eng_gain", 0.0), k.call(0.08))
	_scrape_gain = lerpf(_scrape_gain, _targets.get("scrape", 0.0), k.call(0.03))
	_scrape_cut = lerpf(_scrape_cut, _targets.get("scrape_cut", 2500.0), k.call(0.05))
	_squeal_gain = lerpf(_squeal_gain, _targets.get("squeal", 0.0), k.call(0.05))
	_squeal_cut = lerpf(_squeal_cut, _targets.get("squeal_cut", 1100.0), k.call(0.05))
	_siren_gain = lerpf(_siren_gain, _targets.get("siren", 0.0), k.call(0.1))
	_engine.pitch_scale = clampf(_eng_freq / 100.0, 0.2, 4.0)
	_engine_lp.cutoff_hz = _eng_cut
	_engine.volume_db = linear_to_db(maxf(0.0001, _eng_gain * 2.2))
	_scrape_bp.cutoff_hz = _scrape_cut
	_scrape.volume_db = linear_to_db(maxf(0.0001, _scrape_gain * 2.0))
	_squeal_bp.cutoff_hz = _squeal_cut
	_squeal.volume_db = linear_to_db(maxf(0.0001, _squeal_gain * 2.0))
	_siren.volume_db = linear_to_db(maxf(0.0001, _siren_gain))
