class_name InputCtl
extends RefCounted
## Keyboard + gamepad + on-screen touch input, merged into one control state for the player.
## Port of src/core/Input.ts. Keys are physical (layout independent), like KeyboardEvent.code.

const BINDINGS_FILE := "user://settings.cfg"
## Seconds the restart key must be held (a stray tap shouldn't throw away a race).
const RESTART_HOLD := 0.8

## Driving actions the player can rebind to other keys.
const BIND_LABELS := {
	"throttle": "Gas", "brake": "Rem / achteruit", "left": "Links sturen", "right": "Rechts sturen",
	"handbrake": "Handrem (drift)", "nitro": "Nitro", "bulletTime": "Bullet time", "ramLeft": "Ram links",
	"ramRight": "Ram rechts", "reset": "Terug op de weg", "lookBack": "Achterom kijken",
}
const DEFAULT_BINDINGS := {
	"throttle": [KEY_UP, KEY_W], "brake": [KEY_DOWN, KEY_S], "left": [KEY_LEFT, KEY_A], "right": [KEY_RIGHT, KEY_D],
	"handbrake": [KEY_SPACE], "nitro": [KEY_SHIFT], "bulletTime": [KEY_C], "ramLeft": [KEY_Q], "ramRight": [KEY_E],
	"reset": [KEY_F], "lookBack": [KEY_V],
}
## Keys with a fixed job (menus, pause, music, restart): not available for rebinding.
const RESERVED_KEYS := [KEY_ESCAPE, KEY_P, KEY_M, KEY_N, KEY_T, KEY_R, KEY_ENTER, KEY_KP_ENTER, KEY_EQUAL, KEY_MINUS,
	KEY_KP_ADD, KEY_KP_SUBTRACT, KEY_BACKSPACE, KEY_TAB]
const NAV_KEYS := {KEY_UP: "navUp", KEY_W: "navUp", KEY_DOWN: "navDown", KEY_S: "navDown", KEY_LEFT: "navLeft",
	KEY_A: "navLeft", KEY_RIGHT: "navRight", KEY_D: "navRight", KEY_ESCAPE: "back", KEY_BACKSPACE: "back"}
## Fixed one-shot keys (the rebindable ones are looked up in the bindings).
const EDGE_KEYS := {KEY_ESCAPE: "pause", KEY_P: "pause", KEY_M: "mute", KEY_T: "debug", KEY_N: "nextTrack",
	KEY_EQUAL: "volumeUp", KEY_KP_ADD: "volumeUp", KEY_MINUS: "volumeDown", KEY_KP_SUBTRACT: "volumeDown",
	KEY_ENTER: "confirm", KEY_KP_ENTER: "confirm", KEY_SPACE: "confirm"}
## Rebindable actions that fire once per press.
const EDGE_ACTIONS := {"ramLeft": "ramLeft", "ramRight": "ramRight", "reset": "reset", "bulletTime": "bulletTime"}


## Everything the game reads in one frame.
class Controls:
	var throttle := 0.0
	var brake := 0.0
	var steer := 0.0
	var handbrake := false
	var nitro := false
	var ramLeft := false
	var ramRight := false
	## Ram towards whichever side has a target (touch's single RAM button).
	var ramAuto := false
	## Held: camera looks behind the car.
	var lookBack := false
	var reset := false
	var bulletTime := false
	## Fires once the restart key has been held long enough.
	var restart := false
	## 0..1 while the restart key is held.
	var restartHold := 0.0
	var pause := false
	var mute := false
	var debug := false
	var nextTrack := false
	var volumeUp := false
	var volumeDown := false
	var confirm := false
	var navUp := false
	var navDown := false
	var navLeft := false
	var navRight := false
	var back := false
	var any := false


var bindings := {}
var using_gamepad := false
var using_touch := false
## Player's speed (m/s), set by the game each frame: digital steering eases off at speed.
var vehicle_speed := 0.0
## Held controls fed by the on-screen touch buttons.
var touch := {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "nitro": false, "handbrake": false}
var _keys := {}
var _edges := {}
var _pad_prev := {}
var _steer_state := 0.0
var _restart_t := 0.0
var _restart_fired := false
var _stick_prev := Vector2.ZERO
## Rebinding: the next key press goes here instead of the game.
var _capture: Callable


func _init() -> void:
	bindings = _load_bindings()


## For on-screen buttons and menus: fire a one-shot control.
func press(edge: String) -> void:
	_edges[edge] = true
	_edges.any = true


static func key_name(code: int) -> String:
	var names := {KEY_UP: "↑", KEY_DOWN: "↓", KEY_LEFT: "←", KEY_RIGHT: "→", KEY_SPACE: "SPATIE", KEY_SHIFT: "SHIFT",
		KEY_CTRL: "CTRL", KEY_ALT: "ALT", KEY_META: "CMD", KEY_ENTER: "ENTER", KEY_COMMA: ",", KEY_PERIOD: ".",
		KEY_SLASH: "/", KEY_SEMICOLON: ";", KEY_APOSTROPHE: "'", KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]",
		KEY_BACKSLASH: "\\", KEY_QUOTELEFT: "`", KEY_CAPSLOCK: "CAPS"}
	if names.has(code):
		return names[code]
	return OS.get_keycode_string(code).to_upper()


func _load_bindings() -> Dictionary:
	var out := DEFAULT_BINDINGS.duplicate(true)
	var cfg := ConfigFile.new()
	if cfg.load(BINDINGS_FILE) == OK:
		for k in out:
			var v = cfg.get_value("bindings", k, null)
			if v is Array and v.all(func(c): return c is int):
				out[k] = v.filter(func(c): return not RESERVED_KEYS.has(c))
	return out


func _save_bindings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(BINDINGS_FILE)
	for k in bindings:
		cfg.set_value("bindings", k, bindings[k])
	cfg.save(BINDINGS_FILE)


## Wait for the next key press and bind it to `action` (Escape cancels). done(ok: bool)
func rebind(action: String, done: Callable) -> void:
	_capture = func(code: int) -> void:
		if code == KEY_NONE or RESERVED_KEYS.has(code):
			done.call(false)
			return
		# A key does one thing: take it away from whatever had it.
		for k in bindings:
			bindings[k] = bindings[k].filter(func(c): return c != code)
		bindings[action] = [code]
		_keys.clear()
		_save_bindings()
		done.call(true)


func cancel_rebind() -> void:
	_capture = Callable()


func reset_bindings() -> void:
	bindings = DEFAULT_BINDINGS.duplicate(true)
	_save_bindings()


## Short label of the control for an action on the device in use (for hints).
func label(action: String) -> String:
	if using_touch:
		return {"nitro": "NITRO", "handbrake": "DRIFT", "ramLeft": "RAM", "ramRight": "RAM", "bulletTime": "SLOW", "reset": "↺"}.get(action, "")
	if using_gamepad:
		return {"throttle": "R2", "brake": "L2", "left": "stick", "right": "stick", "handbrake": "✕/A", "nitro": "○/B",
			"bulletTime": "L3/R3", "ramLeft": "L1", "ramRight": "R1", "reset": "△/Y", "lookBack": "rechterstick ↓"}[action]
	return bind_label(action)


func bind_label(action: String) -> String:
	var seen := []
	for c in bindings[action]:
		var n := key_name(c)
		if not seen.has(n):
			seen.append(n)
	return "/".join(seen) if not seen.is_empty() else "—"


func _bound(action: String) -> bool:
	for c in bindings[action]:
		if _keys.has(c):
			return true
	return false


func handle_event(e: InputEvent) -> void:
	if e is InputEventKey:
		var code: int = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
		if e.pressed and not e.echo:
			if _capture.is_valid():
				var cb := _capture
				_capture = Callable()
				cb.call(KEY_NONE if code == KEY_ESCAPE else code)
				return
			_keys[code] = true
			if EDGE_KEYS.has(code):
				_edges[EDGE_KEYS[code]] = true
			for action in EDGE_ACTIONS:
				if bindings[action].has(code):
					_edges[EDGE_ACTIONS[action]] = true
			if NAV_KEYS.has(code):
				_edges[NAV_KEYS[code]] = true
			_edges.any = true
			using_gamepad = false
			using_touch = false
		elif not e.pressed:
			_keys.erase(code)
	elif e is InputEventScreenTouch and e.pressed:
		using_touch = true
		using_gamepad = false
		_edges.any = true
	elif e is InputEventMouseButton and e.pressed:
		_edges.any = true


func clear_keys() -> void:
	_keys.clear()


func poll(dt: float) -> Controls:
	var c := Controls.new()
	# Digital steering (keyboard and touch buttons): eased in, and gentler at speed, so taps make
	# small corrections in town and the car doesn't dart around at 250 km/u.
	var left: bool = _bound("left") or touch.steer < 0
	var right: bool = _bound("right") or touch.steer > 0
	var speed_t := minf(1.0, vehicle_speed / 65.0)
	var target := ((1.0 if right else 0.0) - (1.0 if left else 0.0)) * (1 - 0.18 * speed_t)
	var centering := target == 0 or signf(target) != signf(_steer_state)
	var rate := 6.5 - 2 * speed_t if centering else 5 - 3 * speed_t
	_steer_state += clampf(target - _steer_state, -rate * dt, rate * dt)
	c.steer = _steer_state
	c.throttle = 1.0 if _bound("throttle") else 0.0
	c.brake = 1.0 if _bound("brake") else 0.0
	c.handbrake = _bound("handbrake")
	c.nitro = _bound("nitro")
	c.lookBack = _bound("lookBack")
	for e in _edges:
		c.set(e, true)
	_edges.clear()

	# Touch buttons
	c.throttle = maxf(c.throttle, touch.throttle)
	c.brake = maxf(c.brake, touch.brake)
	c.nitro = c.nitro or touch.nitro
	c.handbrake = c.handbrake or touch.handbrake

	# Gamepad
	var restart_held := _keys.has(KEY_R)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var dev: int = pads[0]
		var btn := func(b: int) -> bool: return Input.is_joy_button_pressed(dev, b)
		var pressed := func(b: int) -> bool: return btn.call(b) and not _pad_prev.get(b, false)
		var ax := Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
		var dead := 0.12
		ax = 0.0 if absf(ax) < dead else (ax - signf(ax) * dead) / (1 - dead)
		var r2 := Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT)
		var l2 := Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT)
		var any_btn := false
		for b in range(0, 15):
			if btn.call(b):
				any_btn = true
		if absf(ax) > 0 or r2 > 0.05 or l2 > 0.05 or any_btn:
			using_gamepad = true
			using_touch = false
		if absf(ax) > absf(c.steer):
			c.steer = signf(ax) * ax * ax # squared for precision
		c.throttle = maxf(c.throttle, r2)
		c.brake = maxf(c.brake, l2)
		c.handbrake = c.handbrake or btn.call(JOY_BUTTON_A)
		c.nitro = c.nitro or btn.call(JOY_BUTTON_B)
		c.ramLeft = c.ramLeft or pressed.call(JOY_BUTTON_LEFT_SHOULDER)
		c.ramRight = c.ramRight or pressed.call(JOY_BUTTON_RIGHT_SHOULDER)
		c.reset = c.reset or pressed.call(JOY_BUTTON_Y)
		# Either stick click: L3 is awkward while you're steering with that same stick.
		c.bulletTime = c.bulletTime or pressed.call(JOY_BUTTON_LEFT_STICK) or pressed.call(JOY_BUTTON_RIGHT_STICK)
		c.lookBack = c.lookBack or Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y) > 0.6
		if btn.call(JOY_BUTTON_BACK):
			restart_held = true
		c.pause = c.pause or pressed.call(JOY_BUTTON_START)
		c.confirm = c.confirm or pressed.call(JOY_BUTTON_A) or pressed.call(JOY_BUTTON_START)
		c.nextTrack = c.nextTrack or pressed.call(JOY_BUTTON_X)
		c.back = c.back or pressed.call(JOY_BUTTON_B)
		c.navUp = c.navUp or pressed.call(JOY_BUTTON_DPAD_UP)
		c.navDown = c.navDown or pressed.call(JOY_BUTTON_DPAD_DOWN)
		c.navLeft = c.navLeft or pressed.call(JOY_BUTTON_DPAD_LEFT)
		c.navRight = c.navRight or pressed.call(JOY_BUTTON_DPAD_RIGHT)
		# The stick also navigates menus (edge when it crosses the threshold).
		var sx := Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
		var sy := Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
		if sx < -0.6 and _stick_prev.x >= -0.6:
			c.navLeft = true
		if sx > 0.6 and _stick_prev.x <= 0.6:
			c.navRight = true
		if sy < -0.6 and _stick_prev.y >= -0.6:
			c.navUp = true
		if sy > 0.6 and _stick_prev.y <= 0.6:
			c.navDown = true
		_stick_prev = Vector2(sx, sy)
		for b in range(0, 15):
			if pressed.call(b):
				c.any = true
			_pad_prev[b] = btn.call(b)

	# Restart only after holding R / Select for a moment.
	if restart_held:
		_restart_t += dt
		if _restart_t >= RESTART_HOLD and not _restart_fired:
			_restart_fired = true
			c.restart = true
	else:
		_restart_t = 0.0
		_restart_fired = false
	c.restartHold = 0.0 if _restart_fired else minf(1.0, _restart_t / RESTART_HOLD)
	return c


func rumble(strong: float, weak: float, ms: float) -> void:
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		Input.start_joy_vibration(pads[0], minf(1.0, weak), minf(1.0, strong), ms / 1000.0)
