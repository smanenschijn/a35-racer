class_name Vehicle
extends RefCounted
## Semi-arcade 2D rigid body on the XZ plane (NFS2SE feel): engine force along the heading,
## yaw rate steered towards a target, and lateral velocity bled off by "grip".
## Height and pitch come from the track. Port of src/vehicle/Vehicle.ts.

const ZONES := ["front", "rear", "left", "right"]
const SIGNS := [1.0, -1.0]

# Tuning values copied out of Config.T (a dictionary lookup per use is slow in the physics step).
static var _aiDamageFactor := 0.0
static var _brakeDecel := 0.0
static var _dragCoef := 0.0
static var _driftGripFactor := 0.0
static var _driftNitroDelay := 0.0
static var _driftSpeedReturn := 0.0
static var _engineAccel := 0.0
static var _grip := 0.0
static var _handbrakeGrip := 0.0
static var _handbrakeYawBoost := 0.0
static var _nitroAccel := 0.0
static var _nitroDrain := 0.0
static var _nitroFillDriftPerSec := 0.0
static var _nitroFillPerDamage := 0.0
static var _nitroFillTakedown := 0.0
static var _nitroTopSpeedFactor := 0.0
static var _playerDamageFactor := 0.0
static var _railDamagePerSpeed := 0.0
static var _railFriction := 0.0
static var _railGlide := 0.0
static var _railRestitution := 0.0
static var _railScrapeDamage := 0.0
static var _ramCooldown := 0.0
static var _ramDuration := 0.0
static var _ramSideSpeed := 0.0
static var _rollingDecel := 0.0
static var _steerRateHigh := 0.0
static var _steerRateLow := 0.0
static var _stunTime := 0.0
static var _takedownRailBonus := 0.0
static var _takedownWindow := 0.0
static var _wreckTotal := 0.0
static var _yawResponse := 0.0


## Refresh the cached tuning values (call after changing Config.T).
static func tune() -> void:
	_aiDamageFactor = Config.T.aiDamageFactor
	_brakeDecel = Config.T.brakeDecel
	_dragCoef = Config.T.dragCoef
	_driftGripFactor = Config.T.driftGripFactor
	_driftNitroDelay = Config.T.driftNitroDelay
	_driftSpeedReturn = Config.T.driftSpeedReturn
	_engineAccel = Config.T.engineAccel
	_grip = Config.T.grip
	_handbrakeGrip = Config.T.handbrakeGrip
	_handbrakeYawBoost = Config.T.handbrakeYawBoost
	_nitroAccel = Config.T.nitroAccel
	_nitroDrain = Config.T.nitroDrain
	_nitroFillDriftPerSec = Config.T.nitroFillDriftPerSec
	_nitroFillPerDamage = Config.T.nitroFillPerDamage
	_nitroFillTakedown = Config.T.nitroFillTakedown
	_nitroTopSpeedFactor = Config.T.nitroTopSpeedFactor
	_playerDamageFactor = Config.T.playerDamageFactor
	_railDamagePerSpeed = Config.T.railDamagePerSpeed
	_railFriction = Config.T.railFriction
	_railGlide = Config.T.railGlide
	_railRestitution = Config.T.railRestitution
	_railScrapeDamage = Config.T.railScrapeDamage
	_ramCooldown = Config.T.ramCooldown
	_ramDuration = Config.T.ramDuration
	_ramSideSpeed = Config.T.ramSideSpeed
	_rollingDecel = Config.T.rollingDecel
	_steerRateHigh = Config.T.steerRateHigh
	_steerRateLow = Config.T.steerRateLow
	_stunTime = Config.T.stunTime
	_takedownRailBonus = Config.T.takedownRailBonus
	_takedownWindow = Config.T.takedownWindow
	_wreckTotal = Config.T.wreckTotal
	_yawResponse = Config.T.yawResponse


class Controls:
	var throttle := 0.0
	var brake := 0.0
	var steer := 0.0 # -1 left .. +1 right
	var handbrake := false
	var nitro := false
	var ram_left := false # edge-triggered, consumed by the vehicle
	var ram_right := false
	var ram_auto := false # ram whichever side has a target (edge-triggered)


var spec: Dictionary
var is_player := false
## Shown in standings and messages (the player can swap cars with a rival).
var driver_name := ""
var role := "racer" # racer | traffic | police
var half_l := 0.0
var half_w := 0.0
var mass := 0.0
var inertia := 0.0

var x := 0.0
var y := 0.0
var z := 0.0
var heading := 0.0
var vx := 0.0
var vz := 0.0
var ang_vel := 0.0
var pitch := 0.0

var input := Controls.new()
var damage := {"front": 0.0, "rear": 0.0, "left": 0.0, "right": 0.0}
var nitro := 0.35
var nitro_active := false
var ram_timer := 0.0
## Short window after a ram lands during which we still count as the rammer.
var ram_hit_timer := 0.0
var ram_cooldown := 0.0
var ram_dir := 0
## Car we're shoving into (null = short dodge without target).
var ram_target: Vehicle = null
var _was_ramming := false
## Longitudinal acceleration of the last step, used for visual body pitch.
var accel_long := 0.0
var stun := 0.0
var wrecked := false
var wreck_time := 0.0
var frozen := true
var drifting := false
## Seconds the current drift has lasted (only sustained drifts fill nitro).
var drift_time := 0.0
var scraping := 0.0
var braking := false
var last_hit_by: Vehicle = null
var last_hit_time := -99.0
var last_contact_time := -99.0
var power_factor := 1.0
var finished := false
var finish_time := 0.0
var takedowns := 0
var proj := Track.Proj.new()
## Extra damage multiplier (AI rivals on the narrow N35).
var damage_scale := 1.0
## Called whenever damage is dealt: (amount, zone, local x, local z).
var on_damage: Callable
## Speed along the road direction (negative for oncoming traffic).
var along_speed := 0.0
## Inactive vehicles (parked traffic/police) are skipped by physics and hidden.
var active := true
## Police: lights and siren on.
var siren_on := false
## Time penalties (seconds) collected from police fines.
var penalty := 0
var _fr := Track.Frame.new()
var _top_speed := 0.0
var _accel_factor := 1.0
var _grip_factor := 1.0


func _init(car_spec: Dictionary, player := false, car_role := "racer") -> void:
	spec = car_spec
	is_player = player
	driver_name = car_spec.driver
	role = car_role
	is_racer = car_role == "racer"
	var len := Config.total_length(car_spec)
	half_l = len / 2.0
	half_w = car_spec.width / 2.0
	mass = car_spec.mass
	inertia = mass * (len * len + car_spec.width * car_spec.width) / 12.0
	_top_speed = car_spec.topSpeed
	_accel_factor = car_spec.accelFactor
	_grip_factor = car_spec.gripFactor
	if _grip == 0.0:
		tune()


## Position on the road (copies of proj.s / proj.d, kept as plain fields: they're read a lot).
var s := 0.0
var d := 0.0
var is_racer := true

var speed: float:
	get:
		return sqrt(vx * vx + vz * vz)

var forward_speed: float:
	get:
		return vx * sin(heading) + vz * cos(heading)

var total_damage: float:
	get:
		return (damage.front + damage.rear + damage.left + damage.right) / 4.0

## 0..100: how close the car is to total loss (worst zone or overall wear).
var wreck_level: float:
	get:
		return minf(100.0, maxf(maxf(maxf(damage.front, damage.rear), maxf(damage.left, damage.right)), total_damage / _wreckTotal * 100.0))

var ramming: bool:
	get:
		return ram_timer > 0 or ram_hit_timer > 0


## Put the car on the road; `reverse` faces it against the direction of travel (oncoming).
func place(track: Track, at_s: float, at_d: float, spd := 0.0, reverse := false) -> void:
	var fr := track.frame(at_s, _fr)
	x = fr.x + fr.rx * at_d
	z = fr.z + fr.rz * at_d
	y = fr.y
	heading = fr.heading + (PI if reverse else 0.0)
	var dir := -1.0 if reverse else 1.0
	vx = fr.fx * spd * dir
	vz = fr.fz * spd * dir
	along_speed = spd * dir
	ang_vel = 0.0
	proj.idx = -1
	track.project(x, z, -1, proj)
	s = proj.s
	d = proj.d


func repair(level: float) -> void:
	for zn in ZONES:
		damage[zn] = minf(damage[zn], level)
	wrecked = false
	stun = 0.0


func add_damage(zone: String, amount: float, lx: float, lz: float, attacker: Vehicle, time: float, events: EventBus) -> void:
	if wrecked or amount <= 0:
		return
	# Whoever recently hit us gets the credit (and nitro) for this damage.
	var credit: Vehicle = attacker
	if credit == null and time - last_hit_time < _takedownWindow:
		credit = last_hit_by
	# damage_scale softens the pack's own pile-ups; whatever the player dishes out counts in full.
	var sc := 1.0 if credit != null and credit.is_player else damage_scale
	var factor: float = (_playerDamageFactor if is_player else _aiDamageFactor) * spec.get("armor", 1.0) * sc
	var dmg := amount * factor
	damage[zone] = minf(100.0, damage[zone] + dmg)
	if on_damage.is_valid():
		on_damage.call(dmg, zone, lx, lz)
	if credit != null and credit != self:
		credit.nitro = minf(1.0, credit.nitro + dmg * _nitroFillPerDamage)

	if wreck_level >= 100:
		wrecked = true
		wreck_time = time
		nitro_active = false
		ang_vel += (randf() - 0.5) * 4
		var by: Vehicle = credit if credit != null and credit != self else null
		if by != null and is_racer:
			by.takedowns += 1
			by.nitro = minf(1.0, by.nitro + _nitroFillTakedown)
		events.emit("wreck", {"victim": self, "attacker": by})


## Map a local contact point (lx right, lz forward) to a damage zone.
func zone_at(lx: float, lz: float) -> String:
	if absf(lz) / half_l > absf(lx) / half_w:
		return "front" if lz > 0 else "rear"
	return "right" if lx > 0 else "left"


func update(dt: float, time: float, track: Track, events: EventBus, others: Array) -> void:
	var inp := input
	var act := not wrecked and not frozen
	var front: float = damage.front / 100.0
	var rear: float = damage.rear / 100.0

	var fx := sin(heading)
	var fz := cos(heading)
	var v_f := vx * fx + vz * fz
	var v_l := vx * -fz + vz * fx
	var spd := sqrt(v_f * v_f + v_l * v_l)

	stun = maxf(0.0, stun - dt)
	ram_cooldown = maxf(0.0, ram_cooldown - dt)
	ram_timer = maxf(0.0, ram_timer - dt)
	ram_hit_timer = maxf(0.0, ram_hit_timer - dt)

	# --- Nitro ---
	nitro_active = act and inp.nitro and nitro > 0.01 and v_f > 3
	if nitro_active:
		nitro = maxf(0.0, nitro - _nitroDrain * dt)

	# --- Longitudinal ---
	var top: float = _top_speed * (1 - 0.3 * front) * (_nitroTopSpeedFactor if nitro_active else 1.0) * power_factor
	var accel: float = _engineAccel * _accel_factor * (1 - 0.35 * front) * power_factor
	var a_f := 0.0
	braking = false
	if act:
		if inp.throttle > 0 and v_f < top:
			a_f += accel * inp.throttle * maxf(0.08, 1 - (v_f / top) * (v_f / top))
		if inp.brake > 0:
			if v_f > 1:
				a_f -= _brakeDecel * inp.brake
				braking = true
			elif v_f > -14:
				a_f -= accel * 0.5 * inp.brake # reverse
		if nitro_active:
			a_f += _nitroAccel * maxf(0.0, 1 - v_f / top)
		if inp.handbrake:
			a_f -= 3 * signf(v_f)
	elif wrecked:
		a_f -= 7 * signf(v_f)
	elif frozen:
		a_f -= _brakeDecel * signf(v_f)
	a_f -= _rollingDecel * signf(v_f) + _dragCoef * v_f * absf(v_f)
	accel_long = a_f
	var new_vf := v_f + a_f * dt
	if signf(new_vf) != signf(v_f) and absf(v_f) < 1 and not (act and (inp.throttle > 0 or inp.brake > 0)):
		v_f = 0.0
	else:
		v_f = new_vf

	# --- Steering / yaw ---
	var side_dmg: float = maxf(damage.left, damage.right) / 100.0
	var speed_t := clampf(spd / 70.0, 0.0, 1.0)
	var max_yaw: float = (_steerRateLow + (_steerRateHigh - _steerRateLow) * speed_t) * (1 - 0.25 * side_dmg)
	max_yaw *= clampf(spd / 7.0, 0.0, 1.0) # no turning on the spot
	var steer := inp.steer if act else 0.0
	if act:
		steer = clampf(steer + (damage.right - damage.left) / 100.0 * 0.2, -1.0, 1.0)
	if act and inp.handbrake:
		max_yaw *= _handbrakeYawBoost
	var target_yaw := -steer * max_yaw * (1.0 if v_f >= 0 else -1.0)
	var response: float = _yawResponse
	if stun > 0:
		response = 1.2
	if wrecked:
		response = 0.6
	ang_vel += (target_yaw - ang_vel) * minf(1.0, response * dt)
	heading += ang_vel * dt

	# Re-express velocity in the rotated frame, then bleed lateral velocity (grip).
	var wx := fx * v_f - fz * v_l
	var wz := fz * v_f + fx * v_l
	fx = sin(heading)
	fz = cos(heading)
	v_f = wx * fx + wz * fz
	v_l = wx * -fz + wz * fx

	var grip: float = _grip * _grip_factor * (1 - 0.45 * rear)
	if act and inp.handbrake:
		grip = _handbrakeGrip
	elif absf(v_l) > 3.5:
		grip *= _driftGripFactor
	if stun > 0:
		grip *= 0.35
	if wrecked:
		grip = 1.5
	var vl_before := v_l
	v_l *= exp(-grip * dt)
	# Arcade: a little of the lost slide becomes forward speed so drifts don't kill momentum
	# (kept small: the handbrake shouldn't be quicker through a bend than driving it clean).
	if act and v_f > 5:
		v_f += absf(vl_before - v_l) * _driftSpeedReturn

	# --- Ram attack: a sideways shove that locks on to a car beside you ---
	if act and ram_cooldown <= 0 and (inp.ram_left or inp.ram_right or inp.ram_auto):
		if inp.ram_auto and not inp.ram_left and not inp.ram_right:
			var l := find_ram_target(others, -1)
			var r := find_ram_target(others, 1)
			ram_dir = 1 if not r.is_empty() and (l.is_empty() or r.score < l.score) else -1
		else:
			ram_dir = 1 if inp.ram_right else -1
		var tgt := find_ram_target(others, ram_dir)
		ram_target = tgt.v if not tgt.is_empty() else null
		if ram_target != null:
			ram_timer = _ramDuration
			ram_cooldown = _ramCooldown
		else:
			# Nobody there: just a small feint, so you don't throw yourself into the rail.
			ram_timer = 0.14
			ram_cooldown = 0.6
		events.emit("ram", {"vehicle": self, "dir": ram_dir})
	inp.ram_left = false
	inp.ram_right = false
	inp.ram_auto = false
	# Never shove ourselves into the rail.
	if ram_timer > 0 and ram_dir * proj.d > Config.ROAD_HALF_WIDTH - half_w - 0.5:
		ram_timer = 0.0
	if ram_timer > 0:
		var target := ram_target
		var side_speed: float = _ramSideSpeed if target != null else 4.0
		v_l += (ram_dir * side_speed - v_l) * minf(1.0, 45 * dt)
		if target != null:
			# Match the target's position along the road so the hit lands door-to-door.
			var ds := target.proj.s - proj.s
			v_f += clampf(target.forward_speed + ds * 2 - v_f, -8.0, 8.0) * minf(1.0, 5 * dt)
		ang_vel *= exp(-12 * dt) # stay straight while shoving
		_was_ramming = true
	elif _was_ramming:
		# Snap back after the shove so the rammer doesn't follow the victim into the rail.
		_was_ramming = false
		ram_target = null
		v_l *= 0.2
		ang_vel *= 0.3

	drifting = act and spd > 15 and absf(v_l) > 4
	drift_time = drift_time + dt if drifting else 0.0
	# Only a sustained drift pays out, so flicking the handbrake isn't a nitro farm.
	if drift_time > _driftNitroDelay:
		nitro = minf(1.0, nitro + _nitroFillDriftPerSec * dt)

	vx = fx * v_f - fz * v_l
	vz = fz * v_f + fx * v_l
	x += vx * dt
	z += vz * dt

	# --- Track ---
	track.project(x, z, proj.idx, proj)
	s = proj.s
	d = proj.d
	_collide_rails(track, dt, time, events)
	d = proj.d
	var fr := track.frame(proj.s, _fr)
	y = fr.y
	along_speed = vx * fr.fx + vz * fr.fz
	var along := cos(heading - fr.heading)
	pitch = -atan(fr.slope * along)


## The vehicles of an s-sorted list with s in [s0, s1] (a binary search, then a short walk).
static func near(sorted: Array, s0: float, s1: float) -> Array:
	var lo := 0
	var hi := sorted.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if (sorted[mid] as Vehicle).s < s0:
			lo = mid + 1
		else:
			hi = mid
	var out := []
	for i in range(lo, sorted.size()):
		var v: Vehicle = sorted[i]
		if v.s > s1:
			break
		out.append(v)
	return out


## Closest car a ram towards `dir` (-1 left, +1 right) would lock on to: {v, score} or {}.
func find_ram_target(others: Array, dir: int) -> Dictionary:
	var best: Vehicle = null
	var best_score := INF
	for o: Vehicle in others:
		if o == self or o.wrecked or not o.active:
			continue
		if role == "police" and not o.is_player:
			continue # police only go for the player
		var ds := o.s - s
		if absf(ds) > 6:
			continue
		var side := (o.d - d) * dir
		if side < 0.8 or side > 6:
			continue
		var score := absf(ds) + side
		if score < best_score:
			best_score = score
			best = o
	if best == null:
		return {}
	return {"v": best, "score": best_score}


## The shove landed: end it a moment later so the impact transfers but we don't keep pushing.
func ram_landed() -> void:
	if ram_timer > 0:
		ram_hit_timer = 0.15
	ram_timer = 0.0 # stop pushing immediately, the impact already transferred


func _collide_rails(track: Track, dt: float, time: float, events: EventBus) -> void:
	var fr := track.frame(proj.s, _fr)
	var fx := sin(heading)
	var fz := cos(heading)
	var rx := -fz
	var rz := fx
	var limit := Config.ROAD_HALF_WIDTH
	var scrape := 0.0

	for side in SIGNS:
		# Find the corner deepest past this side's rail.
		var best := -INF
		var cx := 0.0
		var cz := 0.0
		for a in SIGNS:
			for b in SIGNS:
				var ox: float = fx * half_l * a + rx * half_w * b
				var oz: float = fz * half_l * a + rz * half_w * b
				var cd := proj.d + ox * fr.rx + oz * fr.rz
				var depth: float = side * cd - limit
				if depth > best:
					best = depth
					cx = ox
					cz = oz
		if best <= 0:
			continue

		# Normal points from the rail back into the road.
		var nx: float = -side * fr.rx
		var nz: float = -side * fr.rz
		x += nx * best
		z += nz * best
		proj.d -= side * best

		var vcx := vx + ang_vel * cz
		var vcz := vz - ang_vel * cx
		var vn := vcx * nx + vcz * nz
		var tx := fr.fx
		var tz := fr.fz
		var vt := vx * tx + vz * tz
		var spd := absf(vt)
		var lx := cx * rx + cz * rz
		var lz := cx * fx + cz * fz
		var zone := zone_at(lx, lz)
		var recently_hit: bool = time - last_hit_time < _takedownWindow and last_hit_by != null

		if vn < 0:
			var crn := cz * nx - cx * nz
			var j: float = -(1 + _railRestitution) * vn / (1.0 / mass + crn * crn / inertia)
			vx += j * nx / mass
			vz += j * nz / mass
			ang_vel += (cz * j * nx - cx * j * nz) / inertia
			# Lose some speed along the rail.
			var loss: float = minf(spd, _railFriction * -vn * 1.2) * signf(vt)
			vx -= tx * loss
			vz -= tz * loss

			var impact := -vn
			var threshold := 3.5 if is_player else 2.0
			if impact > threshold:
				var bonus: float = _takedownRailBonus if recently_hit else 1.0
				add_damage(zone, (impact - threshold) * _railDamagePerSpeed * bonus, lx, lz, null, time, events)
				if impact > 5:
					stun = maxf(stun, _stunTime * 0.6)
				events.emit("impact", {"x": x + cx, "y": y + 0.5, "z": z + cz, "strength": impact, "kind": "rail", "a": self, "b": null})
		# Glide: turn the nose parallel to the rail instead of bouncing back into it.
		if not wrecked:
			var err := wrapf(heading - fr.heading, -PI, PI)
			# (Not while already yawing away: on a bend the frame turns under us and would pin us to the rail.)
			if -side * err > 0 and absf(err) < 1.2 and vt > 5 and side * ang_vel < 0.02:
				heading -= err * minf(1.0, _railGlide * dt)
				ang_vel *= exp(-8 * dt)
		# Continuous scraping: damage, speed loss and sparks.
		if spd > 4:
			var bonus: float = _takedownRailBonus if recently_hit else 1.0
			add_damage(zone, spd * _railScrapeDamage * dt * bonus, lx, lz, null, time, events)
			var drag := minf(spd, 3.5 * dt) * signf(vt)
			vx -= tx * drag
			vz -= tz * drag
			scrape = maxf(scrape, minf(1.0, spd / 40.0))
			events.emit("scrape", {"x": x + cx, "y": y + 0.45, "z": z + cz, "intensity": scrape, "vehicle": self, "nx": nx, "nz": nz})
		last_contact_time = time
	scraping = scrape

	# End walls at the start and finish of the stretch.
	if proj.s <= 0.5 or proj.s >= track.length - 0.5:
		var dir := 1.0 if proj.s <= 0.5 else -1.0
		var vt := vx * fr.fx + vz * fr.fz
		if vt * dir < 0:
			vx -= fr.fx * vt * 1.3
			vz -= fr.fz * vt * 1.3
