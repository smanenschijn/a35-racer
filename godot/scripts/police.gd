class_name PoliceManager
extends RefCounted
## Wanted level ("heat", 0..5 stars) driven by the player's chaos, pursuing units that try to box
## the player in, roadblocks from 3 stars, and speed cameras along the road. Port of src/game/Police.ts.

var heat := 0.0
var _calm := 0.0
var _units: Array = [] # {v, state: parked|chase|leave, lane, lane_timer, attack_timer}
var _block_cars: Array = []
var _roadblock := {} # {s, cars}
var _roadblock_cooldown := 0.0
var _bust_timer := 0.0
var _spawn_cooldown := 0.0
var cameras: Array = [] # {s, flash: StandardMaterial3D, flash_t}
var _prev_player_s := 0.0
var _track: Track
var _events: EventBus
var _repair: Callable
## Distance to the nearest chasing unit with its siren on (for audio/HUD).
var nearest_siren := INF


## deps: track, events, create() -> Vehicle, repair(v), parent: Node3D
func _init(deps: Dictionary) -> void:
	_track = deps.track
	_events = deps.events
	_repair = deps.repair
	for i in 3:
		var v: Vehicle = deps.create.call()
		v.active = false
		_units.append({"v": v, "state": "parked", "lane": Config.LANE_CENTERS[1], "lane_timer": 0.0, "attack_timer": 2.0})
	for i in 3:
		var v: Vehicle = deps.create.call()
		v.active = false
		_block_cars.append(v)
	_build_cameras(deps.parent)


var stars: int:
	get:
		return mini(5, floori(heat + 1e-6))


var vehicles: Array:
	get:
		var out := []
		for u in _units:
			out.append(u.v)
		out.append_array(_block_cars)
		return out


func add_heat(amount: float) -> void:
	var before := stars
	heat = clampf(heat + amount, 0.0, 5.99)
	_calm = 0.0
	if stars > before:
		_events.emit("message", {"text": "POLITIE!" if before == 0 else "★".repeat(stars), "color": "#4f8bff", "big": before == 0})


func _build_cameras(parent: Node3D) -> void:
	var t := _track
	var pole := TrackBuilder.mat(Color("8a8f96"), 0.4, 0.6)
	var housing := TrackBuilder.mat(Color("3a3f46"), 0.5, 0.4)
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.12
	pole_mesh.bottom_radius = 0.14
	pole_mesh.height = 3.2
	pole_mesh.radial_segments = 8
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.7, 0.6)
	var lens := BoxMesh.new()
	lens.size = Vector3(0.3, 0.2, 0.05)
	var s := 480.0
	while s < t.length - 200:
		var flash := TrackBuilder.glow_mat(Color("222222"), Color.WHITE, 0.0)
		var g := Node3D.new()
		for part in [[pole_mesh, pole, Vector3(0, 1.6, 0)], [box, housing, Vector3(0, 3.3, 0)], [lens, flash, Vector3(0, 3.3, -0.32)]]:
			var mi := MeshInstance3D.new()
			mi.mesh = part[0]
			mi.material_override = part[1]
			mi.position = part[2]
			g.add_child(mi)
		var fr := t.frame(s)
		g.position = Vector3(fr.x + fr.rx * 7.4, fr.y, fr.z + fr.rz * 7.4)
		g.rotation.y = fr.heading
		parent.add_child(g)
		cameras.append({"s": s, "flash": flash, "flash_t": 0.0})
		s += 760


func reset() -> void:
	heat = 0.0
	_calm = 0.0
	_bust_timer = 0.0
	_spawn_cooldown = 0.0
	_roadblock_cooldown = 10.0
	for u in _units:
		u.state = "parked"
		u.v.active = false
		u.v.siren_on = false
	_clear_roadblock()
	_prev_player_s = 0.0


func _clear_roadblock() -> void:
	for v: Vehicle in _block_cars:
		v.active = false
		v.siren_on = false
	_roadblock = {}


func _desired_units() -> int:
	return [0, 1, 1, 2, 2, 3][stars]


func update(dt: float, player: Vehicle, all: Array, racing: bool) -> void:
	var T := Config.T
	var t := _track

	# --- Speed cameras ---
	var kmh := player.speed * 3.6
	for cam in cameras:
		cam.flash_t = maxf(0.0, cam.flash_t - dt)
		(cam.flash as StandardMaterial3D).emission_energy_multiplier = 12.0 * cam.flash_t if cam.flash_t > 0 else 0.0
		if racing and _prev_player_s < cam.s and player.s >= cam.s and kmh > T.speedCameraKmh:
			cam.flash_t = 0.35
			_events.emit("flash", {"kmh": kmh})
			add_heat(0.7)
	_prev_player_s = player.s

	# --- Heat decay ---
	_calm += dt
	var chasers_close := false
	for u in _units:
		if u.state == "chase" and absf(u.v.s - player.s) < 150:
			chasers_close = true
	if _calm > T.heatDecayDelay:
		heat = maxf(0.0, heat - T.heatDecay * (0.35 if chasers_close else 1.0) * dt)

	# --- Spawning pursuit units ---
	_spawn_cooldown -= dt
	var chasing := 0
	for u in _units:
		if u.state == "chase":
			chasing += 1
	if racing and chasing < _desired_units() and _spawn_cooldown <= 0:
		for u in _units:
			if u.state == "parked":
				_spawn_unit(u, player, all)
				break
		_spawn_cooldown = 4.0
	if stars == 0:
		for u in _units:
			if u.state == "chase":
				_release(u)

	# --- Drive units ---
	nearest_siren = INF
	for u in _units:
		var v: Vehicle = u.v
		if not v.active:
			continue
		if u.state == "chase":
			_chase(u, player, all, dt)
		elif u.state == "leave":
			_cruise(u)
		if v.wrecked and absf(v.s - player.s) > 120:
			_park(u)
		if u.state == "leave" and absf(v.s - player.s) > 300:
			_park(u)
		if v.siren_on and not v.wrecked:
			nearest_siren = minf(nearest_siren, Vector2(v.x - player.x, v.z - player.z).length())

	# --- Roadblocks ---
	_roadblock_cooldown -= dt
	if not _roadblock.is_empty() and player.s > _roadblock.s + 150:
		_clear_roadblock()
	if racing and _roadblock.is_empty() and stars >= 3 and _roadblock_cooldown <= 0:
		var s := player.s + 650
		if s < t.features.finishS - 80:
			_place_roadblock(s, all)
		_roadblock_cooldown = 25.0
	if not _roadblock.is_empty():
		for v: Vehicle in _roadblock.cars:
			if v.active and not v.wrecked:
				nearest_siren = minf(nearest_siren, Vector2(v.x - player.x, v.z - player.z).length())

	# --- Busted: pinned down by the police ---
	var pinned := false
	if racing and stars > 0 and player.speed < 5 and not player.wrecked:
		for p: Vehicle in vehicles:
			if p.active and not p.wrecked and Vector2(p.x - player.x, p.z - player.z).length() < 7.5:
				pinned = true
				break
	_bust_timer = _bust_timer + dt if pinned else maxf(0.0, _bust_timer - dt * 2)
	if _bust_timer > T.bustSeconds:
		var fine: int = stars * T.bustPenalty
		player.penalty += fine
		_events.emit("busted", {"penalty": fine})
		heat = maxf(0.0, heat - 2.5)
		_bust_timer = 0.0
		for u in _units:
			if u.state == "chase":
				_release(u)


var bust_progress: float:
	get:
		return minf(1.0, _bust_timer / Config.T.bustSeconds)


func _spawn_unit(u: Dictionary, player: Vehicle, all: Array) -> void:
	var t := _track
	# Come from behind, out of view; near the start, wait on the shoulder ahead instead.
	var behind := player.s > 260
	var s := player.s - 220 if behind else player.s + 400
	var lane: float = Config.LANE_CENTERS[randi() % 2] if behind else Config.SHOULDER
	var free := func(ss: float) -> bool:
		for o: Vehicle in all:
			if o != u.v and o.active and absf(o.s - ss) < 12 and absf(o.d - lane) < 2.5:
				return false
		return true
	for i in 6:
		if free.call(s):
			break
		s += -15.0 if behind else 15.0
	if s < 10 or s > t.length - 50:
		return
	var v: Vehicle = u.v
	_repair.call(v)
	v.place(t, s, lane, minf(player.speed + 8, 70) if behind else 0.0)
	v.active = true
	v.frozen = false
	v.siren_on = true
	u.state = "chase"
	u.lane = lane
	u.attack_timer = 2.0


func _release(u: Dictionary) -> void:
	u.state = "leave"
	u.v.siren_on = false


func _park(u: Dictionary) -> void:
	u.state = "parked"
	u.v.active = false
	u.v.siren_on = false


func _steer_to(v: Vehicle, lane: float) -> void:
	var spd := v.forward_speed
	var target := _track.point_at(v.s + 9 + maxf(0.0, spd) * 0.45, lane)
	var err := wrapf(atan2(target.x - v.x, target.z - v.z) - v.heading, -PI, PI)
	v.input.steer = clampf(-err * 3.2 + v.ang_vel * 0.15, -1.0, 1.0)


func _chase(u: Dictionary, player: Vehicle, all: Array, dt: float) -> void:
	var v: Vehicle = u.v
	var inp := v.input
	if v.wrecked:
		return
	u.lane_timer -= dt
	u.attack_timer -= dt
	var ds := player.s - v.s # > 0: player ahead of us
	var spd := v.forward_speed

	# Obstacles ahead in our lane.
	var gap := INF
	var ahead: Vehicle = null
	for o: Vehicle in all:
		if o == v or o == player or not o.active:
			continue
		var g := o.s - v.s - o.half_l - v.half_l
		if g > 0 and g < 45 and absf(o.d - u.lane) < o.half_w + v.half_w + 0.3 and g < gap:
			gap = g
			ahead = o

	# Lane choice: pull up next to the player, or get in front to block (3+ stars).
	if u.lane_timer <= 0:
		var lanes := Config.LANE_CENTERS.duplicate()
		lanes.append(Config.SHOULDER)
		var free_lane := func(l: float) -> bool:
			for o: Vehicle in all:
				if o != v and o != player and o.active and o.s - v.s > -6 and o.s - v.s < 35 and absf(o.d - l) < o.half_w + v.half_w + 0.3:
					return false
			return true
		var by_player := func(a, b): return absf(a - player.d) < absf(b - player.d)
		var want_lane: float
		if ds > 8 or stars >= 3:
			var sorted := lanes.duplicate()
			sorted.sort_custom(by_player)
			want_lane = sorted[0]
		else:
			var side_lanes := lanes.filter(func(l): return absf(l - player.d) > 2)
			side_lanes.sort_custom(by_player)
			want_lane = side_lanes[0] if not side_lanes.is_empty() else u.lane
		if ahead != null and gap < 30:
			var alt := lanes.filter(func(l): return absf(l - u.lane) > 1.5 and free_lane.call(l))
			if not alt.is_empty():
				alt.sort_custom(by_player)
				want_lane = alt[0]
		if want_lane != u.lane and (free_lane.call(want_lane) or absf(ds) < 15):
			u.lane = want_lane
		u.lane_timer = 0.8
	var line: float = u.lane
	if absf(ds) < 6:
		line = u.lane + (player.d - u.lane) * 0.3 # lean on the player
	_steer_to(v, clampf(line, -Config.ROAD_HALF_WIDTH + 1.2, Config.ROAD_HALF_WIDTH - 1.2))

	# Speed: catch up hard, then match (or brake-check from the front at 3+ stars).
	var wanted: float
	if ds > 10:
		wanted = v.spec.topSpeed * (1 + 0.04 * stars)
	elif ds > -6:
		wanted = player.forward_speed + ds * 0.6
	else:
		wanted = maxf(0.0, player.forward_speed - 6) if stars >= 3 else player.forward_speed - 10
	if ahead != null and gap < 25 and absf(ahead.d - u.lane) < 2:
		wanted = minf(wanted, ahead.along_speed + (gap - 6) * 0.6)
	v.power_factor = 1.15 if ds > 40 else 1.0
	inp.throttle = 1.0 if spd < wanted else 0.0
	inp.brake = minf(1.0, (spd - wanted) / 10 + 0.3) if spd > wanted + 3 else 0.0
	inp.nitro = false
	inp.handbrake = false

	# PIT: shove the player when alongside.
	var lateral := player.d - v.d
	if absf(ds) < 4 and absf(lateral) > 1.2 and absf(lateral) < 4 and u.attack_timer <= 0 and v.ram_cooldown <= 0:
		if lateral > 0:
			inp.ram_right = true
		else:
			inp.ram_left = true
		u.attack_timer = 3 - stars * 0.3


func _cruise(u: Dictionary) -> void:
	var v: Vehicle = u.v
	if v.wrecked:
		return
	_steer_to(v, Config.LANE_CENTERS[1])
	v.input.throttle = 0.5 if v.forward_speed < 24 else 0.0
	v.input.brake = 0.4 if v.forward_speed > 28 else 0.0


func _place_roadblock(s: float, all: Array) -> void:
	var slots := [Config.LANE_CENTERS[0], Config.LANE_CENTERS[1], Config.SHOULDER]
	var gap_index := randi() % slots.size()
	var used := []
	for i in slots.size():
		if i != gap_index:
			used.append(slots[i])
	var cars := []
	for i in used.size():
		var v: Vehicle = _block_cars[i]
		_repair.call(v)
		v.place(_track, s + (i % 2) * 3, used[i], 0.0)
		v.heading += (1.0 if i % 2 else -1.0) * 0.9 # parked diagonally across the lane
		v.active = true
		v.frozen = true
		v.siren_on = true
		cars.append(v)
	# Traffic already standing in the block would be crushed: nudge it out of the way.
	for o: Vehicle in all:
		if o.role == "traffic" and o.active and absf(o.s - s) < 12:
			o.active = false
	_roadblock = {"s": s, "cars": cars}
	_events.emit("message", {"text": "WEGBLOKKADE VERDEROP!", "color": "#4f8bff", "big": false})
