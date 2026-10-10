class_name Race
extends RefCounted
## The race: racers, traffic and police, the state machine (menu, countdown, racing, finished),
## checkpoints, takedowns, slipstream, bullet time and the per-frame visuals. Port of src/game/Race.ts.

const HIT_WORDS := ["BEUK!", "KNAL!", "PATS!", "BAM!", "KRAK!"]
## How often each contextual hint may still be shown (per session).
const HINTS := {"ram": 3, "nitro": 2, "slow": 1, "lookBack": 1}

## Every physics vehicle: racers, traffic and police.
var vehicles: Array = []
## The eight competitors (player first).
var racers: Array = []
var player: Vehicle
var _ais: Array = []
var _models := {} # Vehicle → CarModel
var traffic: TrafficManager
var police: PoliceManager
var state := "menu" # menu | countdown | racing | finished
## Checkpoint clock (seconds left).
var time_left := 0.0
var _next_checkpoint := 0
var _checkpoint_bonus: Array = []
var _out_of_time := false
var _warned := false
var stats := {}
## In the menu only this racer is shown (showroom).
var showroom: Vehicle = null
## Called once the result is known (after the finish or when time runs out).
var on_finished: Callable
var paused := false
var _countdown_t := 0.0
var _countdown_step := 0
var race_time := 0.0
var _finish_order: Array = []
var _results_shown := false
var _finished_at := 0.0
var time_scale := 1.0
var _slow_mo_t := 0.0
var _slow_mo_scale := 1.0
## Bullet time: a meter the player spends to slow the world down.
var _bullet := 1.0
var _bullet_on := false
var _respawn_t := 0.0
## Seconds the player has been stuck (stopped, off the road or facing the wrong way).
var _player_stuck := 0.0
## Slipstream: time spent tucked in behind someone, and the slingshot boost left after pulling out.
var _draft_t := 0.0
var _sling_t := 0.0
var _reset_cooldown := 0.0
var _prev_ds := {}
var _player_scrape := 0.0
var _sim_time := 0.0
var _last_taunt := -99.0
## One extra stretch of clock per race when time runs out (costs a time penalty).
var _last_chance_used := false
var _help_shown := false
var _hints_left := HINTS.duplicate()
var _last_hint := -99.0
var _key_sig := ""
var _look_back := false
var _restart_hold := 0.0
var _rammed_once := false
var _active: Array = []
## Last time each traffic car cost us heat.
var _heat_hits := {}
## 0-based index of the stage being raced.
var stage_index := 4
## Testing aid: let an AI drive the player's car (--autopilot).
var autopilot := false
## Testing aid: microseconds spent per part of step() (only filled while `profile` is on).
var profile := false
var prof := {}
var _auto_driver: AIDriver

var _parent: Node3D
var _track: Track
var _events: EventBus
var _fx: Effects
var _hud: Hud
var _audio: GameAudio
var _music: MusicPlayer
var _announcer: Announcer
var _cam: ChaseCamera
var _rumble: Callable
var _key_label: Callable


func _init(deps: Dictionary) -> void:
	_parent = deps.parent
	_track = deps.track
	_events = deps.events
	_fx = deps.fx
	_hud = deps.hud
	_audio = deps.audio
	_music = deps.music
	_announcer = deps.announcer
	_cam = deps.cam
	_rumble = deps.rumble
	_key_label = deps.key_label
	player = _add_vehicle(Config.CARS.rx, "racer", true)
	racers.append(player)
	for id in Config.RIVALS:
		var v := _add_vehicle(Config.CARS[id], "racer")
		racers.append(v)
		_ais.append(AIDriver.new(v, Config.AI_PERSONALITIES[id], 0.0))
	var auto_p: Dictionary = Config.AI_PERSONALITIES.golv.duplicate()
	auto_p.playerFocus = 0.0
	_auto_driver = AIDriver.new(player, auto_p, Config.LANE_CENTERS[1])

	traffic = TrafficManager.new({
		"track": _track,
		"create": func(spec): return _add_vehicle(spec, "traffic"),
		"recolor": func(v, hex): _models[v].recolor(hex),
		"repair": func(v): _full_repair(v),
		"model": func(spec): return CarModel.new(spec, _parent),
	})
	police = PoliceManager.new({
		"track": _track,
		"events": _events,
		"create": func(): return _add_vehicle(Config.POLICE_CAR, "police"),
		"repair": func(v): _full_repair(v),
		"parent": _parent,
	})
	_wire_events()
	reset()


func _add_vehicle(spec: Dictionary, role: String, is_player := false) -> Vehicle:
	var v := Vehicle.new(spec, is_player, role)
	var model := CarModel.new(spec, _parent)
	_models[v] = model
	v.on_damage = func(amount: float, zone: String, lx: float, lz: float) -> void:
		model.dent(amount, lx, lz)
		if model.zone_damaged(zone, v.damage[zone]):
			var p := _local_to_world(v, lx, lz, 0.6)
			_fx.debris(p.x, p.y, p.z, 14, v.vx, v.vz)
	vehicles.append(v)
	return v


func model_of(v: Vehicle) -> CarModel:
	return _models[v]


func _full_repair(v: Vehicle) -> void:
	v.repair(0)
	for z in Vehicle.ZONES:
		v.damage[z] = 0.0
	v.last_hit_by = null
	v.last_hit_time = -99.0
	v.ram_cooldown = 0.0
	v.nitro_active = false
	_models[v].repair()


func reset() -> void:
	var t := _track
	var start: float = t.features.startS
	# Grid: two per row, rivals in RIVALS order, the player starts last.
	var order := racers.slice(1)
	order.append(player)
	for i in order.size():
		var v: Vehicle = order[i]
		var row := i / 2
		var lane := i % 2
		v.place(t, start - 10 - row * 10 - lane * 3, Config.LANE_CENTERS[lane], 0.0)
		_full_repair(v)
		v.nitro = 0.35
		v.frozen = true
		v.finished = false
		v.takedowns = 0
		v.penalty = 0
		v.input.throttle = 0.0
		v.input.brake = 0.0
		v.input.steer = 0.0
	for ai: AIDriver in _ais:
		ai.reset(ai.vehicle.d)
	_auto_driver.reset(Config.LANE_CENTERS[1])
	traffic.reset(start, t.features.finishS)
	police.reset()
	Collisions.reset()
	_finish_order = []
	_results_shown = false
	race_time = 0.0
	time_scale = 1.0
	_slow_mo_t = 0.0
	_slow_mo_scale = 1.0
	_bullet = 1.0
	_set_bullet(false)
	_respawn_t = 0.0
	_draft_t = 0.0
	_sling_t = 0.0
	_player_stuck = 0.0
	_last_chance_used = false
	_help_shown = false
	_look_back = false
	_cam.look_back = false
	_restart_hold = 0.0
	_prev_ds.clear()
	_heat_hits.clear()
	paused = false
	_setup_clock()
	stats = {"topSpeed": 0.0, "nearMisses": 0, "biggestHit": 0.0, "busted": 0, "wrecks": 0, "distance": 0.0}
	_cam.snap()
	_fx.clear()
	if state != "menu":
		start_countdown()


## Arcade time limit: enough to reach the first checkpoint; each gate buys the next leg.
func _setup_clock() -> void:
	var f := _track.features
	# Average speed you need, crashes included: ~137 km/h on the motorway, ~100 km/h on the busy
	# two-lane N35 with its oncoming traffic and real bends.
	var leg := func(a: float, b: float) -> float:
		var time := 0.0
		var s := a
		while s < b:
			time += minf(10.0, b - s) / (28.0 if _track.is_single(s) else 38.0)
			s += 10
		return time
	var gates: Array = f.checkpoints.duplicate()
	gates.append(f.finishS)
	time_left = leg.call(f.startS, gates[0]) + 12
	_checkpoint_bonus = []
	for i in range(1, gates.size()):
		_checkpoint_bonus.append(leg.call(gates[i - 1], gates[i]) + 3)
	_next_checkpoint = 0
	_out_of_time = false
	_warned = false


## Swap cars with the rival who drives `id` (they take over your old car).
func set_player_car(id: String) -> void:
	var target: Vehicle = null
	for v: Vehicle in racers:
		if v.spec.id == id:
			target = v
	if target == null or target == player:
		return
	var old := player
	var ai: AIDriver = null
	for a: AIDriver in _ais:
		if a.vehicle == target:
			ai = a
	var rival_name := target.driver_name
	target.is_player = true
	target.driver_name = "Jij"
	old.is_player = false
	old.driver_name = rival_name
	ai.vehicle = old
	_auto_driver.vehicle = target
	player = target
	racers.erase(target)
	racers.push_front(target)
	reset()


func set_stage(i: int) -> void:
	stage_index = i
	_track.set_stage(i)
	reset()


## Menu → race.
func start() -> void:
	state = "countdown"
	reset()


## Race → menu (grid reset, cars frozen).
func to_menu() -> void:
	state = "menu"
	reset()


func start_countdown() -> void:
	state = "countdown"
	_countdown_t = 0.0
	_countdown_step = -1
	_hud.set_help_visible(true)


func _wire_events() -> void:
	_events.on("impact", func(e: Dictionary) -> void:
		var a: Vehicle = e.a
		var b: Vehicle = e.b
		var n := mini(60, floori(e.strength * 2.5))
		var bvx := b.vx if b != null else a.vx
		var bvz := b.vz if b != null else a.vz
		_fx.spark_burst(e.x, e.y, e.z, n, (a.vx + bvx) * 0.4, (a.vz + bvz) * 0.4)
		if e.strength > 10:
			_fx.debris(e.x, e.y, e.z, 8, a.vx, a.vz)
		_models[a].kick(e.x - a.x, e.z - a.z, a, e.strength)
		if b != null:
			_models[b].kick(e.x - b.x, e.z - b.z, b, e.strength)
		var involves_player := a == player or b == player
		var dist := Vector2(e.x - player.x, e.z - player.z).length()
		if dist < 120:
			_audio.crash(e.strength * (1.0 if involves_player else maxf(0.2, 1 - dist / 120)))
		if involves_player:
			stats.biggestHit = maxf(stats.biggestHit, e.strength)
			_cam.add_shake(minf(0.9, e.strength / 20.0))
			_rumble.call(e.strength / 15.0, e.strength / 10.0, 180)
			if e.kind == "car" and e.strength > 9:
				_hud.message(HIT_WORDS[randi() % HIT_WORDS.size()], "#ffd400", false, 0.9)
			# Chaos draws the police: hitting traffic or the police themselves.
			var other: Vehicle = b if a == player else a
			if other != null and state == "racing":
				# One crash is one offence, however many contacts the physics reports.
				var last: float = _heat_hits.get(other, -9.0)
				if other.role == "traffic" and e.strength > 5 and _sim_time - last > 1.5:
					_heat_hits[other] = _sim_time
					police.add_heat(minf(0.35, e.strength * 0.018))
				# Being PIT'ed by the police isn't an offence; ramming them is.
				if other.role == "police" and e.strength > 3 and not other.ramming and _sim_time - last > 1.5:
					_heat_hits[other] = _sim_time
					police.add_heat(0.4)
	)

	_events.on("scrape", func(e: Dictionary) -> void:
		var v: Vehicle = e.vehicle
		if randf() < e.intensity * 0.9:
			_fx.spark_burst(e.x, e.y, e.z, 2, v.vx * 0.7 + e.nx * 2, v.vz * 0.7 + e.nz * 2, 5)
		if v == player:
			_player_scrape = maxf(_player_scrape, e.intensity)
	)

	_events.on("wreck", func(e: Dictionary) -> void:
		var victim: Vehicle = e.victim
		var attacker: Vehicle = e.attacker
		var p := _local_to_world(victim, 0, 0, 0.8)
		_fx.spark_burst(p.x, p.y, p.z, 80, victim.vx * 0.5, victim.vz * 0.5, 14)
		for i in 30:
			_fx.flame(p.x, p.y + randf(), p.z)
		_fx.debris(p.x, p.y, p.z, 30, victim.vx, victim.vz)
		var dist := Vector2(victim.x - player.x, victim.z - player.z).length()
		if dist < 200:
			_audio.crash(25 * maxf(0.3, 1 - dist / 200))
		if victim == player:
			stats.wrecks += 1
			# A total loss should hurt: the nitro tank goes up in flames with the car.
			victim.nitro = 0.0
			_hud.message("TOTAL LOSS!", "#ff2a2a", true, 2.2)
			_announcer.say("Total loss!", true)
			_slow_mo(0.3, 1.2)
			_respawn_t = 2.6
			_cam.add_shake(1)
			_rumble.call(1, 1, 600)
			return
		var by_player := attacker == player
		if victim.is_racer:
			if by_player:
				_hud.message("TAKEDOWN!", "#ffd400", true, 2)
				_bullet = minf(1.0, _bullet + 0.25)
				_announcer.say("Takedown! %s ligt eruit!" % victim.driver_name, true)
				_hud.message("%s ligt eruit!" % victim.driver_name, "#ffffff", false, 2)
				_slow_mo(0.35, 1.1)
				_cam.add_shake(0.6)
				_rumble.call(0.8, 1, 400)
				# Taking out rivals is the game, not a crime: only a little heat (the crash itself adds some).
				police.add_heat(0.2)
			else:
				_hud.message("%s is total loss" % victim.driver_name, "#ff9a3c", false, 1.6)
		elif by_player and victim.role == "police":
			_hud.message("AGENT UITGESCHAKELD!", "#4f8bff", true, 2)
			_announcer.say("Agent uitgeschakeld!")
			_slow_mo(0.4, 0.9)
			police.add_heat(1.2)
		elif by_player:
			_hud.message("BOEM!", "#ff9a3c", false, 1)
			police.add_heat(0.8)
	)

	_events.on("ram", func(e: Dictionary) -> void:
		var vehicle: Vehicle = e.vehicle
		if vehicle == player:
			_audio.whoosh()
			_rammed_once = true
			# Shoving rivals is the race; shoving civilians or the police draws attention.
			if vehicle.ram_target != null and not vehicle.ram_target.is_racer and state == "racing":
				police.add_heat(0.15)
		elif vehicle.is_racer and vehicle.ram_target == player and _sim_time - _last_taunt > 6 and randf() < 0.5:
			# Rivals talk trash when they go for you.
			for ai: AIDriver in _ais:
				if ai.vehicle == vehicle:
					var taunts: Array = ai.personality.taunts
					if not taunts.is_empty():
						_hud.taunt(vehicle.driver_name, taunts[randi() % taunts.size()])
						_last_taunt = _sim_time
	)

	_events.on("nearMiss", func(e: Dictionary) -> void:
		var vehicle: Vehicle = e.vehicle
		var other: Vehicle = e.other
		if vehicle == player:
			if other.role == "traffic" and randf() < 0.6:
				_audio.horn(other.spec.get("kind", "") == "truck", 0.8)
			_hud.message("RAKELINGS!", "#36c6ff", false, 0.9)
			_bullet = minf(1.0, _bullet + 0.05)
			stats.nearMisses += 1
			vehicle.nitro = minf(1.0, vehicle.nitro + Config.T.nitroFillNearMiss)
	)

	_events.on("message", func(m: Dictionary) -> void:
		var big: bool = m.get("big", false)
		_hud.message(m.text, m.get("color", "#ffd400"), big, 2.0 if big else 1.4)
		if m.text == "POLITIE!":
			_announcer.say("Politie!")
		if String(m.text).begins_with("WEGBLOKKADE"):
			_announcer.say("Wegblokkade verderop!")
	)

	_events.on("flash", func(e: Dictionary) -> void:
		_hud.flash()
		_audio.flash()
		_hud.message("GEFLITST! %d km/u" % roundi(e.kmh), "#ffffff", false, 1.6)
		_announcer.say("Geflitst!")
	)

	_events.on("busted", func(e: Dictionary) -> void:
		_hud.message("BEKEURING!", "#ff2a2a", true, 2)
		stats.busted += 1
		_announcer.say("Bekeuring! %d seconden erbij." % e.penalty, true)
		_hud.message("+%d seconden" % e.penalty, "#ffffff", false, 2)
		_audio.crash(6)
	)


func _slow_mo(scale: float, seconds: float) -> void:
	_slow_mo_scale = scale
	_slow_mo_t = seconds
	time_scale = minf(scale, Config.T.bulletScale if _bullet_on else 1.0)


func _set_bullet(on: bool) -> void:
	if on == _bullet_on:
		return
	_bullet_on = on
	_music.set_slow(on)
	if on:
		_hud.message("BULLET TIME", "#c9a2ff", true, 1.0)
		_audio.whoosh()


func _local_to_world(v: Vehicle, lx: float, lz: float, up: float) -> Vector3:
	var fx := sin(v.heading)
	var fz := cos(v.heading)
	return Vector3(v.x + fx * lz - fz * lx, v.y + up, v.z + fz * lz + fx * lx)


## Per-render-frame logic: input, state machine, real-time timers.
func handle_input(c: InputCtl.Controls, real_dt: float) -> void:
	if c.nextTrack:
		_music.next()
	if c.volumeUp or c.volumeDown:
		var vol := _music.change_volume(0.1 if c.volumeUp else -0.1)
		_hud.message("MUZIEK %d%%" % roundi(vol * 100), "#ffffff", false, 0.8)

	if state == "menu":
		return
	_restart_hold = c.restartHold
	if c.restart:
		reset()
		return
	_music.set_muffled(paused or time_scale < 1)
	if paused:
		return

	# Real-time slow-mo timer (takedowns) and the player's bullet time.
	if _slow_mo_t > 0:
		_slow_mo_t -= real_dt
		if _slow_mo_t <= 0:
			_slow_mo_scale = 1.0
	var can := state == "racing" and not player.wrecked and not player.finished
	if c.bulletTime and can:
		if _bullet_on:
			_set_bullet(false)
		elif _bullet > 0.15:
			_set_bullet(true)
		else:
			_hud.message("SLOWMO LEEG", "#c9a2ff", false, 0.8)
	if _bullet_on:
		_bullet -= real_dt / Config.T.bulletSeconds
		if _bullet <= 0 or not can:
			_bullet = maxf(0.0, _bullet)
			_set_bullet(false)
	elif state == "racing":
		_bullet = minf(1.0, _bullet + real_dt / Config.T.bulletRecharge)
	time_scale = minf(_slow_mo_scale, Config.T.bulletScale if _bullet_on else 1.0)

	var p := player
	if state == "finished" or p.finished:
		# Roll to a stop (holding the brake at a standstill would mean reversing).
		p.input.throttle = 0.0
		p.input.brake = 0.4 if p.forward_speed > 0.5 else 0.0
		p.input.steer = 0.0
		p.input.nitro = false
		p.input.handbrake = false
	elif not autopilot:
		p.input.throttle = c.throttle
		p.input.brake = c.brake
		p.input.steer = c.steer
		p.input.handbrake = c.handbrake
		p.input.nitro = c.nitro
		if c.ramLeft:
			p.input.ram_left = true
		if c.ramRight:
			p.input.ram_right = true
		if c.ramAuto:
			p.input.ram_auto = true
	_look_back = c.lookBack and state != "finished"
	_cam.look_back = _look_back

	_reset_cooldown -= real_dt
	if c.reset and state == "racing" and not p.wrecked and _reset_cooldown <= 0:
		_respawn(p, false)
		_reset_cooldown = 2.0


func _respawn(v: Vehicle, repair: bool) -> void:
	var t := _track
	var lanes: Array = Config.LANE_CENTERS
	# Nearest lane, but never the oncoming lane of the two-lane N35.
	var lane: float = lanes[1]
	if not t.is_single(v.s):
		lane = lanes[0] if absf(lanes[0] - v.d) < absf(lanes[1] - v.d) else lanes[1]
	# Find a spot not overlapping anyone.
	var s := v.s
	for tries in 12:
		var taken := false
		for o: Vehicle in vehicles:
			if o != v and o.active and absf(o.s - s) < o.half_l + v.half_l + 4 and absf(o.d - lane) < 2.6:
				taken = true
				break
		if not taken:
			break
		s += 8
	v.place(t, minf(s, t.length - 10), lane, 18.0 if repair else 22.0)
	v.stun = 0.0
	v.ang_vel = 0.0
	if v == player:
		_player_stuck = 0.0
	if repair:
		v.repair(20)
		_models[v].repair()
		v.frozen = false


## Fixed-timestep simulation.
func step(dt: float) -> void:
	if paused or state == "menu":
		return
	_sim_time += dt
	var t := _track

	if state == "countdown":
		_countdown_t += dt
		var stp := floori(_countdown_t)
		if stp != _countdown_step:
			_countdown_step = stp
			if stp < 3:
				_hud.countdown(str(3 - stp))
				_audio.beep(false)
				_announcer.say(["Drie", "Twee", "Eén"][stp], true, 1.3)
			else:
				_hud.countdown("GAS GEAVEN!", true)
				_audio.beep(true)
				_announcer.say("Gas geaven!", true, 1.2, 1.1)
				state = "racing"
				for v: Vehicle in racers:
					v.frozen = false
				_music.play_race()
	else:
		race_time += dt
	# Race time, not wall time: a pause doesn't eat the help line.
	if state == "racing" and not _help_shown and race_time > 10:
		_help_shown = true
		_hud.set_help_visible(false)
	if state == "racing":
		# Bullet time slows the world, not the checkpoint clock: it runs in real time.
		_tick_clock(dt / maxf(time_scale, 0.01) if _bullet_on else dt)
		stats.topSpeed = maxf(stats.topSpeed, player.speed * 3.6)
		stats.distance += maxf(0.0, player.along_speed) * dt

	var tp := Time.get_ticks_usec() if profile else 0
	_active = vehicles.filter(func(v): return v.active)
	# Sorted along the road: the drivers look only at the cars around them.
	_active.sort_custom(func(a, b): return a.s < b.s)
	var all := _active

	if autopilot and not player.finished:
		_auto_driver.update(dt, t, all, _ais[0].vehicle)
		if _auto_driver.needs_reset:
			_auto_driver.needs_reset = false
			_respawn(player, false)
	for ai: AIDriver in _ais:
		var v := ai.vehicle
		v.damage_scale = Config.T.aiSingleDamage if t.is_single(v.s) else 1.0
		ai.update(dt, t, all, player)
		if v.finished:
			v.input.throttle = 0.0
			v.input.brake = 0.5 if v.forward_speed > 0.5 else 0.0
		if ai.needs_reset and not v.wrecked:
			ai.needs_reset = false
			ai.reset_lane()
			_respawn(v, false)
	if profile:
		prof.ai = prof.get("ai", 0) + Time.get_ticks_usec() - tp
		tp = Time.get_ticks_usec()
	traffic.update(dt, all, racers, player)
	if profile:
		prof.traffic = prof.get("traffic", 0) + Time.get_ticks_usec() - tp
		tp = Time.get_ticks_usec()
	police.update(dt, player, all, state == "racing")

	for v: Vehicle in all:
		v.update(dt, _sim_time, t, _events, all)
	if profile:
		prof.vehicles = prof.get("vehicles", 0) + Time.get_ticks_usec() - tp
		tp = Time.get_ticks_usec()
	# Sweep along the road: only cars close in s can touch.
	all.sort_custom(func(a, b): return a.proj.s < b.proj.s)
	var n := all.size()
	for i in n:
		var a: Vehicle = all[i]
		var reach := a.half_l + 9.0
		for j in range(i + 1, n):
			var b: Vehicle = all[j]
			if b.proj.s - a.proj.s > reach:
				break
			Collisions.collide(a, b, _sim_time, _events)
	if profile:
		prof.collisions = prof.get("collisions", 0) + Time.get_ticks_usec() - tp
		tp = Time.get_ticks_usec()

	# Finish line
	var finish_s: float = t.features.finishS
	for v: Vehicle in racers:
		var open := state == "racing" or (state == "finished" and not v.is_player)
		if not v.finished and not v.wrecked and v.s >= finish_s and open and not (v.is_player and _out_of_time):
			v.finished = true
			v.finish_time = race_time + v.penalty
			_finish_order.append(v)
			if v.is_player:
				var pos := 0
				for o: Vehicle in _finish_order:
					if o.finish_time <= v.finish_time:
						pos += 1
				_hud.message("WINNAAR!" if pos == 1 else "%de PLAATS" % pos, "#4dff6a" if pos <= 3 else "#ff9a3c", true, 2.5)
				var line := "Winnaar! Gas geaven!" if pos == 1 else ("Finish! Plaats %d" % pos if pos <= 3 else "Finish. Plaats %d. Dat mot beter." % pos)
				_announcer.say(line, true)
				if v.penalty > 0:
					_hud.message("incl. %d s boete" % v.penalty, "#ff9a3c", false, 2.5)
				_finished_at = race_time
				state = "finished"
	# Wait out the player's penalty so rivals crossing in that window rank fairly.
	if state == "finished" and not _results_shown and race_time - _finished_at > maxf(2.5, player.penalty):
		_results_shown = true
		var rank := ranking()
		var position := rank.find(player) + 1
		var result := {
			"rows": standings(),
			"position": position,
			"time": player.finish_time if player.finished else race_time,
			"takedowns": player.takedowns,
			"outOfTime": _out_of_time,
			"qualified": not _out_of_time and position <= 3,
			"car": player.spec.name,
			"stage": stage_index,
			"stats": stats.duplicate(),
		}
		if on_finished.is_valid():
			on_finished.call(result)
		_music.play_title()

	# Player respawn after a total loss.
	if player.wrecked and _respawn_t > 0:
		_respawn_t -= dt / maxf(time_scale, 0.01)
		if _respawn_t <= 0:
			_respawn(player, true)
			_hud.message("OPGELAPT!", "#4dff6a", false, 1.2)
			_announcer.say("Kump wal goed!")

	# Catch-up for the player: a little extra power when the leader got away.
	var p := player
	var leader := -INF
	for v: Vehicle in racers:
		if v != p and not v.wrecked and not v.finished:
			leader = maxf(leader, v.s)
	var behind := clampf((leader - p.s - 60) / 300.0, 0.0, 1.0) if state == "racing" else 0.0
	p.power_factor = (1 + Config.T.playerCatchUp * behind) * (1 + _slipstream(p, dt))

	# Stuck? Then offer the reset button.
	var fr := t.frame(p.s)
	var rel := wrapf(p.heading - fr.heading, -PI, PI)
	var lost := absf(rel) > 1.3 or absf(p.d) > Config.ROAD_HALF_WIDTH + 0.5
	var stuck := state == "racing" and race_time > 5 and not p.wrecked and not p.finished and not p.frozen and (p.speed < 4 or lost)
	_player_stuck = _player_stuck + dt if stuck else 0.0
	# Still stuck after the prompt has been up a while: put the car back on the road ourselves.
	if _player_stuck > (3.5 if lost else 5.0):
		_respawn(p, false)
		_hud.message("TERUG OP DE WEG", "#ffffff", false, 1)
	_context_hints()
	_detect_near_misses()
	if profile:
		prof.rest = prof.get("rest", 0) + Time.get_ticks_usec() - tp
		prof.steps = prof.get("steps", 0) + 1


## Slipstream for the player: tucked in close behind another car the air is easier (more power,
## nitro trickles in); after a while the slingshot is charged and pulling out gives a burst.
## Returns the extra power factor.
func _slipstream(p: Vehicle, dt: float) -> float:
	var T := Config.T
	var drafting := false
	if state == "racing" and not p.wrecked and not p.finished and p.along_speed > 20:
		for o: Vehicle in _active:
			if o == p or o.wrecked or o.along_speed < 12:
				continue
			var ds := o.s - p.s - o.half_l - p.half_l
			if ds > 0.5 and ds < 24 and absf(o.d - p.d) < 1.5:
				drafting = true
				break
	if drafting:
		var before := _draft_t
		_draft_t += dt
		p.nitro = minf(1.0, p.nitro + 0.05 * dt)
		if before < T.draftCharge and _draft_t >= T.draftCharge:
			_hud.message("IN DE SLIPSTREAM", "#8fd3ff", false, 1.2)
	else:
		if _draft_t >= T.draftCharge and state == "racing":
			_sling_t = T.slingshotTime
			_hud.message("SLINGSHOT!", "#8fd3ff", true, 1.1)
			_audio.whoosh()
			_cam.add_shake(0.2)
		_draft_t = 0.0
	if _sling_t > 0:
		_sling_t -= dt
		return T.slingshotBonus
	return T.draftBonus * minf(1.0, _draft_t / 0.8) if drafting else 0.0


func _tick_clock(dt: float) -> void:
	var f := _track.features
	var p := player
	if _next_checkpoint < f.checkpoints.size() and p.s >= f.checkpoints[_next_checkpoint]:
		var bonus: float = _checkpoint_bonus[_next_checkpoint]
		time_left += bonus
		_next_checkpoint += 1
		_warned = false
		_hud.message("CHECKPOINT!", "#4dff6a", true, 1.8)
		_hud.message("+%d seconden" % roundi(bonus), "#ffffff", false, 1.8)
		_audio.chime()
		_announcer.say("Checkpoint! Extra tijd!")
	time_left = maxf(0.0, time_left - dt)
	if not _warned and time_left < 10:
		_warned = true
		_announcer.say("Tien seconden!", true)
	# One last chance per race: a few more seconds, paid for with a penalty on the finish time.
	if time_left <= 0 and not p.finished and not _last_chance_used:
		_last_chance_used = true
		time_left = 12.0
		p.penalty += 10
		_hud.message("LAATSTE KANS!", "#ff9a3c", true, 2)
		_hud.message("+12 s tijd · 10 s straf", "#ffffff", false, 2)
		_announcer.say("Laatste kans! Gas geaven!", true)
		_audio.chime()
	if time_left <= 0 and not p.finished:
		_out_of_time = true
		state = "finished"
		_finished_at = race_time
		p.input.throttle = 0.0
		_hud.message("TIJD OP!", "#ff2a2a", true, 2.5)
		_announcer.say("Tijd op!", true)


## Explain a control the moment it becomes useful (a few times, then trust the player).
func _context_hints() -> void:
	if state != "racing" or _sim_time - _last_hint < 6:
		return
	var p := player
	if p.wrecked:
		return
	var show := func(k: String, text: String) -> bool:
		if _hints_left[k] <= 0:
			return false
		_hints_left[k] -= 1
		_last_hint = _sim_time
		_hud.message(text, "#ffffff", false, 2.2)
		return true
	var rival_beside := func(dir: int) -> bool:
		var tg := p.find_ram_target(_active, dir)
		return not tg.is_empty() and tg.v.is_racer
	if not _rammed_once and p.ram_cooldown <= 0 and (rival_beside.call(-1) or rival_beside.call(1)):
		var l: String = _key_label.call("ramLeft")
		var r: String = _key_label.call("ramRight")
		var ram := l if l == r else "%s / %s" % [l, r]
		if show.call("ram", "%s: RAM ZE DE VANGRAIL IN!" % ram):
			return
	if p.nitro > 0.99 and not p.nitro_active and show.call("nitro", "NITRO VOL · %s" % _key_label.call("nitro")):
		return
	if _bullet > 0.99 and police.stars >= 2 and show.call("slow", "%s: BULLET TIME" % _key_label.call("bulletTime")):
		return
	if police.stars >= 1 and _key_label.call("lookBack") != "" and show.call("lookBack", "%s: ACHTEROM KIJKEN" % _key_label.call("lookBack")):
		return


## Is there a rival close alongside on this side (not ahead or behind)?
func _rival_alongside(dir: int) -> bool:
	var p := player
	for o: Vehicle in racers:
		if o == p or o.wrecked or o.finished:
			continue
		var side := (o.d - p.d) * dir
		if absf(o.s - p.s) < 9 and side > 0.8 and side < 7:
			return true
	return false


## Push the key labels for the device in use to the HUD whenever they change.
func _sync_keys() -> void:
	var k := _key_label
	var touch: bool = k.call("nitro") == "NITRO"
	var ram_l: String = "◀" if touch else k.call("ramLeft")
	var ram_r: String = "▶" if touch else k.call("ramRight")
	var gamepad: bool = k.call("throttle") == "R2"
	var help := ""
	if gamepad:
		help = "R2/L2 gas-rem · stick sturen · ✕ handrem · ○ nitro · L1/R1 rammen · L3/R3 bullet time · rechterstick ↓ achterom · △ terug op weg · houd SELECT herstart"
	else:
		help = "%s / %s gas-rem  ·  %s / %s sturen  ·  %s handrem  ·  %s nitro  ·  %s bullet time  ·  %s/%s rammen  ·  %s achterom  ·  %s terug op weg  ·  houd R herstart  ·  M geluid  ·  N volgend nummer" % [
			k.call("throttle"), k.call("brake"), k.call("left"), k.call("right"), k.call("handbrake"), k.call("nitro"),
			k.call("bulletTime"), k.call("ramLeft"), k.call("ramRight"), k.call("lookBack"), k.call("reset")]
	var restart := "SELECT" if gamepad else "R"
	var sig := "%s|%s|%s" % [ram_l, ram_r, help]
	if sig == _key_sig:
		return
	_key_sig = sig
	_hud.set_keys({"ramL": ram_l, "ramR": ram_r, "reset": k.call("reset"), "help": help, "restart": restart, "touch": touch})


func _detect_near_misses() -> void:
	var p := player
	if p.wrecked or state != "racing":
		return
	for o: Vehicle in _active:
		if o == p:
			continue
		var ds := o.s - p.s
		var prev = _prev_ds.get(o)
		_prev_ds[o] = ds
		if prev == null or o.wrecked or absf(ds) > 20:
			continue
		if signf(prev) != signf(ds):
			var gap := absf(o.d - p.d) - p.half_w - o.half_w
			var rel := absf(p.along_speed - o.along_speed)
			var recent_contact := _sim_time - p.last_contact_time < 1 and p.last_hit_by == o
			if gap < 1.0 and gap > 0 and rel > 6 and not recent_contact:
				_events.emit("nearMiss", {"vehicle": p, "other": o})


func ranking() -> Array:
	var finished := _finish_order.duplicate()
	finished.sort_custom(func(a, b): return a.finish_time < b.finish_time)
	var running := racers.filter(func(v): return not v.finished and not v.wrecked)
	running.sort_custom(func(a, b): return a.s > b.s)
	var out := racers.filter(func(v): return not v.finished and v.wrecked)
	return finished + running + out


func standings() -> Array:
	var rows := []
	for v: Vehicle in ranking():
		rows.append({
			"name": v.driver_name, "car": v.spec.name, "isPlayer": v.is_player, "wrecked": v.wrecked and not v.finished,
			"finished": v.finished, "time": v.finish_time if v.finished else -1.0, "takedowns": v.takedowns, "penalty": v.penalty,
		})
	return rows


## Per-render-frame visuals: models, particles, audio, HUD.
func render(dt: float, time: float) -> void:
	_hud.show_reset(_player_stuck > 1.2 and state == "racing")
	var sim_dt := 0.0 if paused else dt * time_scale
	var p := player
	var eye := _cam.camera.global_position
	for v: Vehicle in vehicles:
		var model: CarModel = _models[v]
		# Beyond 700 m a car is a few pixels in the haze: skip it. Past 200 m, skip wheels.
		var d2 := (v.x - eye.x) * (v.x - eye.x) + (v.z - eye.z) * (v.z - eye.z)
		var far := d2 > 700 * 700
		model.root.visible = v.active and not far and not (state == "menu" and showroom != null and v.is_racer and v != showroom)
		if not model.root.visible:
			continue
		model.set_detail(d2 < 200 * 200)
		model.sync(v, sim_dt, time)
		if sim_dt <= 0:
			continue
		# Effects only near the player (traffic far away doesn't need smoke).
		if absf(v.s - p.s) > 400:
			continue
		var dmg := maxf(v.damage.front, v.total_damage)
		# Engine smoke grows with front damage; wrecks burn.
		if v.wrecked:
			var w := _local_to_world(v, 0, v.half_l * 0.6, 1)
			if randf() < 0.7:
				_fx.flame(w.x, w.y, w.z)
			if randf() < 0.5:
				_fx.smoke_puff(w.x, w.y + 0.6, w.z, 1)
		elif dmg > 35 and randf() < (dmg - 35) / 60:
			var w := _local_to_world(v, 0, v.half_l * 0.65, 0.9)
			_fx.smoke_puff(w.x, w.y, w.z, minf(1.0, (dmg - 35) / 50), v.vx, v.vz)
		if v.nitro_active:
			for side in [-0.35, 0.35]:
				var w := _local_to_world(v, side, -v.half_l - 0.15, 0.4)
				_fx.nitro_flame(w.x, w.y, w.z, v.vx, v.vz)
		if v.drifting or (v.braking and v.speed > 25 and randf() < 0.3):
			for side in [-0.75, 0.75]:
				var w := _local_to_world(v, side, -v.half_l + 0.7, 0.2)
				_fx.tyre_smoke(w.x, w.y, w.z)
	traffic.render_oncoming(sim_dt, p.s)
	_fx.update(sim_dt)
	if state != "menu":
		_cam.update(p, maxf(sim_dt, 0.0001), time)

	_audio.engine(p.speed, p.input.throttle, p.nitro_active, not p.wrecked and state != "menu")
	_audio.scrape(0.0 if paused else _player_scrape)
	var squeal := 1.0 if p.drifting else (0.5 if p.braking and p.speed > 22 else 0.0)
	_audio.squeal(0.0 if paused or p.wrecked else squeal)
	_audio.siren(0.0 if paused else maxf(0.0, 1 - police.nearest_siren / 220.0))
	_player_scrape = 0.0

	_sync_keys()
	var racing := state == "racing" and not p.wrecked and not paused
	var rank := ranking()
	var st: Dictionary = _track.stage
	_hud.update_state({
		"player": p,
		"position": rank.find(p) + 1,
		"total": racers.size(),
		"rows": standings(),
		"distanceLeft": _track.features.finishS - p.s,
		"raceTime": race_time + p.penalty,
		"stars": police.stars,
		"heat": police.heat,
		"sirenNear": police.nearest_siren < 120,
		"bust": police.bust_progress,
		"timeLeft": -1.0 if state == "menu" else time_left,
		"bullet": _bullet,
		"bulletOn": _bullet_on,
		"stage": "ETAPPE %d/5 · %s → %s" % [st.id, String(st.from).to_upper(), String(st.to).to_upper()],
		"ramTargetL": racing and not p.find_ram_target(_active, -1).is_empty(),
		"ramTargetR": racing and not p.find_ram_target(_active, 1).is_empty(),
		"sideL": racing and _rival_alongside(-1),
		"sideR": racing and _rival_alongside(1),
		"lookBack": _look_back,
		"restartHold": 0.0 if state == "menu" else _restart_hold,
	})
