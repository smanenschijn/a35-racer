extends SceneTree
## Drives the real game with injected key and touch events: title → main → stages → race, steering, ram,
## pause and resume, and the on-screen touch buttons. Run: Godot --path godot -s res://tests/input_test.gd

var main: Node
var t := 0.0
var steps: Array = []
var failures := 0


func _init() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	run.call_deferred()


func key(code: int, down := true) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func tap(code: int) -> void:
	key(code, true)
	await process_frame
	await process_frame
	key(code, false)
	await process_frame


func touch_at(pos: Vector2, idx: int, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.position = pos
	e.index = idx
	e.pressed = down
	Input.parse_input_event(e)


func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


## Wait `sec` seconds of game time (software rendering on a test box runs at a few frames per second).
func wait(sec: float) -> void:
	var end: float = main._time + sec
	while main._time < end:
		await process_frame


## Canvas position → window position (the canvas is stretched to the window).
func to_window(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func run() -> void:
	while not main._ready_done:
		await process_frame
	var menu: Menu = main.menu
	var race: Race = main.race
	check(menu.screen == "title", "title screen first")
	await tap(KEY_ENTER)
	check(menu.screen == "main", "ENTER opens the main menu")
	await tap(KEY_DOWN)
	await tap(KEY_UP)
	await tap(KEY_ENTER)
	check(menu.screen == "stages", "Racen opens the stage list")
	await tap(KEY_DOWN)
	await tap(KEY_DOWN)
	await tap(KEY_ENTER)
	check(not menu.is_open and race.state == "countdown", "stage 2 starts with a countdown")
	check(race.stage_index == 1, "it is stage 2")
	var guard := 0
	while race.state != "racing" and guard < 2000:
		await process_frame
		guard += 1
	check(race.state == "racing", "countdown done: racing")
	key(KEY_UP)
	await wait(3.0)
	check(race.player.speed > 15, "holding ↑ accelerates (%.0f km/u)" % (race.player.speed * 3.6))
	key(KEY_LEFT)
	await wait(0.4)
	check(race.player.input.steer < -0.3, "← steers left")
	key(KEY_LEFT, false)
	await tap(KEY_E)
	await tap(KEY_ESCAPE)
	check(race.paused and menu.screen == "pause", "ESC pauses")
	var s := race.player.s
	await wait(0.5)
	check(absf(race.player.s - s) < 0.01, "nothing moves while paused")
	await tap(KEY_ENTER)
	check(not race.paused and not menu.is_open, "ENTER on Verder resumes")
	key(KEY_UP, false)
	# Touch: GAS button held, then released.
	var tc: TouchControls = main.touch
	tc.enabled = true
	tc.set_shown(true)
	await process_frame
	var gas: Panel = tc._buttons["gas"]
	var c := to_window(gas.get_global_rect().get_center())
	touch_at(c, 0, true)
	await wait(0.2)
	check(main.input.touch.throttle == 1.0, "touching GAS gives throttle")
	touch_at(c, 0, false)
	await wait(0.1)
	check(main.input.touch.throttle == 0.0 or tc._auto_gas, "releasing GAS lets go")
	var left: Panel = tc._buttons["left"]
	var right: Panel = tc._buttons["right"]
	touch_at(to_window(left.get_global_rect().get_center()), 1, true)
	await wait(0.1)
	check(main.input.touch.steer == -1.0, "◀ steers left")
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = to_window(right.get_global_rect().get_center())
	Input.parse_input_event(drag)
	await wait(0.1)
	check(main.input.touch.steer == 1.0, "sliding the thumb to ▶ steers right")
	touch_at(drag.position, 1, false)
	# Hold R to restart.
	key(KEY_R)
	await wait(1.0)
	key(KEY_R, false)
	await process_frame
	check(race.state == "countdown", "holding R restarts the race")
	print("DONE failures=%d" % failures)
	quit(1 if failures else 0)
