class_name Collisions
## 2D oriented-box collisions between vehicles (XZ plane), resolved with an impulse that includes
## rotation, so side hits spin cars and nose-to-tail hits push them. Port of src/physics/Collisions.ts.

## Last contact time per pair ("id_a|id_b"), so a long grinding contact doesn't count as many crashes.
static var _pair_contact := {}


static func _corners(v: Vehicle) -> Array:
	var fx := sin(v.heading)
	var fz := cos(v.heading)
	var rx := -fz
	var rz := fx
	var out := []
	for a in Vehicle.SIGNS:
		for b in Vehicle.SIGNS:
			out.append(Vector2(v.x + fx * v.half_l * a + rx * v.half_w * b, v.z + fz * v.half_l * a + rz * v.half_w * b))
	return out


static func _inside(v: Vehicle, p: Vector2, margin := 0.02) -> bool:
	var dx := p.x - v.x
	var dz := p.y - v.z
	var fx := sin(v.heading)
	var fz := cos(v.heading)
	if absf(dx * fx + dz * fz) > v.half_l + margin:
		return false
	return absf(dx * -fz + dz * fx) <= v.half_w + margin


static func _pair_since(a: Vehicle, b: Vehicle, time: float) -> float:
	var ia := a.get_instance_id()
	var ib := b.get_instance_id()
	var key := "%d|%d" % [mini(ia, ib), maxi(ia, ib)]
	var prev: float = _pair_contact.get(key, -99.0)
	_pair_contact[key] = time
	return time - prev


static func reset() -> void:
	_pair_contact.clear()


## World point → car-local (right, forward) offset.
static func to_local(c: Vehicle, px: float, pz: float) -> Vector2:
	var cx := sin(c.heading)
	var cz := cos(c.heading)
	var wx := px - c.x
	var wz := pz - c.z
	return Vector2(wx * -cz + wz * cx, wx * cx + wz * cz)


static func collide(a: Vehicle, b: Vehicle, time: float, events: EventBus) -> bool:
	var T := Config.T
	# Cheap reject
	var dx := b.x - a.x
	var dz := b.z - a.z
	var reach := a.half_l + b.half_l
	if dx * dx + dz * dz > reach * reach:
		return false
	if absf(a.y - b.y) > 2:
		return false

	var ca := _corners(a)
	var cb := _corners(b)
	var axes := [Vector2(sin(a.heading), cos(a.heading)), Vector2(-cos(a.heading), sin(a.heading)),
		Vector2(sin(b.heading), cos(b.heading)), Vector2(-cos(b.heading), sin(b.heading))]
	var depth := INF
	var n := Vector2.ZERO
	for ax: Vector2 in axes:
		var amin := INF
		var amax := -INF
		var bmin := INF
		var bmax := -INF
		for p: Vector2 in ca:
			var q := p.dot(ax)
			amin = minf(amin, q)
			amax = maxf(amax, q)
		for p: Vector2 in cb:
			var q := p.dot(ax)
			bmin = minf(bmin, q)
			bmax = maxf(bmax, q)
		var overlap := minf(amax, bmax) - maxf(amin, bmin)
		if overlap <= 0:
			return false
		if overlap < depth:
			depth = overlap
			n = ax
	# Normal from A to B.
	if n.x * dx + n.y * dz < 0:
		n = -n
	var nx := n.x
	var nz := n.y

	# Contact point: a corner of one box that lies inside the other.
	var pc := Vector2.ZERO
	var found := 0
	for p: Vector2 in cb:
		if _inside(a, p):
			pc += p
			found += 1
	for p: Vector2 in ca:
		if _inside(b, p):
			pc += p
			found += 1
	if found > 0:
		pc /= found
	else:
		pc = Vector2((a.x + b.x) / 2, (a.z + b.z) / 2)
	var px := pc.x
	var pz := pc.y

	# Effective masses (a ramming car hits like a heavier car).
	var ma: float = a.mass * (T.ramMassFactor if a.ramming else 1.0)
	var mb: float = b.mass * (T.ramMassFactor if b.ramming else 1.0)
	# A rammer is also much harder to spin, so the shove doesn't throw you off yourself.
	var ia: float = a.inertia * (T.ramMassFactor * 3 if a.ramming else 1.0)
	var ib: float = b.inertia * (T.ramMassFactor * 3 if b.ramming else 1.0)

	# Both ramming each other at once: a clash. Both bounce off, little damage.
	if a.ram_timer > 0 and b.ram_timer > 0 and a.ram_target == b and b.ram_target == a:
		a.x -= nx * depth / 2
		a.z -= nz * depth / 2
		b.x += nx * depth / 2
		b.z += nz * depth / 2
		for pair in [[a, -1.0], [b, 1.0]]:
			var v: Vehicle = pair[0]
			var sgn: float = pair[1]
			var along := v.vx * nx + v.vz * nz
			v.vx += nx * (sgn * 4 - along)
			v.vz += nz * (sgn * 4 - along)
			v.ram_landed()
			v.last_contact_time = time
		_pair_since(a, b, time)
		var la := to_local(a, px, pz)
		var lb := to_local(b, px, pz)
		a.add_damage(a.zone_at(la.x, la.y), 4, la.x, la.y, b, time, events)
		b.add_damage(b.zone_at(lb.x, lb.y), 4, lb.x, lb.y, a, time, events)
		events.emit("impact", {"x": px, "y": (a.y + b.y) / 2 + 0.6, "z": pz, "strength": 12.0, "kind": "car", "a": a, "b": b})
		return true

	# A targeted ram that lands is a scripted arcade shove, not a physics bounce.
	var land_a := a.ram_timer > 0 and a.ram_target == b and not (b.ram_timer > 0 and b.ram_target == a)
	var land_b := b.ram_timer > 0 and b.ram_target == a and not (a.ram_timer > 0 and a.ram_target == b)
	if land_a or land_b:
		var r := a if land_a else b
		var v := b if land_a else a
		var sign := 1.0 if land_a else -1.0 # n points from a to b
		v.x += nx * depth * sign
		v.z += nz * depth * sign
		_land_ram(r, v, px, pz, time, events)
		return true

	# Who is the aggressor? Compare how fast each car moves into the other, measured
	# relative to the slower car's pace along the road (so a rear-end shunt blames the
	# faster car and a side swipe blames the one that steered in).
	var wa := _aggressor_share(a, b, nx, nz, time)
	var wb := 1.0 - wa

	# Positional correction: mostly the victim gets pushed out.
	var pa := 1.0 - wa
	var pb := 1.0 - wb
	var pt := pa + pb
	if pt == 0:
		pt = 1.0
	a.x -= nx * depth * (pa / pt)
	a.z -= nz * depth * (pa / pt)
	b.x += nx * depth * (pb / pt)
	b.z += nz * depth * (pb / pt)

	var rax := px - a.x
	var raz := pz - a.z
	var rbx := px - b.x
	var rbz := pz - b.z
	# Velocity of the contact point: v + ω × r, with ω × r = (ω r.z, -ω r.x) in our convention.
	var vax := a.vx + a.ang_vel * raz
	var vaz := a.vz - a.ang_vel * rax
	var vbx := b.vx + b.ang_vel * rbz
	var vbz := b.vz - b.ang_vel * rbx
	var rvx := vbx - vax
	var rvz := vbz - vaz
	var vn := rvx * nx + rvz * nz
	if vn >= 0:
		return true # already separating

	var cra := raz * nx - rax * nz
	var crb := rbz * nx - rbx * nz
	var denom := 1.0 / ma + 1.0 / mb + cra * cra / ia + crb * crb / ib
	var j: float = -(1 + T.carRestitution) * vn / denom

	# Friction along the tangent.
	var tx := rvx - vn * nx
	var tz := rvz - vn * nz
	var tl := sqrt(tx * tx + tz * tz)
	var jt := 0.0
	if tl > 1e-4:
		tx /= tl
		tz /= tl
		var crat := raz * tx - rax * tz
		var crbt := rbz * tx - rbx * tz
		var denom_t := 1.0 / ma + 1.0 / mb + crat * crat / ia + crbt * crbt / ib
		jt = minf(tl / denom_t, T.carFriction * j)

	var jx := j * nx + jt * tx
	var jz := j * nz + jt * tz
	# Arcade: the aggressor feels only part of the recoil (and a rammer none of the spin),
	# so shoving someone doesn't throw you into the opposite rail.
	var recoil_a: float = 0.15 if a.ramming else 1 - T.aggressorRecoil * wa
	var recoil_b: float = 0.15 if b.ramming else 1 - T.aggressorRecoil * wb
	# Rammed cars slide sideways rather than spinning back into the rammer.
	var spin_a := 0.0 if a.ramming else (0.5 if b.ramming else recoil_a)
	var spin_b := 0.0 if b.ramming else (0.5 if a.ramming else recoil_b)
	a.vx -= jx / ma * recoil_a
	a.vz -= jz / ma * recoil_a
	a.ang_vel -= (raz * jx - rax * jz) / ia * spin_a
	b.vx += jx / mb * recoil_b
	b.vz += jz / mb * recoil_b
	b.ang_vel += (rbz * jx - rbx * jz) / ib * spin_b

	if a.ramming:
		a.ram_landed()
	if b.ramming:
		b.ram_landed()

	# Damage: the aggressor takes a fraction, the victim takes more. Rams hit extra hard.
	# Contacts within a fraction of a second of the previous one are part of the same crash.
	var repeat := 0.25 if _pair_since(a, b, time) < 0.25 else 1.0
	var base: float = j * T.damagePerImpulse * repeat
	var to_a: float = base * (1.25 - 0.9 * wa) * (T.ramDamageFactor if b.ramming else 1.0) * (0.6 if a.ramming else 1.0)
	var to_b: float = base * (1.25 - 0.9 * wb) * (T.ramDamageFactor if a.ramming else 1.0) * (0.6 if b.ramming else 1.0)
	var la := to_local(a, px, pz)
	var lb := to_local(b, px, pz)

	# Blame: the aggressor is never the victim of its own shove.
	if wa < 0.7:
		a.last_hit_by = b
		a.last_hit_time = time
	if wb < 0.7:
		b.last_hit_by = a
		b.last_hit_time = time
	a.last_contact_time = time
	b.last_contact_time = time
	a.add_damage(a.zone_at(la.x, la.y), to_a, la.x, la.y, b, time, events)
	b.add_damage(b.zone_at(lb.x, lb.y), to_b, lb.x, lb.y, a, time, events)

	var strength := -vn
	if strength > 6:
		if wa < 0.7:
			a.stun = maxf(a.stun, T.stunTime * minf(1.0, to_a / 12))
		if wb < 0.7:
			b.stun = maxf(b.stun, T.stunTime * minf(1.0, to_b / 12))
	if strength > 1.5:
		events.emit("impact", {"x": px, "y": (a.y + b.y) / 2 + 0.6, "z": pz, "strength": strength, "kind": "car", "a": a, "b": b})
	return true


## Share (0..1) of the closing speed that car a is responsible for.
static func _aggressor_share(a: Vehicle, b: Vehicle, nx: float, nz: float, time: float) -> float:
	if a.ramming and not b.ramming:
		return 1.0
	if b.ramming and not a.ramming:
		return 0.0
	# Follow-up contacts after a shove (the victim bouncing back off the rail) stay in the
	# shover's favour, so you don't get punished for your own successful hit.
	var a_hit_b := b.last_hit_by == a and time - b.last_hit_time < 1.5
	var b_hit_a := a.last_hit_by == b and time - a.last_hit_time < 1.5
	if a_hit_b and not b_hit_a:
		return 0.9
	if b_hit_a and not a_hit_b:
		return 0.1
	# Running into someone else's wreck hurts you too.
	if a.wrecked != b.wrecked:
		return 0.5
	# Road direction ≈ average heading of both cars.
	var tx := sin(a.heading) + sin(b.heading)
	var tz := cos(a.heading) + cos(b.heading)
	var tl := sqrt(tx * tx + tz * tz)
	if tl == 0:
		tl = 1.0
	tx /= tl
	tz /= tl
	var pace := minf(a.vx * tx + a.vz * tz, b.vx * tx + b.vz * tz)
	var refx := tx * pace
	var refz := tz * pace
	var into_b := maxf(0.0, (a.vx - refx) * nx + (a.vz - refz) * nz)
	var into_a := maxf(0.0, -((b.vx - refx) * nx + (b.vz - refz) * nz))
	var total := into_a + into_b
	return 0.5 if total < 0.5 else into_b / total


static func _land_ram(r: Vehicle, v: Vehicle, px: float, pz: float, time: float, events: EventBus) -> void:
	var T := Config.T
	# Shove direction: sideways from the rammer's point of view.
	var fx := sin(r.heading)
	var fz := cos(r.heading)
	var sx := -fz * r.ram_dir
	var sz := fx * r.ram_dir

	# Victim: launched sideways and briefly loses grip.
	var v_along := v.vx * sx + v.vz * sz
	v.vx += sx * (T.ramShoveSpeed - v_along)
	v.vz += sz * (T.ramShoveSpeed - v_along)
	v.ang_vel += (randf() - 0.5) * 1.2
	v.stun = maxf(v.stun, T.stunTime)
	v.last_hit_by = r
	v.last_hit_time = time

	# Rammer: stops its sideways lunge at the contact point and keeps its line.
	var r_along := r.vx * sx + r.vz * sz
	r.vx -= sx * r_along * 0.85
	r.vz -= sz * r_along * 0.85
	r.ang_vel *= 0.3
	r.ram_landed()
	r.last_contact_time = time
	v.last_contact_time = time
	_pair_since(r, v, time)

	var lv := to_local(v, px, pz)
	var lr := to_local(r, px, pz)
	v.add_damage(v.zone_at(lv.x, lv.y), T.ramDamage, lv.x, lv.y, r, time, events)
	r.add_damage(r.zone_at(lr.x, lr.y), 1.5, lr.x, lr.y, null, time, events)
	events.emit("impact", {"x": px, "y": (r.y + v.y) / 2 + 0.6, "z": pz, "strength": 14.0, "kind": "car", "a": r, "b": v})
