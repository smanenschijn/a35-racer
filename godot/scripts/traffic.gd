class_name TrafficManager
extends RefCounted
## Same-direction traffic is fully simulated (you can shove it, wreck it, use it as a weapon).
## Oncoming traffic on the other carriageway is decoration on rails; on the single-carriageway N35
## it's physics too. Port of src/game/Traffic.ts.


static func _pick(arr: Array):
	return arr[randi() % arr.size()]


static func random_template() -> Dictionary:
	var total := 0
	for t in Config.TRAFFIC:
		total += t.weight
	var r := randf() * total
	for t in Config.TRAFFIC:
		r -= t.weight
		if r <= 0:
			return t
	return Config.TRAFFIC[0]


static func random_spec(template: Dictionary) -> Dictionary:
	var spec := template.duplicate(true)
	var kind: String = spec.get("kind", "")
	if kind == "truck":
		spec.color = _pick(Config.TRUCK_COLORS)
		spec.trailerText = _pick(Config.TRUCK_COMPANIES)
	elif kind == "van":
		spec.color = _pick([0xf2f2f2, 0xf2f2f2, 0xdddddd, 0x1f3f7a, 0x333333])
	else:
		spec.color = _pick(Config.TRAFFIC_COLORS)
	return spec


## Plain motorway driving: keep lane, keep distance, keep right, overtake when it's free.
class TrafficDriver:
	var vehicle: Vehicle
	var lane := 0.0
	var desired := 0.0
	var right_only := false
	var _lane_timer := 2 + randf() * 4
	var _yield_off := 0.0
	var stuck := 0.0

	func _init(v: Vehicle, ro: bool, des: float, l: float) -> void:
		vehicle = v
		right_only = ro
		desired = des
		lane = l

	func _lane_free(others: Array, l: float, back: float, front: float, spd: float) -> bool:
		var v := vehicle
		for o: Vehicle in others:
			if o == v or not o.active or absf(o.d - l) > o.half_w + v.half_w + 0.4:
				continue
			var ds := o.s - v.s
			# Mirror check: also look further back for anything coming up fast (racers at 200+ km/h).
			var reach := back + maxf(0.0, o.along_speed - spd) * 3
			if ds > -reach and ds < front:
				return false
		return true

	func update(dt: float, track: Track, others: Array) -> void:
		var v := vehicle
		var inp := v.input
		if v.wrecked:
			return
		var spd := v.forward_speed
		_lane_timer -= dt
		var vs := v.s
		# Only the cars around us matter (others is sorted along the road).
		others = Vehicle.near(others, vs - 200, vs + 95)

		# Nearest vehicle ahead in our lane.
		var ahead: Vehicle = null
		var gap := INF
		for o: Vehicle in others:
			if o == v or not o.active:
				continue
			var ds := o.s - vs
			if ds <= 0 or ds > 90:
				continue
			if absf(o.d - lane) > o.half_w + v.half_w + 0.3:
				continue
			var g := ds - o.half_l - v.half_l
			if g < gap:
				gap = g
				ahead = o

		var right: float = Config.LANE_CENTERS[1]
		var left: float = Config.LANE_CENTERS[0]
		# On a single carriageway the left lane is for oncoming traffic: stay right.
		if track.is_single(vs) and lane != right and _lane_timer <= 0:
			lane = right
			_lane_timer = 2.0
		# Lane changes: overtake a slower vehicle, drive around obstacles, keep right afterwards.
		if _lane_timer <= 0 and not track.is_single(vs + 60):
			var obstacle := ahead != null and (ahead.wrecked or ahead.speed < 3) and gap < 60
			if obstacle:
				for l: float in [left, right, Config.SHOULDER]:
					if absf(l - lane) > 1 and _lane_free(others, l, 15, 40, spd):
						lane = l
						break
				_lane_timer = 2.0
			elif not right_only and ahead != null and ahead.along_speed < desired - 3 and gap < 50 and lane == right and _lane_free(others, left, 25, 40, spd):
				lane = left
				_lane_timer = 5.0
			elif lane != right and _lane_free(others, right, 20, 45, spd):
				lane = right
				_lane_timer = 4.0
			else:
				_lane_timer = 1.5

		# N35: a racer closing in from behind? Move over onto the verge so they can squeeze past.
		var yield_to := 0.0
		if track.is_single(vs) and lane == right:
			var racer_behind := false
			var right_busy := false
			for o: Vehicle in others:
				var ds := o.s - vs
				if o.is_racer and o.active and not o.wrecked and ds < 0 and ds > -90 and o.along_speed > spd + 3:
					racer_behind = true
				# ...unless someone is already down our right-hand side.
				if o != v and o.active and o.d > v.d + 1 and absf(ds) < o.half_l + v.half_l + 3:
					right_busy = true
			if racer_behind and not right_busy:
				yield_to = 2.3
		_yield_off += (yield_to - _yield_off) * minf(1.0, dt * 1.2)

		# Steering: pure pursuit on our lane.
		var look := 10 + maxf(0.0, spd) * 0.6
		var target := track.point_at(vs + look, lane + _yield_off)
		var err := wrapf(atan2(target.x - v.x, target.z - v.z) - v.heading, -PI, PI)
		inp.steer = clampf(-err * 2.4 + v.ang_vel * 0.2, -1.0, 1.0)

		# Speed: desired cruise, follow the car in front with a time gap.
		var wanted := desired
		if ahead != null and gap < 90:
			wanted = minf(wanted, maxf(0.0, ahead.along_speed + (gap - 8 - spd * 0.6) * 0.5))
		inp.throttle = 0.7 if spd < wanted - 0.5 else 0.0
		inp.brake = minf(1.0, (spd - wanted) / 8 + 0.2) if spd > wanted + 2 else 0.0
		inp.handbrake = false
		inp.nitro = false

		var facing_back := absf(wrapf(v.heading - track.frame(vs).heading, -PI, PI)) > 1.6
		if (spd < 2 and not (ahead != null and gap < 15)) or facing_back:
			stuck += dt
		else:
			stuck = 0.0


## Oncoming traffic on a single carriageway: drives against the direction of travel in the
## left lane. Swerves to its own verge and brakes when something comes at it in its lane.
class OncomingDriver:
	var vehicle: Vehicle
	var desired := 27.0
	var stuck := 0.0
	var _lane: float = Config.LANE_CENTERS[0]

	func _init(v: Vehicle) -> void:
		vehicle = v

	func update(dt: float, track: Track, others: Array) -> void:
		var v := vehicle
		var inp := v.input
		if v.wrecked:
			return
		var spd := v.forward_speed
		others = Vehicle.near(others, v.s - 115, v.s + 10)
		# Anything ahead of us (lower s) in our lane?
		var threat := INF
		var threat_d := 0.0
		for o: Vehicle in others:
			if o == v or not o.active:
				continue
			var ds := v.s - o.s
			if ds <= 0 or ds > 110:
				continue
			if absf(o.d - _lane) < o.half_w + v.half_w + 0.6 and ds < threat:
				threat = ds
				threat_d = o.d
		# Swerve away from it (usually onto our verge) and brake when threatened.
		# (Something already on our verge: stay put and just brake.)
		var target_lane: float = Config.LANE_CENTERS[0] if threat >= 70 or threat_d < -3.4 else -4.4
		_lane += (target_lane - _lane) * minf(1.0, dt * 1.5)
		var look := 10 + maxf(0.0, spd) * 0.6
		var target := track.point_at(v.s - look, _lane)
		var err := wrapf(atan2(target.x - v.x, target.z - v.z) - v.heading, -PI, PI)
		inp.steer = clampf(-err * 2.4 + v.ang_vel * 0.2, -1.0, 1.0)
		var wanted := desired * 0.4 if threat < 45 else desired
		inp.throttle = 0.7 if spd < wanted - 0.5 else 0.0
		inp.brake = minf(1.0, (spd - wanted) / 8 + 0.3) if spd > wanted + 2 else 0.0
		inp.handbrake = false
		inp.nitro = false
		var facing_wrong := absf(wrapf(v.heading - track.frame(v.s).heading - PI, -PI, PI)) > 1.6
		stuck = stuck + dt if spd < 2 or facing_wrong else 0.0


var vehicles: Array = []
## Physics oncoming cars for single-carriageway stretches.
var against: Array = []
var _start_s := 0.0
var _tick := 0
var _drivers: Array = []
var _against_drivers: Array = []
var _oncoming: Array = [] # {model, s, lane, speed}
var _track: Track
var _create: Callable
var _recolor: Callable
var _repair: Callable


## deps: track, create(spec) -> Vehicle, recolor(v, hex), repair(v), model(spec) -> CarModel
func _init(deps: Dictionary) -> void:
	_track = deps.track
	_create = deps.create
	_recolor = deps.recolor
	_repair = deps.repair
	for i in Config.T.trafficCount:
		var tpl := random_template()
		var v: Vehicle = _create.call(random_spec(tpl.spec))
		vehicles.append(v)
		var lane: float = Config.LANE_CENTERS[1] if tpl.lane == "right" else _pick(Config.LANE_CENTERS)
		_drivers.append(TrafficDriver.new(v, tpl.lane == "right", 0.0, lane))
	for i in 10:
		var tpl := random_template()
		var v: Vehicle = _create.call(random_spec(tpl.spec))
		v.active = false
		against.append(v)
		_against_drivers.append(OncomingDriver.new(v))
	for i in Config.T.oncomingCount:
		var tpl := random_template()
		var model: CarModel = deps.model.call(random_spec(tpl.spec))
		_oncoming.append({"model": model, "s": 0.0, "lane": _pick(Config.ONCOMING_LANES), "speed": tpl.speed[0]})


func _speed_for(v: Vehicle) -> float:
	var tpl: Dictionary = Config.TRAFFIC[0]
	for t in Config.TRAFFIC:
		if t.spec.id == v.spec.id:
			tpl = t
	return tpl.speed[0] + randf() * (tpl.speed[1] - tpl.speed[0])


func _spawn(i: int, s: float) -> bool:
	var v: Vehicle = vehicles[i]
	var drv: TrafficDriver = _drivers[i]
	var single := _track.is_single(s)
	# The N35 is busy enough as it is: thinner traffic there, and always in the right-hand lane.
	if single and randf() < 0.45:
		return false
	var lane: float = Config.LANE_CENTERS[1] if single or drv.right_only or randf() < 0.6 else Config.LANE_CENTERS[0]
	# Keep a safe distance from anyone already there.
	var clear := func(ss: float) -> bool:
		for j in vehicles.size():
			var o: Vehicle = vehicles[j]
			if j != i and o.active and absf(o.s - ss) < o.half_l + v.half_l + 18 and absf(o.d - lane) < 2.5:
				return false
		return true
	var tries := 0
	while not clear.call(s) and tries < 8:
		s += 30
		tries += 1
	if s > _track.length - 80 or not clear.call(s):
		return false
	drv.desired = _speed_for(v)
	drv.lane = lane
	drv.stuck = 0.0
	_repair.call(v)
	var kind: String = v.spec.get("kind", "")
	if kind != "truck":
		_recolor.call(v, _pick([0xf2f2f2, 0xdddddd, 0x1f3f7a]) if kind == "van" else _pick(Config.TRAFFIC_COLORS))
	v.place(_track, s, lane, drv.desired)
	v.active = true
	v.frozen = false
	return true


## Spread traffic over the stage, keeping the start area clear.
func reset(start_s: float, finish_s: float) -> void:
	_start_s = start_s
	var from := start_s + 260
	var span := minf(_track.length - 120, finish_s + 300) - from
	for i in vehicles.size():
		vehicles[i].active = false
		_spawn(i, from + span * (i + randf() * 0.8) / vehicles.size())
	for v: Vehicle in against:
		v.active = false
	for o in _oncoming:
		o.s = start_s - 200 + randf() * 1400
		o.speed = 25 + randf() * 9
		o.lane = _pick(Config.ONCOMING_LANES)


## all: the active vehicles, sorted along the road. Each driver thinks every other physics step.
func update(dt: float, all: Array, racers: Array, player: Vehicle) -> void:
	_tick += 1
	var min_s := player.s
	var max_s := player.s
	for r: Vehicle in racers:
		if not r.wrecked:
			min_s = minf(min_s, r.s)
			max_s = maxf(max_s, r.s)
	for i in vehicles.size():
		var v: Vehicle = vehicles[i]
		if not v.active:
			# Re-enter ahead of the leading racer, out of sight.
			if randf() < 0.02:
				_spawn(i, max_s + 500 + randf() * 400)
			continue
		var drv: TrafficDriver = _drivers[i]
		if (i + _tick) % 2 == 0:
			drv.update(dt * 2, _track, all)
		if v.s < min_s - 150 or v.s > _track.length - 50 or drv.stuck > 4:
			v.active = false
	_update_against(all, player, min_s, dt)


func _update_against(all: Array, player: Vehicle, min_s: float, dt: float) -> void:
	var t := _track
	for i in against.size():
		var v: Vehicle = against[i]
		var drv: OncomingDriver = _against_drivers[i]
		if not v.active:
			# Appear ahead of the player on a single carriageway, coming towards us.
			if randf() < 0.02 and player.s > _start_s + 500:
				var s := player.s + 380 + randf() * 600
				# Not straight into the face of a racer: nobody may be just short of the spawn point.
				var clear := true
				for o: Vehicle in all:
					if o.active and ((absf(o.s - s) < 30 and o.d < -0.5) or (o.is_racer and o.s > s - 300 and o.s < s + 30)):
						clear = false
						break
				if s < t.length - 60 and t.is_single(s) and t.is_single(s - 250) and clear:
					_repair.call(v)
					drv.desired = 24 + randf() * 7
					drv.stuck = 0.0
					v.place(t, s, Config.LANE_CENTERS[0], drv.desired, true)
					v.active = true
					v.frozen = false
			continue
		if (i + _tick) % 2 == 0:
			drv.update(dt * 2, t, all)
		# Gone past everyone, turned off onto the other carriageway, or stuck in a wreck.
		if v.s < min_s - 150 or not t.is_single(v.s + 20) or drv.stuck > 4:
			v.active = false


## Oncoming carriageway: kinematic, recycled around the player.
func render_oncoming(dt: float, player_s: float) -> void:
	var t := _track
	for o in _oncoming:
		o.s -= o.speed * dt
		if o.s < player_s - 180 or o.s < 5 or t.is_single(o.s):
			o.s = minf(t.length - 5, player_s + 700 + randf() * 700)
			if t.is_single(o.s):
				o.s = player_s - 400 # hidden behind us until a dual stretch comes
			o.speed = 25 + randf() * 9
			o.lane = _pick(Config.ONCOMING_LANES)
		var fr := t.frame(o.s)
		var m: CarModel = o.model
		m.place(fr.x + fr.rx * o.lane, fr.y, fr.z + fr.rz * o.lane, fr.heading + PI, o.speed, dt)
		m.set_detail(absf(o.s - player_s) < 200)
