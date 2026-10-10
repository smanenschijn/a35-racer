class_name TouchControls
extends CanvasLayer
## On-screen controls for iPhone and iPad: steering pads on the left, pedals on the right,
## nitro/handbrake/ram/slow-mo buttons in between and pause, reset and auto-gas at the edge.
## Multi-touch; a finger can slide from one steering pad to the other without lifting.
## Port of src/ui/Touch.ts.

const SETTINGS := "user://settings.cfg"

var input: InputCtl
var enabled := false
var _root: Control
var _buttons := {} # key → Panel
var _held := {} # finger index → key
## Auto-gas: throttle stays on unless you brake (no thumb pinned to GAS the whole race).
var _auto_gas := false
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
	# Sizes in web-CSS pixels; a phone shows the 900-high canvas at less than half size.
	var k := 2.0 if phone else 1.15
	var circle := 999
	# Left: steering
	var steer := 84 * k
	_add("left", "◀", Control.PRESET_BOTTOM_LEFT, Vector2(18 * k, -24 * k - steer), Vector2(steer, steer), circle, 30 * k)
	_add("right", "▶", Control.PRESET_BOTTOM_LEFT, Vector2(18 * k + steer + 14 * k, -24 * k - steer), Vector2(steer, steer), circle, 30 * k)
	# Right: pedals
	var gas := Vector2(96, 120) * k
	var brake := 78 * k
	_add("gas", "GAS", Control.PRESET_BOTTOM_RIGHT, Vector2(-18 * k - gas.x, -24 * k - gas.y), gas, int(22 * k), 20 * k)
	_add("brake", "REM", Control.PRESET_BOTTOM_RIGHT, Vector2(-18 * k - gas.x - 14 * k - brake, -24 * k - brake), Vector2(brake, brake), circle, 15 * k)
	# Middle: ram, drift, nitro, slow
	var mid := ["ram", "drift", "nitro", "slow"]
	var labels := {"ram": "RAM", "drift": "DRIFT", "nitro": "NITRO", "slow": "SLOW"}
	var bs := Vector2(64, 50) * k
	if phone:
		# One row centred at the bottom, between the thumbs.
		var w := 4 * bs.x + 3 * 10 * k
		for i in 4:
			_add(mid[i], labels[mid[i]], Control.PRESET_CENTER_BOTTOM, Vector2(-w / 2 + i * (bs.x + 10 * k), -14 * k - bs.y), bs, int(12 * k), 11 * k)
	else:
		var right := 18 * k + gas.x + 14 * k + brake + 40 * k
		for i in 4:
			var col := i % 2
			var row := i / 2
			_add(mid[i], labels[mid[i]], Control.PRESET_BOTTOM_RIGHT,
				Vector2(-right - (2 - col) * (bs.x + 10 * k), -30 * k - (2 - row) * (bs.y + 10 * k)), bs, int(12 * k), 11 * k)
	# Edge: pause, reset, auto-gas
	var e := 46 * k
	_add("auto", "AUTO\nGAS", Control.PRESET_CENTER_RIGHT, Vector2(-14 * k - e, -e / 2 - 96 * k), Vector2(e, e), circle, 9 * k)
	_add("pause", "II", Control.PRESET_CENTER_RIGHT, Vector2(-14 * k - e, -e / 2), Vector2(e, e), circle, 14 * k)
	_add("reset", "↺", Control.PRESET_CENTER_RIGHT, Vector2(-14 * k - e, -e / 2 + 38 * k + e / 2), Vector2(e, e), circle, 22 * k)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		_set_auto_gas(cfg.get_value("touch", "auto_gas", false))
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
		if p.get_global_rect().grow(6).has_point(pos):
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
		# Steering: sliding the thumb across to the other pad switches direction.
		var k: String = _held.get(idx, "")
		if k == "left" or k == "right":
			var nk := _key_at(pos)
			if (nk == "left" or nk == "right") and nk != k:
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


func _set_auto_gas(on: bool) -> void:
	_auto_gas = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("touch", "auto_gas", on)
	cfg.save(SETTINGS)
	_sync()


func _style(k: String, on: bool) -> void:
	var sb := _buttons[k].get_theme_stylebox("panel") as StyleBoxFlat
	sb.bg_color = Color(1, 138 / 255.0, 0, 0.55) if on else Color(10 / 255.0, 12 / 255.0, 22 / 255.0, 0.45)
	sb.border_color = Hud.YELLOW if on else Color(1, 1, 1, 0.35)


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
