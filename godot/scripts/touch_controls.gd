class_name TouchControls
extends CanvasLayer
## On-screen controls for iPhone and iPad: steering pads on the left, a controller-style diamond
## of action buttons on the right (nitro, brake, ram, drift; slow-mo in the corner) and pause,
## reset and auto-gas at the edge. Auto-gas is on by default; turned off, a GAS pedal appears
## beside the diamond. Multi-touch; a finger can slide between the steering pads, or across the
## diamond, without lifting.
## Port of src/ui/Touch.ts.

const SETTINGS := "user://settings.cfg"
const SLIDE := [["left", "right"], ["brake", "nitro", "drift", "gas"]]
const NITRO_RIM := Color(1, 216 / 255.0, 0, 0.6)

var input: InputCtl
var enabled := false
var _root: Control
var _buttons := {} # key → Panel
var _held := {} # finger index → key
## Auto-gas: throttle stays on unless you brake (no thumb pinned to GAS the whole race).
var _auto_gas := true
var _font: Font


func _ready() -> void:
	layer = 4
	enabled = Config.is_touch()
	_font = load("res://assets/fonts/RussoOne-Regular.ttf")
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var pts := DisplayServer.window_get_size().y / maxf(1.0, DisplayServer.screen_get_scale())
	var phone := pts < 600
	# Sizes in web-CSS pixels (the short-screen set on phones, where main.gd scales the canvas up).
	var k := 1.0 if phone else 1.15
	var circle := 999
	# Left: steering
	var steer := (64.0 if phone else 84.0) * k
	_add("left", "◀", Control.PRESET_BOTTOM_LEFT, Vector2(18 * k, -24 * k - steer), Vector2(steer, steer), circle, 26 * k)
	_add("right", "▶", Control.PRESET_BOTTOM_LEFT, Vector2(18 * k + steer + 14 * k, -24 * k - steer), Vector2(steer, steer), circle, 26 * k)
	# Right: action diamond like a controller's face buttons — NITRO under the thumb, REM left,
	# RAM right, DRIFT on top, SLOW small in the top-left corner.
	var d := (60.0 if phone else 76.0) * k
	var cell := d * 0.78
	var pad := Vector2(-(14 if phone else 18) * k - 3 * cell, -(14 if phone else 24) * k - 3 * cell) # top-left of the 3×3 grid
	var at := func(col: int, row: int, size: float) -> Vector2:
		return pad + Vector2((col + 0.5) * cell, (row + 0.5) * cell) - Vector2(size, size) / 2
	var fs := (11.0 if phone else 13.0) * k
	_add("drift", "DRIFT", Control.PRESET_BOTTOM_RIGHT, at.call(1, 0, d), Vector2(d, d), circle, fs)
	_add("brake", "REM", Control.PRESET_BOTTOM_RIGHT, at.call(0, 1, d), Vector2(d, d), circle, fs)
	_add("ram", "RAM", Control.PRESET_BOTTOM_RIGHT, at.call(2, 1, d), Vector2(d, d), circle, fs)
	_add("nitro", "NITRO", Control.PRESET_BOTTOM_RIGHT, at.call(1, 2, d), Vector2(d, d), circle, fs + k)
	var slow := d * 0.62
	_add("slow", "SLOW", Control.PRESET_BOTTOM_RIGHT, pad, Vector2(slow, slow), circle, (8.0 if phone else 9.0) * k)
	# Gas pedal left of the diamond, only while auto-gas is off.
	var gas := (Vector2(74, 92) if phone else Vector2(92, 116)) * k
	_add("gas", "GAS", Control.PRESET_BOTTOM_RIGHT, Vector2(pad.x - 14 * k - gas.x, pad.y + 3 * cell - gas.y), gas, int(20 * k), (16.0 if phone else 19.0) * k)
	# Edge: pause, reset, auto-gas (a bit higher on phones, clear of the diamond)
	var e := (40.0 if phone else 46.0) * k
	var up := 30.0 if phone else 0.0
	_add("auto", "AUTO\nGAS", Control.PRESET_CENTER_RIGHT, Vector2(-14 * k - e, -e / 2 - up - (82 if phone else 96) * k), Vector2(e, e), circle, 8 * k)
	_add("pause", "II", Control.PRESET_CENTER_RIGHT, Vector2(-14 * k - e, -e / 2 - up), Vector2(e, e), circle, 13 * k)
	_add("reset", "↺", Control.PRESET_CENTER_RIGHT, Vector2(-14 * k - e, (32 if phone else 38) * k - up), Vector2(e, e), circle, 20 * k)
	_set_auto_gas(true, false)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		# (v2 key: auto-gas became the default; the old key stored false for everyone.)
		_set_auto_gas(cfg.get_value("touch", "auto_gas2", true), false)
	set_shown(false)


func _add(key: String, text: String, preset: int, pos: Vector2, size: Vector2, radius: int, font_size: float) -> void:
	var p := Panel.new()
	p.set_anchors_preset(preset)
	p.position = Vector2.ZERO
	p.offset_left = pos.x
	p.offset_top = pos.y
	p.offset_right = pos.x + size.x
	p.offset_bottom = pos.y + size.y
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(10 / 255.0, 12 / 255.0, 22 / 255.0, 0.45)
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	var lb := Label.new()
	lb.text = text
	lb.set_anchors_preset(Control.PRESET_FULL_RECT)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.add_theme_font_override("font", _font)
	lb.add_theme_font_size_override("font_size", int(font_size))
	lb.add_theme_constant_override("line_spacing", -int(font_size * 0.3))
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(lb)
	_root.add_child(p)
	_buttons[key] = p


func set_shown(v: bool) -> void:
	visible = v and enabled
	if not visible and not _held.is_empty():
		_held.clear()
		_sync()


func _key_at(pos: Vector2) -> String:
	for k in _buttons:
		var p: Panel = _buttons[k]
		if p.visible and p.get_global_rect().grow(6).has_point(pos):
			return k
	return ""


func _input(e: InputEvent) -> void:
	if not visible:
		return
	var idx := -1
	var pos := Vector2.ZERO
	var pressed := false
	var drag := false
	if e is InputEventScreenTouch:
		idx = e.index
		pos = e.position
		pressed = e.pressed
	elif e is InputEventScreenDrag:
		idx = e.index
		pos = e.position
		drag = true
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		idx = 99
		pos = e.position
		pressed = e.pressed
	elif e is InputEventMouseMotion and _held.has(99):
		idx = 99
		pos = e.position
		drag = true
	else:
		return
	if drag:
		# Sliding the thumb switches between the steering pads, or between the held diamond
		# buttons (e.g. from REM onto NITRO). Taps like RAM and SLOW only fire on a fresh press.
		var k: String = _held.get(idx, "")
		for group in SLIDE:
			if k in group:
				var nk := _key_at(pos)
				if nk != k and nk in group:
					_held[idx] = nk
					_sync()
		return
	if pressed:
		var k := _key_at(pos)
		if k == "":
			return
		get_viewport().set_input_as_handled()
		input.using_touch = true
		_held[idx] = k
		match k:
			"pause":
				input.press("pause")
			"reset":
				input.press("reset")
			"slow":
				input.press("bulletTime")
			"ram":
				input.press("ramAuto")
			"auto":
				_set_auto_gas(not _auto_gas)
		_sync()
	elif _held.has(idx):
		_held.erase(idx)
		_sync()


func _set_auto_gas(on: bool, save := true) -> void:
	_auto_gas = on
	_buttons["gas"].visible = not on
	if save:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS)
		cfg.set_value("touch", "auto_gas2", on)
		cfg.save(SETTINGS)
	_sync()


func _style(k: String, on: bool) -> void:
	var sb := _buttons[k].get_theme_stylebox("panel") as StyleBoxFlat
	sb.bg_color = Color(1, 138 / 255.0, 0, 0.55) if on else Color(10 / 255.0, 12 / 255.0, 22 / 255.0, 0.45)
	sb.border_color = Hud.YELLOW if on else (NITRO_RIM if k == "nitro" else Color(1, 1, 1, 0.35))


func _sync() -> void:
	var keys := {}
	for i in _held:
		keys[_held[i]] = true
	for k in _buttons:
		_style(k, _auto_gas if k == "auto" else keys.has(k))
	if input == null:
		return
	var t := input.touch
	t.steer = (1.0 if keys.has("right") else 0.0) - (1.0 if keys.has("left") else 0.0)
	t.brake = 1.0 if keys.has("brake") else 0.0
	t.throttle = 1.0 if keys.has("gas") or (_auto_gas and t.brake == 0) else 0.0
	t.nitro = keys.has("nitro")
	t.handbrake = keys.has("drift")
