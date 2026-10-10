class_name AIDriver
extends RefCounted
## Racing AI: pure-pursuit steering towards a lane target, corner speed from upcoming curvature,
## lane changes to overtake, and opportunistic shoves into rivals. Port of src/vehicle/AIDriver.ts.

var vehicle: Vehicle
var personality: Dictionary
var _target_d := 0.0
var _lane_timer := 0.0
var _stuck_time := 0.0
var _attack_timer := 6 + randf() * 4 # no shoving right off the grid
var _seen_hit_time := -99.0
var _recover_timer := 0.0
var _brake_tap_timer := 3 + randf() * 5
var _brake_tap := 0.0
## Set when the AI wants to be reset onto the road.
var needs_reset := false


func _init(v: Vehicle, p: Dictionary, start_d: float) -> void:
	vehicle = v
	personality = p
	_target_d = start_d


func update(dt: float, track: Track, others: Array, player: Vehicle) -> void:
	var T := Config.T
	var v := vehicle
	var inp := v.input
	if v.wrecked or v.frozen:
		return
	var p := personality
	var spd := v.forward_speed
	_lane_timer -= dt
	_attack_timer -= dt

	# --- Rubber banding: a pack that ran away eases off, one that fell behind pushes on ---
	var gap := player.s - v.s
	if gap > 60:
		v.power_factor = 1 + (T.rubberBandBehind - 1) * minf(1.0, (gap - 60) / 200)
	elif gap < -40:
		v.power_factor = 1 - (1 - T.rubberBandAhead) * minf(1.0, (-gap - 40) / T.rubberBandRange)
	else:
		v.power_factor = 1.0

	# --- Look around: who's ahead in our lane, who's beside us ---
	# How far ahead to react depends on closing speed: awareness is in metres at 20 m/s closing.
	var look_time: float = p.awareness / 20.0
	var scan := 25 + spd * (1 + look_time)
	var ahead: Vehicle = null
	var ahead_ds := INF
	var victim: Vehicle = null
	# Single carriageway (N35): the left lane belongs to oncoming traffic.
	var single := track.is_single(v.s) or track.is_single(v.s + 120)
	var opp_lane: float = Config.LANE_CENTERS[0]
	var own_lane: float = Config.LANE_CENTERS[1]
	var oncoming_ds := INF
	var oncoming_speed := 0.0
	# Traffic moving over onto the verge for us: squeeze past it on its left.
	var squeeze_d := INF
	var vs := v.s
	var vd := v.d
	# Only the cars around us matter (others is sorted along the road).
	others = Vehicle.near(others, vs - 60, vs + 450)
	for o: Vehicle in others:
		if o == v or not o.active:
			continue
		var ds := o.s - vs
		if ds > scan + 30 or ds < -40:
			continue
		var dd := o.d - vd
		if single and not o.is_racer and o.along_speed > 0 and o.d > 1.9 and ds > -o.half_l - v.half_l - 3 and ds < scan:
			squeeze_d = minf(squeeze_d, o.d - o.half_w - v.half_w - 0.5)
			if o.d > 2.4:
				continue # far enough over: not in our way
		# Check both our target lane and the lane we're physically in.
		var in_lane := absf(o.d - _target_d) < o.half_w + v.half_w + 0.4 or absf(dd) < o.half_w + v.half_w + 0.2
		if ds > 0 and ds < scan and in_lane and ds - o.half_l - v.half_l < ahead_ds:
			ahead = o
			ahead_ds = ds - o.half_l - v.half_l
		if single and o.along_speed < -2 and ds > -5 and ds < oncoming_ds and absf(o.d - opp_lane) < 2.6:
			oncoming_ds = ds
			oncoming_speed = -o.along_speed
		if o.is_racer and not o.wrecked and absf(ds) < 4.5 and absf(dd) < 3.8 and absf(dd) > 1.2:
			if victim == null or o == player:
				victim = o
	var ahead_slower := ahead != null and (ahead.along_speed < spd - 1 or ahead.wrecked)
	# Bennie: a rival in front gets shunted, not overtaken.
	var shunting: bool = p.shunter and ahead != null and ahead.is_racer and not ahead.wrecked and ahead_ds < 30
	var closing := maxf(0.0, spd - ahead.along_speed) if ahead != null else 0.0
	var blocked := ahead_slower and ahead_ds < 12 + closing * (0.8 + look_time) and not shunting

	var lane_changed := false
	if blocked and _lane_timer <= 0:
		var lanes := Config.LANE_CENTERS.duplicate()
		if not single:
			lanes.append(Config.SHOULDER)
		# Only to an adjacent lane: jumping two lanes cuts straight through the traffic in between.
		var free := []
		for l: float in lanes:
			if absf(l - _target_d) <= 1.5 or absf(l - vd) >= 4.2:
				continue
			# A lane is free if nobody is beside us there and nothing slow is coming up in it.
			var taken := false
			for o: Vehicle in others:
				if o == v or not o.active or absf(o.d - l) > o.half_w + v.half_w + 0.3:
					continue
				var ds := o.s - vs
				if ds > -8 - o.half_l and ds < 8 + o.half_l:
					taken = true
					break
				var close := maxf(0.0, spd - o.along_speed)
				# Overtaking on the N35: the oncoming lane must be clear for a whole pass.
				if single and l < -1 and o.along_speed < -2:
					if ds > -10 and ds < 40 + close * 6:
						taken = true
						break
				elif ds > 0 and ds < 15 + close * (1 + look_time):
					taken = true
					break
			if not taken:
				free.append(l)
		if not free.is_empty():
			# Prefer the nearest free lane.
			free.sort_custom(func(a, b): return absf(a - vd) < absf(b - vd))
			_target_d = free[0]
			_lane_timer = p.laneChangeDelay
			lane_changed = true

	# --- Focus on the player (Henk-Jan): go hunt them down ---
	if p.playerFocus > 0.8 and absf(gap) < 60 and not player.wrecked and _lane_timer <= 0 and not blocked:
		_target_d = clampf(player.d, -Config.ROAD_HALF_WIDTH + 1.3, Config.ROAD_HALF_WIDTH - 1.3)
		_lane_timer = 0.8

	# --- N35: back to the right lane after a pass, at once when something's coming ---
	var head_on := false
	if single and (_target_d < -1 or vd < -1):
		var closing_on := spd + oncoming_speed
		head_on = oncoming_ds < 30 + closing_on * 2.8
		var right_free := true
		for o: Vehicle in others:
			if o != v and o.active and absf(o.d - own_lane) < o.half_w + v.half_w + 0.3 and absf(o.s - vs) < 7 + o.half_l:
				right_free = false
				break
		if right_free and (head_on or _lane_timer <= 0):
			_target_d = own_lane
			_lane_timer = maxf(_lane_timer, 0.6)

	# Aggressive drivers steer into the rival beside them and use the ram.
	var line_d := _target_d
	# The two-lane N35 leaves no room to dodge: less shoving there.
	var aggro: float = p.aggression * T.aiAggression * (0.45 if single else 1.0)
	# Just got shoved: no counter-attack until we've regained control.
	if v.last_hit_time != _seen_hit_time:
		_seen_hit_time = v.last_hit_time
		_recover_timer = 1.2
	_recover_timer -= dt
	var recovering := v.stun > 0 or _recover_timer > 0
	if victim != null and aggro > 0 and not recovering:
		var dir := signf(victim.d - vd)
		# Rivals mostly gang up on the player; AI-vs-AI fights depend on the character.
		var weight: float = 1.0 if victim == player else 0.15 + (1 - p.playerFocus) * 0.5
		if _attack_timer <= 0 and v.ram_cooldown <= 0:
			# One roll per opportunity, not per physics step.
			if randf() < aggro * weight:
				if dir > 0:
					inp.ram_right = true
				else:
					inp.ram_left = true
				_attack_timer = 2.5 + randf() * 3 * (1 - aggro)
			else:
				_attack_timer = 1.2
		line_d = line_d + (victim.d - line_d) * 0.5 * aggro * weight
	elif aggro > 0.5 and gap < 0 and gap > -25 and absf(player.d - vd) < 4:
		# Block the player behind us by drifting into their lane.
		line_d += (player.d - line_d) * 0.35 * aggro
	# On the N35 there's no hard shoulder: keep off the railings.
	line_d = clampf(line_d, -Config.ROAD_HALF_WIDTH + (1.9 if single else 1.3), Config.ROAD_HALF_WIDTH - (2.6 if single else 1.3))
	if head_on:
		line_d = _target_d # no fighting while dodging a head-on
	if squeeze_d < line_d and not head_on:
		line_d = maxf(-Config.ROAD_HALF_WIDTH + 1.9, squeeze_d)

	# --- Steering: pure pursuit towards a point ahead on the chosen line ---
	var look := 9 + maxf(0.0, spd) * 0.45
	var target := track.point_at(vs + look, line_d)
	var desired := atan2(target.x - v.x, target.z - v.z)
	var err := wrapf(desired - v.heading, -PI, PI)
	inp.steer = clampf(-err * 3.2 + v.ang_vel * 0.15, -1.0, 1.0)

	# --- Speed: corners, traffic ahead we can't pass, brake taps ---
	var max_k := 0.0
	for a in range(0, 140, 10):
		max_k = maxf(max_k, absf(track.curvature_at(vs + a)))
	var lat: float = T.aiCornerLatAccel * (0.75 + 0.25 * p.skill)
	var corner_speed := sqrt(lat / max_k) if max_k > 1e-5 else INF
	var wanted: float = minf(v.spec.topSpeed * (0.9 + 0.1 * p.skill), corner_speed)
	if blocked and not lane_changed and ahead != null and absf(_target_d - vd) < 1.5:
		# Stuck behind someone: follow at a distance (reckless drivers leave less room).
		var room: float = 4 + p.awareness * 0.25
		# Brake early enough: v² = v_ahead² + 2·a·gap with a comfortable 9 m/s².
		var av := maxf(0.0, ahead.along_speed)
		var safe := sqrt(maxf(0.0, av * av + 2 * 9 * maxf(0.0, ahead_ds - room)))
		wanted = minf(wanted, safe)
	if head_on and _target_d < -1:
		# Can't get back in yet: drop back behind the car we were passing.
		wanted = minf(wanted, spd - 6)
	if p.erratic > 0:
		_brake_tap_timer -= dt
		if _brake_tap_timer <= 0:
			_brake_tap = 0.5 + randf() * 0.6
			_brake_tap_timer = 4 + randf() * 6 / p.erratic
	_brake_tap = maxf(0.0, _brake_tap - dt)

	inp.throttle = 1.0 if spd < wanted else (0.3 if spd < wanted + 2 else 0.0)
	inp.brake = minf(1.0, (spd - wanted) / 10 + 0.3) if spd > wanted + 3 else 0.0
	if _brake_tap > 0:
		inp.throttle = 0.0
		inp.brake = 0.7
	inp.handbrake = false
	# (No nitro while waiting for a player who fell behind.)
	if gap < -Config.T.aiNitroLead:
		inp.nitro = false
	elif v.nitro > 0.6 and absf(inp.steer) < 0.3 and spd > 25 and not blocked and randf() < 0.02 * (1 + p.skill):
		inp.nitro = true
	else:
		inp.nitro = inp.nitro and v.nitro > 0.1 and not blocked

	# --- Stuck recovery ---
	var facing_back := absf(wrapf(v.heading - track.frame(vs).heading, -PI, PI)) > 1.8
	var waiting_in_traffic := blocked and ahead != null and ahead.speed < 3
	if (absf(spd) < 3 and not waiting_in_traffic) or facing_back:
		_stuck_time += dt
	else:
		_stuck_time = 0.0
	if _stuck_time > 2.5:
		needs_reset = true
		_stuck_time = 0.0


func set_lane(d: float) -> void:
	_target_d = d


## New race: forget timers from the last one.
func reset(d: float) -> void:
	_target_d = d
	_attack_timer = 6 + randf() * 4
	_lane_timer = 0.0
	_recover_timer = 0.0
	_stuck_time = 0.0
	needs_reset = false


func reset_lane() -> void:
	_target_d = Config.LANE_CENTERS[randi() % Config.LANE_CENTERS.size()]
