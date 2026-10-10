extends Node3D
## Boot, world, lights, the fixed-step loop, menus and the showroom camera. Port of src/main.ts +
## src/game/Game.ts.
##
## Testing: Godot --path godot -- --autoshot=/tmp/shot.png [--autoplay] [--stage=4] [--wait=20] [--touch]

const FIXED_DT := 1.0 / 120.0

var track: Track
var race: Race
var hud: Hud
var menu: Menu
var touch: TouchControls
var audio: GameAudio
var music: MusicPlayer
var announcer: Announcer
var cam: ChaseCamera
var landmarks: Landmarks
var input := InputCtl.new()
var events := EventBus.new()
var env: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var _sun_dir := Vector3.ZERO
var _accumulator := 0.0
var _time := 0.0
var _preview_id := "rx"
## Running "hele race" campaign: accumulated time of the cleared stages.
var _campaign := {}
var _ready_done := false
var _loading: CanvasLayer
var _auto := {}
# Adaptive resolution: full sharpness whenever the device keeps up, a step down only when it doesn't.
var _scale_max := 1.0
var _dt_avg := 1.0 / 60.0
var _slow_t := 0.0
var _fast_t := 0.0
var _up_wait := 6.0
var _last_drop := -99.0
var _warmup := 3.0


func _ready() -> void:
	_show_loading()
	# Two frames so the loading screen is on before the heavy lifting.
	await get_tree().process_frame
	await get_tree().process_frame
	Tex.host = self
	CarModel.preload_models()
	track = Track.new(Track.load_route())
	_setup_world()

	audio = GameAudio.new()
	add_child(audio)
	music = MusicPlayer.new()
	add_child(music)
	announcer = Announcer.new()
	hud = Hud.new()
	add_child(hud)
	hud.reset_pressed.connect(func(): input.press("reset"))
	music.track_started.connect(func(t): hud.show_now_playing(t))

	var fx := Effects.new(self)
	cam = ChaseCamera.new()
	add_child(cam.camera)
	cam.camera.current = true
	race = Race.new({
		"parent": self, "track": track, "events": events, "fx": fx, "hud": hud, "audio": audio, "music": music,
		"announcer": announcer, "cam": cam,
		"rumble": func(s, w, ms): input.rumble(s, w, ms),
		"key_label": func(a): return input.label(a),
	})
	race.on_finished = _on_finished

	touch = TouchControls.new()
	touch.input = input
	add_child(touch)
	menu = Menu.new()
	menu.input = input
	menu.stages = track.features.stages
	menu.actions = {
		"start_stage": func(i: int, campaign: bool) -> void:
			_campaign = {"total": 0.0} if campaign else {}
			menu.close()
			race.set_stage(i)
			race.start(),
		"next_stage": func() -> void:
			menu.close()
			race.set_stage(race.stage_index + 1)
			race.start(),
		"restart_race": func() -> void:
			menu.close()
			race.paused = false
			race.start(),
		"resume": func() -> void:
			menu.close()
			race.paused = false,
		"to_menu": func() -> void:
			race.paused = false
			race.to_menu()
			announcer.stop()
			music.play_title()
			menu.open("main"),
		"choose_car": func(id: String): race.set_player_car(id),
		"preview_car": func(id: String): _preview_id = id,
		"sound": func(): _toggle_sound(),
	}
	add_child(menu)
	music.play_title()
	await Tex.flush()
	_loading.queue_free()
	_ready_done = true
	menu.open("title")
	_parse_auto_args()


func _show_loading() -> void:
	_loading = CanvasLayer.new()
	_loading.layer = 10
	var bg := ColorRect.new()
	bg.color = Color("0b0d14")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.add_theme_font_override("normal_font", load("res://assets/fonts/Bangers-Regular.ttf"))
	title.add_theme_font_size_override("normal_font_size", 64)
	title.text = "[color=#ff8a00]A35[/color] [color=#e8e8f0]RACER[/color]"
	box.add_child(title)
	var sub := Label.new()
	sub.text = "auto's worden getankt…"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_override("font", load("res://assets/fonts/RussoOne-Regular.ttf"))
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color("ffd400"))
	box.add_child(sub)
	_loading.add_child(box)
	add_child(_loading)


func _setup_world() -> void:
	# Golden-hour sun low in the west-southwest: behind you on the long run east to Enschede.
	var elevation := deg_to_rad(3.5)
	var azimuth := deg_to_rad(-75.0)
	_sun_dir = Vector3(cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth))

	env = Environment.new()
	# Golden hour: deep blue overhead, warm orange haze at the horizon, the sun just above it.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("3d6db0")
	sky_mat.sky_horizon_color = Color("f0a46a")
	sky_mat.sky_curve = 0.12
	sky_mat.sky_energy_multiplier = 1.1
	sky_mat.ground_horizon_color = Color("e8a070")
	sky_mat.ground_bottom_color = Color("6a5a48")
	sky_mat.ground_curve = 0.05
	sky_mat.sun_angle_max = 8.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.6
	env.ambient_light_color = Color("ffd2a8")
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("e8a070")
	env.fog_density = 1.0
	env.fog_depth_begin = 250.0
	env.fog_depth_end = 2600.0
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 0.7
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color("ffc48a")
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 2.0
	sun.transform = Transform3D(Basis.looking_at(-_sun_dir, Vector3.UP), Vector3.ZERO)
	add_child(sun)
	# Soft fill from behind the camera so cars facing away from the low sun keep their colour.
	fill = DirectionalLight3D.new()
	fill.light_color = Color("9fb8ff")
	fill.light_energy = 0.45
	fill.shadow_enabled = false
	add_child(fill)

	var builder := TrackBuilder.new(track)
	add_child(builder.build())
	landmarks = Landmarks.new(track, builder)
	add_child(landmarks.root)


func _toggle_sound() -> void:
	audio.set_muted(not audio.muted)
	announcer.muted = audio.muted
	hud.message("GELUID UIT" if audio.muted else "GELUID AAN", "#ffffff", false, 0.8)


func _on_finished(r: Dictionary) -> void:
	var stage_id: int = track.features.stages[r.stage].id
	var unlocked := Progress.record_race(stage_id, r.position, r.qualified, r.takedowns, r.stats)
	var campaign := not _campaign.is_empty()
	if campaign and r.qualified:
		_campaign.total += r.time
	if _auto.has("play"):
		print("[auto] finished position=%d time=%.1f qualified=%s" % [r.position, r.time, r.qualified])
		return
	menu.show_result(r, {"campaign": campaign, "campaignTotal": _campaign.get("total", 0.0), "unlocked": unlocked})
	if campaign and not r.qualified:
		_campaign = {} # failed: campaign over, the stage can be retried


## In the menus the camera slowly circles the car you're looking at on the grid.
func _showroom_camera() -> void:
	var v: Vehicle = race.player
	for r: Vehicle in race.racers:
		if r.spec.id == _preview_id:
			v = r
	race.showroom = v
	var c := cam.camera
	var a := _time * 0.25
	var r := 4.2 + v.half_l * 1.25
	c.look_at_from_position(Vector3(v.x + sin(a) * r, v.y + 1.7, v.z + cos(a) * r), Vector3(v.x, v.y + 0.7, v.z))
	c.fov = 50
	# Shift the picture so the car sits right of the menu panel (wide screens only).
	var vp := get_viewport().get_visible_rect().size
	c.h_offset = -r * 0.42 if vp.x / vp.y > 1.2 and not menu.compact else 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _ready_done and race.state in ["racing", "countdown"] and not race.paused and not _auto.has("play"):
		race.paused = true
		menu.open("pause")


func _input(e: InputEvent) -> void:
	input.handle_event(e)
	if e is InputEventKey and e.pressed and not e.echo and _ready_done and not menu.is_open:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _ready_done:
		return
	var real_dt := minf(0.1, delta)
	_time += real_dt
	_adapt_resolution(real_dt)
	input.vehicle_speed = race.player.speed
	var c := input.poll(real_dt)
	if c.mute:
		_toggle_sound()
	if menu.is_open:
		menu.set_gamepad(input.using_gamepad)
		menu.handle(c)
		music.set_muffled(menu.screen == "pause")
	elif c.pause and race.state in ["racing", "countdown"]:
		race.paused = true
		menu.open("pause")
	else:
		race.handle_input(c, real_dt)
	var in_menu := race.state == "menu"
	hud.set_visible_hud(not in_menu)
	touch.set_shown(not menu.is_open and not in_menu)

	# Fixed-step physics, scaled by slow-mo.
	var t0 := Time.get_ticks_usec()
	if not race.paused:
		_accumulator += real_dt * race.time_scale
		var steps := 0
		while _accumulator >= FIXED_DT and steps < 24:
			race.step(FIXED_DT)
			_accumulator -= FIXED_DT
			steps += 1
		if steps >= 24:
			_accumulator = 0.0

	var t1 := Time.get_ticks_usec()
	race.render(real_dt, _time)
	if _auto.has("shot"):
		_auto.phys_us = _auto.get("phys_us", 0) + t1 - t0
		_auto.render_us = _auto.get("render_us", 0) + Time.get_ticks_usec() - t1
	if in_menu:
		_showroom_camera()
	else:
		cam.camera.h_offset = 0.0
	landmarks.update(0.0 if race.paused else real_dt)

	# Fill light shines from behind the camera onto the player.
	var p := race.player
	var to_car := Vector3(p.x, p.y, p.z) - cam.camera.global_position
	if to_car.length() > 0.5:
		fill.global_transform = Transform3D(Basis.looking_at(to_car.normalized() + Vector3(0, -0.4, 0), Vector3.UP), Vector3.ZERO)
	_auto_step(real_dt)


## Below ~52 fps for two seconds: render a step less sharp. Smooth again for a while: step back up.
## If stepping up made it slow again, wait longer before the next try.
func _adapt_resolution(real_dt: float) -> void:
	var vp := get_viewport()
	if race.state == "menu" or race.paused or _auto.has("shot"):
		_slow_t = 0.0
		_fast_t = 0.0
		return
	if _warmup > 0:
		_warmup -= real_dt # shaders compiling, models uploading
		return
	_dt_avg += (real_dt - _dt_avg) * 0.05
	if _dt_avg > 1.0 / 52:
		_slow_t += real_dt
		_fast_t = 0.0
	elif _dt_avg < 1.0 / 58 and vp.scaling_3d_scale < _scale_max:
		_fast_t += real_dt
		_slow_t = 0.0
	else:
		_slow_t = 0.0
		_fast_t = 0.0
	if _slow_t > 2 and vp.scaling_3d_scale > 0.55:
		if _time - _last_drop < _up_wait + 4:
			_up_wait = minf(60.0, _up_wait * 2)
		vp.scaling_3d_scale = maxf(0.5, vp.scaling_3d_scale - 0.125)
		_last_drop = _time
		_slow_t = 0.0
		_warmup = 0.5
	elif _fast_t > _up_wait:
		vp.scaling_3d_scale = minf(_scale_max, vp.scaling_3d_scale + 0.125)
		_fast_t = 0.0
		_warmup = 0.5


# ------------------------------------------------------------------ automation (screenshots / smoke tests)

func _parse_auto_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoshot="):
			_auto.shot = a.substr(11)
		elif a == "--autoplay":
			_auto.play = true
		elif a.begins_with("--wait="):
			_auto.wait = float(a.substr(7))
		elif a.begins_with("--stage="):
			_auto.stage = int(a.substr(8))
		elif a.begins_with("--at="):
			_auto.at = float(a.substr(5))
		elif a.begins_with("--menu="):
			_auto.menu = a.substr(7)
		elif a == "--autopilot":
			race.autopilot = true
	if _auto.has("shot"):
		_auto.t = 0.0
		_auto.wait = _auto.get("wait", 6.0)
		_auto.frames = 0
		_auto.steps_ms = 0.0
		race.profile = true
	if _auto.has("play"):
		menu.close()
		race.autopilot = true
		race.set_stage(_auto.get("stage", 4))
		if _auto.has("at"):
			# Screenshots: put the grid somewhere along the route.
			track.features.startS = _auto.at
		race.start()
	elif _auto.has("menu"):
		menu.open(_auto.menu)


func _auto_step(dt: float) -> void:
	if not _auto.has("shot"):
		return
	_auto.t += dt
	_auto.frames += 1
	if _auto.t >= _auto.wait:
		if DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(_auto.shot)
		if race.profile:
			var n: float = race.prof.get("steps", 1)
			print("[auto] per step (µs): ai %.0f, traffic %.0f, vehicles %.0f, collisions %.0f, rest %.0f" % [
				race.prof.get("ai", 0) / n, race.prof.get("traffic", 0) / n, race.prof.get("vehicles", 0) / n,
				race.prof.get("collisions", 0) / n, race.prof.get("rest", 0) / n])
		print("[auto] per frame: physics %.2f ms, visuals %.2f ms (sim %.1f s)" % [_auto.get("phys_us", 0) / 1000.0 / _auto.frames,
			_auto.get("render_us", 0) / 1000.0 / _auto.frames, race.race_time])
		var p := race.player
		print("[auto] screenshot %s  t=%.1fs frames=%d state=%s pos=%d/8 s=%.0f speed=%d km/u dmg=%d stars=%d timeLeft=%.0f" % [
			_auto.shot, _auto.t, _auto.frames, race.state, race.ranking().find(p) + 1, p.s - track.features.startS,
			roundi(p.speed * 3.6), roundi(p.wreck_level), race.police.stars, race.time_left])
		get_tree().quit()
